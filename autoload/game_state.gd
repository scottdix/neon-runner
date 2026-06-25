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
## HORDE (#90, H5): the survival-mode level. has_boss=false (auto-completes at length_m), a finite
## ~75 s survival length (600 m @ 8 m/s), EMPTY enemy_waves (the continuous fodder spawner
## Targets.set_horde replaces authored waves), and a +/×-ONLY gate_formations schedule — those gates
## are the PLAYER firepower-recovery mechanic (HORDE gates are add/mul only; enemies ignore them). The
## WIN is "survive to the finish": tick_run auto-completes at length_m because has_boss is false.
const HORDE_LEVEL_PATH := "res://data/level_horde.tres"

## Fire volume / swarm size. Drives the fleet's rate of fire (#52). Gates mutate
## this; the fleet and HUD react via Events, not direct calls.
var projectile_count: int = 0

## Stream STANCE (#79). SPRAY = the default wide light wall of fire; LANCE = a narrow
## heavy piercing beam. Gate polarity flips it: positive (+/×) gates -> SPRAY, focusing
## (−/÷) gates -> LANCE. SPRAY=0 so a bare Fleet's `_stance` default (0) IS SPRAY, and
## SPRAY is the run default so verify_combat's wide-stream invariants hold. GameState is
## the SINGLE owner of stance — it's set here (from gate_passed) and announced via Events.
enum Stance { SPRAY, LANCE }
const START_STANCE := Stance.SPRAY
var stance: int = Stance.SPRAY

var score: int = 0
var run_active: bool = false

## GEOM_OVERDRIVE POC (#87): a kill-fed resource the player burns to enter a LANCE "smart-bomb"
## overdrive. Run state — reset to 0 each run; kills add to it (add_geom on enemy_destroyed), the
## overdrive burn drains it (drain_geom), and it auto-reverts the stance to SPRAY when it empties.
## `overdrive_active` is the live LANCE-overdrive flag the Fleet/run.gd read for the visual spike.
## Inert unless Settings.poc_mode == GEOM_OVERDRIVE (the StanceController gates the activation).
const MAX_GEOM := 100.0
const GEOM_PER_KILL := 12.0          # charge gained per enemy destroyed (~8 kills to a full gauge)
var geom_charge: float = 0.0
var overdrive_active: bool = false

## In-run token wallet (#78). Tokens drop from kills and are absorbed by the ship; this
## holds the current run's haul. Reset to 0 in start_run; banked to the persistent SpliceLab
## wallet on BOTH terminals (complete_run AND fail_run). An abandoned-to-title run FORFEITS it
## (no bank call). Mutated only via collect_token, which announces tokens_changed.
var run_tokens: int = 0

## A boss is armed (#82/#83). While true, tick_run MUST NOT auto-complete on distance>=length —
## run.gd owns the boss and calls complete_run() on Events.boss_defeated. This guard is
## GameState's ONLY boss-related edit; the boss lives entirely in run.gd's scene tree.
var boss_active: bool = false

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

## HORDE (#90, H3) — FIREPOWER-AS-HEALTH. In HORDE the swarm volume (projectile_count) doubles as the
## loss channel: the run seeds this firepower at start (instead of START_PROJECTILES), a breach removes
## a chunk (drain_firepower), and the run fails when it hits 0. The Glow Battery is left inert in HORDE
## (no negative gates / no battery drain feed it — the battery bar is repurposed as the FIREPOWER bar by
## run.gd). Inert for LEGACY/KINETIC/GEOM, which seed START_PROJECTILES and bleed the battery as before.
const HORDE_START_FIREPOWER := 40

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

## Phase-scoped buff state (#84 phase 6). These are RESET to neutral on EVERY phase boundary
## (Events.phase_changed → _reset_phase_buffs) AND in start_run — a buff bought from an Efficiency
## gate lasts only for the phase it was claimed in (the "phase clear" is the next boundary). The
## Efficiency tradeoff lives here: geom_drain_mult scales LANCE charge burn (StanceController reads
## it), burst_damage_mult scales LANCE/overdrive per-hit weight (Fleet.hit_weight reads it).
var geom_drain_mult: float = 1.0
var burst_damage_mult: float = 1.0

