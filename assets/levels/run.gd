extends Node2D
## The Run scene — MVP core-loop vertical slice (replaces the POC #6 scene as the
## main scene). Assembles the neon environment, the player ship (analog steer),
## and the always-on fleet fire stream, wired through the Events bus only — Run
## never lets Player and Fleet reference each other directly.
##
## This slice: analog steer + always-on fire + shootable targets (#9/#10/#52/#14).
## Gates (#11/#56), the Glow Battery (#55), and the finish line (#51) land next.

const SHIP_BOTTOM_MARGIN := 240.0

# Instanced via preload (not the bare class names) so this scene parses in the
# headless dev loop, where the global class_name cache isn't built without a
# project --import. The entity scripts keep their class_name regardless.
const PLAYER_SCRIPT := preload("res://assets/player/player.gd")
const FLEET_SCRIPT := preload("res://assets/projectiles/fleet.gd")
const TARGETS_SCRIPT := preload("res://assets/obstacles/targets.gd")

var _player: Node2D
var _fleet: Node2D
var _targets: Node2D
var _hud: Label


func _ready() -> void:
	var design := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var ship_pos := Vector2(design.x * 0.5, design.y - SHIP_BOTTOM_MARGIN)

	_build_environment()

	_player = PLAYER_SCRIPT.new()
	_player.name = "Player"
	_player.position = ship_pos
	add_child(_player)

	# Fleet is a world-space SIBLING of the ship (fired bullets must NOT ride the
	# ship). Run keeps the muzzle under the ship by mirroring steer x via Events.
	_fleet = FLEET_SCRIPT.new()
	_fleet.name = "Fleet"
	_fleet.position = ship_pos
	add_child(_fleet)

	# Shootable targets — each consumes the fleet's bullets that reach it and
	# takes damage per impact (Run injects the fleet; the two stay decoupled).
	_targets = TARGETS_SCRIPT.new()
	_targets.name = "Targets"
	add_child(_targets)
	_targets.set_fleet(_fleet)

	_build_hud()
	Events.player_steered.connect(_on_player_steered)

	GameState.start_run()


func _process(_delta: float) -> void:
	if _hud:
		_hud.text = "FPS %d   swarm %d\nscore %d   kills %d" % [
			Engine.get_frames_per_second(), GameState.projectile_count,
			GameState.score, (_targets.kills if _targets else 0)]


func _on_player_steered(x: float, _x_norm: float) -> void:
	if _fleet:
		_fleet.position.x = x


func _build_hud() -> void:
	# Separate CanvasLayer, modulate <=1 so the readout stays OUT of the bloom.
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(36, 60)
	_hud.modulate = Color(0.85, 0.95, 1.0)
	_hud.add_theme_font_size_override("font_size", 44)
	layer.add_child(_hud)


func _build_environment() -> void:
	# Same HDR bloom recipe proven on device in POC #6.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.04)
	env.glow_enabled = true
	env.glow_intensity = 1.4
	env.glow_strength = 1.0
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
