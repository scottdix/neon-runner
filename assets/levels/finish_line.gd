class_name FinishLine
extends Node2D
## The scrolling FINISH bar (#51, DESIGN_SPEC screen 03: "checkered bar with FINISH
## label scrolling down"). Purely cosmetic — it sits at the very end of the track
## (track_m = level length) and scrolls in on the SHARED TrackView projection, so
## it moves at the same rate as the gates and arrives at the ship line exactly when
## the run completes. The actual win is GameState's distance logic; this shows it.
##
## Rendered as a TEXTURED, additive, HDR-green Sprite2D so it blooms — the glow
## gotcha (memory: glow-immediate-draw-no-bloom) means draw_*/polylines never glow,
## so all neon art goes through the textured path.

const TRACK := preload("res://assets/levels/track.gd")

const BAR_H := 64.0                 # bar thickness in px
const CELL := 32                    # checker cell size in px
# Success/finish colour is Palette.SUCCESS_GREEN (acid green #39ff14), set at runtime.

var _design := Vector2(1080, 1920)
var _track_m := 320.0               # finish sits at the end of the level
var _trigger_y := 1680.0            # ship line — where the bar lands at distance == track_m
var _sprite: Sprite2D


## Run calls this with the level length and the ship's canvas y before the first
## distance update, so the bar scrolls on the same projection as everything else.
func setup(track_m: float, trigger_y: float) -> void:
	_track_m = track_m
	_trigger_y = trigger_y


func _ready() -> void:
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_build_sprite()
	visible = false
	Events.distance_changed.connect(_on_distance_changed)


func _on_distance_changed(distance: float, _progress: float) -> void:
	var y: float = TRACK.screen_y(_track_m, distance, _trigger_y)
	position = Vector2(_design.x * 0.5, y)
	visible = y > -BAR_H            # appears once it scrolls in from the top


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Bar"
	_sprite.texture = _make_checker_texture()
	_sprite.modulate = Palette.SUCCESS_GREEN
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sprite.material = mat
	add_child(_sprite)


## A full-width checkerboard strip: alternating opaque / transparent cells so the
## additive bar reads as a racing-style finish line.
func _make_checker_texture() -> ImageTexture:
	var w := int(_design.x)
	var h := int(BAR_H)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var on := ((x / CELL) + (y / CELL)) % 2 == 0
			img.set_pixel(x, y, Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.12))
	return ImageTexture.create_from_image(img)
