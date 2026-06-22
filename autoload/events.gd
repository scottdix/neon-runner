extends Node
## Global event bus (autoload singleton: `Events`).
##
## A central place for decoupled, fire-and-forget communication between game
## systems. Emitters don't need a reference to listeners and vice versa:
##   Events.gate_passed.emit("multiply", 2.0, new_count)   # emit from anywhere
##   Events.gate_passed.connect(_on_gate_passed)           # listen from anywhere
##
## Keep this file signals-only — no state, no logic. Game state lives in
## GameState; this is purely the wiring. Registered first in the autoload order
## so every other singleton/scene can rely on it being present.

# --- Player events -----------------------------------------------------------
signal player_died
## Analog slide-steer (D1, GAME_SCOPE): emitted as the ship's x moves. `x` is the
## ship's canvas x; `x_normalized` is 0..1 across the steerable width. Supersedes
## the old discrete `player_lane_changed` (lanes are now visual-only grid columns).
signal player_steered(x: float, x_normalized: float)

# --- Fleet / fire ------------------------------------------------------------
## Always-on fire (D1, GAME_SCOPE): the swarm volume. Re-emitted by GameState
## whenever projectile_count changes (gates spike/decimate it).
signal projectile_count_changed(count: int)
## Emitted each volley the fleet fires — hook for audio/muzzle vfx.
signal fleet_fired(shots: int)

# --- Targets / enemies -------------------------------------------------------
## A shootable target was destroyed by the fleet — hook for score/particles/audio.
signal enemy_destroyed(at: Vector2, points: int)

# --- Gate events -------------------------------------------------------------
signal gate_passed(gate_type: String, value: float, new_count: int)
signal gate_spawned(gate: Node2D)

# --- Game flow ---------------------------------------------------------------
signal game_started
signal game_paused
signal game_resumed
signal game_over(final_score: int)

# --- Scoring -----------------------------------------------------------------
signal score_changed(new_score: int)
signal multiplier_changed(new_multiplier: float)
signal combo_updated(combo_count: int)

# --- Effects -----------------------------------------------------------------
signal spawn_particles(position: Vector2, type: String)
signal trigger_screen_shake(intensity: float, duration: float)
signal trigger_grid_ripple(position: Vector2, is_implosion: bool)
