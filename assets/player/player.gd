class_name Player
extends Node2D
## The player ship — analog slide-steer (D1, GAME_SCOPE, LOCKED).
##
## Continuous touch-drag maps to ship-x, smoothed + clamped to the steerable
## width. NOT discrete lanes. Steering aims both the ship and the bullet stream
## (the Fleet reads `position.x`). Always-on fire means steering is the ONLY
## player input; there is no fire button.
##
## Input: touch/screen-drag (mobile) or mouse (desktop, via emulate_touch) sets
## the target x; keyboard left/right also nudge it for desktop testing (#10).
## The steering MATH is in `step()` so it can be driven headless with no GPU.

## Half-width kept clear of each screen edge so the ship never clips off-screen.
@export var edge_margin: float = 80.0
## Higher = snappier follow. Frame-rate-independent (see `step`).
@export var steer_responsiveness: float = 12.0
## Keyboard nudge speed (px/sec) for desktop testing.
@export var key_steer_speed: float = 1400.0

var _design_width: float = 1080.0
var _target_x: float = 540.0
var _min_x: float = 80.0
var _max_x: float = 1000.0


func _ready() -> void:
	_design_width = float(ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1080))
	_min_x = edge_margin
	_max_x = _design_width - edge_margin
	if position.x <= 0.0:
		position.x = _design_width * 0.5
	_target_x = position.x
	_build_ship_visual()


# --- Ship visual -------------------------------------------------------------
# The ship is drawn via a textured MultiMesh instance with an additive material
# and an HDR instance color — the SAME path the orb fleet uses, which is the only
# one Godot's 2D bloom actually picks up. Immediate-mode draw_colored_polygon
# (the previous approach) never blooms regardless of how bright the color is
# (confirmed on device twice — see memory glow-immediate-draw-no-bloom).

const SHIP_TEX_SIZE := 64
const SHIP_QUAD := 96.0

func _build_ship_visual() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(SHIP_QUAD, SHIP_QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.set_instance_transform_2d(0, Transform2D())
	# Luminance-rich cyan HDR; additive + soft mask makes the cores read white-hot.
	mm.set_instance_color(0, Color(0.5, 3.8, 4.4, 1.0))
	var mmi := MultiMeshInstance2D.new()
	mmi.name = "ShipMesh"
	mmi.multimesh = mm
	mmi.texture = _make_ship_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mmi.material = mat
	add_child(mmi)


func _make_ship_texture() -> ImageTexture:
	# A soft-edged upward arrowhead (alpha mask). Shape comes from alpha; the glow
	# colour comes from the HDR instance color above.
	var img := Image.create(SHIP_TEX_SIZE, SHIP_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var apex_y := 8.0
	var base_y := 56.0
	var cx := SHIP_TEX_SIZE * 0.5
	var base_half := 26.0
	for y in SHIP_TEX_SIZE:
		var t: float = clampf((float(y) - apex_y) / (base_y - apex_y), 0.0, 1.0)
		var hw: float = t * base_half
		for x in SHIP_TEX_SIZE:
			var dx: float = absf(float(x) - cx)
			# Signed distance to the triangle edges (positive = inside).
			var h_dist: float = hw - dx
			var v_dist: float = minf(float(y) - apex_y, base_y - float(y))
			var d: float = minf(h_dist, v_dist)
			var a: float = clampf((d + 5.0) / 9.0, 0.0, 1.0)  # soft edge + faint halo
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _unhandled_input(event: InputEvent) -> void:
	# Touch drag / press, and (via emulate_touch_from_mouse) desktop mouse.
	if event is InputEventScreenDrag:
		set_target_x(event.position.x)
	elif event is InputEventScreenTouch and event.pressed:
		set_target_x(event.position.x)


func _process(delta: float) -> void:
	# Keyboard steer for desktop testing — additive to whatever touch set.
	var key_axis := Input.get_axis("ui_left", "ui_right")
	if key_axis != 0.0:
		set_target_x(_target_x + key_axis * key_steer_speed * delta)
	step(delta)


## Advance the steer one frame. Pure + GPU-free so headless tests can call it
## directly. Lerp is exponential-smoothed so it's identical at any frame rate.
func step(delta: float) -> void:
	var t: float = 1.0 - pow(0.0001, delta * (steer_responsiveness / 12.0))
	position.x = lerpf(position.x, clampf(_target_x, _min_x, _max_x), t)
	var span: float = maxf(1.0, _max_x - _min_x)
	var x_norm: float = clampf((position.x - _min_x) / span, 0.0, 1.0)
	Events.player_steered.emit(position.x, x_norm)


## Request a new steer target; always clamped to the steerable width.
func set_target_x(x: float) -> void:
	_target_x = clampf(x, _min_x, _max_x)


func get_target_x() -> float:
	return _target_x
