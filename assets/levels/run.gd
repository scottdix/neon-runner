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
const EFFECT_LAYER_SCRIPT := preload("res://assets/effects/effect_layer.gd")
const PAUSE_SCRIPT := preload("res://assets/ui/pause.gd")
const UI := preload("res://assets/ui/ui_kit.gd")

var _player: Node2D
var _fleet: Node2D
var _targets: Node2D
var _finish_line: Node2D
var _gates: Node2D
var _grid: Node2D
var _effects: Node2D
var _env: Environment
var _score_value: Label
var _combo_value: Label
var _pause: CanvasLayer
var _battery_fill: ColorRect
var _distance: float = 0.0
var _progress: float = 0.0

# Glow Battery is a thin full-width strip pinned to the very TOP EDGE of the screen
# (above the SCORE/COMBO readout row at y=70) — out of the playfield and clear of the
# SCORE rect, per DESIGN_SPEC 03·RUN where the status row tops the HUD. Device-only
# placement (the green bar "very much in the way" on build #11, issue #75).
const BATTERY_BAR := Vector2(UI.DESIGN.x, 12.0)
const BATTERY_TOP := 0.0
# Battery / HUD colours live in Palette (BATTERY_LOW_HUD / BATTERY_HIGH_HUD, kept <=1).


func _ready() -> void:
	var design := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	# Place the ship near the ACTUAL bottom of the device viewport, not the fixed 1920
	# design height. On a tall 19.5:9 phone the real viewport is ~2340 units high, so keying
	# the ship line off `design.y` (1920) left it stranded ~72% down the screen. Use the real
	# visible-rect height (floored to the design height so headless/16:9 is unchanged); the
	# fleet muzzle, breach line, gate-crossing line and finish all derive from this y.
	var screen_h: float = maxf(get_viewport().get_visible_rect().size.y, design.y)
	var ship_pos := Vector2(design.x * 0.5, screen_h - SHIP_BOTTOM_MARGIN)

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

	# GPU-particle effects layer (#19 kill explosions / #20 gate collect+decimate bursts).
	# Self-connects to the bus; added LAST among the world entities so bursts read over the
	# swarm. gate_passed carries no position, so feed it the ship-line y — gate crossings
	# happen there and it tracks ship x off player_steered.
	_effects = EFFECT_LAYER_SCRIPT.new()
	_effects.name = "Effects"
	add_child(_effects)
	_effects.set_crossing_y(ship_pos.y)

	_build_hud()
	# Run no longer reacts to the run terminals — SceneManager listens for run_completed /
	# grid_collapsed and swaps to the Results screen (#44), freeing this scene.
	Events.player_steered.connect(_on_player_steered)
	Events.distance_changed.connect(_on_distance_changed)
	Events.glow_battery_changed.connect(_on_battery_changed)
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
	if _score_value:
		_score_value.text = UI.commafy(GameState.score)
	if _combo_value:
		_combo_value.text = "×%d" % GameState.combo if GameState.combo > 0 else "—"


## Pause on the back/escape action (also wired to the on-screen pause button).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _pause != null:
		_pause.open()


func _on_player_steered(x: float, _x_norm: float) -> void:
	if _fleet:
		_fleet.position.x = x


func _on_distance_changed(distance: float, progress: float) -> void:
	_distance = distance
	_progress = progress


func _on_battery_changed(value: float, max_value: float) -> void:
	if _battery_fill == null:
		return
	var frac: float = clampf(value / max_value, 0.0, 1.0)
	_battery_fill.size.x = BATTERY_BAR.x * frac
	_battery_fill.color = Palette.BATTERY_LOW_HUD.lerp(Palette.BATTERY_HIGH_HUD, frac)


func _build_hud() -> void:
	# Separate CanvasLayer, colours kept <=1 so the readout stays OUT of the bloom (03 RUN,
	# docs/design/SCREENS.md): SCORE top-left, COMBO ×N top-right, Glow Battery bar, pause.
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	var score_cap := UI.text("SCORE", Fonts.arcade, 26, Palette.TEXT_DIM_HUD)
	score_cap.position = Vector2(60, 70)
	layer.add_child(score_cap)
	_score_value = UI.text("0", Fonts.arcade, 60, Palette.HUD_CYAN)
	_score_value.position = Vector2(60, 110)
	layer.add_child(_score_value)

	var combo_cap := UI.text("COMBO", Fonts.arcade, 26, Palette.TEXT_DIM_HUD, HORIZONTAL_ALIGNMENT_RIGHT)
	combo_cap.size.x = 360.0
	combo_cap.position = Vector2(UI.DESIGN.x - 540.0, 70)
	layer.add_child(combo_cap)
	_combo_value = UI.text("—", Fonts.arcade, 64, Palette.COMBO_ORANGE_HUD, HORIZONTAL_ALIGNMENT_RIGHT)
	_combo_value.size.x = 360.0
	_combo_value.position = Vector2(UI.DESIGN.x - 540.0, 110)
	layer.add_child(_combo_value)

	# Pause button (top-right corner). Raises the pause overlay (#43).
	var pause_btn := UI.panel(Vector2(96.0, 96.0), Palette.ACCENT_CYAN_HUD, 0.05, 2.0, 12)
	pause_btn.position = Vector2(UI.DESIGN.x - 156.0, 64.0)
	var pl := UI.text("II", Fonts.arcade, 34, Palette.ACCENT_CYAN_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	pl.set_anchors_preset(Control.PRESET_FULL_RECT)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_btn.add_child(pl)
	layer.add_child(pause_btn)
	UI.hit_overlay(pause_btn).pressed.connect(func() -> void: _pause.open())

	# Glow Battery bar (#55) — the health/loss readout. Dark track + colored fill.
	# Thin full-width strip flush to the top edge so it never overlaps SCORE or the play
	# area (the fill shrinks toward the left as the battery drains — see _on_battery_changed).
	var bar_pos := Vector2(0.0, BATTERY_TOP)
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

	# Pause overlay — created hidden; raised by the pause button / ui_cancel (#43).
	_pause = PAUSE_SCRIPT.new()
	_pause.name = "Pause"
	add_child(_pause)


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
