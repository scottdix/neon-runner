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
const GRID_FLOOR_SCRIPT := preload("res://assets/levels/grid_floor.gd")

var _player: Node2D
var _fleet: Node2D
var _targets: Node2D
var _finish_line: Node2D
var _gates: Node2D
var _grid: Node2D
var _env: Environment
var _hud: Label
var _battery_fill: ColorRect
var _distance: float = 0.0
var _progress: float = 0.0

const BATTERY_BAR := Vector2(420.0, 34.0)
# Battery / HUD colours live in Palette (BATTERY_LOW_HUD / BATTERY_HIGH_HUD, kept <=1).


func _ready() -> void:
	var design := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var ship_pos := Vector2(design.x * 0.5, design.y - SHIP_BOTTOM_MARGIN)

	# Reactive vector grid floor — sits behind everything (its own CanvasLayer -1),
	# scrolls with distance, warps under action. Built before the environment so the
	# AMOLED/low-power pass can dim it, and before the entities so it reads as the
	# ground they fly over.
	_grid = GRID_FLOOR_SCRIPT.new()
	_grid.name = "GridFloor"
	add_child(_grid)

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
	# #53 cross-cutting interactions: Targets queries the gate system for gate-hijack
	# (park/clear occupants) + multiply-through (positive gate bands). One-way injection
	# (Targets → Gates); the spawner never holds a Targets reference.
	_targets.set_gates(_gates)

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
	Events.amoled_mode_changed.connect(_on_amoled_mode_changed)

	GameState.start_run()
	# The level owns the segment schedule (#13): hand the gate formations + enemy waves
	# to their systems now that the level has loaded. Both stream by track_m on the
	# shared TrackView projection; the finish sits at the very end of the track.
	var level: Resource = GameState.active_level
	_gates.build_formations(level.gate_formations)
	_targets.set_schedule(level.enemy_waves)
	_finish_line.setup(level.length_m, ship_pos.y)


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
	_build_results_overlay("RUN COMPLETE", Palette.WIN_GREEN_HUD, final_score, distance, false)
	get_tree().paused = true


## LOSS — Glow Battery emptied (#55). The grid collapses to a dark dead state and
## we show the loss Results. Shares the win overlay path; the dark backdrop is the
## MVP stand-in for the reactive-grid collapse animation (that lands with the grid).
func _on_grid_collapsed() -> void:
	_build_results_overlay("GRID COLLAPSE", Palette.LOSS_RED_HUD, GameState.score, _distance, true)
	get_tree().paused = true


func _on_battery_changed(value: float, max_value: float) -> void:
	if _battery_fill == null:
		return
	var frac: float = clampf(value / max_value, 0.0, 1.0)
	_battery_fill.size.x = BATTERY_BAR.x * frac
	_battery_fill.color = Palette.BATTERY_LOW_HUD.lerp(Palette.BATTERY_HIGH_HUD, frac)


func _build_hud() -> void:
	# Separate CanvasLayer, modulate <=1 so the readout stays OUT of the bloom.
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(36, 60)
	_hud.modulate = Palette.HUD_CYAN
	_hud.add_theme_font_size_override("font_size", 40)
	Fonts.apply(_hud, Fonts.mono)           # Share Tech Mono — legible multi-line debug readout
	layer.add_child(_hud)

	# Glow Battery bar (#55) — the health/loss readout. Dark track + colored fill.
	var bar_pos := Vector2(36, 270)
	var track := ColorRect.new()
	track.name = "BatteryTrack"
	track.position = bar_pos
	track.size = BATTERY_BAR
	track.color = Palette.BATTERY_TRACK_HUD
	layer.add_child(track)
	_battery_fill = ColorRect.new()
	_battery_fill.name = "BatteryFill"
	_battery_fill.position = bar_pos
	_battery_fill.size = BATTERY_BAR
	_battery_fill.color = Palette.BATTERY_HIGH_HUD
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
	Fonts.apply(label, Fonts.display)               # Orbitron — the big results wordmark/score
	label.anchors_preset = Control.PRESET_FULL_RECT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)


func _build_environment() -> void:
	# Same HDR bloom recipe proven on device in POC #6.
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.glow_enabled = true
	_env.glow_strength = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.glow_hdr_threshold = 1.0
	_apply_display_mode(Settings.amoled_mode)        # clear colour + bloom intensity
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	add_child(we)


## Apply the AMOLED / low-power display mode to the environment (and the grid). AMOLED
## clears to pitch #000000 so OLED pixels switch fully off, and runs a LOWER-cost bloom
## (less intensity/bloom spread) per DESIGN_SPEC "Platform feel"; standard is the
## near-black neon path. Live-swappable from the settings toggle.
func _apply_display_mode(amoled: bool) -> void:
	if _env == null:
		return
	_env.background_color = Palette.BG_AMOLED if amoled else Palette.BG_STANDARD
	_env.glow_intensity = 1.0 if amoled else 1.4
	_env.glow_bloom = 0.08 if amoled else 0.15
	if _grid != null and _grid.has_method("set_low_power"):
		_grid.set_low_power(amoled)


func _on_amoled_mode_changed(enabled: bool) -> void:
	_apply_display_mode(enabled)
