class_name PhaseDirector
extends Node
## The phase-pacing director (#59) — walks the level's authored intensity curve and
## announces each boundary crossing on the Events bus. A THIN authored crescendo, NOT a
## deaths/successes feedback loop: it reads ONLY GameState.distance and the level's
## ordered PhaseDef schedule, firing phase_changed once per boundary as the run scrolls
## through it.
##
## The #59 pacing (MATRIX -> QUICKENING -> SINGULARITY -> OVERDRIVE) is authored on the
## LevelDef as distance marks (NOT mm:ss — DISTANCE-keyed off the live scroll). Each phase
## carries the ambient config {grid_mode, spawn_density_mult, gate_speed_mult, gate_moving,
## gravity}; v1 EMITS this only — spawn/gate multiplier CONSUMPTION is deferred. grid_floor
## MAY consume grid_mode as a leaf edit (the one v1 consumer).
##
## When the active phase's gravity != 0 (the SINGULARITY pull), the director also emits
## gravity_shift(dir, strength) — the SAME signal the Singularity boss reuses (there is no
## boss-specific gravity signal). It fires once on ENTRY to a gravity phase.
##
## All advancement lives in a PURE step(distance) so verify_director.gd drives it headless
## on a bare instance (CLAUDE.md gotchas): _process under -s is deferred past _initialize, and
## the autoload globals (Events) are reached via the script's `Events` reference only inside a
## scene script, so the director reads GameState/Events through the autoload globals it gets at
## _ready, but the verifier feeds distance directly and listens on the Events bus.

## The phases this director walks — the level's authored schedule (ascending start_m). Set in
## _ready from GameState.active_level; the verifier injects a schedule via set_phases() so it
## never depends on a loaded level.
var _phases: Array = []

## Index of the currently-active phase (the last boundary crossed). -1 = no phase entered yet,
## so the very first step into phase 0 fires phase_changed exactly once. Monotonic: it only ever
## advances forward (distance never rewinds in a run), so a phase is announced exactly once.
var _current: int = -1


func _ready() -> void:
	# Seed the schedule from the active run's level. Null-safe so an isolated headless
	# instance (no GameState/level) just starts empty until the verifier injects phases.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var level: Resource = gs.get("active_level")
		if level != null:
			var p: Variant = level.get("phases")
			if p is Array:
				set_phases(p)


## Inject the phase schedule (the level's authored PhaseDef list). Sorts a working copy by
## start_m ascending so out-of-order authoring still walks correctly, and resets the walk
## (a fresh run re-enters phase 0). The verifier calls this with a hand-built schedule.
func set_phases(phases: Array) -> void:
	_phases = phases.duplicate()
	_phases.sort_custom(func(a, b) -> bool:
		return float(a.start_m) < float(b.start_m))
	_current = -1


## Advance the walk to the phase the run is now in (PURE — no signals). Returns the index of
## the active phase at `distance` given the ordered schedule: the highest phase whose start_m
## <= distance, or -1 before the first phase. Does NOT mutate state — step() is the mutator.
func phase_at(distance: float) -> int:
	var idx: int = -1
	for i in _phases.size():
		if distance >= float(_phases[i].start_m):
			idx = i
		else:
			break
	return idx


## Step the director one frame against the live distance. Crosses any boundaries reached since
## the last step and emits phase_changed ONCE per crossing (so re-stepping inside a phase is a
## no-op), plus gravity_shift on entry to a gravity phase. Driven by run.gd's _process (fed
## GameState.distance); the verifier calls it directly. Idempotent within a phase: if the
## active phase index is unchanged, nothing is emitted.
func step(distance: float) -> void:
	var target: int = phase_at(distance)
	# Walk forward one phase at a time so EVERY skipped boundary still emits once (a big delta
	# that leaps two phases in a frame announces both). Distance is monotonic in a run, so we
	# never walk backward.
	while _current < target:
		_current += 1
		_enter(_current)


## Emit the boundary signals for entering phase `idx`. phase_changed always; gravity_shift only
## when this phase carries a non-zero gravity pull (the SINGULARITY field the boss also reuses).
func _enter(idx: int) -> void:
	if idx < 0 or idx >= _phases.size():
		return
	var ph: Variant = _phases[idx]
	var cfg: Dictionary = ph.config()
	Events.phase_changed.emit(idx, String(ph.phase_name), cfg)
	var grav: Vector2 = ph.gravity
	if grav != Vector2.ZERO:
		Events.gravity_shift.emit(grav.normalized(), grav.length())
