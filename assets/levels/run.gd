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

# #82/#83: arm the boss just BEFORE the finish line (a pre-finish trigger), not exactly at it. Arming
# at >=1.0 alone raced the auto-complete: on the crossing frame GameState.tick_run integrated distance
# past length_m before run.gd's arm block ran, so the run ended first. Arming at 0.999 flips
# GameState.boss_active a frame early — and the arm block now runs ABOVE tick_run — so boss_active is
# already true when distance crosses. (The decisive guard is LevelDef.has_boss in tick_run, which never
# auto-completes a boss level; this pre-finish arm is the belt-and-braces that the climax starts on time.)
const BOSS_ARM_PROGRESS := 0.999

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
# Game Feel (v0.4.0, #22): juice systems that self-wire to the bus — screen shake/flash (#23),
# floating score numbers (#27), and swarm-volume milestone celebrations (#28). Audio (#24/#25/#61)
# is the AudioManager autoload, so it needs no instancing here.
const FEEDBACK_SCRIPT := preload("res://assets/effects/feedback_manager.gd")
const POPUP_SCRIPT := preload("res://assets/ui/score_popup_layer.gd")
const MILESTONE_SCRIPT := preload("res://assets/effects/milestone_banner.gd")
const PAUSE_SCRIPT := preload("res://assets/ui/pause.gd")
const UI := preload("res://assets/ui/ui_kit.gd")
# Session 21 features (#82/#83 boss, #78 economy, #59 phase director, #35/#38 perf). Preloaded by
# PATH (not the bare class_name) so this scene parses in the headless dev loop — same rule as above.
const BOSS_SCRIPT := preload("res://assets/bosses/singularity.gd")
const TOKEN_LAYER_SCRIPT := preload("res://assets/economy/token_layer.gd")
const PHASE_DIRECTOR_SCRIPT := preload("res://assets/levels/phase_director.gd")
const PERF_OVERLAY_SCRIPT := preload("res://assets/ui/perf_overlay.gd")
const VIEWPORT_CULL_SCRIPT := preload("res://assets/levels/viewport_cull.gd")