## Tungsten armor-cracking buff (#84 phase 5) — GLOBAL / whole-run, NOT phase-scoped. Reset to 1.0
## in start_run ONLY (survives phase boundaries, so it is deliberately absent from _reset_phase_buffs).
## Scales the LANCE hit weight (Fleet.hit_weight), the single seam that drives Rhombus armor-cracking
## (there is no per-bullet pierce count — weight IS the cracking lever). Latches the highest mult seen.
var lance_hit_weight_mult: float = 1.0

## Gate-effect dispatch table (the seam): effect_id -> Callable handler. Populated in wire_events
## (so the bound _fx_* Callables capture this live autoload). Each handler is the SINGLE owner of
## the run-state mutation for its effect; _on_gate_effect looks the id up here and .call(params)s it,
## warning + no-op on an unknown id (forward-compatible with unshipped effects).
var _gate_effects: Dictionary = {}


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
	# Gate-effect dispatch seam: a NON-arithmetic gate emits Events.gate_effect (instead of
	# gate_passed) and GameState routes effect_id through this Callable table. A map keeps every
	# state mutation inside GameState (single-owner rule) and is O(1) to extend — new effects add a
	# row here + a _fx_* method, with no change to gate_passed or its count-semantics consumers.
	# Built here (not as a member initialiser) so the bound Callables capture this live instance.
	_gate_effects = {
		"geom_cache": _fx_geom_cache,
		"tungsten": _fx_tungsten,
		"efficiency": _fx_efficiency,
	}
	if not Events.gate_effect.is_connected(_on_gate_effect):
		Events.gate_effect.connect(_on_gate_effect)
	# Phase boundaries are the "phase clear" for phase-scoped buffs (#84 phase 6): the PhaseDirector
	# emits phase_changed ONLY on a forward boundary (there is no phase-clear event), so consuming it
	# here resets the per-phase Efficiency mults each time a new phase begins. Bound to a lambda that
	# discards the (index, name, config) args — the reset is unconditional, it doesn't read the phase.
	if not Events.phase_changed.is_connected(_on_phase_changed):
		Events.phase_changed.connect(_on_phase_changed)
	# GEOM_OVERDRIVE POC (#87): every kill feeds the overdrive charge. Listening here (not in the
	# StanceController) keeps the charge filling regardless of which POC is active, so switching modes
	# never strands a half-built gauge; the StanceController only GATES the burn on poc_mode.
	if not Events.enemy_destroyed.is_connected(_on_enemy_destroyed):
		Events.enemy_destroyed.connect(_on_enemy_destroyed)


## React to a gate firing (#11/#56). The gate's emitted `new_count` is already its
## post-op value floored at 0; we commit it (set_projectile_count re-clamps for
## safety) and, for a negative gate (−/÷), drain the Glow Battery — the risk side of
## the Split Choice. The spawner used to do this inline; now it only calls trigger().
func _on_gate_passed(gate_type: String, _value: float, new_count: int) -> void:
	set_projectile_count(new_count)
	# Stance follows gate polarity (#79): a POSITIVE gate (+/×) opens up to a wide SPRAY,
	# a NEGATIVE/focusing gate (−/÷) converges the stream into a heavy LANCE. set_stance is
	# idempotent (no-op + no signal when unchanged), so repeated same-polarity gates are free.
	# #86/#87: the gate→STANCE coupling only applies in the LEGACY POC. In the KINETIC_CLUTCH /
	# GEOM_OVERDRIVE POCs an alternative driver (StanceController) OWNS the stance, so a gate must not
	# fight it — but the projectile-count economy + the negative-gate battery drain stay unconditional
	# (a divide gate still costs charge and thins the swarm; it just no longer forces LANCE).
	var legacy: bool = int(Settings.poc_mode) == Settings.PocMode.LEGACY
	if gate_type == "subtract" or gate_type == "divide":
		if legacy:
			set_stance(Stance.LANCE)
		# #80: the negative-gate drain is mode-scaled (EASY 0.7 gentler, HARD 1.35 harsher).
		drain_battery(DRAIN_PER_NEGATIVE_GATE * Difficulty.drain_mult())
	elif legacy:
		set_stance(Stance.SPRAY)


