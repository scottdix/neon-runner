class_name Singularity
extends Boss
## THE SINGULARITY (#83) — the first concrete boss, built ON Boss (#82). A collapsing-vortex
## GRAVITY FIELD that INVERTS the run's economy: while it's alive it
##   • PULLS the swarm's projectiles OFF the positive (+/×) gates (your fire is dragged toward the
##     vortex core, so the easy "spray a + gate" answer is bent away), and
##   • PULLS THE SHIP TOWARD the negative (−/÷) gates (the steering you'd use to dodge a bad gate is
##     fought by the pull, so you're dragged onto the economy-draining gates).
## In short: the things that USUALLY help (positive gates, free steer) are inverted into hazards,
## which is the boss's whole identity — you must out-muscle the field, not play the normal game.
##
## It reuses Events.gravity_shift (NO boss-specific gravity signal, per the contract): each frame the
## active pull vector + strength are announced so the Fleet/ship/grid can bias toward it — exactly the
## same signal PhaseDirector (#59) emits, so consumers need one code path.
##
## ONE-THUMB ONLY: it adds NO new input. The whole fight is the existing steer + always-on fire vs the
## field. The pull is a force the player resists with the thumb they already use to steer.
##
## All the field math is PURE (gravity_on_projectile / pull_on_ship / field_vector) so the headless
## verify asserts the inversion directly with no GPU. Inherits the phase ladder + fat-hull collision
## from Boss; only the mechanic (gravity) + visual differ.

const BOSS_NAME := "SINGULARITY"
const SING_MAX_HP := 7000.0

## The vortex's reach (px): beyond this the field is ~0 (a projectile/ship outside it is unaffected).
## Boss-scale so the inversion bites across most of the playfield.
const FIELD_RADIUS := 760.0
## Peak pull acceleration at the core (px/s²). Falls off with distance (1 - d/FIELD_RADIUS), so the
## closer to the vortex, the harder the drag. Tuned so it bends fire/steer without being a hard wall.
const PROJECTILE_PULL_ACCEL := 1400.0
const SHIP_PULL_ACCEL := 900.0
## The field BREATHES with the collapse: strength oscillates so the grid + bloom can pulse with it
## (the "collapsing vortex" read). 0..1 multiplier on the base accel, never fully off (min floor).
const PULSE_MIN := 0.6
const PULSE_HZ := 0.5
var _pulse_t: float = 0.0
var _pulse: float = 1.0


func _init() -> void:
	# Seed the boss-base tuning for this concrete boss. Set BEFORE arm() so boss_spawned carries the
	# right max_hp. (Constructor runs for both the scene instance and a bare new() in the verify.)
	boss_name = BOSS_NAME
	max_hp = SING_MAX_HP
	hp = SING_MAX_HP


## A representative reference point the broadcast direction is measured FROM (screen-centre). The
## net field reads as a pull from here toward the vortex core, matching the per-entity field_vector
## math (which is `core - from`); a hardcoded Vector2.DOWN would disagree with where the core is.
const BROADCAST_REF := Vector2(540.0, 960.0)
## Only re-broadcast gravity_shift when the direction OR the pulse moved at least this much — so the
## signal isn't an unconditional 60Hz storm once consumers attach (it still fires on a meaningful
## change, e.g. the breathing pulse crossing the threshold). First emit always fires (sentinel below).
const BROADCAST_DIR_EPS := 0.02
const BROADCAST_STR_EPS := 0.02
var _last_bcast_dir: Vector2 = Vector2.INF
var _last_bcast_str: float = -1.0