var _player: Node2D
var _fleet: Node2D
var _targets: Node2D
var _finish_line: Node2D
var _gates: Node2D
var _grid: Node2D
var _effects: Node2D
var _feedback: Node2D
var _popups: Node2D
var _milestone: CanvasLayer
var _env: Environment
# Session 21: the end-of-run boss (#82/#83), the token economy layer (#78), the phase director
# (#59), and the perf cluster (#35 overlay + #38 cull).
var _boss: Node2D
var _boss_armed := false
var _token_layer: Node2D
var _phase_director: Node
var _perf: CanvasLayer
var _cull: Node
var _score_value: Label
var _combo_value: Label
var _token_value: Label
var _pause: CanvasLayer
var _battery_fill: ColorRect
var _distance: float = 0.0
var _progress: float = 0.0
# #26 combo visual feedback: pulse the COMBO readout on every increase, dim-blink it on a break.
var _last_combo: int = 0
var _combo_tween: Tween

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

	# Token economy layer (#78) — a world sibling that owns the drifting token pickups a kill
	# drops (Targets._kill emits token_dropped). Added AFTER Targets so the drop has a live
	# listener; it self-wires to token_dropped + player_steered and reads the ship line for absorb.
	_token_layer = TOKEN_LAYER_SCRIPT.new()
	_token_layer.name = "TokenLayer"
	add_child(_token_layer)
	_token_layer.set_ship_line(ship_pos.y)

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

	# --- Game Feel juice (#22) — each self-wires to the bus in _ready; we only add them. ---
	# FeedbackManager owns the run's authoritative Camera2D (FIXED_TOP_LEFT @ origin = identity view;
	# it shakes only world-space entities — the HUD/grid CanvasLayers are immune) plus the flash overlay.
	_feedback = FEEDBACK_SCRIPT.new()
	_feedback.name = "Feedback"
	add_child(_feedback)
	# Floating score numbers ride the world (so they sit at the kill point and shake with it). Added
	# after the swarm/effects so they read on top; fed the ship line for any gate-crossing popup.
	_popups = POPUP_SCRIPT.new()
	_popups.name = "ScorePopups"
	add_child(_popups)
	_popups.set_crossing_y(ship_pos.y)
	# Milestone celebrations (100/500/1000 swarm) — its own CanvasLayer (60: above the HUD, below pause).
	_milestone = MILESTONE_SCRIPT.new()
	_milestone.name = "Milestone"
	add_child(_milestone)

	# --- Perf cluster (#35/#38) — pure instrumentation; both are guard-safe (they NEVER change a
	# gameplay result). The overlay starts hidden + non-processing (toggled by F3). The cull is an
	# off-screen-PROCESSING gate that only flips set_process on off-band Node2D CHILDREN of the layers
	# it's given (never deletes/moves a node). NOTE (#38 honest scope): the heavy scrollers — bullets
	# and enemies — are batched MultiMesh data arrays, NOT child nodes, so this cull does no work on
	# them in v1; it's a correctness-safe seam, not the batched-array optimiser (that's the device
	# perf pass #39). We do NOT add the Effects layer: its pooled GPUParticles2D emitters are
	# GPU-driven one-shots, so gating their script process is pointless churn (and _apply skips them
	# defensively anyway). ---
	_perf = PERF_OVERLAY_SCRIPT.new()
	_perf.name = "PerfOverlay"
	add_child(_perf)
	_cull = VIEWPORT_CULL_SCRIPT.new()
	_cull.name = "ViewportCull"
	add_child(_cull)
	_cull.add_target(_targets)
	_cull.add_target(_fleet)
	_cull.set_band(0.0, screen_h)

	_build_hud()
	# Run no longer reacts to the run terminals — SceneManager listens for run_completed /
	# grid_collapsed and swaps to the Results screen (#44), freeing this scene.
	Events.player_steered.connect(_on_player_steered)
	Events.distance_changed.connect(_on_distance_changed)
	Events.glow_battery_changed.connect(_on_battery_changed)
	Events.amoled_mode_changed.connect(_on_amoled_mode_changed)
	Events.combo_updated.connect(_on_combo_updated)        # #26 pulse/break visual feedback
	Events.tokens_changed.connect(_on_tokens_changed)      # #78 in-run token counter
	Events.boss_defeated.connect(_on_boss_defeated)        # #82/#83 the run's WIN terminal

	GameState.start_run()
	# The level owns the segment schedule (#13): hand the gate formations + enemy waves
	# to their systems now that the level has loaded. Both stream by track_m on the
	# shared TrackView projection; the finish sits at the very end of the track.
	var level: Resource = GameState.active_level
	_gates.build_formations(level.gate_formations)
	_targets.set_schedule(level.enemy_waves)
	_finish_line.setup(level.length_m, ship_pos.y)

	# Phase-pacing director (#59) — walks the level's authored PhaseDef schedule, emitting
	# phase_changed once per boundary + gravity_shift on a gravity phase. Added after start_run so
	# its _ready can seed from GameState.active_level.phases (deferred, runs after add_child).
	_phase_director = PHASE_DIRECTOR_SCRIPT.new()
	_phase_director.name = "PhaseDirector"
	add_child(_phase_director)

	# End-of-run boss (#82/#83). Built DORMANT now (the ship line + fleet both exist by here) and
	# ARMED only when the track ends in _process — the boss is the run's climax, not its start. It
	# self-_process()es step() once in the tree; run.gd only arms it + drains its add intent. The fat
	# hull sits above the ship line so it fills the upper playfield (tune the 600 offset on device).
	_boss = BOSS_SCRIPT.new()
	_boss.name = "Boss"
	_boss.position = Vector2(design.x * 0.5, ship_pos.y - 600.0)
	add_child(_boss)
	_boss.set_fleet(_fleet)


func _process(delta: float) -> void:
	# End-of-run boss (#82/#83). ARM it just BEFORE the finish line, and BEFORE GameState.tick_run
	# integrates this frame's distance — so GameState.boss_active is already true on the crossing
	# frame. (Previously this ran AFTER tick_run, which on the crossing frame had already called
	# complete_run() and flipped run_active false, so arm() never fired — the climax was dead on
	# arrival. The decisive guard is now LevelDef.has_boss in tick_run, which never auto-completes a
	# boss level; arming here ensures the boss is live as the track ends.) The boss self-steps via its
	# own _process once in the tree — we do NOT call step() here. We only DRAIN its queued adds.
	if not _boss_armed and GameState.run_active and _progress >= BOSS_ARM_PROGRESS:
		_boss_armed = true
		GameState.boss_active = true
		_boss.arm()

	# Advance the finite-level scroll (GameState integrates distance + trips the
	# finish line / win). Run drives the frame; GameState owns the state.
	GameState.tick_run(delta)

	# Phase director (#59): step against the post-tick distance so a boundary crosses on the right
	# frame. Idempotent within a phase, so calling every frame is free.
	if _phase_director:
		_phase_director.step(GameState.distance)

	# Boss upkeep (#82/#83): drain queued adds + apply the Singularity GRAVITY FIELD to live gameplay.
	if _boss_armed:
		for a in _boss.take_pending_adds():
			_targets.spawn_add(a)
		_apply_boss_gravity(delta)

	# Viewport cull (#38): a cheap off-screen-processing gate. Additive — it never deletes/moves a
	# node, only set_process on off-band Node2D CHILDREN of the swept layers (the batched MultiMesh
	# entities aren't child nodes, so this is a no-op on them in v1), so the gameplay result is identical.
	if _cull != null:
		_cull._step()

	if _score_value:
		_score_value.text = UI.commafy(GameState.score)
	if _combo_value:
		_combo_value.text = "×%d" % GameState.combo if GameState.combo > 0 else "—"


