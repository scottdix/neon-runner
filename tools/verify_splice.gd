extends SceneTree
## Headless verification for the Splice Lab → firing chain (#73 device-feedback fix):
##   - SpliceLab.equip_next : two taps fill both slots (A then B) -> can_splice().
##   - active_modifiers     : NEUTRAL until two mods are equipped, then NON-neutral
##                            (rate/spread/speed mults move off 1.0, or a SHOTS bonus).
##   - Fleet.apply_splice   : a spliced Fleet's step() behaviour measurably DIFFERS from a
##                            neutral one — more shots over N seconds AND/OR a denser starting
##                            swarm AND/OR a faster muzzle band — proving the equip lands on
##                            firing on a fresh run (the "nothing affects shooting" symptom).
##
## GPU-free: drives the pure logic directly and writes a verdict file the runner polls for
## (CLAUDE.md gotchas). Scripts are loaded by PATH (no class_name cache under -s). Run:
##   tools/run-headless.sh res://tools/verify_splice.gd /tmp/verify_splice_result.txt

const RESULT_PATH := "/tmp/verify_splice_result.txt"

const NEUTRAL := {
	"rate_mult": 1.0, "spread_mult": 1.0, "speed_mult": 1.0, "start_projectiles_bonus": 0,
}


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# Scripts + autoloads present.
	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	if FleetS == null:
		lines.append("RESULT=FAIL (fleet script missing)"); _write(lines); return
	var lab: Node = root.get_node_or_null("SpliceLab")
	var gs: Node = root.get_node_or_null("GameState")
	if lab == null or gs == null:
		lines.append("RESULT=FAIL (SpliceLab/GameState autoloads missing)"); _write(lines); return

	# Deterministic starting state: re-seed inventory, clear slots (idempotent helpers).
	lab.call("_seed_inventory")
	lab.call("clear_slots")

	# 1) Nothing equipped -> NEUTRAL modifiers (the verify_combat invariant: a fresh run
	#    with no Splice Lab interaction fires EXACTLY as before).
	var neutral_fx: Dictionary = lab.call("active_modifiers")
	lines.append("empty: can_splice=%s fx=%s" % [lab.call("can_splice"), neutral_fx])
	if bool(lab.call("can_splice")) or not _is_neutral(neutral_fx):
		lines.append("neutral FAIL: an un-spliced lab is not neutral"); ok = false
	else:
		lines.append("neutral OK: no equip -> neutral modifiers (today's firing preserved)")

	# 2) Two card taps via equip_next fill slot A then slot B -> can_splice() and NON-neutral
	#    modifiers. Slot 0 = SPREAD FIRE (x2 SPEED), slot 2 = GRID BURST (x2 RATE).
	lab.call("equip_next", 0)            # -> slot_a
	lab.call("equip_next", 2)            # -> slot_b
	var fx: Dictionary = lab.call("active_modifiers")
	lines.append("equipped: slot_a=%d slot_b=%d can_splice=%s fx=%s" % [
		lab.get("slot_a"), lab.get("slot_b"), lab.call("can_splice"), fx])
	if int(lab.get("slot_a")) != 0 or int(lab.get("slot_b")) != 2 or not bool(lab.call("can_splice")):
		lines.append("equip FAIL: equip_next did not fill A then B"); ok = false
	if _is_neutral(fx):
		lines.append("modifiers FAIL: two equipped mods still yield NEUTRAL firing"); ok = false
	else:
		lines.append("modifiers OK: equip_next x2 -> non-neutral (rate x%.1f speed x%.1f bonus %d)" % [
			fx["rate_mult"], fx["speed_mult"], fx["start_projectiles_bonus"]])

	# 3) splice() commits without changing the numeric modifiers (active_modifiers is the
	#    machine twin; splice() only sets the DISPLAY output). Firing must NOT require it.
	var before_splice: Dictionary = lab.call("active_modifiers").duplicate()
	lab.call("splice")
	var after_splice: Dictionary = lab.call("active_modifiers")
	if not _same_fx(before_splice, after_splice):
		lines.append("splice FAIL: pressing SPLICE changed the firing modifiers (it shouldn't)"); ok = false
	else:
		lines.append("splice OK: SPLICE button commits display; firing reads the equip directly")

	# 4) A spliced Fleet's step() output measurably differs from a NEUTRAL Fleet on a fresh
	#    run. Same volume + same number of frames for both; the only difference is the equip.
	#    Build the NEUTRAL fleet against an empty lab, the spliced one against the equipped lab.
	# Fix the starting swarm volume for BOTH fleets (set_projectile_count, not start_run —
	# we want the economy value without _load_level()'s headless scene dependency).
	gs.call("set_projectile_count", 30)

	# Neutral baseline: empty the lab so apply_splice() is a no-op.
	lab.call("clear_slots")
	var neutral := _run_fleet(FleetS)
	# Spliced: re-equip the two mods, rebuild a fresh fleet (apply_splice in _ready folds them).
	lab.call("equip_next", 0)
	lab.call("equip_next", 2)
	var spliced := _run_fleet(FleetS)

	lines.append("neutral fleet:  start=%d shots_60f=%d top=%d speed_band=%.0f" % [
		neutral["start"], neutral["shots"], neutral["top"], neutral["reach"]])
	lines.append("spliced fleet:  start=%d shots_60f=%d top=%d speed_band=%.0f" % [
		spliced["start"], spliced["shots"], spliced["top"], spliced["reach"]])

	# The equip MUST change firing somehow: more shots over the window (rate), OR a denser
	# starting swarm (SHOTS bonus), OR faster bullets (speed -> bullets reach higher / clear
	# the top sooner -> different live top count). Any one proves the chain lands on firing.
	var more_shots: bool = spliced["shots"] > neutral["shots"]
	var denser_start: bool = spliced["start"] > neutral["start"]
	var faster: bool = spliced["reach"] > neutral["reach"] + 0.5
	if not (more_shots or denser_start or faster):
		lines.append("firing FAIL: an equipped splice did NOT change Fleet.step() output"); ok = false
	else:
		lines.append("firing OK: equip changes firing (more_shots=%s denser_start=%s faster=%s)" % [
			more_shots, denser_start, faster])

	# Restore a clean lab so the persisted state isn't left mid-test.
	lab.call("clear_slots")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## Build a fresh Fleet (apply_splice runs in _ready against the current lab state), record its
