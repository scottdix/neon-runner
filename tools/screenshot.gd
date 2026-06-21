extends SceneTree
## Render a scene WINDOWED for a few frames and save a PNG, for autonomous visual
## validation (no human needs to look live). Requires a GPU/display session on the box
## (run WITHOUT --headless). Verdict + path -> /tmp/screenshot_result.txt.
##
##   godot -s res://tools/screenshot.gd --path <project>   # note: NO --headless
##
## Scene + output are constants here; edit per use (kept dead-simple on purpose).

const SCENE := "res://assets/poc/glow_stress.tscn"
const OUT := "/tmp/poc_shot.png"
const RESULT := "/tmp/screenshot_result.txt"
const WARMUP_FRAMES := 50

var _scene: Node = null
var _frame := 0

func _initialize() -> void:
	# Smaller window = faster readback and fits a typical screen; keeps the 9:16 ratio.
	DisplayServer.window_set_size(Vector2i(540, 960))
	var packed: Variant = load(SCENE)
	if packed != null:
		_scene = packed.instantiate()
		root.add_child(_scene)

func _process(_delta: float) -> bool:
	if _scene == null:
		_write("scene_load=FAIL")
		return true
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false
	var img: Image = root.get_texture().get_image()
	var saved := false
	if img != null:
		saved = (img.save_png(OUT) == OK)
	_write("scene_load=OK\nsaved_png=%s\npath=%s\nsize=%s" % [saved, OUT, (img.get_size() if img else Vector2i.ZERO)])
	return true

func _write(body: String) -> void:
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string(body + "\n")
		f.close()
	print(body)
	quit()
