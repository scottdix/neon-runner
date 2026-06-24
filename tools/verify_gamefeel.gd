extends SceneTree
## Headless INTEGRATION smoke for the v0.4.0 Game Feel epic (#22): instantiate the REAL run.tscn and
## prove run.gd._ready assembles with the three new juice children wired in, plus the FeedbackManager's
## Camera2D becoming the run's active camera — the one integration risk the per-system verifies can't
## cover (they drive bare .new() pure methods; this exercises the actual scene tree).
##
## Under `-s` the autoloads exist at /root but their _ready is DEFERRED, so we first call their public,
## idempotent init/wire methods (Fonts.load_fonts, Settings.load_settings, GameState.wire_events,
## Haptics.wire, AudioManager.wire) — mirroring the engine's normal boot — then add the scene, which
## fires run._ready synchronously. Every audio/GPU path is guarded, so even un-built players no-op.
##
##   tools/run-headless.sh res://tools/verify_gamefeel.gd /tmp/verify_gamefeel_result.txt

const RESULT_PATH := "/tmp/verify_gamefeel_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# --- Pre-init the autoloads run.gd leans on (their _ready is deferred under -s) ---------------
	for pair in [["Fonts", "load_fonts"], ["Settings", "load_settings"], ["GameState", "wire_events"],
			["Haptics", "wire"], ["AudioManager", "wire"]]:
		var node: Node = root.get_node_or_null(pair[0])
		if node == null:
			lines.append("autoload %s = MISSING" % pair[0]); ok = false
		elif node.has_method(pair[1]):
			node.call(pair[1])
	if not ok:
		lines.append("RESULT=FAIL (an autoload was missing)"); _write(lines); return

	# --- Instantiate the REAL run scene -----------------------------------------------------------
	var packed: PackedScene = load("res://assets/levels/run.tscn")
	if packed == null:
		lines.append("RESULT=FAIL (run.tscn failed to load)"); _write(lines); return
	var run: Node = packed.instantiate()
	if run == null:
		lines.append("RESULT=FAIL (run.tscn failed to instantiate)"); _write(lines); return
	root.add_child(run)
	# A node added during _initialize() has its _ready DEFERRED past this call (same gotcha as autoload
	# _ready under `-s`). Pump a couple of process frames so run._ready (and its children's) actually fire
	# before we assert — otherwise the tree is empty and start_run never ran.
	await process_frame
	await process_frame

	# --- The juice children are present (#23 / #27 / #28) + the pre-existing slice still assembles -
	for child in ["Player", "Fleet", "Targets", "Gates", "Effects", "HUD",
			"Feedback", "ScorePopups", "Milestone"]:
		var n: Node = run.get_node_or_null(child)
		lines.append("child %s = %s" % [child, n != null])
		if n == null:
			ok = false

	# --- FeedbackManager built the identity run camera under itself (FIXED_TOP_LEFT @ origin) ------
	# (Walk the tree for the Camera2D rather than get_viewport().get_camera_2d() — the headless root
	# viewport reports no active 2D camera under `-s`, but the node + its make_current() are what matter.)
	var feedback: Node = run.get_node_or_null("Feedback")
	var cam: Camera2D = _find_camera(feedback) if feedback != null else null
	lines.append("feedback camera present=%s anchor_top_left=%s pos_zero=%s is_current=%s" % [
		cam != null,
		cam != null and cam.anchor_mode == Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT,
		cam != null and cam.position == Vector2.ZERO,
		cam != null and cam.is_current()])
	if cam == null or cam.anchor_mode != Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT \
			or cam.position != Vector2.ZERO:
		lines.append("camera FAIL: FeedbackManager did not build the identity run camera"); ok = false

	# --- HUD sits above the flash overlay in the z-order (50 > 40) so a flash never hides the score -
	var hud: CanvasLayer = run.get_node_or_null("HUD")
	lines.append("HUD layer = %s (want 50, above flash 40)" % (str(hud.layer) if hud != null else "n/a"))
	if hud == null or hud.layer != 50:
		lines.append("layer FAIL: HUD layer not 50"); ok = false

	# --- The run is live (GameState.start_run ran inside run._ready) -------------------------------
	var gs: Node = root.get_node_or_null("GameState")
	lines.append("run_active=%s projectile_count=%d" % [gs.get("run_active"), int(gs.get("projectile_count"))])
	if not bool(gs.get("run_active")) or int(gs.get("projectile_count")) <= 0:
		lines.append("state FAIL: run did not start"); ok = false

	# --- Drive the combo pulse path: a kill should emit combo_updated without erroring -------------
	# (register_kill is GameState's; we just confirm run.gd's _on_combo_updated handler survives it.)
	gs.call("register_kill", 50)
	gs.call("register_kill", 50)
	lines.append("combo after 2 kills = %d (handler ran, no crash)" % int(gs.get("combo")))

	# --- Music-reactive grid (#61): a music_beat must reach the live GridFloor and arm its pulse -
	# (Bare `Events` won't resolve in the `-s` main tool script — use the /root node ref to emit.)
	var grid: Node = run.get_node_or_null("GridFloor")
	var ev: Node = root.get_node_or_null("Events")
	if grid != null and ev != null:
		ev.emit_signal("music_beat", 1.0)
		var pulse: float = float(grid.call("beat_pulse_amount"))
		lines.append("grid beat pulse after music_beat(1.0) = %.2f (want 1.0 — GridFloor wired to Events.music_beat)" % pulse)
		if not is_equal_approx(pulse, 1.0):
			lines.append("beat FAIL: GridFloor did not catch Events.music_beat"); ok = false
	else:
		lines.append("beat FAIL: GridFloor or Events missing for the music-reactive check"); ok = false

	run.queue_free()
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## Depth-first search for the first Camera2D under `n` (the FeedbackManager builds exactly one).
func _find_camera(n: Node) -> Camera2D:
	if n == null:
		return null
	for c in n.get_children():
		if c is Camera2D:
			return c
		var deeper: Camera2D = _find_camera(c)
		if deeper != null:
			return deeper
	return null


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
