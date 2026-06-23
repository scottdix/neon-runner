extends SceneTree
## Headless INTEGRATION smoke for the Run scene. The verify_run/verify_combat scripts
## drive each system's pure step() in isolation; this instantiates the real
## res://assets/levels/run.tscn and runs it for a stretch of frames, so the paths
## those skip — _ready (MultiMesh build, texture gen), _process, and _render (per-frame
## instance writes) — actually execute. Catches GDScript runtime errors in the wiring
## that logic tests can't (e.g. a bad key in _render, a type slip in the HUD).
##
## Headless has a dummy renderer: MultiMesh/Image data ops run fine without a GPU (the
## bloom itself can't be judged here — that's the device's job, #47). We only assert the
## scene comes up, ticks without erroring, and reaches a sane live state.
##
##   tools/run-headless.sh res://tools/verify_scene.gd /tmp/verify_scene_result.txt
##
## NOTE: under `-s`, autoload _ready is deferred, so we wire GameState's gate bus by
## hand first (the engine does this itself in a normal launch).

const RESULT_PATH := "/tmp/verify_scene_result.txt"
const SCENE := "res://assets/levels/run.tscn"
const RUN_FRAMES := 420            # long enough that distance passes the first enemy wave (18 m)
                                   # so the wave spawn + enemy _render path actually runs here

var _scene: Node = null
var _frame := 0
var _lines: Array[String] = []


func _initialize() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.call("wire_events")
	var packed: Variant = load(SCENE)
	if packed == null:
		_lines.append("scene load FAIL: %s did not load" % SCENE)
		_lines.append("RESULT=FAIL"); _write(); return
	_scene = packed.instantiate()
	if _scene == null:
		_lines.append("instantiate FAIL: %s" % SCENE)
		_lines.append("RESULT=FAIL"); _write(); return
	root.add_child(_scene)
	_lines.append("scene up: %s instantiated + added" % SCENE)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < RUN_FRAMES:
		return false                # keep ticking _ready/_process/_render on all nodes

	var ok := true
	var gs: Node = root.get_node_or_null("GameState")
	var fleet: Node = _scene.get_node_or_null("Fleet")
	var targets: Node = _scene.get_node_or_null("Targets")
	var player: Node = _scene.get_node_or_null("Player")

	_lines.append("nodes: Player=%s Fleet=%s Targets=%s" % [player != null, fleet != null, targets != null])
	if player == null or fleet == null or targets == null:
		_lines.append("node FAIL: run scene missing a core child"); ok = false

	if gs != null:
		_lines.append("state: run_active=%s swarm=%d score=%d battery=%.0f distance=%.1f" % [
			gs.get("run_active"), gs.get("projectile_count"), gs.get("score"),
			gs.get("glow_battery"), gs.get("distance")])
		if not gs.get("run_active"):
			_lines.append("state FAIL: run ended within the smoke window (unexpected)"); ok = false
		if float(gs.get("distance")) <= 0.0:
			_lines.append("scroll FAIL: distance did not advance over %d frames" % RUN_FRAMES); ok = false

	if fleet != null:
		var live: int = fleet.call("live_count")
		_lines.append("fleet: live bullets=%d" % live)
		if live <= 0:
			_lines.append("fleet FAIL: no live bullets after warmup"); ok = false

	if targets != null:
		var ec: int = targets.call("live_count")
		var waves: int = targets.call("scheduled_wave_count")
		_lines.append("targets: live enemies=%d kills=%d scheduled_waves=%d" % [
			ec, targets.get("kills"), waves])
		# Enemies are SCHEDULED (#13) — they may not have spawned yet at the smoke
		# distance, so assert the wave schedule was wired from the level, not a live count.
		if waves <= 0:
			_lines.append("targets FAIL: enemy wave schedule not wired from the level"); ok = false

	_lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write()
	return true


func _write() -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	quit()