## #83 Singularity GRAVITY FIELD consumer — the boss's economy inversion applied to LIVE gameplay
## (not just the pure helpers the verify asserts). While the Singularity is armed and a world point is
## inside its field, each frame:
##   • the swarm's bullets are dragged toward the vortex core (Fleet.apply_gravity_bias) — so a bullet
##     sailing up through a positive (+/×) gate band is pulled OFF it, and
##   • the ship/muzzle x is pulled toward the core (the same vortex), so the steering that would dodge a
##     negative (−/÷) gate the core sits over is fought — the economy inversion is REAL, not dead code.
## The pull is applied to the Fleet's position.x (the muzzle rides under the ship); _on_player_steered
## settles the steer each frame, so this nudge composes with the player's thumb. No-op for a base Boss
## (no gravity_on_projectile/pull_on_ship) so only the Singularity inverts the economy.
func _apply_boss_gravity(delta: float) -> void:
	if _boss == null or _fleet == null:
		return
	if not _boss.has_method("pull_on_ship") or not _boss.has_method("gravity_on_projectile"):
		return
	# Bullet bias: drag every live bullet toward the core (off the positive gates).
	if _boss.has_method("in_field") and not bool(_boss.call("in_field", _fleet.position)):
		# The ship/muzzle is outside the field — skip the ship pull, but bullets spread across the
		# field still get biased inside apply_gravity_bias (its per-bullet field_vector gates itself).
		_fleet.call("apply_gravity_bias", _boss, delta)
		return
	_fleet.call("apply_gravity_bias", _boss, delta)
	# Ship pull: drag the muzzle x toward the core (toward a negative gate the core sits on).
	var ship_pos: Vector2 = _fleet.position
	var pull: Vector2 = _boss.call("pull_on_ship", ship_pos, delta)
	_fleet.position.x += pull.x * delta


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


## #78: the in-run token wallet changed — update the HUD readout. start_run emits tokens_changed(0)
## so this initialises to 0 at the top of a run.
func _on_tokens_changed(in_run: int) -> void:
	if _token_value:
		_token_value.text = UI.commafy(in_run)


## #82/#83: the boss died — this is the run's WIN. Clear the boss_active guard (harmless before
## complete_run's own run_active guard) and complete the run (banks tokens, emits run_completed →
## SceneManager swaps to Results).
func _on_boss_defeated(_name: String, _at: Vector2) -> void:
	GameState.boss_active = false
	GameState.complete_run()


func _on_battery_changed(value: float, max_value: float) -> void:
	if _battery_fill == null:
		return
	var frac: float = clampf(value / max_value, 0.0, 1.0)
	_battery_fill.size.x = BATTERY_BAR.x * frac
	_battery_fill.color = Palette.BATTERY_LOW_HUD.lerp(Palette.BATTERY_HIGH_HUD, frac)


## #26 combo visual feedback. GameState owns the combo count (it emits combo_updated from
## register_kill on a growing chain and from _tick_combo on a lull-reset); we just animate the
## readout: a scale-pop + white flash on every increase, a quick dim-blink on a break. _process
## still writes the text each frame, so the tween only touches scale/modulate and never fights it.
func _on_combo_updated(combo_count: int) -> void:
	if _combo_value == null:
		return
	if combo_count > _last_combo and combo_count > 0:
		_pulse_combo()
	elif combo_count == 0 and _last_combo > 0:
		_break_combo()
	_last_combo = combo_count


func _pulse_combo() -> void:
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_value.scale = Vector2(1.28, 1.28)
	_combo_value.modulate = Palette.HUD_WHITE
	_combo_tween = create_tween().set_parallel(true)
	_combo_tween.tween_property(_combo_value, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(_combo_value, "modulate", Palette.COMBO_ORANGE_HUD, 0.28)


func _break_combo() -> void:
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_value.scale = Vector2.ONE
	_combo_value.modulate = Palette.TEXT_DIM_HUD
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo_value, "modulate", Palette.COMBO_ORANGE_HUD, 0.40)