## Dispatch a NON-arithmetic gate effect (the seam). A gate with a non-empty effect_id emits
## Events.gate_effect instead of gate_passed; we look effect_id up in the Callable table and run its
## handler (which owns the actual state mutation — single-owner rule). An unknown id warns and no-ops
## so an unshipped/typo'd effect fails soft rather than crashing the run. `at` is forwarded to the
## handlers that want a position (vfx); the stubs ignore it for now.
func _on_gate_effect(effect_id: String, params: Dictionary, _at: Vector2) -> void:
	var handler: Variant = _gate_effects.get(effect_id)
	if handler is Callable:
		(handler as Callable).call(params)
	else:
		push_warning("GameState: unknown gate effect_id '%s' — no-op" % effect_id)


## Gate effect handler (the seam). Bodies are STUBS — registered in _gate_effects so the dispatch
## compiles and routes today; the real economy mutation is filled in a later phase.
## Geom Cache (phase 4): instantly grant Geom charge. add_geom clamps to MAX_GEOM, emits
## geom_changed, and no-ops when !run_active — so this is a one-liner over the single owner.
func _fx_geom_cache(params: Dictionary) -> void:
	add_geom(float(params.get("amount", 40.0)))


## Tungsten (#84 phase 5): GLOBAL armor-cracking buff — raises the LANCE hit-weight multiplier for the
## REST of the run (not phase-scoped). LATCHES the highest mult seen (maxf) so re-claiming a weaker
## Tungsten can't downgrade an already-stronger one; reset only happens in start_run. Fleet.hit_weight
## folds this into the LANCE branch, which is what cracks Rhombus armor (weight is the only lever — no
## per-bullet pierce count to bump).
func _fx_tungsten(params: Dictionary) -> void:
	lance_hit_weight_mult = maxf(lance_hit_weight_mult, float(params.get("mult", 1.5)))


## Efficiency (#84 phase 6): the sustain-vs-burst tradeoff, PHASE-SCOPED (reset at the next boundary).
## SET (not stacked) — claiming it again within the same phase just re-applies the same values. Lowers
## the LANCE charge drain (StanceController reads geom_drain_mult) at the cost of LANCE/overdrive burst
## damage (Fleet.hit_weight reads burst_damage_mult): play longer in LANCE, hit softer per bullet.
func _fx_efficiency(params: Dictionary) -> void:
	geom_drain_mult = float(params.get("drain_mult", 0.6))
	burst_damage_mult = float(params.get("burst_mult", 0.75))


## Phase boundary reached (#84 phase 6) — the "phase clear" for phase-scoped buffs. Discards the
## (index, name, config) args; the reset is unconditional (a new phase always starts neutral).
func _on_phase_changed(_index: int, _name: String, _config: Dictionary) -> void:
	_reset_phase_buffs()


## Reset the PHASE-SCOPED buff mults to neutral (#84 phase 6). Called on EVERY phase boundary and in
## start_run. Deliberately does NOT touch lance_hit_weight_mult (Tungsten is global — whole-run).
func _reset_phase_buffs() -> void:
	geom_drain_mult = 1.0
	burst_damage_mult = 1.0


## Set the stream stance (#79) — the SINGLE place stance mutates. Idempotent: a no-op
## (no signal) when unchanged, else commit and announce via Events.stance_changed with the
## convenience `is_spray` bool so consumers (Fleet/HUD/grid) bind the int without the enum.
## Public so the verify + future hijack-cleared paths can drive it directly.
func set_stance(s: int) -> void:
	if s == stance:
		return
	stance = s
	Events.stance_changed.emit(stance, stance == Stance.SPRAY)


func is_spray() -> bool:
	return stance == Stance.SPRAY


