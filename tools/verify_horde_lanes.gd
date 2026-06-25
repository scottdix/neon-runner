extends SceneTree
## Headless verification for HORDE H1 — permanent divider + far-side firing boundary (#90):
##   1) LaneArena.lane_bounds_for is the validated half-field geometry (LEFT = left half clear of
##      the divider, RIGHT = right half), and LaneArena.side_of splits at CENTER_X (540).
##   2) Far-side FILTER: in HORDE, Targets.step()'s damage pass only feeds enemies on the SAME side
##      of CENTER_X as the fleet muzzle (_fleet.position.x) into consume_volumes. Driven with a STUB
##      fleet whose position.x we control + that records every volume it's fed and returns 1 hit
##      each — so a far-side enemy (opposite the muzzle) is NEVER fed (0 hits, full HP) and a
##      near-side enemy IS fed (>0 hits, HP dropped). We flip the muzzle to the other side and
##      confirm the roles swap.
##   3) NON-HORDE invariant: with HORDE off, BOTH sides are fed (the filter is HORDE-only).
##
## GPU-free: drives the pure step() with a stub fleet; writes a verdict file the runner polls for.
##   tools/run-headless.sh res://tools/verify_horde_lanes.gd /tmp/verify_horde_lanes_result.txt

const RESULT_PATH := "/tmp/verify_horde_lanes_result.txt"
const CENTER := 540.0
const LEFT_X := 200.0      # comfortably LEFT of the divider
const RIGHT_X := 880.0     # comfortably RIGHT of the divider


