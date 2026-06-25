extends SceneTree
## Headless verification for HORDE FIREPOWER-AS-HEALTH (H3):
##   1) A HORDE start_run seeds projectile_count == HORDE_START_FIREPOWER (NOT START_PROJECTILES) and
##      leaves the Glow Battery inert (glow_battery untouched at MAX).
##   2) drain_firepower(streams) removes exactly `streams` of swarm volume (clamped >= 0).
##   3) A Targets._breach in HORDE drains firepower by the enemy's STATS `streams` quantum (GLITCH=1,
##      RHOMBUS=6) — the breach loss channel is firepower, not the battery, in HORDE.
##   4) When firepower reaches 0, fail_run fires (Events.grid_collapsed) and run_active flips false.
##   5) A LEGACY start_run still seeds START_PROJECTILES (prior modes byte-for-byte unchanged).
##
## GPU-free: drives the GameState autoload + a bare new() Targets (no fleet/render). Bare-instance
## autoload rules: get nodes off root; runtime load() the Targets script; type every Dict-lookup local.
##   tools/run-headless.sh res://tools/verify_horde_firepower.gd /tmp/verify_horde_firepower_result.txt

const RESULT_PATH := "/tmp/verify_horde_firepower_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var st: Node = root.get_node_or_null("Settings")
	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if st == null or gs == null or ev == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return

	# GameState's _ready (wire_events) is deferred under -s; call it explicitly (idempotent).
	gs.call("wire_events")

	var HORDE: int = 3
	var start_fp: int = int(gs.get("HORDE_START_FIREPOWER"))
	var start_proj: int = int(gs.get("START_PROJECTILES"))

	# --- 1) HORDE start seeds firepower, battery inert -------------------------
	st.call("set_poc_mode", HORDE)
	gs.call("start_run")
	var fp: int = int(gs.get("projectile_count"))
	lines.append("seed: HORDE start projectile_count=%d (want %d)" % [fp, start_fp])
	if fp != start_fp:
		lines.append("seed FAIL: HORDE did not seed HORDE_START_FIREPOWER"); ok = false
	if start_fp == start_proj:
		lines.append("seed WARN: HORDE_START_FIREPOWER == START_PROJECTILES (no distinction)")
	var batt: float = float(gs.get("glow_battery"))
	var max_batt: float = float(gs.get("MAX_GLOW_BATTERY"))
	lines.append("battery: glow_battery=%.1f (want inert == MAX %.1f)" % [batt, max_batt])
	if not is_equal_approx(batt, max_batt):
		lines.append("battery FAIL: Glow Battery not inert in HORDE"); ok = false

	# --- 2) drain_firepower(streams) removes exactly that many streams ---------
	gs.call("drain_firepower", 5)
	var after: int = int(gs.get("projectile_count"))
	lines.append("drain: after drain_firepower(5) projectile_count=%d (want %d)" % [after, start_fp - 5])
	if after != start_fp - 5:
		lines.append("drain FAIL: wrong quantum removed"); ok = false

	# --- 3) Targets._breach in HORDE drains by the STATS streams quantum -------
	var TargetsScript: GDScript = load("res://assets/obstacles/targets.gd")
	var tg: Node = TargetsScript.new()
	root.add_child(tg)
	await process_frame   # _ready (build_multimesh) is deferred under -s
	tg.call("set_force_horde", true)

	# Reset firepower to a known full seed for a clean breach test.
	gs.call("set_projectile_count", start_fp)
	var before_breach: int = int(gs.get("projectile_count"))
	# GLITCH fodder breach -> streams == 1.
	var glitch: Dictionary = tg.call("_new_enemy", 0, 0.0)   # 0 == KIND_GLITCH
	var glitch_streams: int = int(glitch.get("streams", -1))
	lines.append("stats: GLITCH streams=%d (want 1)" % glitch_streams)
	if glitch_streams != 1:
		lines.append("stats FAIL: GLITCH streams != 1"); ok = false
	tg.call("_breach", glitch)
	var after_glitch: int = int(gs.get("projectile_count"))
	lines.append("breach(glitch): %d -> %d (want -%d)" % [before_breach, after_glitch, glitch_streams])
	if after_glitch != before_breach - glitch_streams:
		lines.append("breach(glitch) FAIL: firepower not dropped by streams"); ok = false

	# RHOMBUS breach -> streams == 6 (a bigger quantum).
	var before_r: int = int(gs.get("projectile_count"))
	var rhom: Dictionary = tg.call("_new_enemy", 1, 0.0)     # 1 == KIND_RHOMBUS
	var rhom_streams: int = int(rhom.get("streams", -1))
	lines.append("stats: RHOMBUS streams=%d (want 6)" % rhom_streams)
	if rhom_streams != 6:
		lines.append("stats FAIL: RHOMBUS streams != 6"); ok = false
	tg.call("_breach", rhom)
	var after_r: int = int(gs.get("projectile_count"))
	lines.append("breach(rhombus): %d -> %d (want -%d)" % [before_r, after_r, rhom_streams])
	if after_r != before_r - rhom_streams:
		lines.append("breach(rhombus) FAIL: firepower not dropped by streams"); ok = false

	# Battery STILL inert after HORDE breaches (drain went to firepower, not the battery).
	var batt2: float = float(gs.get("glow_battery"))
	if not is_equal_approx(batt2, max_batt):
		lines.append("battery FAIL: HORDE breach drained the Glow Battery (should be firepower)"); ok = false

	# --- 4) firepower -> 0 fails the run (Events.grid_collapsed) ---------------
	var collapsed := [false]
	ev.connect("grid_collapsed", func() -> void: collapsed[0] = true)
	# Seed exactly 3, breach a GLITCH (1) twice -> 1 left, then drain_firepower(1) -> 0 -> fail.
	gs.call("set_projectile_count", 3)
	gs.call("drain_firepower", 3)        # straight to 0
	var dead_fp: int = int(gs.get("projectile_count"))
	var active: bool = bool(gs.get("run_active"))
	lines.append("death: projectile_count=%d run_active=%s grid_collapsed=%s" % [dead_fp, str(active), str(collapsed[0])])
	if dead_fp != 0:
		lines.append("death FAIL: firepower did not clamp to 0"); ok = false
	if active:
		lines.append("death FAIL: run still active at 0 firepower"); ok = false
	if not collapsed[0]:
		lines.append("death FAIL: grid_collapsed did not fire at 0 firepower"); ok = false

	# --- 5) LEGACY start still seeds START_PROJECTILES ------------------------
	st.call("set_poc_mode", 0)           # LEGACY
	gs.call("start_run")
	var legacy_fp: int = int(gs.get("projectile_count"))
	lines.append("legacy: LEGACY start projectile_count=%d (want %d)" % [legacy_fp, start_proj])
	if legacy_fp != start_proj:
		lines.append("legacy FAIL: LEGACY seed changed (prior modes broken)"); ok = false

	tg.queue_free()
	# Leave LEGACY persisted so later verifies start from the shipped default.
	st.call("set_poc_mode", 0)
	st.call("save_settings")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
