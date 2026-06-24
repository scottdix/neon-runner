extends Resource
class_name PhaseDef
## PhaseDef — one segment of the authored intensity curve (#59 phase director).
##
## Spine-scaffold stub: holds the shape the phase-director author fleshes out. A phase is
## DISTANCE-keyed (starts at `start_m` metres into the run, NOT a time mark) and carries the
## ambient config the PhaseDirector emits at the boundary via Events.phase_changed. Loaded by
## PATH in LevelDef (no class_name cache under the headless `-s` loop); the `class_name` stays
## so `.tres` instances can type it.
##
## The config keys map the #59 mm:ss pacing onto distance: grid_mode (visual grid behaviour),
## spawn_density_mult / gate_speed_mult / gate_moving (DEFERRED consumption in v1 — EMIT only),
## and gravity (the Singularity pull; the PhaseDirector also emits gravity_shift when != 0).

## Display label, e.g. "MATRIX".
@export var phase_name: String = ""
## Distance (metres) at which this phase BECOMES active. Phases are evaluated in ascending order.
@export var start_m: float = 0.0
## Grid visual mode — a leaf string grid_floor MAY consume in v1 (e.g. "ambient"/"pulse"/"dissolve").
@export var grid_mode: String = "ambient"
## Spawn density multiplier (DEFERRED consumption in v1 — emitted for later spawner use).
@export var spawn_density_mult: float = 1.0
## Gate scroll-speed multiplier (DEFERRED consumption in v1).
@export var gate_speed_mult: float = 1.0
## Whether gates drift laterally in this phase (DEFERRED consumption in v1).
@export var gate_moving: bool = false
## Gravity pull vector for this phase (zero = none). The PhaseDirector emits gravity_shift when
## this is non-zero; the Singularity boss reuses that same signal.
@export var gravity: Vector2 = Vector2.ZERO


## Factory: new a PhaseDef with all fields set (lets LevelDef seed its default schedule in code).
static func make(p_name: String, p_start_m: float, p_grid: String, p_density: float,
		p_gate_speed: float, p_moving: bool, p_gravity: Vector2) -> PhaseDef:
	var ph := PhaseDef.new()
	ph.phase_name = p_name
	ph.start_m = p_start_m
	ph.grid_mode = p_grid
	ph.spawn_density_mult = p_density
	ph.gate_speed_mult = p_gate_speed
	ph.gate_moving = p_moving
	ph.gravity = p_gravity
	return ph


## The config Dictionary the PhaseDirector emits in Events.phase_changed.
func config() -> Dictionary:
	return {
		"grid_mode": grid_mode,
		"spawn_density_mult": spawn_density_mult,
		"gate_speed_mult": gate_speed_mult,
		"gate_moving": gate_moving,
		"gravity": gravity,
	}