## A minimal Fleet stand-in: records the positions it's fed each consume_volumes call and returns
## 1 hit for every fed volume (so "was this enemy fed?" == "did it take damage?"). position.x is the
## muzzle the far-side filter keys off. No GPU, no real bullets.
class StubFleet:
	extends Node2D
	var fed: PackedVector2Array = PackedVector2Array()
	func consume_volumes(positions: PackedVector2Array, _radii: PackedFloat32Array) -> PackedInt32Array:
		fed = positions
		var h := PackedInt32Array()
		h.resize(positions.size())
		for i in positions.size():
			h[i] = 1
		return h
	func hit_weight() -> float: return 1.0
	func crack_weight() -> float: return 1.0
	func is_piercing() -> bool: return false


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ArenaS: GDScript = load("res://assets/obstacles/lane_arena.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	if ArenaS == null or TargetsS == null:
		lines.append("RESULT=FAIL (H1 scripts missing)"); _write(lines); return

	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		lines.append("RESULT=FAIL (GameState autoload missing)"); _write(lines); return
	gs.call("wire_events")

	# --- 1) LaneArena geometry (pure) ---
	var arena: Node2D = ArenaS.new()
	root.add_child(arena)
	await process_frame                      # _ready is deferred under -s; let it seed _design
	var left_b: Vector2 = arena.call("lane_bounds_for", 0)
	var right_b: Vector2 = arena.call("lane_bounds_for", 1)
	lines.append("lanes: LEFT=%s RIGHT=%s (split=%.0f)" % [str(left_b), str(right_b), CENTER])
	if not (left_b.x < left_b.y and left_b.y <= CENTER):
		lines.append("lanes FAIL: LEFT bound is not a left-half range clear of the divider"); ok = false
	if not (right_b.x >= CENTER and right_b.x < right_b.y):
		lines.append("lanes FAIL: RIGHT bound is not a right-half range clear of the divider"); ok = false
	var side_l: int = int(ArenaS.call("side_of", LEFT_X))
	var side_r: int = int(ArenaS.call("side_of", RIGHT_X))
	lines.append("side_of: x=%.0f->%d  x=%.0f->%d (want 0, 1)" % [LEFT_X, side_l, RIGHT_X, side_r])
	if side_l != 0 or side_r != 1:
		lines.append("lanes FAIL: side_of did not split at CENTER_X"); ok = false
	if ok:
		lines.append("lanes OK: each lane is the half-field on its side, divider splits at 540")

	# --- 2) Far-side filter (HORDE) ---
	# Build a Targets with HORDE forced on + a stub fleet. Place ONE enemy on each side, drive the
	# muzzle to the LEFT side, and assert ONLY the left enemy is fed/damaged.
	var t: Node2D = TargetsS.new()
	root.add_child(t)
	await process_frame                      # _ready (builds the MultiMesh, seeds _design)
	t.call("set_force_horde", true)
	var fleet := StubFleet.new()
	root.add_child(fleet)
	t.call("set_fleet", fleet)

	# Stamp two enemies directly into the live set (one per side), both unarmored full-HP glitches.
	var e_left: Dictionary = _glitch_at(TargetsS, Vector2(LEFT_X, 400.0))
	var e_right: Dictionary = _glitch_at(TargetsS, Vector2(RIGHT_X, 400.0))
	t.set("_enemies", [e_left, e_right] as Array[Dictionary])

	# Muzzle on the LEFT side: only the left enemy is damageable.
	fleet.position.x = LEFT_X
	t.call("step", 0.016)
	var fed_left_only: PackedVector2Array = fleet.fed
	var live: Array = t.get("_enemies")
	var hp_left_a: float = _hp_at(live, LEFT_X)
	var hp_right_a: float = _hp_at(live, RIGHT_X)
	lines.append("muzzle LEFT(%.0f): fed=%d hp_left=%.0f hp_right=%.0f (max=40)" % [
		LEFT_X, fed_left_only.size(), hp_left_a, hp_right_a])
	if fed_left_only.size() != 1:
		lines.append("filter FAIL: muzzle LEFT fed %d volumes (want 1 — only the near-side enemy)" % fed_left_only.size()); ok = false
	if hp_left_a >= 40.0:
		lines.append("filter FAIL: near-side (LEFT) enemy took NO damage"); ok = false
	if hp_right_a < 40.0:
		lines.append("filter FAIL: far-side (RIGHT) enemy was damaged across the divider"); ok = false

	# Flip the muzzle to the RIGHT side: the roles must swap (only the right enemy is now damageable).
	# Reset HP so the assertion is unambiguous.
	live = t.get("_enemies")
	for e in live:
		e["hp"] = 40.0
	fleet.position.x = RIGHT_X
	t.call("step", 0.016)
	var fed_right_only: PackedVector2Array = fleet.fed
	live = t.get("_enemies")
	var hp_left_b: float = _hp_at(live, LEFT_X)
	var hp_right_b: float = _hp_at(live, RIGHT_X)
	lines.append("muzzle RIGHT(%.0f): fed=%d hp_left=%.0f hp_right=%.0f (max=40)" % [
		RIGHT_X, fed_right_only.size(), hp_left_b, hp_right_b])
	if fed_right_only.size() != 1:
		lines.append("filter FAIL: muzzle RIGHT fed %d volumes (want 1)" % fed_right_only.size()); ok = false
	if hp_right_b >= 40.0:
		lines.append("filter FAIL: near-side (RIGHT) enemy took NO damage after the flip"); ok = false
	if hp_left_b < 40.0:
		lines.append("filter FAIL: far-side (LEFT) enemy was damaged across the divider after the flip"); ok = false
	if fed_left_only.size() == 1 and fed_right_only.size() == 1:
		lines.append("filter OK: far-side filter follows the muzzle (only the near side takes hits)")

	# --- 3) NON-HORDE invariant: with HORDE off, BOTH sides are fed regardless of muzzle x ---
	# This batch LOCKS the live Settings autoload to poc_mode == HORDE (3) unconditionally, and
	# Targets._is_horde() falls back to the LIVE Settings when _force_horde is false — so
	# set_force_horde(false) alone is NOT enough to leave HORDE here. Temporarily drop the live
	# Settings.poc_mode to a non-HORDE mode (LEGACY == 0) for this assertion, then restore it.
	t.call("set_force_horde", false)
	var settings: Node = root.get_node_or_null("Settings")
	var saved_pm: int = int(settings.get("poc_mode")) if settings != null else 3
	if settings != null:
		settings.set("poc_mode", 0)              # PocMode.LEGACY — far-side filter must switch OFF
	live = t.get("_enemies")
	for e in live:
		e["hp"] = 40.0
	fleet.position.x = LEFT_X
	t.call("step", 0.016)
	var fed_both: PackedVector2Array = fleet.fed
	if settings != null:
		settings.set("poc_mode", saved_pm)       # restore the locked HORDE state
	lines.append("non-HORDE: muzzle LEFT fed=%d (want 2 — filter is HORDE-only)" % fed_both.size())
	if fed_both.size() != 2:
		lines.append("invariant FAIL: non-HORDE damage pass did not feed BOTH enemies"); ok = false
	else:
		lines.append("invariant OK: outside HORDE both sides are damageable (byte-for-byte unchanged)")

	fleet.free()
	t.free()
	arena.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## A full-HP unarmored Glitch dict at a world position (matches Targets._new_enemy's shape for the
## fields step()/_apply_damage/_render touch). HP 40 == STATS[KIND_GLITCH].hp.
func _glitch_at(TargetsS: GDScript, pos: Vector2) -> Dictionary:
	return {
		"kind": TargetsS.KIND_GLITCH,
		"pos": pos,
		"hp": 40.0, "max_hp": 40.0,
		"size": 52.0, "speed": 0.0,       # speed 0 so it can't breach/move out of the assertion
		"armor": 0, "points": 50,
		"breach": 6.0, "split": false,
		"flash": 0.0,
		"parked": false, "gate_id": -1, "multiplied": false,
	}


## HP of the live enemy nearest world-x `x` (the two test enemies are far apart, so nearest == the
## one we placed there). Returns 40 (full) if it was killed/removed (so a wrongly-damaged far enemy
## that died still reads as "damaged" via the <40 check on its survivor — here it'd be gone, but in
## our test the speed-0 enemies never leave, and a single frame can't kill 40 HP).
func _hp_at(live: Array, x: float) -> float:
	var best_hp: float = 40.0
	var best_d: float = 1.0e9
	for e in live:
		var d: float = absf(float((e["pos"] as Vector2).x) - x)
		if d < best_d:
			best_d = d
			best_hp = float(e["hp"])
	return best_hp


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
