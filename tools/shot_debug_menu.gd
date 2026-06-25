extends SceneTree
## Dev tool — render the Debug menu overlay to a PNG to eyeball its layout (flat UI, no bloom needed,
## so this works on the mini). Run WITHOUT --headless:
##   ~/.local/bin/godot --path . -s res://tools/shot_debug_menu.gd
const MENU := "res://assets/ui/debug_menu.gd"
const OUT := "/tmp/debug_menu_shot.png"
const RESULT := "/tmp/shot_debug_result.txt"

var _menu: Node = null
var _frame := 0

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(540, 960))
	var s: GDScript = load(MENU)
	if s == null:
		_write("FAIL: debug_menu.gd missing"); return
	_menu = s.new()
	root.add_child(_menu)   # _ready is deferred under -s; open() is called from _process after a frame


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2 and _menu != null and _menu.has_method("open"):
		_menu.call("open")
	if _frame < 18:
		return false
	var img: Image = root.get_texture().get_image()
	var ok := false
	if img != null:
		ok = (img.save_png(OUT) == OK)
	_write("saved=%s path=%s size=%s" % [ok, OUT, (img.get_size() if img != null else Vector2i.ZERO)])
	return true


func _write(body: String) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	f.store_string(body + "\n")
	f.close()
	quit()
