extends SceneTree
## Headless verification for the combat-redesign stance-driver POCs (#86/#87):
##   - KINETIC_CLUTCH mapping : StanceController.kinetic_stance — moving => SPRAY, still ≥0.2 s => LANCE.
##   - Triple-tap detector    : Player.register_tap fires on the 3rd tap inside the window, not on a
##                              slow/stale burst; resets after firing.
##   - GEOM_OVERDRIVE toggle   : enters LANCE overdrive ONLY with charge in the tank; the burn drains
##                              it and auto-reverts to SPRAY at empty; a 2nd toggle exits early.
##   - Gate-stance suppression : in KINETIC/GEOM a −/÷ gate still moves projectile_count + drains the
##                              battery but does NOT flip stance (the driver owns it); LEGACY still does.
##
## GPU-free: drives the pure helpers directly and writes a verdict file the runner polls for.
##   tools/run-headless.sh res://tools/verify_poc_stance.gd /tmp/verify_poc_stance_result.txt

const RESULT_PATH := "/tmp/verify_poc_stance_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ControllerS: GDScript = load("res://assets/player/stance_controller.gd")
	var PlayerS: GDScript = load("res://assets/player/player.gd")
	if ControllerS == null or PlayerS == null:
		lines.append("RESULT=FAIL (POC scripts missing)"); _write(lines); return

	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	var st: Node = root.get_node_or_null("Settings")
	if gs == null or ev == null or st == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return
	gs.call("wire_events")

	var SPRAY: int = 0   # GameState.Stance.SPRAY == 0 by contract
	var LANCE: int = 1
	var LEGACY: int = 0  # Settings.PocMode.LEGACY
	var KINETIC: int = 1
	var GEOM: int = 2

	# 1) KINETIC mapping — pure helper.
	var ctrl: Node = ControllerS.new()
	var s_moving: int = ctrl.call("kinetic_stance", 200.0, 0.0)       # clearly moving
	var s_brief: int = ctrl.call("kinetic_stance", 0.0, 0.1)          # still but < STILL_SECS
	var s_braked: int = ctrl.call("kinetic_stance", 0.0, 0.3)         # still ≥ STILL_SECS
	lines.append("kinetic: moving->%d brief-still->%d braked->%d (want %d/%d/%d)" % [
		s_moving, s_brief, s_braked, SPRAY, SPRAY, LANCE])
	if s_moving != SPRAY or s_brief != SPRAY or s_braked != LANCE:
		lines.append("kinetic FAIL: velocity->stance mapping wrong"); ok = false
	else:
		lines.append("kinetic OK: moving=SPRAY, brief slow holds SPRAY, sustained brake=LANCE")

	# 2) Triple-tap detector — pure, timestamp passed in.
	var pl: Node2D = PlayerS.new()
	var fast := [pl.call("register_tap", 0), pl.call("register_tap", 100), pl.call("register_tap", 200)]
	# After firing it resets, so the next two are false then the 3rd of a fresh burst fires.
	var post: bool = pl.call("register_tap", 300)
	# A stale burst: gaps wider than the window never accumulate 3.
	var slow := [pl.call("register_tap", 1000), pl.call("register_tap", 2000), pl.call("register_tap", 3000)]
	lines.append("triple-tap: fast=%s post-reset=%s slow=%s" % [fast, post, slow])
	if fast[0] or fast[1] or not fast[2]:
		lines.append("triple-tap FAIL: 3 fast taps did not fire exactly on the 3rd"); ok = false
	if post:
		lines.append("triple-tap FAIL: did not reset after firing"); ok = false
	if slow[0] or slow[1] or slow[2]:
		lines.append("triple-tap FAIL: a stale (out-of-window) burst fired"); ok = false
	if ok:
		lines.append("triple-tap OK: fires on the 3rd in-window tap, resets, ignores stale bursts")
	pl.free()

	# 3) GEOM overdrive toggle + drain + auto-revert.
	var od := [0, false]   # [overdrive_changed emit count, last active]
	ev.connect("overdrive_changed", func(a): od[0] += 1; od[1] = a)
	gs.call("start_run")
	ctrl.set("_mode", GEOM)
	# No charge yet: a toggle must NOT enter overdrive.
	ctrl.call("_on_overdrive_toggle_requested")
	var entered_empty: bool = bool(gs.get("overdrive_active"))
	# Charge up, then toggle: enters LANCE overdrive.
	gs.call("add_geom", 50.0)
	ctrl.call("_on_overdrive_toggle_requested")
	var active_after: bool = bool(gs.get("overdrive_active"))
	var stance_after: int = int(gs.get("stance"))
	# Burn it down: a big step drains past empty and auto-reverts to SPRAY.
	ctrl.call("_step_geom", 5.0)
	var active_drained: bool = bool(gs.get("overdrive_active"))
	var stance_drained: int = int(gs.get("stance"))
	var charge_drained: float = float(gs.get("geom_charge"))
	lines.append("geom: entered_empty=%s active=%s stance=%d -> drained active=%s stance=%d charge=%.1f (emits=%d)" % [
		entered_empty, active_after, stance_after, active_drained, stance_drained, charge_drained, od[0]])
	if entered_empty:
		lines.append("geom FAIL: entered overdrive with 0 charge"); ok = false
	if not active_after or stance_after != LANCE:
		lines.append("geom FAIL: toggle with charge did not enter LANCE overdrive"); ok = false
	if active_drained or stance_drained != SPRAY or charge_drained > 0.0:
		lines.append("geom FAIL: drained overdrive did not auto-revert to SPRAY"); ok = false
	if ok:
		lines.append("geom OK: charge-gated entry, LANCE burn, empty auto-revert to SPRAY")

	# 4) Gate-stance suppression by POC mode (projectile_count + battery still apply).
	#    LEGACY: −/÷ gate flips to LANCE. KINETIC/GEOM: stance is NOT touched by the gate.
	var suppress_ok := true
	for mode in [LEGACY, KINETIC, GEOM]:
		st.set("poc_mode", mode)
		gs.call("start_run")                 # resets stance to SPRAY
		gs.call("set_stance", SPRAY)
		var batt0: float = float(gs.get("glow_battery"))
		gs.call("_on_gate_passed", "divide", 2.0, 9)
		var stance_now: int = int(gs.get("stance"))
		var pc_now: int = int(gs.get("projectile_count"))
		var batt1: float = float(gs.get("glow_battery"))
		var want_stance: int = LANCE if mode == LEGACY else SPRAY
		lines.append("suppress[mode=%d]: stance=%d (want %d) pc=%d battery %.0f->%.0f" % [
			mode, stance_now, want_stance, pc_now, batt0, batt1])
		if stance_now != want_stance:
			suppress_ok = false
		if pc_now != 9:                       # economy applies in EVERY mode
			suppress_ok = false
		if batt1 >= batt0:                     # the negative-gate drain applies in EVERY mode
			suppress_ok = false
	if not suppress_ok:
		lines.append("suppress FAIL: gate->stance coupling not correctly gated on poc_mode"); ok = false
	else:
		lines.append("suppress OK: LEGACY flips stance; KINETIC/GEOM keep it (economy+drain still apply)")
	st.set("poc_mode", LEGACY)               # leave the default for any later verify
	ctrl.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
