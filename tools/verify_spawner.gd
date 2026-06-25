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
	var FAM = GateS.Family       # Gate.Family enum (#86/#88): SPRAY_AUG, LANCE_AUG, GEOM, UTILITY, DEVIL

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

	# 7) STANCE-BASED POOL FILTER (#88): the UNIVERSAL families (GEOM, UTILITY) are ALWAYS built and
	#    NEVER pool_filtered, regardless of the run's stance allegiance. The allegiance is derived from
	#    the LOCKED-IN Settings.poc_mode (NOT the live stance, which start_run resets to SPRAY), so to get
	#    a LANCE allegiance — under which a SPRAY_AUG math gate WOULD be off-allegiance — we set poc_mode to
	#    GEOM_OVERDRIVE (the LANCE-overdrive run) before build, then restore it. This mirrors the real
	#    start_run()->build_formations sequence (no fake set_stance injection the game never performs).
	var settings: Node = root.get_node_or_null("Settings")
	var prev_poc: int = int(settings.get("poc_mode")) if settings != null else 0
	if settings != null:
		settings.set("poc_mode", 2)                       # 2 == Settings.PocMode.GEOM_OVERDRIVE -> LANCE allegiance
	gs.call("start_run")
	var sp_u: Node2D = SpawnerS.new()
	sp_u.call("setup", 1680.0)
	# A formation whose LEFT side is a universal GEOM effect gate and RIGHT a universal UTILITY effect gate.
	sp_u.call("build_formations", [
		{"m": 30.0,
			"l": ["fx", {"effect": "geom_cache", "params": {}, "family": FAM.GEOM}],
			"r": ["fx", {"effect": "util_pickup", "params": {}, "family": FAM.UTILITY}]},
	])
	var uforms: Array = sp_u.get("_formations")
	var uni_built: bool = uforms.size() == 1
	if not uni_built:
		lines.append("universal FAIL: build_formations did not build the universal pair"); ok = false
		lines.append("RESULT=FAIL"); _write(lines); return
	var ul: Node2D = uforms[0]["left"]
	var ur: Node2D = uforms[0]["right"]
	var uni_fam_ok: bool = uni_built \
		and int(ul.get("family")) == int(FAM.GEOM) \
		and int(ur.get("family")) == int(FAM.UTILITY)
	var uni_not_filtered: bool = uni_built and not bool(ul.get("pool_filtered")) and not bool(ur.get("pool_filtered"))
	# The pool-filter's own off-allegiance predicate must treat GEOM + UTILITY as NEVER off-allegiance,
	# even though the run is built around LANCE (so a SPRAY_AUG gate WOULD be off-allegiance).
	var uni_eligible: bool = not bool(sp_u.call("_gate_off_allegiance", ul)) and not bool(sp_u.call("_gate_off_allegiance", ur))
	lines.append("universal: built=%s fam(geom=%d,util=%d) ok=%s not_filtered=%s off_alleg=%s" % [
		uni_built, int(FAM.GEOM), int(FAM.UTILITY), uni_fam_ok, uni_not_filtered, not uni_eligible])
	if not (uni_built and uni_fam_ok and uni_not_filtered and uni_eligible):
		lines.append("universal FAIL: GEOM/UTILITY not built/eligible regardless of stance (#88)"); ok = false
	else:
		lines.append("universal OK: GEOM + UTILITY always build, never off-allegiance, never pool_filtered")
	sp_u.free()
	if settings != null:
		settings.set("poc_mode", prev_poc)                # restore the locked-in mode (SPRAY allegiance for #8)

	# 8) WRONG-STANCE GHOSTING (#86) via the spawner's _gate_ghosted(gate, stance). Off-stance STANCE gates
	#    are flagged ghosted; the on-stance one and the UNIVERSAL families are NOT. Build a SPRAY-allegiance
	#    run with a math split (add->SPRAY_AUG, sub->LANCE_AUG) plus the universal gates from (7), then read
	#    ghosting under a LANCE live stance: SPRAY_AUG dims (off-stance), LANCE_AUG/GEOM/UTILITY don't.
	gs.call("start_run")                                   # stance -> SPRAY (allegiance = SPRAY)
	var sp_g: Node2D = SpawnerS.new()
	sp_g.call("setup", 1680.0)
	# Add the spawner to the tree (mirrors production) so build_formations' add_child(left/right) enters
	# the gates into the tree and runs their _ready SYNCHRONOUSLY — which is what derives a math gate's
	# `family` from its op. await one frame first so the spawner's own _ready has run. (The documented
	# '_ready is deferred under -s' gotcha: a detached spawner never enters the tree, so the gates' family
	# would stay the default 0 / SPRAY_AUG and the fam_axis assertion below would spuriously fail.)
	root.add_child(sp_g)
	await process_frame
	sp_g.call("build_formations", [
		{"m": 30.0, "l": ["add", 5.0], "r": ["sub", 3.0]},
	])
	var gforms: Array = sp_g.get("_formations")
	var spray_aug: Node2D = gforms[0]["left"]              # add -> SPRAY_AUG
	var lance_aug: Node2D = gforms[0]["right"]             # sub -> LANCE_AUG
	# The run allegiance is SPRAY, so the LANCE_AUG (sub) gate is OFF-allegiance and the pool filter may
	# have pre-ghosted it (sticky pool_filtered). Clear that mark here so the FAMILY-axis ghosting checks
	# below test the pure stance<->family logic; the sticky behaviour is exercised explicitly at the end.
	lance_aug.set("pool_filtered", false)
	# Family derivation sanity (add->SPRAY_AUG, sub->LANCE_AUG) so the ghosting axis is grounded.
	var fam_ax_ok: bool = int(spray_aug.get("family")) == int(FAM.SPRAY_AUG) and int(lance_aug.get("family")) == int(FAM.LANCE_AUG)
	# Under a LANCE live stance: SPRAY_AUG mismatches -> ghosted; LANCE_AUG matches -> not.
	var lance_live: int = 1                                 # Stance.LANCE
	var spray_aug_ghost: bool = sp_g.call("_gate_ghosted", spray_aug, lance_live)
	var lance_aug_ghost: bool = sp_g.call("_gate_ghosted", lance_aug, lance_live)
	# Universal gates from a fresh build never ghost under EITHER live stance.
	var geom_g: Node2D = GateS.new()
	geom_g.call("configure_effect", "geom_cache", {}, int(FAM.GEOM))
	var util_g: Node2D = GateS.new()
	util_g.call("configure_effect", "util_pickup", {}, int(FAM.UTILITY))
	var spray_live: int = 0                                 # Stance.SPRAY
	var uni_never_ghost: bool = not sp_g.call("_gate_ghosted", geom_g, lance_live) \
		and not sp_g.call("_gate_ghosted", geom_g, spray_live) \
		and not sp_g.call("_gate_ghosted", util_g, lance_live) \
		and not sp_g.call("_gate_ghosted", util_g, spray_live)
	lines.append("ghosting: fam_axis=%s sprayAUG@LANCE=%s(want true) lanceAUG@LANCE=%s(want false) universal_never=%s" % [
		fam_ax_ok, spray_aug_ghost, lance_aug_ghost, uni_never_ghost])
	if not fam_ax_ok:
		lines.append("ghosting FAIL: add/sub did not derive SPRAY_AUG/LANCE_AUG families"); ok = false
	if not spray_aug_ghost:
		lines.append("ghosting FAIL: off-stance SPRAY_AUG gate not flagged ghosted under LANCE"); ok = false
	if lance_aug_ghost:
		lines.append("ghosting FAIL: on-stance LANCE_AUG gate was ghosted under LANCE"); ok = false
	if not uni_never_ghost:
		lines.append("ghosting FAIL: a universal GEOM/UTILITY gate ghosted (must never dim)"); ok = false
	# A STICKY pool_filtered gate stays ghosted no matter the live stance (the #88 sticky-mark OR).
	lance_aug.set("pool_filtered", true)
	var sticky_ok: bool = sp_g.call("_gate_ghosted", lance_aug, lance_live)   # on-stance but pool_filtered -> still ghosted
	if not sticky_ok:
		lines.append("ghosting FAIL: a pool_filtered gate did not stay ghosted (sticky mark lost)"); ok = false
	if ok or (fam_ax_ok and spray_aug_ghost and not lance_aug_ghost):
		lines.append("ghosting OK: off-stance dims, on-stance/universal don't, pool_filtered stays sticky")
	geom_g.free()
	util_g.free()
	sp_g.free()

	# 9) GAUNTLET spawn_split (#86) still builds a lane-split formation AND fires the lane the ship is in.
	#    spawn_split APPENDS one ad-hoc formation (no schedule clear); scrolling it past the line must fire
	#    exactly the side whose lane the ship occupies (left lane here) via the same trigger() -> gate_passed
	#    path the authored gates use. Fresh spawner so triggers/recycled start at 0.
	gs.call("start_run")
	var sp_gl: Node2D = SpawnerS.new()
	sp_gl.call("setup", 1680.0)
	sp_gl.call("spawn_split", 30.0, "add", 7.0, "div", 2.0)
	var glforms: Array = sp_gl.get("_formations")
	var gl_built: bool = glforms.size() == 1
	if not gl_built:
		lines.append("gauntlet FAIL: spawn_split did not append a formation"); ok = false
		lines.append("RESULT=FAIL"); _write(lines); return
	var gl_left: Node2D = glforms[0]["left"]
	var gl_ops_ok: bool = gl_built \
		and int(gl_left.get("operation")) == O.ADD \
		and int(glforms[0]["right"].get("operation")) == O.DIVIDE
	# Ship parked in the LEFT lane (x=280 < LANE_SPLIT 540); scroll the formation past the line.
	sp_gl.call("update", 20.0, 280.0)                      # @30m above the line — kept, not fired
	var gl_before: int = int(sp_gl.get("triggers"))
	sp_gl.call("update", 50.0, 280.0)                      # @30m past the line — left gate fires
	var gl_after: int = int(sp_gl.get("triggers"))
	var gl_left_fired: bool = bool(gl_left.get("has_been_triggered"))
	lines.append("gauntlet: built=%s ops_ok=%s triggers %d->%d left_fired=%s" % [
		gl_built, gl_ops_ok, gl_before, gl_after, gl_left_fired])
	if not (gl_built and gl_ops_ok):
		lines.append("gauntlet FAIL: spawn_split did not build a lane-split formation with the right ops"); ok = false
	if gl_before != 0 or gl_after != 1 or not gl_left_fired:
		lines.append("gauntlet FAIL: the gauntlet lane gate did not fire as it crossed the line"); ok = false
	if gl_built and gl_ops_ok and gl_after == 1 and gl_left_fired:
		lines.append("gauntlet OK: spawn_split builds + fires the lane the ship is committed to")
	sp_gl.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