## starting swarm, then drive 60 frames at 1/60s and report shots fired + how far the leading
## bullet travelled (a proxy for projectile speed). GPU-free: step() is pure.
func _run_fleet(FleetS: GDScript) -> Dictionary:
	var fl: Node2D = FleetS.new()
	fl.position = Vector2(540.0, 1680.0)
	root.add_child(fl)
	# Under `-s`, _ready() does NOT fire (autoload-ready-deferred-headless gotcha), so the
	# run-start init that _ready performs on device never runs. Drive it explicitly: seed the
	# volume, then fold the equipped splice — apply_splice() is public + idempotent for exactly
	# this (CLAUDE.md "wire via a public idempotent method tests call explicitly"). Both the
	# neutral and spliced fleet get the SAME volume, so any firing delta is purely the splice.
	fl.set("_volume", 30)
	fl.call("apply_splice")
	var start_count: int = fl.call("live_count")
	# Total fires over the window come off the fleet_fired bus signal. A locally-held Callable
	# is connected then disconnected so each fleet's tally is isolated.
	var ev: Node = root.get_node_or_null("Events")
	var fire_tally := [0]
	var tally_cb := func(n: int) -> void: fire_tally[0] += n
	if ev != null and ev.has_signal("fleet_fired"):
		ev.connect("fleet_fired", tally_cb)
	var min_y := 1e9
	for i in 60:
		fl.call("step", 1.0 / 60.0)
		# Track the muzzle reach: the smallest y any live bullet has climbed to (up = -y).
		for p in fl.get("_proj"):
			min_y = minf(min_y, (p as Vector2).y)
	var top_live: int = fl.call("live_count")
	var muzzle_y := 1680.0 - 28.0   # position.y + muzzle_offset.y
	var reach := muzzle_y - min_y if min_y < 1e8 else 0.0
	if ev != null and ev.has_signal("fleet_fired") and ev.is_connected("fleet_fired", tally_cb):
		ev.disconnect("fleet_fired", tally_cb)
	fl.free()
	return {"start": start_count, "shots": fire_tally[0], "top": top_live, "reach": reach}


func _is_neutral(fx: Dictionary) -> bool:
	return _same_fx(fx, NEUTRAL)


func _same_fx(a: Dictionary, b: Dictionary) -> bool:
	return absf(float(a.get("rate_mult", 1.0)) - float(b.get("rate_mult", 1.0))) < 0.0001 \
		and absf(float(a.get("spread_mult", 1.0)) - float(b.get("spread_mult", 1.0))) < 0.0001 \
		and absf(float(a.get("speed_mult", 1.0)) - float(b.get("speed_mult", 1.0))) < 0.0001 \
		and int(a.get("start_projectiles_bonus", 0)) == int(b.get("start_projectiles_bonus", 0))


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
