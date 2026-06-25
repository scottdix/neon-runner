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
	# Defer adding the scene to the FIRST _process frame (below), NOT here. Under `-s`,
	# autoload _ready is deferred — Settings._ready calls load_settings(), which FORCES
	# poc_mode = HORDE. If we set LEGACY now it gets clobbered by that deferred _ready before
	# the scene's own _ready (start_run / set_schedule) runs. By the first _process frame all
	# deferred _ready callbacks have fired, so forcing LEGACY there sticks.


func _process(_delta: float) -> bool:
	_frame += 1

	if _scene.get_parent() == null:
		# Force LEGACY before the scene's _ready runs: this smoke asserts the enemy WAVE schedule
		# is wired from the level (scheduled_wave_count > 0). HORDE (the forced default) uses the
		# continuous fodder spawner with an EMPTY enemy_waves, so that assertion only holds on the
		# authored-waves path. Set the global Settings.poc_mode field directly (0 = LEGACY); do NOT
		# call set_poc_mode (it persists). Production reads this same live autoload field. Done here
		# (first frame), after the deferred Settings.load_settings() that would otherwise re-force HORDE.
		var s: Node = root.get_node_or_null("Settings")
		if s != null:
			s.set("poc_mode", 0)
		root.add_child(_scene)
		_lines.append("scene up: %s instantiated + added" % SCENE)
		return false

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

	# ---- LIVE WIRING (#82/#83/#79): these signals once had ZERO consumers in the real scene (the
	# boss HUD + stance indicator were missing live integration). Assert the run scene actually
	# CONNECTS them, so that class of "verified-but-dead" gap can't pass again. We check the live
	# Events autoload's connection list — the scene's _ready must have wired each.
	var ev: Node = root.get_node_or_null("Events")
	if ev != null:
		# #86/#87 added the combat-POC signals; assert the run scene wires each (lane_clamp_changed ->
		# Player, overdrive_toggle_requested -> StanceController, overdrive_changed + geom_changed -> run.gd)
		# so the same "verified-but-dead" class the dead Singularity gravity shipped as can't pass again.
		# gate_effect (the non-arithmetic gate dispatch seam) is consumed by the GameState autoload in
		# wire_events (Events.gate_effect -> _on_gate_effect); _initialize calls wire_events up front, so
		# the live-autoload connection list below sees it — guard it too so the seam can't ship dead.
		for sig in ["boss_spawned", "boss_phase_changed", "stance_changed",
				"lane_clamp_changed", "overdrive_toggle_requested", "overdrive_changed", "geom_changed",
				"gate_effect"]:
			var conns: int = ev.get_signal_connection_list(sig).size()
			_lines.append("wiring: Events.%s connections=%d" % [sig, conns])
			if conns <= 0:
				_lines.append("wiring FAIL: Events.%s has NO consumer in the live run scene" % sig); ok = false
	else:
		_lines.append("wiring FAIL: Events autoload missing"); ok = false

	_lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write()
	return true


func _write() -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	quit()
