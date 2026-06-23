extends Node2D
## The Run scene — MVP core-loop vertical slice (replaces the POC #6 scene as the
## main scene). Assembles the neon environment, the player ship (analog steer),
## and the always-on fleet fire stream, wired through the Events bus only — Run
## never lets Player and Fleet reference each other directly.
##
## This slice: analog steer + always-on fire + shootable targets (#9/#10/#52/#14)
## + finite distance track / finish line / "RUN COMPLETE" win (#51).
## Gates (#11/#56) and the Glow Battery (#55) land next.

const SHIP_BOTTOM_MARGIN := 240.0

# Instanced via preload (not the bare class names) so this scene parses in the
# headless dev loop, where the global class_name cache isn't built without a
# project --import. The entity scripts keep their class_name regardless.
const PLAYER_SCRIPT := preload("res://assets/player/player.gd")
const FLEET_SCRIPT := preload("res://assets/projectiles/fleet.gd")
const TARGETS_SCRIPT := preload("res://assets/obstacles/targets.gd")
const FINISH_LINE_SCRIPT := preload("res://assets/levels/finish_line.gd")
const GATE_SPAWNER_SCRIPT := preload("res://assets/gates/gate_spawner.gd")

var _player: Node2D
var _fleet: Node2D
var _targets: Node2D
var _finish_line: Node2D
var _gates: Node2D
var _hud: Label
var _battery_fill: ColorRect
var _distance: float = 0.0
var _progress: float = 0.0

const BATTERY_BAR := Vector2(420.0, 34.0)
const BATTERY_LOW := Color(1.0, 0.3, 0.3)      # empty (red)
const BATTERY_HIGH := Color(0.35, 1.0, 0.6)    # full (green); kept <=1 (HUD, no bloom)


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
	# Enemies that reach the ship line breach + drain the Glow Battery (#53/#55) —
	# the loss pressure that makes shooting the swarm matter.
	_targets.set_breach_line(ship_pos.y)

	# Split Choice gate formations — scroll down the track; the one the ship steers
	# through mutates the swarm volume (fleet fire reacts via Events).
	_gates = GATE_SPAWNER_SCRIPT.new()
	_gates.name = "Gates"
	_gates.setup(ship_pos.y)
	add_child(_gates)

	# Finite-level FINISH bar — scrolls in on the same projection as the gates and
	# lands at the ship line at the win. Cosmetic; the win is GameState's logic.
	_finish_line = FINISH_LINE_SCRIPT.new()
	_finish_line.name = "FinishLine"
	add_child(_finish_line)

	_build_hud()
	Events.player_steered.connect(_on_player_steered)
	Events.distance_changed.connect(_on_distance_changed)
	Events.run_completed.connect(_on_run_completed)
	Events.glow_battery_changed.connect(_on_battery_changed)
	Events.grid_collapsed.connect(_on_grid_collapsed)

	GameState.start_run()
	# Finish sits at the very end of the track; set it up after the level loads.
	_finish_line.setup(GameState.active_level.length_m, ship_pos.y)


func _process(delta: float) -> void:
	# Advance the finite-level scroll (GameState integrates distance + trips the
	# finish line / win). Run drives the frame; GameState owns the state.
	GameState.tick_run(delta)
	if _hud:
		_hud.text = "FPS %d   swarm %d\nscore %d   kills %d\ncombo %d  ×%.1f\ndist %dm  %d%%" % [
			Engine.get_frames_per_second(), GameState.projectile_count,
			GameState.score, (_targets.kills if _targets else 0),
			GameState.combo, GameState.combo_multiplier,
			int(_distance), int(_progress * 100.0)]


func _on_player_steered(x: float, _x_norm: float) -> void:
	if _fleet:
		_fleet.position.x = x


func _on_distance_changed(distance: float, progress: float) -> void:
	_distance = distance
	_progress = progress


## WIN — finish line crossed. Show the "RUN COMPLETE" Results and freeze the game.
func _on_run_completed(final_score: int, distance: float) -> void:
	_build_results_overlay("RUN COMPLETE", Color(0.7, 1.0, 0.85), final_score, distance, false)
	get_tree().paused = true


## LOSS — Glow Battery emptied (#55). The grid collapses to a dark dead state and
## we show the loss Results. Shares the win overlay path; the dark backdrop is the
## MVP stand-in for the reactive-grid collapse animation (that lands with the grid).
func _on_grid_collapsed() -> void:
	_build_results_overlay("GRID COLLAPSE", Color(1.0, 0.5, 0.45), GameState.score, _distance, true)
	get_tree().paused = true


func _on_battery_changed(value: float, max_value: float) -> void:
	if _battery_fill == null:
		return
	var frac: float = clampf(value / max_value, 0.0, 1.0)
	_battery_fill.size.x = BATTERY_BAR.x * frac
	_battery_fill.color = BATTERY_LOW.lerp(BATTERY_HIGH, frac)


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

	# Glow Battery bar (#55) — the health/loss readout. Dark track + colored fill.
	var bar_pos := Vector2(36, 270)
	var track := ColorRect.new()
	track.name = "BatteryTrack"
	track.position = bar_pos
	track.size = BATTERY_BAR
	track.color = Color(0.06, 0.08, 0.12)
	layer.add_child(track)
	_battery_fill = ColorRect.new()
	_battery_fill.name = "BatteryFill"
	_battery_fill.position = bar_pos
	_battery_fill.size = BATTERY_BAR
	_battery_fill.color = BATTERY_HIGH
	layer.add_child(_battery_fill)


func _build_results_overlay(title: String, color: Color, final_score: int, distance: float, darken: bool) -> void:
	# Minimal Results (DESIGN_SPEC screen 04), win or loss. On its own CanvasLayer
	# (out of the bloom) and PROCESS_MODE_ALWAYS so it survives the tree pause. The
	# full Results screen (stats + RETRY/MENU buttons) is #44.
	var layer := CanvasLayer.new()
	layer.name = "Results"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	if darken:
		var bg := ColorRect.new()                  # the "dark dead state" of a collapse
		bg.color = Color(0.0, 0.0, 0.0, 0.82)
		bg.anchors_preset = Control.PRESET_FULL_RECT
		layer.add_child(bg)
	var label := Label.new()
	label.text = "%s\n\nSCORE %d\nDISTANCE %dm" % [title, final_score, int(distance)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color                          # kept <=1 (HUD path, no bloom)
	label.add_theme_font_size_override("font_size", 96)
	label.anchors_preset = Control.PRESET_FULL_RECT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)


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
