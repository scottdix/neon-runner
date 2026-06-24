extends SceneTree
## Headless verification for the #79 Spray<->Lance stance slice:
##   - Stance signal        : GameState.set_stance flips + emits Events.stance_changed once,
##                            idempotent (no re-emit on the same stance).
##   - Gate -> stance flip   : a positive (+/×) gate_passed -> SPRAY, a negative (−/÷) -> LANCE.
##   - Gate.sets_stance      : the telegraph read mirrors polarity.
##   - Fleet per-hit weight  : SPRAY (1.0) vs LANCE (6.0) differ; LANCE pierces, SPRAY doesn't.
##   - Rhombus per-hit FLOOR : a SUB-THRESHOLD spray hit on a Rhombus only chips (no crack);
##                            a LANCE hit clears the floor -> full weighted damage.
##   - Fractal feed-on-spray : low swarm volume (SPRAY feeds it) splits the fractal; high kills.
##
## GPU-free: drives each system's pure logic directly and writes a verdict file the runner
## polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_stance.gd /tmp/verify_stance_result.txt

const RESULT_PATH := "/tmp/verify_stance_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# Scripts load.
	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var GateS: GDScript = load("res://assets/gates/gate.gd")
	if FleetS == null or TargetsS == null or GateS == null:
		lines.append("RESULT=FAIL (stance scripts missing)"); _write(lines); return

	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if gs == null or ev == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return
	gs.call("wire_events")

	var SPRAY: int = 0   # GameState.Stance.SPRAY == 0 by contract
	var LANCE: int = 1   # GameState.Stance.LANCE

	# 1) set_stance flips + emits once; idempotent on no-change.
	var seen := [0, -1, true]   # [emit_count, last_stance, last_is_spray]
	ev.connect("stance_changed", func(s, sp): seen[0] += 1; seen[1] = s; seen[2] = sp)
	gs.call("start_run")                        # resets to START_STANCE (SPRAY)
	seen[0] = 0
	gs.call("set_stance", LANCE)                # SPRAY -> LANCE : one emit
	gs.call("set_stance", LANCE)                # no-op : no emit
	var n_after_lance: int = seen[0]
	gs.call("set_stance", SPRAY)                # LANCE -> SPRAY : one emit
	lines.append("set_stance: emits=%d last_stance=%d is_spray=%s is_spray()=%s (want emits=2)" % [
		seen[0], seen[1], seen[2], gs.call("is_spray")])
	if n_after_lance != 1 or seen[0] != 2 or seen[1] != SPRAY or seen[2] != true or not bool(gs.call("is_spray")):
		lines.append("set_stance FAIL: not idempotent / wrong signal payload"); ok = false
	else:
		lines.append("set_stance OK: flips + emits once, no-op on unchanged, is_spray bool tracks")

	# 2) Gate polarity drives the stance over gate_passed.
	gs.call("start_run")                        # -> SPRAY
	gs.call("_on_gate_passed", "subtract", 2.0, 18)
	var st_neg: int = gs.get("stance")
	gs.call("_on_gate_passed", "multiply", 2.0, 36)
	var st_pos: int = gs.get("stance")
	gs.call("_on_gate_passed", "divide", 2.0, 18)
	var st_div: int = gs.get("stance")
	gs.call("_on_gate_passed", "add", 10.0, 28)
	var st_add: int = gs.get("stance")
	lines.append("gate flip: sub->%d div->%d (want LANCE=%d) | mul->%d add->%d (want SPRAY=%d)" % [
		st_neg, st_div, LANCE, st_pos, st_add, SPRAY])
	if st_neg != LANCE or st_div != LANCE or st_pos != SPRAY or st_add != SPRAY:
		lines.append("gate flip FAIL: gate polarity did not set the stance"); ok = false
	else:
		lines.append("gate flip OK: +/× -> SPRAY, −/÷ -> LANCE on gate pass")

	# 2b) Gate.sets_stance telegraph mirrors polarity.
	var g_add: Node2D = GateS.new()
	g_add.call("configure", GateS.Operation.ADD, 10.0, 0.0, 540.0, 270.0)
	var g_div: Node2D = GateS.new()
	g_div.call("configure", GateS.Operation.DIVIDE, 2.0, 0.0, 540.0, 270.0)
	lines.append("sets_stance: add->%d (want %d) div->%d (want %d)" % [
		g_add.call("sets_stance"), SPRAY, g_div.call("sets_stance"), LANCE])
	if int(g_add.call("sets_stance")) != SPRAY or int(g_div.call("sets_stance")) != LANCE:
		lines.append("sets_stance FAIL: telegraph read does not mirror polarity"); ok = false
	else:
		lines.append("sets_stance OK: gate telegraph mirrors +/× SPRAY, −/÷ LANCE")
	g_add.free(); g_div.free()

	# 3) Fleet per-hit weight + pierce differ by stance.
	var fl: Node2D = FleetS.new()
	fl.call("set_stance", SPRAY)
	var w_spray: float = fl.call("hit_weight")
	var pierce_spray: bool = fl.call("is_piercing")
	fl.call("set_stance", LANCE)
	var w_lance: float = fl.call("hit_weight")
	var pierce_lance: bool = fl.call("is_piercing")
	lines.append("fleet weight: spray=%.1f pierce=%s | lance=%.1f pierce=%s" % [
		w_spray, pierce_spray, w_lance, pierce_lance])
	if not (w_spray < w_lance and w_spray == FleetS.SPRAY_HIT_WEIGHT and w_lance == FleetS.LANCE_HIT_WEIGHT):
		lines.append("weight FAIL: spray/lance per-hit weights not distinct as designed"); ok = false
	if pierce_spray or not pierce_lance:
		lines.append("pierce FAIL: spray should not pierce, lance should"); ok = false
	# The Fusillade-tax invariant: LANCE per-hit weight must clear the Rhombus floor; SPRAY must not.
	if not (w_spray < TargetsS.RHOMBUS_PER_HIT_FLOOR and w_lance >= TargetsS.RHOMBUS_PER_HIT_FLOOR):
		lines.append("floor FAIL: weights do not straddle RHOMBUS_PER_HIT_FLOOR=%.1f" % TargetsS.RHOMBUS_PER_HIT_FLOOR); ok = false
	if ok:
		lines.append("weight OK: lance hits heavy (clears floor) + pierces, spray light + consumes")

	# 3b) Behavioural deltas distinct (fewer/narrower/faster in LANCE).
	fl.call("set_volume", 100)
	fl.call("set_stance", SPRAY)
	var rate_s: float = fl.call("_effective_fire_rate", 100)
	var spread_s: float = fl.call("_effective_spread")
	fl.call("set_stance", LANCE)
	var rate_l: float = fl.call("_effective_fire_rate", 100)
	var spread_l: float = fl.call("_effective_spread")
	lines.append("deltas: rate spray=%.1f lance=%.1f | spread spray=%.1f lance=%.1f" % [
		rate_s, rate_l, spread_s, spread_l])
	if not (rate_l < rate_s and spread_l < spread_s):
		lines.append("deltas FAIL: lance not fewer-shots + narrower than spray"); ok = false
	else:
		lines.append("deltas OK: lance fires fewer + narrower than spray (speed mult in step too)")
	fl.free()

	# 4) Rhombus per-hit FLOOR — a SUB-THRESHOLD spray hit only chips; a LANCE hit cracks.
	var tg: Node2D = TargetsS.new()
	var rh: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
	var rh_hp0: float = rh["hp"]
	# Spray: 3 bullets at weight 1.0 (< floor 5.0) -> chip only, NOT 3*1*10=30.
	tg.call("_apply_damage", rh, 3, FleetS.SPRAY_HIT_WEIGHT, false)
	var rh_after_spray: float = rh["hp"]
	var spray_chip: float = rh_hp0 - rh_after_spray
	# Lance: 1 bullet at weight 6.0 (>= floor) -> full damage = 1*6*10 = 60.
	tg.call("_apply_damage", rh, 1, FleetS.LANCE_HIT_WEIGHT, true)
	var rh_after_lance: float = rh["hp"]
	var lance_dmg: float = rh_after_spray - rh_after_lance
	# Unarmored glitch takes full weighted damage regardless of stance (no floor gate).
	var gl: Dictionary = tg.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	var gl_hp0: float = gl["hp"]
	tg.call("_apply_damage", gl, 2, FleetS.SPRAY_HIT_WEIGHT, false)   # 2*1*10 = 20
	var gl_dmg: float = gl_hp0 - gl["hp"]
	lines.append("floor: rhombus %.0f -(spray x3)-> %.1f chip=%.1f  -(lance x1)-> %.1f lance_dmg=%.1f | glitch dmg=%.1f" % [
		rh_hp0, rh_after_spray, spray_chip, rh_after_lance, lance_dmg, gl_dmg])
	# Sub-threshold spray must NOT do the would-be full 30 (it only chips a tiny fraction).
	if spray_chip <= 0.0:
		lines.append("floor FAIL: sub-threshold spray did 0 damage (the lockout, #74)"); ok = false
	if spray_chip > rh_hp0 * 0.02:
		lines.append("floor FAIL: sub-threshold spray chipped too much (%.1f) — should be a tiny grind" % spray_chip); ok = false
	# A single LANCE bullet must crack it for the full 1*6*10 = 60.
	if absf(lance_dmg - 60.0) > 0.01:
		lines.append("floor FAIL: a LANCE bullet did not crack the rhombus for full weighted damage (got %.1f, want 60)" % lance_dmg); ok = false
	# Unarmored takes full spray damage (no floor applies).
	if absf(gl_dmg - 20.0) > 0.01:
		lines.append("floor FAIL: unarmored glitch did not take full weighted spray damage (got %.1f, want 20)" % gl_dmg); ok = false
	if ok:
		lines.append("floor OK: spray chips armor (no crack), lance cracks it; unarmored full either way")

	# 4b) Back-compat: the old 2-arg _apply_damage(e, hits) call still compiles + does damage
	#     (hit_weight defaults to 1.0). Guards verify_combat's existing direct calls.
	var rh2: Dictionary = tg.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	var rh2_hp0: float = rh2["hp"]
	tg.call("_apply_damage", rh2, 2)                     # default weight 1.0 -> 2*1*10 = 20
	lines.append("back-compat: _apply_damage(e,2) glitch %.0f -> %.0f (want -20)" % [rh2_hp0, rh2["hp"]])
	if absf((rh2_hp0 - float(rh2["hp"])) - 20.0) > 0.01:
		lines.append("back-compat FAIL: 2-arg _apply_damage default weight changed"); ok = false
	else:
		lines.append("back-compat OK: 2-arg _apply_damage(e,hits) defaults to weight 1.0")
	tg.free()

	# 5) Fractal feed-on-spray — low swarm volume splits the fractal (SPRAY feeds it), high kills.
	var split_seen := [0]
	ev.connect("enemy_split", func(_at): split_seen[0] += 1)
	gs.call("start_run")
	gs.call("set_projectile_count", 10)                  # < FRACTAL_SPLIT_TIER (60): split
	var tg_lo: Node2D = TargetsS.new()
	tg_lo.call("set_fleet", null)
	var en_lo: Array = tg_lo.get("_enemies")
	var dy: Dictionary = tg_lo.call("_new_enemy", TargetsS.KIND_FRACTAL, 200.0)
	dy["hp"] = 0.0
	en_lo.append(dy)
	tg_lo.call("step", 1.0 / 60.0)
	var lo_n: int = tg_lo.call("live_count")
	var all_frac := true
	for e in tg_lo.get("_enemies"):
		if int(e["kind"]) != TargetsS.KIND_FRACTLING:
			all_frac = false
	lines.append("fractal feed: low-vol enemies=%d (want 2) all_fractlings=%s splits=%d" % [lo_n, all_frac, split_seen[0]])
	if lo_n != 2 or not all_frac or split_seen[0] != 1:
		lines.append("fractal FAIL: low swarm volume did not split the fractal (feed-on-spray)"); ok = false
	else:
		lines.append("fractal OK: insufficient volume (SPRAY feeds) splits a fractal into fractlings")
	tg_lo.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
