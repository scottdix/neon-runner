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
	Events.tokens_changed.emit(run_tokens)   # #78: reset the in-run wallet display
	Events.geom_changed.emit(geom_charge, MAX_GEOM)  # #87: reset the overdrive gauge display
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
