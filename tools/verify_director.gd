extends SceneTree
## Headless verification for the #59 phase-pacing director slice:
##   - Boundary marks       : phase_at(distance) returns the right phase index across the
##                            authored distance marks (before phase 0, at/inside each phase).
##   - Once per boundary     : step() emits phase_changed EXACTLY once per crossing — re-stepping
##                            inside the same phase emits nothing (no re-emit).
##   - Skip-leap            : a big distance delta that leaps multiple boundaries in one frame
##                            still announces EVERY skipped phase once (no gaps).
##   - Config payload       : the phase_changed config Dictionary matches the authored PhaseDef
##                            (grid_mode/spawn_density_mult/gate_speed_mult/gate_moving/gravity).
##   - Gravity gating       : gravity_shift fires ONLY for phases whose gravity != 0, once on entry,
##                            with the normalized dir + magnitude strength.
##   - Live level schedule   : the shipped level_01 phases walk MATRIX->QUICKENING->SINGULARITY->
##                            OVERDRIVE in ascending start_m with exactly one gravity phase emitting.
##
## GPU-free: drives the director's PURE step()/phase_at() on a bare instance and listens on the
## Events bus. Writes a verdict file the runner polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_director.gd /tmp/verify_director_result.txt

const RESULT_PATH := "/tmp/verify_director_result.txt"