## GEOM_OVERDRIVE (#87): add overdrive charge (kills feed it via _on_enemy_destroyed). Clamped to
## MAX_GEOM, announces geom_changed. No-op once the run ends so a late kill-burst can't refill it.
func add_geom(amount: float) -> void:
	if not run_active:
		return
	var prev: float = geom_charge
	geom_charge = clampf(geom_charge + absf(amount), 0.0, MAX_GEOM)
	if geom_charge != prev:
		Events.geom_changed.emit(geom_charge, MAX_GEOM)


## GEOM_OVERDRIVE (#87): drain overdrive charge (the LANCE burn spends it each tick). Clamped at 0,
## announces geom_changed. The StanceController watches for empty (geom_charge <= 0) to auto-revert.
func drain_geom(amount: float) -> void:
	var prev: float = geom_charge
	geom_charge = clampf(geom_charge - absf(amount), 0.0, MAX_GEOM)
	if geom_charge != prev:
		Events.geom_changed.emit(geom_charge, MAX_GEOM)


## GEOM_OVERDRIVE (#87): set the live LANCE-overdrive flag (the Fleet + run.gd read it for the visual
## spike). Idempotent + announces overdrive_changed only on an actual flip. The StanceController owns
## the transition logic (charge gate, triple-tap toggle, empty auto-revert); this is the state seam.
func set_overdrive_active(active: bool) -> void:
	if active == overdrive_active:
		return
	overdrive_active = active
	Events.overdrive_changed.emit(overdrive_active)


## Every kill feeds the GEOM_OVERDRIVE charge (#87), regardless of the active POC (so the gauge is
## never stranded by a mode switch). Wired in wire_events; the burn is gated elsewhere on poc_mode.
func _on_enemy_destroyed(_at: Vector2, _points: int) -> void:
	add_geom(GEOM_PER_KILL)


func start_run() -> void:
	active_level = _load_level()
	run_active = true
	run_won = false
	score = 0
	distance = 0.0
	run_tokens = 0                           # #78: fresh wallet each run (banked on a terminal)
	boss_active = false                      # #82/#83: no boss until run.gd arms it
	glow_battery = MAX_GLOW_BATTERY
	stance = START_STANCE                    # #79: every run starts in the wide SPRAY
	geom_charge = 0.0                        # #87: fresh overdrive gauge each run
	overdrive_active = false                 # #87: never start a run mid-overdrive
	lance_hit_weight_mult = 1.0              # #84 ph5: Tungsten is GLOBAL — reset ONLY here, not per-phase
	_reset_phase_buffs()                     # #84 ph6: neutral Efficiency mults for the run's first phase
	combo = 0
	combo_multiplier = 1.0
	_combo_timer = 0.0
	peak_multiplier = 1.0
	peak_fleet = 0
	best_combo = 0
	is_new_best = false
	# HORDE (#90, H3): firepower IS health — seed the bigger HORDE_START_FIREPOWER swarm (the loss channel)
	# instead of the small starter volume, and leave the Glow Battery inert (no negative gates feed it in
	# HORDE; run.gd repurposes the battery bar as the FIREPOWER readout). LEGACY/KINETIC/GEOM seed the
	# normal START_PROJECTILES and bleed the battery as before.
	if int(Settings.poc_mode) == Settings.PocMode.HORDE:
		set_projectile_count(HORDE_START_FIREPOWER)
	else:
		set_projectile_count(START_PROJECTILES)
	Events.score_changed.emit(score)
	Events.distance_changed.emit(distance, 0.0)
	Events.glow_battery_changed.emit(glow_battery, MAX_GLOW_BATTERY)
	Events.combo_updated.emit(combo)
	Events.multiplier_changed.emit(combo_multiplier)
	Events.tokens_changed.emit(run_tokens)   # #78: reset the in-run wallet display
	Events.geom_changed.emit(geom_charge, MAX_GEOM)  # #87: reset the overdrive gauge display
	Events.game_started.emit()


