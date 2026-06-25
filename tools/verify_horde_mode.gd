extends SceneTree
## Headless verification for HORDE mode-seam (H0):
##   - Settings.PocMode gained a 4th value (HORDE == 3) and set_poc_mode/load_settings clamp 0..3.
##   - set_poc_mode(3) round-trips (get == 3) and PERSISTS across a fresh load_settings().
##   - The clamp still rejects out-of-range (4 -> 3), so the widened bound is exactly 0..3.
##   - Events gained `lane_boss_spawned(side, at)` (used by H4).
##
## GPU-free: pokes the Settings autoload + reads its persisted cfg the way load_settings() does.
##   tools/run-headless.sh res://tools/verify_horde_mode.gd /tmp/verify_horde_mode_result.txt

const RESULT_PATH := "/tmp/verify_horde_mode_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var st: Node = root.get_node_or_null("Settings")
	var ev: Node = root.get_node_or_null("Events")
	if st == null or ev == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return

	var HORDE: int = 3   # Settings.PocMode.HORDE by contract

	# 0) The new signal exists on the bus.
	if ev.has_signal("lane_boss_spawned"):
		lines.append("signal OK: Events.lane_boss_spawned present")
	else:
		lines.append("signal FAIL: Events.lane_boss_spawned missing"); ok = false

	# 1) set_poc_mode(3) round-trips to get == 3 (the widened clamp accepts HORDE).
	st.call("set_poc_mode", HORDE)
	var got: int = int(st.get("poc_mode"))
	lines.append("set/get: set_poc_mode(3) -> poc_mode=%d (want %d)" % [got, HORDE])
	if got != HORDE:
		lines.append("set/get FAIL: HORDE not accepted by set_poc_mode clamp"); ok = false

	# 2) Persists across a fresh load_settings() (save happened inside set_poc_mode).
	st.set("poc_mode", 0)            # scribble over the live value
	st.call("load_settings")        # re-read the persisted cfg
	var loaded: int = int(st.get("poc_mode"))
	lines.append("persist: after load_settings poc_mode=%d (want %d)" % [loaded, HORDE])
	if loaded != HORDE:
		lines.append("persist FAIL: HORDE did not survive load_settings (load clamp too tight?)"); ok = false

	# 3) The widened bound is EXACTLY 0..3 — an out-of-range 4 clamps down to HORDE.
	st.call("set_poc_mode", 99)
	var clamped: int = int(st.get("poc_mode"))
	lines.append("clamp: set_poc_mode(99) -> poc_mode=%d (want %d)" % [clamped, HORDE])
	if clamped != HORDE:
		lines.append("clamp FAIL: set_poc_mode did not clamp to 3"); ok = false

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
