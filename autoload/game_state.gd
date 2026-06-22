extends Node
## Run state (autoload singleton: `GameState`). Registered AFTER Events.
##
## The ONE place that mutates run state and re-emits the scoring/economy signals
## on the Events bus. Systems read from here and listen to Events; they never
## hold references to each other (see CLAUDE.md "Decoupling via the Events bus").
##
## This slice covers the MVP core loop's economy: `projectile_count` is the
## swarm "volume of fire" (D1 always-on fire; gates spike/decimate it later via
## #11/#56). Score + finish-line live here too, growing as later issues land.

## Fire volume / swarm size. Drives the fleet's rate of fire (#52). Gates mutate
## this; the fleet and HUD react via Events, not direct calls.
var projectile_count: int = 0

var score: int = 0
var run_active: bool = false

## Starting swarm volume for a fresh run. Small but non-zero so the stream is
## visibly firing from frame one.
const START_PROJECTILES := 20


func start_run() -> void:
	run_active = true
	score = 0
	set_projectile_count(START_PROJECTILES)
	Events.score_changed.emit(score)
	Events.game_started.emit()


func end_run() -> void:
	if not run_active:
		return
	run_active = false
	Events.game_over.emit(score)


func add_score(amount: int) -> void:
	score += amount
	Events.score_changed.emit(score)


## Set the swarm volume (clamped to >= 0) and announce it. Gates call this with
## deltas via `add_projectiles`; callers that overwrite use this directly.
func set_projectile_count(count: int) -> void:
	var clamped: int = maxi(0, count)
	if clamped == projectile_count:
		return
	projectile_count = clamped
	Events.projectile_count_changed.emit(projectile_count)


func add_projectiles(delta: int) -> void:
	set_projectile_count(projectile_count + delta)
