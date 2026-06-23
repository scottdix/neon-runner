extends Node
## Run state (autoload singleton: `GameState`). Registered AFTER Events.
##
## The ONE place that mutates run state and re-emits the scoring/economy signals
## on the Events bus. Systems read from here and listen to Events; they never
## hold references to each other (see CLAUDE.md "Decoupling via the Events bus").
##
## This slice covers the MVP core loop's economy: `projectile_count` is the
## swarm "volume of fire" (D1 always-on fire; gates spike/decimate it later via
## #11/#56). Score + the finite-level distance/finish-line (#51) live here too.

# Preloaded (not the bare `LevelDef` class_name) so this autoload's level
# fallback works in the headless dev loop, where the class_name cache isn't
# built without a project --import. The .tres refs its script by path so it
# loads headless fine; the preload is only the in-code default.
const LEVEL_DEF := preload("res://resources/level_def.gd")
const DEFAULT_LEVEL_PATH := "res://data/level_01.tres"

## Fire volume / swarm size. Drives the fleet's rate of fire (#52). Gates mutate
## this; the fleet and HUD react via Events, not direct calls.
var projectile_count: int = 0

var score: int = 0
var run_active: bool = false

## Finite-level state (#51). `active_level` is the LevelDef for this run;
## `distance` is metres travelled; `run_won` records the win terminal.
var active_level: Resource
var distance: float = 0.0
var run_won: bool = false

## Glow Battery (#55, §4.6) — health and the ONLY loss channel. Negative gates
## (and later enemy/hazard hits) drain it; 0 = grid collapse = loss. Winning is
## unrelated (crossing the finish line). MVP = the bar + loss-at-0; the secondary
## effects (dim bloom, music low-pass, tier downgrade) are deferred (v0.4.0+).
const MAX_GLOW_BATTERY := 100.0
## Battery lost per negative (−/÷) gate crossing. Flat for MVP (4 bad gates = death);
## scaling by gate severity is a balance pass for later.
const DRAIN_PER_NEGATIVE_GATE := 25.0
var glow_battery: float = MAX_GLOW_BATTERY

## Starting swarm volume for a fresh run. Small but non-zero so the stream is
## visibly firing from frame one.
const START_PROJECTILES := 20

## Kill-combo scoring. Consecutive kills within COMBO_WINDOW seconds raise a score
## multiplier; a lull resets it to 1×. Wires the previously-dormant combo/multiplier
## signals. The multiplier scales every kill's points (Targets routes kills through
## `register_kill`, not `add_score`, so this is the one place scoring is computed).
const COMBO_WINDOW := 2.5
const COMBO_STEP := 0.1
const MAX_COMBO_MULT := 5.0
var combo: int = 0
var combo_multiplier: float = 1.0
var _combo_timer: float = 0.0

## Results-screen stats (#44/SCREENS.md): peaks tracked across the run, finalised on a
## terminal. `is_new_best` drives the NEW BEST badge (Settings persists the best score).
var peak_multiplier: float = 1.0
var peak_fleet: int = 0
var best_combo: int = 0
var is_new_best: bool = false


func _ready() -> void:
	wire_events()


## Connect GameState to the gate bus. Gate effects are applied HERE, not by the
## spawner (CLAUDE.md "Decoupling via the Events bus"): a gate emits gate_passed;
## GameState reacts and mutates the economy. This is the single owner of run-state
## mutation (review debt #1–#3). Public + idempotent because under the headless `-s`
## loop autoload _ready is deferred past _initialize, so the verify scripts call this
## explicitly in setup (doing the engine's normal _ready wiring). Events is the first
## autoload, so it's always present by the time this runs.
func wire_events() -> void:
	if not Events.gate_passed.is_connected(_on_gate_passed):
		Events.gate_passed.connect(_on_gate_passed)


## React to a gate firing (#11/#56). The gate's emitted `new_count` is already its
## post-op value floored at 0; we commit it (set_projectile_count re-clamps for
## safety) and, for a negative gate (−/÷), drain the Glow Battery — the risk side of
## the Split Choice. The spawner used to do this inline; now it only calls trigger().
func _on_gate_passed(gate_type: String, _value: float, new_count: int) -> void:
	set_projectile_count(new_count)
	if gate_type == "subtract" or gate_type == "divide":
		drain_battery(DRAIN_PER_NEGATIVE_GATE)


