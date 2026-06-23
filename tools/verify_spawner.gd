extends SceneTree
## Headless verification for the segment-driven spawner (#13): the level's authored
## schedule (LevelDef.gate_formations + enemy_waves) drives BOTH the gate spawner and
## the enemy waves by track_m / world-x, and things recycle past the player.
##
##   - Gate op-string mapping  : "mul"/"add"/"sub"/"div" -> Gate.Operation (LevelDef stays
##                               dependency-free; ops are plain strings).
##   - build_formations(specs) : instantiates the level's formations.
##   - Gate recycle            : a formation that scrolls well past the ship line is freed.
##   - Enemy waves             : spawn when distance reaches `m` (not before), at authored
##                               world-x (spread across the playfield), NOT lane indices.
##   - Finite removal          : killed / offscreen enemies are removed (no respawn).
##
## GPU-free: drives pure logic + writes a verdict file the runner polls for.
##   tools/run-headless.sh res://tools/verify_spawner.gd /tmp/verify_spawner_result.txt

const RESULT_PATH := "/tmp/verify_spawner_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var GateS: GDScript = load("res://assets/gates/gate.gd")
	var SpawnerS: GDScript = load("res://assets/gates/gate_spawner.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var LevelS: GDScript = load("res://resources/level_def.gd")
	for pair in [["gate", GateS], ["spawner", SpawnerS], ["targets", TargetsS], ["leveldef", LevelS]]:
		if pair[1] == null:
			lines.append("load %s = FAIL" % pair[0]); ok = false
	if not ok:
		lines.append("RESULT=FAIL (scripts missing)"); _write(lines); return

	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		lines.append("RESULT=FAIL (GameState autoload missing)"); _write(lines); return
	gs.call("wire_events")

	var O = GateS.Operation

	# 1) Op-string mapping: every authored op string resolves to its Operation.
	var map_ok: bool = GateS.op_from_string("mul") == O.MULTIPLY \
		and GateS.op_from_string("add") == O.ADD \
		and GateS.op_from_string("sub") == O.SUBTRACT \
		and GateS.op_from_string("div") == O.DIVIDE
	lines.append("op-string map: mul/add/sub/div -> %s" % map_ok)
	if not map_ok:
		lines.append("op-string FAIL: a string op did not map to its Operation"); ok = false

	# 2) LevelDef carries an authored schedule (the default the .tres uses).
	var lvl: Resource = load("res://data/level_01.tres")
	var gf: Array = lvl.gate_formations
	var ew: Array = lvl.enemy_waves
	lines.append("schedule on level: %d gate formations, %d enemy waves" % [gf.size(), ew.size()])
	if gf.is_empty() or ew.is_empty():
		lines.append("schedule FAIL: level has no authored gate/enemy schedule"); ok = false

	# 3) build_formations(specs) instantiates with the right ops from string specs.
	var sp: Node2D = SpawnerS.new()
	sp.call("setup", 1680.0)
	sp.call("build_formations", [
		{"m": 30.0, "l": ["mul", 2.0], "r": ["sub", 5.0]},
		{"m": 80.0, "l": ["add", 9.0], "r": ["div", 3.0]},
	])
	var forms: Array = sp.get("_formations")
	var build_ok: bool = forms.size() == 2 \
		and forms[0]["left"].get("operation") == O.MULTIPLY \
		and forms[0]["right"].get("operation") == O.SUBTRACT \
		and forms[1]["left"].get("operation") == O.ADD \
		and forms[1]["right"].get("operation") == O.DIVIDE
	lines.append("build_formations: %d formations, ops mapped=%s" % [forms.size(), build_ok])
	if not build_ok:
		lines.append("build FAIL: formations/ops not built from string specs"); ok = false

	# 4) Recycle: a formation that has triggered and scrolled well past the ship line is
	#    freed and dropped; one still above the line is kept.
	gs.call("start_run")
	sp.call("update", 20.0, 540.0)                 # @30m y=1020 (above line) — kept, not fired
	var before_recycle: int = sp.get("_formations").size()
	sp.call("update", 50.0, 540.0)                 # @30m y=3000 (past bottom) — fired then recycled
	var after_recycle: int = sp.get("_formations").size()
	lines.append("recycle: formations %d -> %d, recycled=%d triggers=%d" % [
		before_recycle, after_recycle, sp.get("recycled"), sp.get("triggers")])
	if before_recycle != 2 or after_recycle != 1 or int(sp.get("recycled")) != 1 or int(sp.get("triggers")) != 1:
		lines.append("recycle FAIL: passed formation not fired-then-freed (or wrong count)"); ok = false
	else:
		lines.append("recycle OK: a passed formation fires once then is freed; the rest stay")
	sp.free()

	# 5) Enemy waves spawn by distance, at world-x — not before the mark, not lane-indexed.
	var tg: Node2D = TargetsS.new()
	tg.call("set_breach_line", 1680.0)
	tg.call("set_schedule", [{"m": 50.0, "kind": "glitch", "count": 4}])
	gs.call("start_run")
	gs.set("distance", 0.0)
	tg.call("step", 1.0 / 60.0)                     # distance 0 < 50 -> no spawn
	var before_wave: int = tg.call("live_count")
	gs.set("distance", 50.0)
	tg.call("step", 1.0 / 60.0)                     # distance reaches 50 -> wave spawns
	var after_wave: int = tg.call("live_count")
	var all_glitch := true
	var min_x := 99999.0
	var max_x := -1.0
	for e in tg.get("_enemies"):
		if int(e["kind"]) != TargetsS.KIND_GLITCH:
			all_glitch = false
		var ex: float = float(e["pos"].x)
		min_x = minf(min_x, ex)
		max_x = maxf(max_x, ex)
	lines.append("waves: before=%d after=%d all_glitch=%s x-span=%.0f (min %.0f max %.0f)" % [
		before_wave, after_wave, all_glitch, max_x - min_x, min_x, max_x])
	if before_wave != 0:
		lines.append("wave FAIL: spawned before reaching its track_m"); ok = false
	if after_wave != 4 or not all_glitch:
		lines.append("wave FAIL: wrong count/kind on spawn at the mark"); ok = false
	if max_x - min_x < 300.0:
		lines.append("wave FAIL: enemies not spread across world-x (lane-clustered?)"); ok = false
	if ok:
		lines.append("waves OK: spawn at the mark, correct kind, spread across world-x")

	# 6) Finite removal: a killed enemy and an offscreen enemy are both removed (no respawn).
	gs.call("start_run")
	var tg2: Node2D = TargetsS.new()
	var en2: Array = tg2.get("_enemies")
	var dead: Dictionary = tg2.call("_new_enemy", TargetsS.KIND_GLITCH, 500.0)
	dead["hp"] = 0.0; dead["pos"] = Vector2(300.0, 500.0); dead["speed"] = 0.0
	en2.append(dead)
	tg2.call("step", 1.0 / 60.0)
	var after_kill: int = tg2.call("live_count")
	var kills_after: int = tg2.get("kills")
	var off: Dictionary = tg2.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	off["hp"] = 40.0; off["pos"] = Vector2(300.0, 2200.0); off["speed"] = 0.0
	tg2.get("_enemies").append(off)
	tg2.call("step", 1.0 / 60.0)
	var after_off: int = tg2.call("live_count")
	lines.append("finite: after_kill live=%d kills=%d, after_offscreen live=%d" % [
		after_kill, kills_after, after_off])
	if after_kill != 0 or kills_after != 1 or after_off != 0:
		lines.append("finite FAIL: killed/offscreen enemy was not removed (respawned?)"); ok = false
	else:
		lines.append("finite OK: killed + offscreen enemies are removed, not respawned")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
