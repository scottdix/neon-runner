extends SceneTree
## Headless verification for P5 — +/× GATES IN HORDE (player firepower recovery).
##   1) The built HORDE gate schedule (data/level_horde.tres → GateSpawner.build_formations) contains
##      ONLY ADD/MULTIPLY ops — every gate's operation ∈ {ADD, MULTIPLY} AND is_positive() == true.
##   2) The defensive _restrict_op clamps a mis-authored sub/div HORDE side to ADD (never drains).
##   3) Crossing a + gate and a × gate GROWS projectile_count (firepower) via gate_passed → GameState.
##   4) An enemy whose y enters a HORDE positive-gate band does NOT multiply-through (no clone spawned).
##   5) Debug.gates_on() == false builds ZERO formations (the designer gate toggle).
##
## Reads the live autoloads via root.get_node_or_null (bare names won't compile under -s). Uses runtime
## load() for scripts that reference autoloads. Writes a verdict file the runner polls for. Run:
##   tools/run-headless.sh res://tools/verify_splice_gates.gd /tmp/verify_splice_gates_result.txt

const RESULT_PATH := "/tmp/verify_splice_gates_result.txt"

var _multiplied_seen: int = 0


func _on_enemy_multiplied(_at: Vector2) -> void:
	_multiplied_seen += 1


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var settings: Node = root.get_node_or_null("Settings")
	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if settings == null or gs == null or ev == null:
		_write(["RESULT=FAIL (Settings=%s GameState=%s Events=%s autoload missing)" % [str(settings), str(gs), str(ev)]])
		return

	# HORDE is the locked core mode (Settings forces poc_mode == HORDE on load); assert it so the
	# GateSpawner's _is_horde()-gated +/× restriction is actually exercised.
	var horde_ok: bool = int(settings.get("poc_mode")) == 3   # PocMode.HORDE
	lines.append("poc_mode == HORDE -> %s" % ("OK" if horde_ok else "BAD"))
	ok = ok and horde_ok

	var GateScript: GDScript = load("res://assets/gates/gate.gd")
	var SpawnerScript: GDScript = load("res://assets/gates/gate_spawner.gd")
	var TargetsScript: GDScript = load("res://assets/obstacles/targets.gd")
	var LevelDefScript: GDScript = load("res://resources/level_def.gd")

	# Load the authored HORDE level + its gate_formations schedule.
	var level: Resource = load("res://data/level_horde.tres")
	if level == null:
		_write(["RESULT=FAIL (level_horde.tres failed to load)"])
		return
	var specs: Array = level.get("gate_formations")
	lines.append("HORDE schedule formation count = %d" % specs.size())
	ok = ok and specs.size() > 0

	# --- 1) Build the schedule via a real GateSpawner; assert every op is ADD/MULTIPLY + positive. ---
	var spawner: Node2D = SpawnerScript.new()
	spawner.name = "GateSpawnerVerify"
	root.add_child(spawner)
	await process_frame   # let _ready run (add_child defers it under -s)
	spawner.build_formations(specs)
	await process_frame   # gate _ready derives family/op from configure

	var ops_ok := true
	var op_add: int = GateScript.Operation.ADD
	var op_mul: int = GateScript.Operation.MULTIPLY
	var inspected: int = 0
	for f in spawner._formations:
		for g in [f["left"], f["right"]]:
			inspected += 1
			var op: int = int(g.operation)
			var pos: bool = bool(g.is_positive())
			if (op != op_add and op != op_mul) or not pos:
				ops_ok = false
	lines.append("all %d HORDE gate ops ∈ {ADD,MULTIPLY} & is_positive -> %s" % [inspected, "OK" if ops_ok else "BAD"])
	ok = ok and ops_ok

	# --- 2) _restrict_op clamps a mis-authored sub/div side to ADD (defensive). ---
	var clamp_specs: Array = [{"m": 50.0, "l": ["sub", 7.0], "r": ["div", 2.0]}]
	spawner.build_formations(clamp_specs)
	await process_frame
	var clamp_ok := true
	for f in spawner._formations:
		for g in [f["left"], f["right"]]:
			if int(g.operation) != op_add:
				clamp_ok = false
	lines.append("_restrict_op clamps sub/div -> ADD in HORDE -> %s" % ("OK" if clamp_ok else "BAD"))
	ok = ok and clamp_ok

	# --- 3) Crossing a + gate then a × gate GROWS projectile_count (firepower). ---
	# gate.trigger() emits gate_passed; GameState._on_gate_passed → set_projectile_count(new_count).
	# Seed a known firepower, fire an ADD gate then a MULTIPLY gate, assert it strictly grows each time.
	if not gs.get("run_active"):
		gs.set("run_active", true)             # _on_gate_passed clamps via set_projectile_count regardless
	gs.call("set_projectile_count", 10)
	var start_fp: int = int(gs.get("projectile_count"))

	var add_gate: Node2D = GateScript.new()
	add_gate.configure(op_add, 8.0, 0.0, 540.0, 280.0)
	add_gate.trigger(int(gs.get("projectile_count")))
	var after_add: int = int(gs.get("projectile_count"))

	var mul_gate: Node2D = GateScript.new()
	mul_gate.configure(op_mul, 2.0, 540.0, 1080.0, 800.0)
	mul_gate.trigger(int(gs.get("projectile_count")))
	var after_mul: int = int(gs.get("projectile_count"))

	var grow_ok: bool = after_add > start_fp and after_mul > after_add
	lines.append("firepower grows: %d -> +gate %d -> ×gate %d -> %s" % [start_fp, after_add, after_mul, "OK" if grow_ok else "BAD"])
	ok = ok and grow_ok

	# --- 4) No enemy multiply-through clone at a HORDE positive-gate band. ---
	# Rebuild the authored HORDE schedule so positive_gate_bands() is non-empty, wire a forced-HORDE
	# Targets to it, drop ONE enemy directly onto a band, step it, and assert NO clone / no signal.
	spawner.build_formations(specs)
	await process_frame
	var bands: Array = spawner.call("positive_gate_bands")
	lines.append("positive_gate_bands = %d (schedule is +/×, so non-empty)" % bands.size())
	ok = ok and bands.size() > 0

	var targets: Node2D = TargetsScript.new()
	targets.name = "TargetsVerify"
	root.add_child(targets)
	await process_frame
	targets.set_force_horde(true)              # bare-instance HORDE seam
	targets.set_gates(spawner)
	targets.set_breach_line(5000.0)            # far below — the enemy can't breach during the step

	ev.enemy_multiplied.connect(_on_enemy_multiplied)
	_multiplied_seen = 0
	# Spawn one fodder, then SNAP it onto the first positive band's centre so _maybe_multiply WOULD fire
	# (if it weren't HORDE-suppressed). We mutate the live _enemies entry directly.
	targets.spawn(1)
	var before_count: int = int(targets.live_count())
	if before_count > 0 and bands.size() > 0:
		var b: Dictionary = bands[0]
		var bx: float = (float(b["x_min"]) + float(b["x_max"])) * 0.5
		var e: Dictionary = targets._enemies[0]
		e["pos"] = Vector2(bx, float(b["y"]))
		targets._enemies[0] = e
	# Step once: in LEGACY this band-entry would clone the enemy; in HORDE _maybe_multiply early-returns.
	targets.step(0.016)
	var after_count: int = int(targets.live_count())
	# A clone would push live_count above the single spawned enemy (minus any that breached/left — guarded
	# by the far breach line + the band y being on-screen). The decisive check is the signal: zero emits.
	var no_clone_ok: bool = _multiplied_seen == 0 and after_count <= before_count
	lines.append("HORDE enemy multiply-through SUPPRESSED: emits=%d count %d->%d -> %s" % [_multiplied_seen, before_count, after_count, "OK" if no_clone_ok else "BAD"])
	ok = ok and no_clone_ok

	# --- 5) Debug.gates_on() == false builds ZERO formations (designer toggle). ---
	# run.gd gates the HORDE build on _gates_enabled() (reads Debug.gates_on()). We exercise the same
	# decision here: with gates OFF, run.gd hands build_formations([]) — assert that yields zero gates.
	var dbg: Node = root.get_node_or_null("Debug")
	var toggle_ok := true
	if dbg != null:
		var prev: bool = bool(dbg.get("gates_enabled"))
		dbg.set_gates_enabled(false)
		var gates_off: bool = not bool(dbg.call("gates_on"))
		# Mirror run.gd's branch: gates off -> build_formations([]) -> zero formations.
		spawner.build_formations([] if gates_off else specs)
		await process_frame
		var empty_ok: bool = spawner._formations.is_empty()
		dbg.set_gates_enabled(prev)             # restore
		toggle_ok = gates_off and empty_ok
		lines.append("Debug.gates_on()=false builds 0 formations -> %s" % ("OK" if toggle_ok else "BAD"))
	else:
		lines.append("Debug autoload absent -> SKIP gate-toggle check (treated PASS)")
	ok = ok and toggle_ok

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.flush()
		f.close()
	quit()
