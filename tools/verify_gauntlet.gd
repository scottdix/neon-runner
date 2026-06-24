extends SceneTree
## Headless verification for the Walled Gauntlet (#86):
##   - 7-second pacing       : barrier_height_px == LEN_M(56) × PIXELS_PER_METER(66) == 3696 px.
##   - Lane commitment       : the trap ENGAGES when the front edge reaches the ship line (latching
##                            the lane the ship is in + emitting that lane's clamp) and RELEASES
##                            (full width) when the back edge passes — exactly a 56 m / 7 s window.
##   - Lane bounds           : LEFT commits to the left half, RIGHT to the right half, both clear of
##                            the divider.
##   - Occupant + gate spawn : engaging injects the Glitch swarm + Rhombus (Targets) and the lane
##                            Split Choice gate (GateSpawner).
##
## GPU-free: drives the pure _step + helpers directly and writes a verdict file the runner polls for.
##   tools/run-headless.sh res://tools/verify_gauntlet.gd /tmp/verify_gauntlet_result.txt

const RESULT_PATH := "/tmp/verify_gauntlet_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var GauntletS: GDScript = load("res://assets/obstacles/walled_gauntlet.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var SpawnerS: GDScript = load("res://assets/gates/gate_spawner.gd")
	var TrackS: GDScript = load("res://assets/levels/track.gd")
	if GauntletS == null or TargetsS == null or SpawnerS == null or TrackS == null:
		lines.append("RESULT=FAIL (gauntlet scripts missing)"); _write(lines); return

	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if gs == null or ev == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return
	gs.call("wire_events")

	# 1) 7-second pacing.
	var g: Node2D = GauntletS.new()
	var h: float = float(g.call("barrier_height_px"))
	var want_h: float = GauntletS.LEN_M * TrackS.PIXELS_PER_METER
	lines.append("pacing: barrier=%.0f px want=%.0f (=%.0f m × %.0f px/m)" % [
		h, want_h, GauntletS.LEN_M, TrackS.PIXELS_PER_METER])
	if absf(h - want_h) > 0.01 or absf(want_h - 3696.0) > 0.01:
		lines.append("pacing FAIL: barrier height != a 7 s / 56 m span"); ok = false
	else:
		lines.append("pacing OK: 56 m × 66 px/m == 3696 px == 7 s on the line")

	# 2) Lane bounds — pure.
	var left_b: Vector2 = g.call("lane_bounds_for", 0)
	var right_b: Vector2 = g.call("lane_bounds_for", 1)
	lines.append("lanes: LEFT=%s RIGHT=%s (split=%.0f)" % [left_b, right_b, GauntletS.CENTER_X])
	if not (left_b.x < left_b.y and left_b.y <= GauntletS.CENTER_X):
		lines.append("lanes FAIL: LEFT bound not a left-half range"); ok = false
	if not (right_b.x >= GauntletS.CENTER_X and right_b.x < right_b.y):
		lines.append("lanes FAIL: RIGHT bound not a right-half range"); ok = false
	if ok:
		lines.append("lanes OK: each lane is the half-field on its side, clear of the divider")

	# 3) Commitment window — engage on front, release on back. Inject real Targets + Spawner so the
	#    occupant/gate spawn path runs too.
	var targets: Node2D = TargetsS.new()
	var spawner: Node2D = SpawnerS.new()
	g.call("set_targets", targets)
	g.call("set_gates", spawner)
	g.call("set_ship_line", 1680.0)
	g.call("set_start_m", 80.0)

	var clamps: Array = []   # captured lane_clamp_changed emissions
	ev.connect("lane_clamp_changed", func(a, b): clamps.append(Vector2(a, b)))
	gs.call("start_run")

	var ship_x: float = 300.0                       # ship sits LEFT of centre at engage
	g.call("_step", 79.0, ship_x)                   # PENDING: front not yet at the line
	var trapping_pre: bool = bool(g.call("is_trapping"))
	g.call("_step", 80.0, ship_x)                   # ENGAGE
	var trapping_on: bool = bool(g.call("is_trapping"))
	var lane: int = int(g.call("committed_lane"))
	var enemies_after: int = int(targets.call("live_count"))
	var formations_after: int = (spawner.get("_formations") as Array).size()
	g.call("_step", 100.0, ship_x)                  # still inside the window (<= 136)
	var trapping_mid: bool = bool(g.call("is_trapping"))
	g.call("_step", 137.0, ship_x)                  # back edge passed (> 80 + 56) -> RELEASE
	var trapping_off: bool = bool(g.call("is_trapping"))

	lines.append("window: pre=%s on=%s mid=%s off=%s lane=%d clamps=%d enemies=%d formations=%d" % [
		trapping_pre, trapping_on, trapping_mid, trapping_off, lane, clamps.size(), enemies_after, formations_after])
	if trapping_pre or not trapping_on or not trapping_mid or trapping_off:
		lines.append("window FAIL: trap did not engage on front / hold / release on back"); ok = false
	if lane != 0:
		lines.append("window FAIL: ship left of centre did not commit to the LEFT lane"); ok = false
	# Two clamps: the lane lock on engage + the full-width release.
	if clamps.size() != 2:
		lines.append("window FAIL: expected exactly 2 lane_clamp_changed (lock + release), got %d" % clamps.size()); ok = false
	else:
		var lock: Vector2 = clamps[0]
		var release: Vector2 = clamps[1]
		if not (lock.x == left_b.x and lock.y == left_b.y):
			lines.append("window FAIL: lock clamp != LEFT lane bounds"); ok = false
		if release.y < GauntletS.CENTER_X * 1.5:    # release is the full design width
			lines.append("window FAIL: release clamp was not the full steerable width"); ok = false
	# Occupants: 4 glitches + 1 rhombus = 5; one Split Choice formation appended.
	if enemies_after != 5:
		lines.append("window FAIL: expected 5 lane occupants (4 glitch + 1 rhombus), got %d" % enemies_after); ok = false
	if formations_after != 1:
		lines.append("window FAIL: expected 1 lane Split Choice formation, got %d" % formations_after); ok = false
	if ok:
		lines.append("window OK: engage->lock LEFT, hold 56 m, release full width; occupants + gate spawned")

	targets.free()
	spawner.free()
	g.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