func start_run() -> void:
	active_level = _load_level()
	run_active = true
	run_won = false
	score = 0
	distance = 0.0
	glow_battery = MAX_GLOW_BATTERY
	combo = 0
	combo_multiplier = 1.0
	_combo_timer = 0.0
	peak_multiplier = 1.0
	peak_fleet = 0
	best_combo = 0
	is_new_best = false
	set_projectile_count(START_PROJECTILES)
	Events.score_changed.emit(score)
	Events.distance_changed.emit(distance, 0.0)
	Events.glow_battery_changed.emit(glow_battery, MAX_GLOW_BATTERY)
	Events.combo_updated.emit(combo)
	Events.multiplier_changed.emit(combo_multiplier)
	Events.game_started.emit()


## Drain the Glow Battery (positive `amount` removes charge). Announces the change
## and, on reaching 0, fails the run. No-op once the run has ended.
func drain_battery(amount: float) -> void:
	if not run_active:
		return
	glow_battery = clampf(glow_battery - absf(amount), 0.0, MAX_GLOW_BATTERY)
	Events.glow_battery_changed.emit(glow_battery, MAX_GLOW_BATTERY)
	if glow_battery <= 0.0:
		fail_run()


## LOSS: the battery emptied — the grid collapses. Terminal (run lost, not won).
func fail_run() -> void:
	if not run_active:
		return
	run_active = false
	run_won = false
	is_new_best = Settings.record_score(score)
	Events.grid_collapsed.emit()


## Advance the finite-level scroll one frame: integrate distance from the level's
## scroll speed, announce progress, and trip the win when the finish line is
## reached. Driven by Run's _process; pure + GPU-free so it runs headless.
func tick_run(delta: float) -> void:
	if not run_active or active_level == null:
		return
	_tick_combo(delta)
	distance += active_level.scroll_speed_mps * delta
	var progress: float = clampf(distance / active_level.length_m, 0.0, 1.0)
	Events.distance_changed.emit(distance, progress)
	if distance >= active_level.length_m:
		complete_run()


## WIN: crossed the finish line. Terminal — clamps distance to the line and emits
## run_completed (Run shows "RUN COMPLETE"). Loss path (Glow Battery 0) is #55.
func complete_run() -> void:
	if not run_active:
		return
	run_active = false
	run_won = true
	distance = active_level.length_m if active_level != null else distance
	is_new_best = Settings.record_score(score)
	Events.run_completed.emit(score, distance)


func end_run() -> void:
	if not run_active:
		return
	run_active = false
	Events.game_over.emit(score)


## Load this run's level: the authored .tres if present, else a code default so
## the run is always playable (and headless tests never depend on the import cache).
func _load_level() -> Resource:
	var lv: Resource = load(DEFAULT_LEVEL_PATH)
	if lv == null:
		lv = LEVEL_DEF.new()
	return lv


func add_score(amount: int) -> void:
	score += amount
	Events.score_changed.emit(score)


## Score a kill through the combo system — Targets calls this instead of add_score so
## the multiplier is applied in one place. Each consecutive kill (within COMBO_WINDOW)
## bumps the combo and its multiplier; returns the points actually awarded. The first
## kill of a chain is 1.0× (combo - 1), so combos reward sustained fire, not one shot.
func register_kill(base_points: int) -> int:
	if not run_active:
		return 0
	combo += 1
	_combo_timer = COMBO_WINDOW
	combo_multiplier = clampf(1.0 + COMBO_STEP * float(combo - 1), 1.0, MAX_COMBO_MULT)
	peak_multiplier = maxf(peak_multiplier, combo_multiplier)
	best_combo = maxi(best_combo, combo)
	var pts: int = int(round(float(base_points) * combo_multiplier))
	score += pts
	Events.score_changed.emit(score)
	Events.combo_updated.emit(combo)
	Events.multiplier_changed.emit(combo_multiplier)
	return pts


## Decay the kill combo: once COMBO_WINDOW elapses with no new kill, the chain breaks
## back to 1×. Driven by tick_run so it only runs during an active run.
func _tick_combo(delta: float) -> void:
	if _combo_timer <= 0.0:
		return
	_combo_timer -= delta
	if _combo_timer <= 0.0 and combo > 0:
		combo = 0
		combo_multiplier = 1.0
		Events.combo_updated.emit(0)
		Events.multiplier_changed.emit(1.0)


## Set the swarm volume (clamped to >= 0) and announce it. Gates call this with
## deltas via `add_projectiles`; callers that overwrite use this directly.
func set_projectile_count(count: int) -> void:
	var clamped: int = maxi(0, count)
	peak_fleet = maxi(peak_fleet, clamped)
	if clamped == projectile_count:
		return
	projectile_count = clamped
	Events.projectile_count_changed.emit(projectile_count)


func add_projectiles(delta: int) -> void:
	set_projectile_count(projectile_count + delta)
