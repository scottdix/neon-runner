extends SceneTree
## Headless verification for HORDE WIN CONDITION + LEVEL (H5):
##   1) A HORDE start_run loads a level with has_boss == false and a finite survival length_m (>= 480 m,
##      ~60-90 s @ scroll_speed_mps), with EMPTY gate_formations / enemy_waves (the fodder spawner is the
##      loop, not authored splice gates/waves).
##   2) Ticking the run past length_m AUTO-COMPLETES it (because has_boss is false): Events.run_completed
##      fires, run_active flips false, run_won is true, and distance is clamped to length_m.
##   3) A LEGACY start_run still loads the authored boss level (has_boss == true) and does NOT
##      auto-complete on distance (prior modes byte-for-byte unchanged).
##
## GPU-free: drives the GameState + Settings autoloads only (no run scene / fleet / render). Bare-instance
## autoload rules: get nodes off root; type every Dict/Variant local explicitly.
##   tools/run-headless.sh res://tools/verify_horde_win.gd /tmp/verify_horde_win_result.txt

const RESULT_PATH := "/tmp/verify_horde_win_result.txt"


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

	# --- 1) HORDE level: has_boss false, finite survival length, empty schedule ---
	st.call("set_poc_mode", HORDE)
	gs.call("start_run")
	var level: Resource = gs.get("active_level")
	if level == null:
		lines.append("RESULT=FAIL (HORDE active_level null)"); _write(lines); return

	var has_boss: bool = bool(level.get("has_boss"))
	var length_m: float = float(level.get("length_m"))
	var scroll: float = float(level.get("scroll_speed_mps"))
	var survival_s: float = length_m / maxf(scroll, 0.001)
	var formations: Array = level.get("gate_formations")
	var waves: Array = level.get("enemy_waves")
	lines.append("horde level: has_boss=%s length_m=%.1f scroll=%.1f survival=%.1fs gates=%d waves=%d" % [
		str(has_boss), length_m, scroll, survival_s, formations.size(), waves.size()])
	if has_boss:
		lines.append("level FAIL: HORDE level has_boss != false (would never auto-complete)"); ok = false
	if length_m < 480.0:
		lines.append("level FAIL: HORDE length_m too short for ~60-90s survival"); ok = false
	if survival_s < 55.0 or survival_s > 120.0:
		lines.append("level WARN: HORDE survival %.1fs outside ~60-90s target" % survival_s)
	if not formations.is_empty():
		lines.append("level WARN: HORDE gate_formations not empty (sparse expected)")
	if not waves.is_empty():
		lines.append("level WARN: HORDE enemy_waves not empty (fodder spawner is the loop)")

	# --- 2) Ticking past length_m AUTO-COMPLETES (Events.run_completed) -----------
	var completed := [false]
	var completed_dist := [0.0]
	ev.connect("run_completed", func(_score: int, dist: float) -> void:
		completed[0] = true
		completed_dist[0] = dist)
	# Big delta to integrate distance well past length_m in one tick (then a couple more to be sure).
	gs.call("tick_run", survival_s + 2.0)
	gs.call("tick_run", 1.0)
	var active: bool = bool(gs.get("run_active"))
	var won: bool = bool(gs.get("run_won"))
	var dist_now: float = float(gs.get("distance"))
	lines.append("win: run_completed=%s run_active=%s run_won=%s distance=%.1f (length %.1f)" % [
		str(completed[0]), str(active), str(won), dist_now, length_m])
	if not completed[0]:
		lines.append("win FAIL: HORDE run did not auto-complete at length_m (run_completed never fired)"); ok = false
	if active:
		lines.append("win FAIL: HORDE run still active after crossing length_m"); ok = false
	if not won:
		lines.append("win FAIL: HORDE terminal is not a WIN (run_won false)"); ok = false
	if not is_equal_approx(dist_now, length_m):
		lines.append("win FAIL: distance not clamped to length_m on complete (%.1f != %.1f)" % [dist_now, length_m]); ok = false
	if completed[0] and not is_equal_approx(completed_dist[0], length_m):
		lines.append("win FAIL: run_completed reported distance %.1f != length_m %.1f" % [completed_dist[0], length_m]); ok = false

	# --- 3) LEGACY still loads the authored boss level + does NOT auto-complete ---
	st.call("set_poc_mode", 0)           # LEGACY
	gs.call("start_run")
	var legacy_level: Resource = gs.get("active_level")
	var legacy_boss: bool = bool(legacy_level.get("has_boss")) if legacy_level != null else false
	lines.append("legacy: has_boss=%s (want true — authored boss level)" % str(legacy_boss))
	if not legacy_boss:
		lines.append("legacy FAIL: LEGACY level has_boss changed (prior modes broken)"); ok = false
	# Tick LEGACY past its length: a boss level must NOT auto-complete on distance (run stays active).
	var l_len: float = float(legacy_level.get("length_m")) if legacy_level != null else 0.0
	var l_scroll: float = float(legacy_level.get("scroll_speed_mps")) if legacy_level != null else 8.0
	var l_completed := [false]
	ev.connect("run_completed", func(_s: int, _d: float) -> void: l_completed[0] = true)
	gs.call("tick_run", (l_len / maxf(l_scroll, 0.001)) + 5.0)
	var l_active: bool = bool(gs.get("run_active"))
	lines.append("legacy tick-past: run_active=%s run_completed=%s (boss level must NOT auto-complete)" % [
		str(l_active), str(l_completed[0])])
	if not l_active:
		lines.append("legacy FAIL: LEGACY boss level auto-completed on distance"); ok = false
	if l_completed[0]:
		lines.append("legacy FAIL: LEGACY boss level fired run_completed on distance crossing"); ok = false

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