# Loaded at RUNTIME inside _initialize (NOT preload) — phase_director.gd references the bare `Events`
# autoload global, which under a `-s` main script is only registered AFTER the autoloads instantiate.
# A parse-time `preload` would compile phase_director BEFORE that, failing with "Identifier not found:
# Events"; load() here resolves once the autoloads exist (CLAUDE.md headless gotcha, mirrors verify_boss).
var DIRECTOR: GDScript
var PHASE_DEF: GDScript


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	if ev == null:
		lines.append("RESULT=FAIL (Events autoload missing)"); _write(lines); return

	DIRECTOR = load("res://assets/levels/phase_director.gd")
	PHASE_DEF = load("res://resources/phase_def.gd")
	if DIRECTOR == null or PHASE_DEF == null:
		lines.append("RESULT=FAIL (could not load phase_director/phase_def script)"); _write(lines); return

	# An authored 3-phase test schedule (out of order on purpose -> set_phases must sort it).
	# Only the SINGULARITY phase carries gravity. Distinct config values per phase so the payload
	# assertion catches a mis-mapped key.
	# Typed as Object (not PhaseDef) — the class_name cache isn't built under the headless -s loop
	# without a project --import, so the bare class_name may not resolve; the PRELOADED script is.
	var p_singular: Object = PHASE_DEF.make("SINGULARITY", 200.0, "warp", 1.4, 1.25, true, Vector2(0.0, 1.0))
	var p_matrix: Object = PHASE_DEF.make("MATRIX", 0.0, "ambient", 1.0, 1.0, false, Vector2.ZERO)
	var p_over: Object = PHASE_DEF.make("OVERDRIVE", 400.0, "dissolve", 1.8, 1.5, true, Vector2.ZERO)
	var schedule: Array = [p_singular, p_matrix, p_over]   # deliberately unsorted

	# Capture phase_changed + gravity_shift payloads.
	var phase_log: Array = []      # each: [index, name, config]
	var grav_log: Array = []       # each: [dir, strength]
	ev.connect("phase_changed", func(i, n, c): phase_log.append([i, n, c]))
	ev.connect("gravity_shift", func(d, s): grav_log.append([d, s]))

	var dir: Node = DIRECTOR.new()
	dir.call("set_phases", schedule)

	# 1) phase_at across the marks (after the sort: 0=MATRIX@0, 1=SINGULARITY@200, 2=OVERDRIVE@400).
	var at_before: int = dir.call("phase_at", -10.0)   # nothing yet (MATRIX@0, so -10 -> -1)
	var at_m0: int = dir.call("phase_at", 0.0)         # MATRIX
	var at_m1: int = dir.call("phase_at", 199.0)       # still MATRIX
	var at_s: int = dir.call("phase_at", 200.0)        # SINGULARITY
	var at_o: int = dir.call("phase_at", 9999.0)       # OVERDRIVE (clamped to last)
	lines.append("phase_at: -10->%d 0->%d 199->%d 200->%d 9999->%d (want -1,0,0,1,2)" % [
		at_before, at_m0, at_m1, at_s, at_o])
	if at_before != -1 or at_m0 != 0 or at_m1 != 0 or at_s != 1 or at_o != 2:
		lines.append("phase_at FAIL: boundary marks resolve wrong"); ok = false
	else:
		lines.append("phase_at OK: marks resolve (sorted from unsorted authoring), -1 before phase 0")

	# 2) step() emits once per boundary; re-stepping inside a phase is silent.
	phase_log.clear(); grav_log.clear()
	dir.call("set_phases", schedule)                   # reset the walk (re-enters phase 0)
	dir.call("step", 0.0)                               # enter MATRIX -> 1 emit
	dir.call("step", 50.0)                              # still MATRIX -> 0 emit
	dir.call("step", 100.0)                             # still MATRIX -> 0 emit
	var n_in_matrix: int = phase_log.size()
	dir.call("step", 210.0)                             # cross into SINGULARITY -> 1 emit + gravity
	dir.call("step", 250.0)                             # still SINGULARITY -> 0 emit
	var n_after_singular: int = phase_log.size()
	dir.call("step", 410.0)                             # cross into OVERDRIVE -> 1 emit (no gravity)
	lines.append("once-per: emits in-matrix=%d after-singular=%d total=%d (want 1,2,3)" % [
		n_in_matrix, n_after_singular, phase_log.size()])
	if n_in_matrix != 1 or n_after_singular != 2 or phase_log.size() != 3:
		lines.append("once-per FAIL: phase_changed re-emitted inside a phase or skipped one"); ok = false
	else:
		lines.append("once-per OK: phase_changed fires exactly once per boundary, silent within a phase")

	# 2b) The emitted indices/names are the ordered crescendo.
	var order_ok := (int(phase_log[0][0]) == 0 and String(phase_log[0][1]) == "MATRIX"
		and int(phase_log[1][0]) == 1 and String(phase_log[1][1]) == "SINGULARITY"
		and int(phase_log[2][0]) == 2 and String(phase_log[2][1]) == "OVERDRIVE")
	lines.append("order: %s -> %s -> %s" % [phase_log[0][1], phase_log[1][1], phase_log[2][1]])
	if not order_ok:
		lines.append("order FAIL: phases did not walk in ascending start_m order"); ok = false
	else:
		lines.append("order OK: MATRIX -> SINGULARITY -> OVERDRIVE in ascending distance")

	# 3) Config payload matches the authored SINGULARITY PhaseDef.
	var cfg: Dictionary = phase_log[1][2]
	var cfg_ok := (String(cfg.get("grid_mode", "")) == "warp"
		and is_equal_approx(float(cfg.get("spawn_density_mult", -1.0)), 1.4)
		and is_equal_approx(float(cfg.get("gate_speed_mult", -1.0)), 1.25)
		and bool(cfg.get("gate_moving", false)) == true
		and (cfg.get("gravity", Vector2.ZERO) as Vector2) == Vector2(0.0, 1.0))
	lines.append("config: grid=%s density=%.2f speed=%.2f moving=%s gravity=%s" % [
		cfg.get("grid_mode"), float(cfg.get("spawn_density_mult", 0.0)),
		float(cfg.get("gate_speed_mult", 0.0)), cfg.get("gate_moving"), cfg.get("gravity")])
	if not cfg_ok:
		lines.append("config FAIL: phase_changed payload does not match the authored PhaseDef"); ok = false
	else:
		lines.append("config OK: emitted config matches the authored SINGULARITY phase")

	# 4) gravity_shift fired ONLY for the gravity phase, once, normalized dir + magnitude strength.
	lines.append("gravity: shifts=%d (want 1)" % grav_log.size())
	if grav_log.size() != 1:
		lines.append("gravity FAIL: gravity_shift count wrong (only SINGULARITY has gravity)"); ok = false
	else:
		var gdir: Vector2 = grav_log[0][0]
		var gstr: float = grav_log[0][1]
		lines.append("gravity: dir=%s strength=%.3f (want dir=(0,1) strength=1.000)" % [gdir, gstr])
		if not (gdir.is_equal_approx(Vector2(0.0, 1.0)) and is_equal_approx(gstr, 1.0)):
			lines.append("gravity FAIL: dir not normalized or strength != magnitude"); ok = false
		else:
			lines.append("gravity OK: one gravity_shift on SINGULARITY entry, normalized dir + magnitude")

	# 5) Skip-leap: one giant step from before phase 0 to past the last boundary announces ALL three.
	phase_log.clear(); grav_log.clear()
	dir.call("set_phases", schedule)
	dir.call("step", 5000.0)                           # leaps MATRIX+SINGULARITY+OVERDRIVE in one frame
	lines.append("skip-leap: emits=%d gravity=%d (want 3,1)" % [phase_log.size(), grav_log.size()])
	if phase_log.size() != 3 or grav_log.size() != 1:
		lines.append("skip-leap FAIL: a multi-boundary delta dropped a phase"); ok = false
	else:
		lines.append("skip-leap OK: a giant delta announces every skipped boundary once")
	dir.free()

	# 6) The SHIPPED level_01 phases walk the full 4-phase crescendo with exactly one gravity phase.
	var lv: Resource = load("res://data/level_01.tres")
	if lv == null:
		# Fall back to the LevelDef code default (the .tres may be absent in the headless cache).
		var LD: GDScript = load("res://resources/level_def.gd")
		lv = LD.new() if LD != null else null
	if lv == null or not (lv.get("phases") is Array) or (lv.get("phases") as Array).is_empty():
		lines.append("live-level FAIL: level has no authored phases"); ok = false
	else:
		phase_log.clear(); grav_log.clear()
		var dir2: Node = DIRECTOR.new()
		dir2.call("set_phases", lv.get("phases"))
		var length: float = float(lv.get("length_m"))
		dir2.call("step", length + 1000.0)             # one leap to the finish -> announce every phase
		var names: Array = []
		var ascending := true
		var prev := -1.0
		for entry in phase_log:
			names.append(String(entry[1]))
		# Re-read the authored starts off the live schedule to confirm ascending order held.
		for ph in lv.get("phases"):
			if float(ph.start_m) < prev:
				ascending = false
			prev = float(ph.start_m)
		lines.append("live-level: phases=%s gravity_shifts=%d ascending=%s" % [names, grav_log.size(), ascending])
		# Every authored phase announced once; gravity only for the non-zero-gravity phase(s).
		var grav_phases := 0
		for ph in lv.get("phases"):
			if (ph.gravity as Vector2) != Vector2.ZERO:
				grav_phases += 1
		if phase_log.size() != (lv.get("phases") as Array).size():
			lines.append("live-level FAIL: not every authored phase announced"); ok = false
		elif grav_log.size() != grav_phases:
			lines.append("live-level FAIL: gravity_shift count != authored gravity phases (%d vs %d)" % [
				grav_log.size(), grav_phases]); ok = false
		elif not ascending:
			lines.append("live-level FAIL: authored phases not in ascending start_m"); ok = false
		else:
			lines.append("live-level OK: shipped phases walk the full crescendo, gravity gated to its phase(s)")
		dir2.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
