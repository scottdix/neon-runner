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
## Stream STANCE changed (#79). The fire mode flips between SPRAY (wide, light, many
## bullets) and LANCE (narrow, heavy, piercing, fewer bullets) as the player crosses
## gates: positive (+/×) gates set SPRAY, focusing (−/÷) gates set LANCE. Emitted ONLY
## by GameState.set_stance on an ACTUAL change (single owner of run-state). `is_spray`
## is the convenience bool (== stance == GameState.Stance.SPRAY) so Fleet/HUD/grid bind
## the int without importing the enum.
signal stance_changed(stance: int, is_spray: bool)
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
## Full-screen colour flash (#23 FeedbackManager). A CanvasLayer ColorRect snaps to
## `color` and fades to transparent over `duration` s. Consumed by FeedbackManager;
## emitted on impactful beats (gate hijack denied / breach / collapse) alongside shake.
signal trigger_screen_flash(color: Color, duration: float)
signal trigger_grid_ripple(position: Vector2, is_implosion: bool)
## A music BEAT landed (#61 adaptive audio). AudioManager runs a beat clock locked to the
## game bed's bass-note tempo and emits this on each onset; `strength` is 0..1 with the bar
## DOWNBEAT (the bass root) strongest. GridFloor turns it into a global brightness/warp
## "breath" so the grid pulses to the music — the music-reactive half of #61 (the gameplay
## ripples on trigger_grid_ripple are the action-reactive half).
signal music_beat(strength: float)
## A swarm-volume milestone was crossed (#28). The MilestoneBanner watches
## projectile_count_changed and emits this once per threshold (100/500/1000) so audio
## (fanfare), haptics (heavy), and effects can punctuate the celebration. `count` is the
## milestone value crossed, not the live projectile_count.
signal milestone_reached(count: int)

# --- Settings / platform feel ------------------------------------------------
## AMOLED / low-power display mode toggled (#NEW, DESIGN_SPEC "Platform feel"). The
## Run environment swaps to a pitch-black clear + a dimmer bloom/grid path when on.
## Re-emitted by Settings whenever the flag changes so live toggling works.
signal amoled_mode_changed(enabled: bool)
## Difficulty mode changed (#80). 0=EASY 1=MEDIUM 2=HARD. Emitted ONLY by Settings.set_difficulty
## on an actual change; the Difficulty autoload re-reads its active profile on this, and any open
## settings UI refreshes its selector. Single owner = Settings (persists the int).
signal difficulty_changed(mode: int)

# --- Loadout / Splice (meta-progression: #67 garage, #68 splice lab) ----------
## The player's ship loadout changed (hull / trail / engine). Garage commits via the
## Loadout autoload; the in-run ship recolours. Consumers read Loadout for the new values.
signal loadout_changed
## The equipped splice changed (#68) — the active spliced-weapon output was updated. The
## Splice Lab commits via the SpliceLab autoload; consumers read SpliceLab for the output.
signal splice_changed

# --- Boss (#82/#83) ----------------------------------------------------------
## A boss armed at the end of the track. `max_hp` seeds the boss HP bar. Emitted ONCE
## by the boss on spawn; run.gd flips GameState.boss_active so tick_run stops auto-completing.
signal boss_spawned(boss_name: String, max_hp: float)
## A boss crossed into a new phase. Emitted ONCE per transition (TELEGRAPH / ARMORED /
## ADD_SWARM / DEFEATED); HUD/audio/vfx punctuate. `phase` is the int, `phase_name` the label.
signal boss_phase_changed(phase: int, phase_name: String)
## The boss reached HP<=0. Emitted ONCE; run.gd consumes this and calls
## GameState.complete_run() (the boss is the run's WIN terminal — GameState never auto-completes
## while boss_active). `at` is the death position for the kill vfx.
signal boss_defeated(boss_name: String, at: Vector2)

# --- Economy / tokens (#78) --------------------------------------------------
## A token dropped from a destroyed enemy (Targets._kill). `value` is the bounty; the
## TokenLayer spawns a drifting pickup at `at`.
signal token_dropped(at: Vector2, value: int)
## A drifting token was absorbed by the ship (TokenLayer, on touch within the magnet radius).
## `wallet_total` is the IN-RUN running total AFTER this pickup (== GameState.run_tokens, the same
## value tokens_changed carries) — NOT the persistent SpliceLab.tokens wallet (that's only updated
## when the run BANKS on a terminal). A chime/HUD reading this gets the live run subtotal. Hook for a
## pickup chime/vfx.
signal token_collected(at: Vector2, value: int, wallet_total: int)
## The in-run token count changed (GameState.collect_token). `in_run` is the live run total;
## HUD binds it. Banked to the persistent SpliceLab wallet on a terminal.
signal tokens_changed(in_run: int)
## The meta draft mutated (SpliceLab shelf / wallet / perks). The Splice Lab screen re-renders
## off this (Events-bus decoupling) — it never holds a direct ref to the lab.
signal draft_changed

# --- Phase director (#59) ----------------------------------------------------
## The run crossed a phase boundary (PhaseDirector, DISTANCE-keyed off GameState.distance).
## `config` carries {grid_mode, spawn_density_mult, gate_speed_mult, gate_moving, gravity}.
## v1 consumers: grid_floor may read grid_mode; spawn/gate consumption is deferred.
signal phase_changed(phase_index: int, phase_name: String, config: Dictionary)
## A gravity field is active (PhaseDirector when the live phase's gravity != 0; the Singularity
## boss REUSES this — there is no boss-specific gravity signal). `direction` is a NORMALIZED unit
## pull vector; `strength` is a NORMALIZED 0..1 magnitude (BOTH emitters honour this one unit so a
## single consumer shares one scale — the director emits grav.normalized()/grav.length() of its unit
## SINGULARITY vector, the boss emits the unit core-direction + its 0..1 collapse pulse). The actual
## px/s² pull acceleration is INTERNAL to the boss's pure helpers (gravity_on_projectile/pull_on_ship),
## which run.gd consumes directly for the live bullet/ship bias — this signal is the cosmetic
## broadcast (grid warp / ship feel), not the force scale.
signal gravity_shift(direction: Vector2, strength: float)