func _build_hud() -> void:
	# Separate CanvasLayer, colours kept <=1 so the readout stays OUT of the bloom (03 RUN,
	# docs/design/SCREENS.md): SCORE top-left, COMBO ×N top-right, Glow Battery bar, pause.
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	# Explicit z-order: world(0) < flash(40) < HUD(50) < milestone(60) < pause(100). The HUD sits
	# above the screen-flash overlay so the SCORE/COMBO readout stays crisp through an impact flash.
	layer.layer = 50
	add_child(layer)

	# Push the whole top row down past the device's top safe-area inset (notch / front
	# camera cutout). On iPhone 12/12 Pro the COMBO readout and battery strip were tucked
	# under the notch at y≈70 (#76); on a notchless screen / headless this is 0 (no shift).
	var top: float = _safe_top_inset()

	var score_cap := UI.text("SCORE", Fonts.arcade, 26, Palette.TEXT_DIM_HUD)
	score_cap.position = Vector2(60, 70 + top)
	layer.add_child(score_cap)
	_score_value = UI.text("0", Fonts.arcade, 60, Palette.HUD_CYAN)
	_score_value.position = Vector2(60, 110 + top)
	layer.add_child(_score_value)

	# Token readout (#78) — the in-run meta-currency haul, under SCORE. Binds tokens_changed; the
	# colours are kept <=1 (HUD palette) so it stays out of the bloom like the rest of the row.
	var token_cap := UI.text("TOKENS", Fonts.arcade, 26, Palette.TEXT_DIM_HUD)
	token_cap.position = Vector2(60, 200 + top)
	layer.add_child(token_cap)
	_token_value = UI.text("0", Fonts.arcade, 48, Palette.MENU_GOLD_HUD)
	_token_value.position = Vector2(60, 236 + top)
	layer.add_child(_token_value)

	var combo_cap := UI.text("COMBO", Fonts.arcade, 26, Palette.TEXT_DIM_HUD, HORIZONTAL_ALIGNMENT_RIGHT)
	combo_cap.size.x = 360.0
	combo_cap.position = Vector2(UI.DESIGN.x - 540.0, 70 + top)
	layer.add_child(combo_cap)
	_combo_value = UI.text("—", Fonts.arcade, 64, Palette.COMBO_ORANGE_HUD, HORIZONTAL_ALIGNMENT_RIGHT)
	_combo_value.size.x = 360.0
	_combo_value.position = Vector2(UI.DESIGN.x - 540.0, 110 + top)
	# Scale the combo pop around the readout's right edge (where the right-aligned ×N sits) so the
	# pulse grows toward the centre of the screen instead of drifting off the right margin (#26).
	_combo_value.pivot_offset = Vector2(360.0, 40.0)
	layer.add_child(_combo_value)

	# Pause button (top-right corner). Raises the pause overlay (#43).
	var pause_btn := UI.panel(Vector2(96.0, 96.0), Palette.ACCENT_CYAN_HUD, 0.05, 2.0, 12)
	pause_btn.position = Vector2(UI.DESIGN.x - 156.0, 64.0 + top)
	var pl := UI.text("II", Fonts.arcade, 34, Palette.ACCENT_CYAN_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	pl.set_anchors_preset(Control.PRESET_FULL_RECT)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_btn.add_child(pl)
	layer.add_child(pause_btn)
	UI.hit_overlay(pause_btn).pressed.connect(func() -> void: _pause.open())

	# Glow Battery bar (#55) — the health/loss readout. Dark track + colored fill.
	# Thin full-width strip flush to the top edge so it never overlaps SCORE or the play
	# area (the fill shrinks toward the left as the battery drains — see _on_battery_changed).
	var bar_pos := Vector2(0.0, BATTERY_TOP + top)
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


## Top safe-area inset expressed in CANVAS units (the design-space the HUD lays out in).
## The OS reports the cutout in real SCREEN pixels; under stretch=expand the canvas scales
## uniformly, so we convert by (visible-canvas-height / window-height). Returns 0 when the
## device has no top inset and headless (the safe area == the full window). See #76.
func _safe_top_inset() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var to_canvas: float = get_viewport().get_visible_rect().size.y / float(win.y)
	return maxf(0.0, float(safe.position.y) * to_canvas)


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
