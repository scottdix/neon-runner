class_name GridFloor
extends Node2D
## The reactive vector grid floor (#NEW, DESIGN_SPEC "Reactive vector grid"). A faint
## blue grid that scrolls toward the ship and warps under action — the primary ground
## signature (supersedes the first-pass perspective rings; those can stay as a secondary
## accent later).
##
## It is ONE full-screen ColorRect driven by shaders/reactive_grid.gdshader, parented to
## its own CanvasLayer at layer -1 so it renders BEHIND every world entity regardless of
## tree order. Wiring is Events-only: scroll follows `distance_changed` on the SHARED
## TrackView projection (so the grid moves at the same rate as gates/finish), and
## `trigger_grid_ripple` pokes a transient radial warp. Glow + warp are device-unproven
## here (Intel UHD 630 can't compile glow pipelines) — confirm on iPhone (#47/#54).

const TRACK := preload("res://assets/levels/track.gd")
const GRID_SHADER := preload("res://shaders/reactive_grid.gdshader")

const CELL_PX := 96.0               # must match the shader's default feel
## A poked ripple expands at this px/sec and fades over RIPPLE_LIFE seconds.
const RIPPLE_SPEED := 900.0
const RIPPLE_LIFE := 0.55
const RIPPLE_START_STRENGTH := 26.0 # px of displacement at the ring's birth

var _mat: ShaderMaterial
var _design := Vector2(1080, 1920)
var _ripple_age: float = -1.0       # < 0 = no active ripple


func _ready() -> void:
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))

	_mat = ShaderMaterial.new()
	_mat.shader = GRID_SHADER
	_mat.set_shader_parameter("resolution", _design)
	_mat.set_shader_parameter("cell_size", CELL_PX)
	_mat.set_shader_parameter("grid_color", Palette.GRID_BLUE)

	var rect := ColorRect.new()
	rect.name = "GridRect"
	rect.material = _mat
	rect.size = _design
	rect.position = Vector2.ZERO
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat steer touches

	var layer := CanvasLayer.new()
	layer.name = "GridLayer"
	layer.layer = -1                                  # behind all world entities
	layer.add_child(rect)
	add_child(layer)

	Events.distance_changed.connect(_on_distance_changed)
	Events.trigger_grid_ripple.connect(_on_grid_ripple)


func _process(delta: float) -> void:
	if _ripple_age < 0.0:
		return
	_ripple_age += delta
	if _ripple_age >= RIPPLE_LIFE:
		_ripple_age = -1.0
		_mat.set_shader_parameter("ripple_strength", 0.0)
		return
	var k: float = _ripple_age / RIPPLE_LIFE          # 0..1 over the ripple's life
	_mat.set_shader_parameter("ripple_radius", _ripple_age * RIPPLE_SPEED)
	_mat.set_shader_parameter("ripple_strength", RIPPLE_START_STRENGTH * (1.0 - k))


## Scroll the grid in CELLS, derived from metres travelled on the shared projection so
## it tracks gates/finish exactly (PIXELS_PER_METER px per metre / CELL_PX px per cell).
func _on_distance_changed(distance: float, _progress: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("scroll", distance * TRACK.PIXELS_PER_METER / CELL_PX)


func _on_grid_ripple(at: Vector2, _is_implosion: bool) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("ripple_center", at)
	_ripple_age = 0.0


## AMOLED / low-power: dim the grid and calm its warp so the screen is quieter and the
## bloom path cheaper (DESIGN_SPEC "Platform feel"). Standard mode is the brighter grid.
func set_low_power(low: bool) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("intensity", 0.18 if low else 0.35)
	_mat.set_shader_parameter("warp_amp", 3.0 if low else 7.0)
