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
## An enemy reached the ship line without being destroyed — it breaches and drains
## the Glow Battery (#53/#55 combat loop). Hook for screen-shake / red-flash / audio.
signal enemy_breached(at: Vector2, damage: float)
## A Fractal enemy was hit with insufficient firepower and split into fractlings
## (#53/#54 tier behaviour) instead of dying — hook for a split vfx/audio sting.
signal enemy_split(at: Vector2)
## A free enemy crossed a POSITIVE gate band and DUPLICATED (#53 cross-cutting:
## "an enemy crossing a + gate multiplies"). Hook for a clone-pop vfx/audio.
signal enemy_multiplied(at: Vector2)

# --- Gate events -------------------------------------------------------------
## A gate fired (#11/#56). CONSUMED BY GameState, which applies the economy effect
## (set the new swarm volume, drain the battery on a negative gate) — the spawner no
## longer reaches into GameState directly (CLAUDE.md decoupling). `new_count` is the
## gate's post-op count, already floored at 0; HUD/audio may also listen.
signal gate_passed(gate_type: String, value: float, new_count: int)
signal gate_spawned(gate: Node2D)
## A HIJACKED gate reached the ship line with its occupant still alive, so the splice
## was DENIED (#53 cross-cutting: "enemy parks in a gate, must be killed to claim the
## upgrade"). NOT a gate_passed — no economy effect applied. Hook for a denied sting /
## red flash / heavier haptic.
signal gate_hijack_blocked(gate_type: String, at: Vector2)

# --- Glow Battery (health / loss) --------------------------------------------
## Health = the Glow Battery (#55, §4.6). Re-emitted by GameState whenever it
## changes; the HUD bar reacts. `value`/`max_value` are in 0..max.
signal glow_battery_changed(value: float, max_value: float)
## Battery hit 0 — the grid collapses to a dead state. LOSS terminal (→ Results,
## loss path). Distinct from run_completed (the WIN, finish-line crossing).
signal grid_collapsed

# --- Level / distance --------------------------------------------------------
## Finite-level progress (D2/§4.5). Re-emitted by GameState each run tick:
## `distance` is metres travelled, `progress` is 0..1 toward the finish line.
## HUD + the scrolling FINISH bar react to this; nothing polls GameState.
signal distance_changed(distance: float, progress: float)

# --- Game flow ---------------------------------------------------------------
signal game_started
signal game_paused
signal game_resumed
signal game_over(final_score: int)
## WIN terminal (#51): the ship crossed the finish line. Triggers the
## "RUN COMPLETE" / Results screen (#44). Loss path (Glow Battery 0) is #55.
signal run_completed(final_score: int, distance: float)

# --- Scoring -----------------------------------------------------------------
signal score_changed(new_score: int)
signal multiplier_changed(new_multiplier: float)
signal combo_updated(combo_count: int)

# --- Effects -----------------------------------------------------------------
signal spawn_particles(position: Vector2, type: String)
signal trigger_screen_shake(intensity: float, duration: float)
signal trigger_grid_ripple(position: Vector2, is_implosion: bool)

# --- Settings / platform feel ------------------------------------------------
## AMOLED / low-power display mode toggled (#NEW, DESIGN_SPEC "Platform feel"). The
## Run environment swaps to a pitch-black clear + a dimmer bloom/grid path when on.
## Re-emitted by Settings whenever the flag changes so live toggling works.
signal amoled_mode_changed(enabled: bool)

# --- Loadout / Splice (meta-progression: #67 garage, #68 splice lab) ----------
## The player's ship loadout changed (hull / trail / engine). Garage commits via the
## Loadout autoload; the in-run ship recolours. Consumers read Loadout for the new values.
signal loadout_changed
## The equipped splice changed (#68) — the active spliced-weapon output was updated. The
## Splice Lab commits via the SpliceLab autoload; consumers read SpliceLab for the output.
signal splice_changed