## The vortex pulses each frame (the collapse breathing) and BROADCASTS its field so the swarm/ship/
## grid can bias toward the core — reusing Events.gravity_shift (NOT a boss-specific signal). The
## direction is from a representative reference (screen-centre) TOWARD the vortex core, so it agrees
## with the per-entity field_vector math (`core - from`); a hardcoded Vector2.DOWN would point the
## wrong way once the core drifts off-centre. Strength is the NORMALIZED 0..1 pulse (the same unit
## PhaseDirector emits — grav.length() of the unit SINGULARITY vector is 1.0 — so a single consumer can
## share one scale; the px/s² peak accel stays internal to the pure pull helpers). Rate-limited: only
## re-emitted when the dir/strength moved a meaningful amount, not every frame. Runs every phase incl.
## TELEGRAPH so the field foreshadows.
func _step_mechanic(delta: float) -> void:
	_pulse_t += delta
	_pulse = lerpf(PULSE_MIN, 1.0, 0.5 + 0.5 * sin(_pulse_t * TAU * PULSE_HZ))
	var dir: Vector2 = (global_position - BROADCAST_REF)
	dir = dir.normalized() if dir.length() > 0.001 else Vector2.DOWN
	var strength: float = _pulse     # normalized 0..1, consistent with PhaseDirector's gravity_shift
	# Rate-limit: emit on the first frame (sentinel) and whenever dir/strength moved meaningfully.
	if _last_bcast_str < 0.0 \
			or absf(strength - _last_bcast_str) >= BROADCAST_STR_EPS \
			or _last_bcast_dir.distance_to(dir) >= BROADCAST_DIR_EPS:
		_last_bcast_dir = dir
		_last_bcast_str = strength
		Events.gravity_shift.emit(dir, strength)


# --- Gravity field (PURE — the inversion math the verify asserts) ------------

## Unit pull direction from a world point toward the vortex core, and the normalized field strength
## (0 at/beyond FIELD_RADIUS, ramping to 1 at the core). Shared by both pull helpers so the falloff
## is defined ONCE. Returns {dir:Vector2, strength:float}.
func field_vector(from: Vector2) -> Dictionary:
	var to_core: Vector2 = global_position - from
	var dist: float = to_core.length()
	if dist <= 0.001 or dist >= FIELD_RADIUS:
		return {"dir": Vector2.ZERO, "strength": 0.0}
	var strength: float = (1.0 - dist / FIELD_RADIUS) * _pulse
	return {"dir": to_core / dist, "strength": strength}


## The per-frame velocity delta a PROJECTILE at `proj_pos` gets dragged by — toward the vortex core.
## This is what pulls the swarm OFF a positive gate: a bullet that would sail up through a + gate is
## bent toward the core instead, so the field strength * direction * dt is added to its motion. PURE:
## the verify checks that a bullet sitting on a + gate band is deflected AWAY from that gate (its x/y
## moves toward the core, off the gate's x-span). Returns the Δvelocity for this frame.
func gravity_on_projectile(proj_pos: Vector2, delta: float) -> Vector2:
	var fv: Dictionary = field_vector(proj_pos)
	return (fv["dir"] as Vector2) * (PROJECTILE_PULL_ACCEL * float(fv["strength"]) * delta)


## The per-frame velocity delta the SHIP gets dragged by — toward the vortex core. This is the
## economy inversion on the steering side: when the core sits over a negative (−/÷) gate, the ship is
## pulled TOWARD it, so the player must fight the field to avoid the draining gate. PURE: the verify
## puts the core on a negative gate and checks the ship's pull points toward that gate's x. Returns
## the Δvelocity for this frame.
func pull_on_ship(ship_pos: Vector2, delta: float) -> Vector2:
	var fv: Dictionary = field_vector(ship_pos)
	return (fv["dir"] as Vector2) * (SHIP_PULL_ACCEL * float(fv["strength"]) * delta)


## Whether a world point is inside the active field (a cheap gate for consumers to skip the math).
func in_field(at: Vector2) -> bool:
	return global_position.distance_to(at) < FIELD_RADIUS


## The live pulse multiplier (0..1) — the verify can read it to confirm the collapse breathes.
func field_pulse() -> float:
	return _pulse


# --- Visual (distinct from the base hull; textured/additive so it blooms) -----

## The vortex reads as a hot magenta core (×multiply gate colour) so it's instantly the "economy"
## boss. HDR so it clears the bloom threshold (device-only render).
func _hull_color() -> Color:
	return Palette.GATE_MULTIPLY
