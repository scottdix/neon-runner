extends SceneTree
## Dev tool — persist Settings.poc_mode = HORDE (3) so the next game launch boots into HORDE mode.
## Loads the existing settings first (so it doesn't clobber other persisted values), then flips the mode.
## Run:  ~/.local/bin/godot --headless --path . -s res://tools/set_horde_mode.gd
## (writes /tmp/set_horde_result.txt). Set to a different int below to pick another mode.

const HORDE := 3

func _initialize() -> void:
	var s: Node = root.get_node_or_null("Settings")
	if s == null:
		_write("FAIL: Settings autoload missing")
		return
	if s.has_method("load_settings"):
		s.call("load_settings")   # populate from the existing cfg so save preserves other keys
	s.call("set_poc_mode", HORDE) # clamps 0..3, persists via save_settings(), emits poc_mode_changed
	_write("poc_mode=%d (3=HORDE)" % int(s.get("poc_mode")))


func _write(body: String) -> void:
	var f := FileAccess.open("/tmp/set_horde_result.txt", FileAccess.WRITE)
	f.store_string(body + "\n")
	f.close()
	quit()