## HORDE (#90, H3): FIREPOWER-AS-HEALTH drain. A breach removes `streams` of the swarm volume via
## add_projectiles (which clamps >= 0 and emits projectile_count_changed, so the fleet thins/shatters
## and the run.gd FIREPOWER bar follows). When the firepower hits 0 the run fails — projectile_count IS
## the loss channel in HORDE. No-op once the run has ended (mirrors drain_battery). Only Targets._breach
## calls this, and only in HORDE; the Glow Battery stays inert there.
func drain_firepower(streams: int) -> void:
	if not run_active:
		return
	add_projectiles(-streams)
	if projectile_count <= 0:
		fail_run()


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
	_bank_tokens()                                # #78: a lost run still banks its haul
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
	# #82/#83: at the end of the track a boss arms (run.gd). A BOSS level NEVER auto-completes on
	# distance — run.gd arms the boss as the track ends and owns the WIN, calling complete_run() on
	# boss_defeated. This is the fix for the arming race: tick_run integrating past length_m used to
	# call complete_run() on the very crossing frame (boss_active was still false there because run.gd
	# hadn't run yet that frame), killing the run before the boss could arm. Gating on the level's
	# authored `has_boss` (not the transient boss_active flag) means the crossing frame can't end the
	# run. `boss_active` stays an extra guard so even a bossless-level race can't double-complete.
	var level_has_boss: bool = bool(active_level.get("has_boss")) if active_level.get("has_boss") != null else false
	if distance >= active_level.length_m and not level_has_boss and not boss_active:
		complete_run()


## WIN: crossed the finish line. Terminal — clamps distance to the line and emits
## run_completed (Run shows "RUN COMPLETE"). Loss path (Glow Battery 0) is #55.
func complete_run() -> void:
	if not run_active:
		return
	run_active = false
	run_won = true
	distance = active_level.length_m if active_level != null else distance
	_bank_tokens()                                # #78: a won run banks its haul
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
	# HORDE (#90, H5) swaps in the survival level (has_boss=false → auto-complete at length_m, empty
	# enemy_waves — the fodder spawner is the loop — plus a +/×-only firepower-recovery gate schedule).
	# LEGACY/KINETIC/GEOM keep the authored DEFAULT_LEVEL_PATH byte-for-byte. If the HORDE .tres is
	# somehow absent, fall back to a degenerate gate-less safety level (has_boss off, no formations) so
	# a HORDE run is always at least playable — survival still ends at length_m.
	if int(Settings.poc_mode) == Settings.PocMode.HORDE:
		var hv: Resource = load(HORDE_LEVEL_PATH)
		if hv == null:
			hv = LEVEL_DEF.new()
			hv.set("display_name", "Horde")
			hv.set("length_m", 600.0)
			hv.set("has_boss", false)
			hv.set("gate_formations", [])
			hv.set("enemy_waves", [])
		return hv
	var lv: Resource = load(DEFAULT_LEVEL_PATH)
	if lv == null:
		lv = LEVEL_DEF.new()
	return lv


func add_score(amount: int) -> void:
	score += amount
	Events.score_changed.emit(score)


## Collect a token into the in-run wallet (#78). Pure economy: NO score / register_kill /
## combo interaction (tokens are a separate meta currency from score). The TokenLayer calls
## this on a ship-touch pickup; we add the value and announce the new running total. Banked to
## the persistent SpliceLab wallet on a terminal; forfeited on an abandoned-to-title run.
func collect_token(value: int) -> void:
	run_tokens += value
	Events.tokens_changed.emit(run_tokens)


## Bank this run's token haul into the persistent SpliceLab wallet (#78). Called on BOTH
## terminals (complete_run AND fail_run) — only an abandoned-to-title run forfeits. Null-safe
## via get_node_or_null so the headless `-s` verify loop (where the SpliceLab autoload may be
## absent for an isolated GameState test) doesn't crash. Run-state owner stays GameState; the
## wallet's mutation/persistence is SpliceLab's job (deposit_tokens persists + emits draft_changed).
func _bank_tokens() -> void:
	if run_tokens <= 0:
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var lab: Node = (loop as SceneTree).root.get_node_or_null("SpliceLab")
		if lab != null and lab.has_method("deposit_tokens"):
			lab.call("deposit_tokens", run_tokens)


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
