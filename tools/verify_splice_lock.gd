extends SceneTree
## Headless verification for P1 — LOCK HORDE AS THE CORE GAME.
##   - Settings.poc_mode default is HORDE (PocMode.HORDE == 3).
##   - load_settings() forces poc_mode = HORDE UNCONDITIONALLY, ignoring any persisted value:
##     we persist poc_mode = LEGACY(0) to the real config file FIRST, then load_settings and
##     assert it comes back HORDE (the persisted LEGACY is ignored).
##
## Uses the live Settings autoload via root.get_node_or_null (bare `Settings` won't compile under
## -s). Writes a verdict file the runner polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_splice_lock.gd /tmp/verify_splice_lock_result.txt

const RESULT_PATH := "/tmp/verify_splice_lock_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var settings: Node = root.get_node_or_null("Settings")
	if settings == null:
		lines.append("RESULT=FAIL (Settings autoload missing)")
		_write(lines)
		return

	# PocMode.HORDE == 3 (enum LEGACY,KINETIC_CLUTCH,GEOM_OVERDRIVE,HORDE).
	var horde: int = 3
	var legacy: int = 0

	# 1) Fresh default is HORDE.
	var default_mode: int = int(settings.poc_mode)
	var default_ok: bool = (default_mode == horde)
	lines.append("default poc_mode=%d (HORDE=%d) -> %s" % [default_mode, horde, "OK" if default_ok else "BAD"])
	ok = ok and default_ok

	# 2) Persist LEGACY(0) to the real config file, then load_settings must IGNORE it and force HORDE.
	var cfg_path: String = String(settings.CONFIG_PATH)
	var progress: String = String(settings.PROGRESS)
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)  # best-effort; keep any other keys
	cfg.set_value(progress, "poc_mode", legacy)
	cfg.save(cfg_path)

	# Sanity: the file really holds LEGACY now.
	var check := ConfigFile.new()
	check.load(cfg_path)
	var persisted: int = int(check.get_value(progress, "poc_mode", -1))
	var persist_ok: bool = (persisted == legacy)
	lines.append("persisted poc_mode=%d (forced LEGACY=%d) -> %s" % [persisted, legacy, "OK" if persist_ok else "BAD"])
	ok = ok and persist_ok

	# 3) load_settings ignores the persisted LEGACY and forces HORDE.
	settings.poc_mode = legacy  # pretend something set it to LEGACY too
	settings.load_settings()
	var loaded_mode: int = int(settings.poc_mode)
	var load_ok: bool = (loaded_mode == horde)
	lines.append("after load_settings poc_mode=%d (HORDE=%d, persisted was LEGACY) -> %s" % [loaded_mode, horde, "OK" if load_ok else "BAD"])
	ok = ok and load_ok

	# Cleanup: remove the LEGACY key we wrote so we don't leave the box's config dirty.
	var clean := ConfigFile.new()
	clean.load(cfg_path)
	clean.erase_section_key(progress, "poc_mode")
	clean.save(cfg_path)

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.flush()
		f.close()
	quit()
