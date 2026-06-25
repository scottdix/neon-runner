class_name Targets
extends Node2D
## The Entropy faction — shootable enemies the fleet fights (#53/#54/#14). Three
## archetypes with distinct behaviour, plus the fractlings a Fractal spawns:
##
##   • GLITCH    — fast, low-HP swarm. The bread-and-butter target (MVP enemy).
##   • RHOMBUS   — slow, dense, ARMORED: shrugs off a thin stream; only a swarm
##                 firing hard enough (hits/frame above its armor) chips it. Models
##                 "force a weapon upgrade to crack" via firepower, not a flat wall.
##   • FRACTAL   — splits into two faster fractlings when killed with INSUFFICIENT
##                 firepower (swarm volume below the split tier); a strong swarm
##                 vaporises it outright. "Insufficient firepower splits it" (#53).
##   • FRACTLING — the small fast shards a Fractal leaves behind; can't re-split.
##
## Spawning is SEGMENT-DRIVEN + FINITE (#13): Run injects the level's `enemy_waves`
## schedule via set_schedule(); each wave spawns its enemies (at authored world-x) when
## the run's distance reaches its `m` mark, and killed/breached/offscreen enemies are
## REMOVED (no endless respawn). The level is therefore a finite, authored sequence of
## waves, not an infinite spawner. spawn(n) remains for tests / ad-hoc bursts.
##
## Damage is resolved in ONE batched pass (Fleet.consume_volumes): all enemies are
## queried against the live bullets together, not one consume_near() per enemy — the
## D3 batched collision layer (#54), with an x-band cull so cost stays ~O(bullets)
## as the swarm + enemy counts scale (#14). Enemies that reach the ship line BREACH:
## they drain the Glow Battery (#55) and emit enemy_breached — so ignoring them now
## costs you, closing the combat loop. Kills score through GameState.register_kill
## (combo multiplier). Sim is in step() so it runs/asserts headless with no GPU.

## KIND_LANEBOSS (#90, H4) is the HORDE 20-s LANE-BOSS: a heavy single enemy that spawns on an
## ALTERNATING side of the firing divider every LANEBOSS_INTERVAL. It rides the EXISTING MultiMesh /
## consume_volumes / _apply_damage / _kill path (no new collision/render code) — it's just a fat,
## unarmored, high-point archetype with a moderate breach cost. Beatable now: a representative SPRAY
## DPS clears its ~600 hp inside a bounded time (the verify asserts this). Appended LAST so the existing
## enum ordinals (GLITCH=0…FRACTLING=3) are byte-for-byte unchanged — no other archetype shifts.
enum { KIND_GLITCH, KIND_RHOMBUS, KIND_FRACTAL, KIND_FRACTLING, KIND_LANEBOSS }

## MAX_ENEMIES raised 48 -> 128 for HORDE (#90, H2): the continuous fodder spawner sustains a
## far denser live set than the authored waves ever did. The MultiMesh instance_count tracks this
## (MAX_ENEMIES + MAX_BURSTS) so the render path can show the full cap. LEGACY/KINETIC/GEOM never
## approach the old 48 with the sparse authored schedule, so the higher cap is inert for them.
const MAX_ENEMIES := 128
const MAX_BURSTS := 24
## P3: the GENEROUS HARD MultiMesh enemy buffer, sized once at build. MAX_ENEMIES is only the LEGACY
## fodder default; the live HORDE soft cap is Debug.enemy_cap (UNBOUNDED, default 256), so the render
## buffer must comfortably exceed 256 to let the designer push toward the perf wall without rebuilding.
const MMI_HARD_MAX := 1024
const DIAMOND_TEX_SIZE := 48
const BASE_QUAD := 96.0             # MultiMesh quad size; per-instance scaled by size

const DAMAGE_PER_BULLET := 10.0
## Armor "chip" floor (#74): a stream AT/BELOW an enemy's armor still does this fraction
## of one bullet's damage per frame (only while it's actually being hit). It keeps the
## "a dense swarm cracks armor faster" intent but removes the hard lockout that made a
## thinned-out Rhombus literally unkillable — a sustained sub-armor stream now eventually
## wins, while a single stray hit stays negligible (one frame = 0.15 bullet ≈ 1.5 hp).
const ARMOR_CHIP_FRACTION := 0.15
## Rhombus per-hit armor FLOOR (#79): the per-bullet DAMAGE WEIGHT a single bullet must
## reach to CRACK an armored enemy. A SPRAY bullet (weight 1.0) is below it -> chips only; a
## LANCE bullet (weight 6.0) clears it -> full damage. This replaces the old "hits above an
## int armor count" model with a per-hit threshold: armor is now a quality gate (need a heavy
## bullet), not a quantity gate (need many bullets). Set above SPRAY_HIT_WEIGHT, below LANCE.
const RHOMBUS_PER_HIT_FLOOR := 5.0
## Per-run difficulty seam (#80 populates; #79 ships the field + neutral default). Scales the
## per-hit floor so a harder mode demands an even heavier bullet to crack armor.
var armor_floor_mult: float = 1.0
const CONSUME_PAD := 10.0           # collision radius = visible half-size + this
const FLASH_DECAY := 0.06           # seconds an impact flash-pulse lasts (shortened for a snappier per-hit pop, #88)
const BURST_LIFE := 0.30            # seconds a death burst lives

## A Fractal hit while the swarm volume is below this "tier" splits instead of dying.
## Above it, the fleet has enough firepower to destroy it cleanly.
const FRACTAL_SPLIT_TIER := 60

## Wave spawning (#13): enemies in a wave enter from above the top, staggered, and the
## wave clears `WAVE_EDGE_MARGIN` of the screen edges for its world-x spread.
const WAVE_STAGGER := 70.0          # vertical gap (px) between successive enemies in a wave
const WAVE_EDGE_MARGIN := 160.0     # keep wave enemies this far from each screen edge
const WAVE_DEFAULT_SPREAD := 220.0  # half-width (px) of a clustered wave when "x" is given

## Multiply-through (#53): a free enemy duplicates when its y comes within this band of a
## POSITIVE gate's y while inside the gate's x-span (≈ the gate panel's half-height).
const MULTIPLY_BAND := 80.0

## Per-archetype stat block. Looked up by kind; enemies carry a copy so test code can
## still inject bare dicts (they default to GLITCH behaviour via the get() fallbacks).
## `streams` (#90, H3) is the FIREPOWER cost a breach inflicts in HORDE, where projectile_count IS the
## loss channel: a breaching enemy removes this many streams of swarm volume (GameState.drain_firepower)
## and you die at 0. GLITCH fodder costs 1; the tougher archetypes cost proportionally more. Inert
## outside HORDE — there a breach drains the Glow Battery by `breach` as before (the `breach` field is
## untouched, so LEGACY/KINETIC/GEOM are byte-for-byte unchanged).
const STATS := {
	KIND_GLITCH:    {"hp": 40.0,  "size": 52.0,  "spd": [220.0, 320.0], "armor": 0, "points": 50,  "breach": 6.0,  "split": false, "streams": 1},
	KIND_RHOMBUS:   {"hp": 320.0, "size": 108.0, "spd": [70.0, 120.0],  "armor": 3, "points": 250, "breach": 18.0, "split": false, "streams": 6},
	KIND_FRACTAL:   {"hp": 110.0, "size": 78.0,  "spd": [130.0, 200.0], "armor": 0, "points": 120, "breach": 10.0, "split": true,  "streams": 3},
	KIND_FRACTLING: {"hp": 28.0,  "size": 42.0,  "spd": [280.0, 380.0], "armor": 0, "points": 40,  "breach": 4.0,  "split": false, "streams": 1},
	KIND_LANEBOSS:  {"hp": 600.0, "size": 150.0, "spd": [90.0, 110.0],  "armor": 0, "points": 1000, "breach": 24.0, "split": false, "streams": 10},
}

# Per-archetype HDR colour now lives in Palette (Entropy faction = hot rose #ff007f).
# Direction (session 12): one faction hue, varied by INTENSITY (not hue) so the four
# archetypes read as one faction but stay tellable apart. See _enemy_color().

var _design := Vector2(1080, 1920)
var _fleet: Node2D                  # injected by Run; queried for bullet hits
var _breach_line: float = 1.0e9     # disabled until Run injects the ship line (set_breach_line)
var _gates: Node2D = null           # injected GateSpawner; queried for #53 interactions (null-safe)
var _waves: Array = []              # [{m, kind, count, x?, spread?, spawned:bool}, ...] schedule
var _enemies: Array[Dictionary] = []
var _bursts: Array = []             # [{pos:Vector2, life:float, col:Color}, ...] death pops
var _rng := RandomNumberGenerator.new()
var _mmi: MultiMeshInstance2D
var kills: int = 0
var breaches: int = 0               # enemies that reached the ship line (debug/verify)

# --- HORDE continuous spawner (#90, H2) -------------------------------------
## True only in HORDE: the field is fed by a CONTINUOUS ramping fodder spawner (KIND_GLITCH) instead
## of (only) the authored waves. Run flips this on via set_horde(true) when poc_mode == HORDE. The
## authored-wave path (_spawn_due_waves) still runs underneath, harmless if the level has no waves.
var _horde_active: bool = false
## Fractional-spawn accumulator: _horde_rate() enemies/sec accrue here; whole units spawn, the
## fraction carries to the next frame so a sub-1/frame rate still spawns smoothly over time.
var _horde_accum: float = 0.0
## HORDE fodder spawn rate ramp (enemies/sec): lerps from MIN at run start to MAX at the finish so
## the pressure climbs across the (finite) run. Scaled by Difficulty.spawn_density_mult when present.
const HORDE_RATE_MIN := 2.0
const HORDE_RATE_MAX := 8.0
## Keep HORDE fodder clear of the centre divider (firing boundary) by this margin, and inside the
## screen edges by WAVE_EDGE_MARGIN, so every spawn lands cleanly in the LEFT or RIGHT half-field.
const HORDE_CENTER_GAP := 60.0

# --- HORDE 20-s LANE-BOSS (#90, H4) ------------------------------------------
## Every LANEBOSS_INTERVAL of HORDE step() time, ONE KIND_LANEBOSS spawns on an ALTERNATING side of
## the firing divider (left, then right, then left…) at that lane's centre-x, and Events.lane_boss_spawned
## is emitted so run.gd can telegraph it. The accumulator advances only while HORDE is active AND the
## run is live, so paused/non-HORDE time never advances it. Inert outside HORDE (LEGACY/KINETIC/GEOM
## never set_horde(true), and the step() gate also checks _is_horde()).
const LANEBOSS_INTERVAL := 20.0
var _boss_accum: float = 0.0
## Which side the NEXT lane-boss spawns on: starts LEFT (0), flips each spawn so bosses alternate
## sides across the run. Reset by set_horde so each run begins on the LEFT.
var _boss_next_side: int = 0


func _ready() -> void:
	_rng.seed = 0xDA77
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_build_multimesh()
	# No initial spawn — enemies arrive via the scheduled waves (set_schedule).


func _process(delta: float) -> void:
	step(delta)
	_render()


## The fleet whose projectiles damage these targets (Run injects it; Fleet and
## Targets never reference each other directly).
func set_fleet(fleet: Node2D) -> void:
	_fleet = fleet


## The canvas y of the ship line: an enemy crossing it BREACHES (drains battery).
## Run injects the ship's y; left disabled (huge) for unit tests that don't want it.
func set_breach_line(y: float) -> void:
	_breach_line = y


## The gate system, for the #53 cross-cutting interactions (gate-hijack +
## multiply-through). One-way: Targets QUERIES the spawner (positive_gate_bands,
## take_pending_hijacks, gate_info) and reports occupant deaths (notify_hijack_cleared).
## The spawner never holds a reference back. Null-safe — unset in unit tests.
func set_gates(gates: Node2D) -> void:
	_gates = gates


## Arm/disarm the HORDE continuous fodder spawner (#90, H2). Run calls set_horde(true) only when
## poc_mode == HORDE; LEGACY/KINETIC/GEOM never call it, so _spawn_horde is fully inert for them
## (the step() gate also short-circuits on it). Resets the accumulator so each run starts clean.
func set_horde(active: bool) -> void:
	_horde_active = active
	_horde_accum = 0.0
	_boss_accum = 0.0
	_boss_next_side = 0   # first lane-boss of the run spawns on the LEFT, then alternates


## Install the level's enemy-wave schedule (#13). Each wave is duplicated and tagged
## `spawned:false` so we never mutate the LevelDef's shared dicts (that would leak the
## spawned flag across runs). Waves fire by `m` as the run's distance reaches them.
func set_schedule(waves: Array) -> void:
	_waves = []
	for w in waves:
		var c: Dictionary = (w as Dictionary).duplicate()
		c["spawned"] = false
		_waves.append(c)


func scheduled_wave_count() -> int:
	return _waves.size()


## Spawn a single boss ADD (#82/#83). The Boss declares add INTENT only ({kind, x}) and run.gd
## hands each queued add here every frame — the boss never holds a Targets ref (decoupled). The
## add enters from above the top like a wave enemy, at the boss's authored world-x (edge-clamped).
## No-op once the field is full so a long boss fight can't overflow the live set.
func spawn_add(a: Dictionary) -> void:
	if _enemies.size() >= MAX_ENEMIES:
		return
	var kind: int = _kind_from_string(String(a.get("kind", "glitch")))
	var e: Dictionary = _new_enemy(kind, -float(STATS[kind]["size"]))
	var p: Vector2 = e["pos"]
	p.x = clampf(float(a.get("x", _design.x * 0.5)), WAVE_EDGE_MARGIN, _design.x - WAVE_EDGE_MARGIN)
	e["pos"] = p
	_enemies.append(e)


## Immediately spawn n enemies (weighted archetype mix) scattered down the upper track.
## Not the gameplay path (that's scheduled waves) — kept for tests / ad-hoc bursts.
func spawn(n: int) -> void:
	_enemies.clear()
	for i in mini(n, MAX_ENEMIES):
		_enemies.append(_new_enemy(_pick_kind(), _rng.randf() * _design.y * 0.4))


## Spawn any scheduled wave whose `m` mark the run has now reached (#13). Enemies enter
## from above the top, staggered, at the wave's authored world-x. No-op without a
## schedule or while the run is inactive.
func _spawn_due_waves() -> void:
	if _waves.is_empty() or not GameState.run_active:
		return
	var d: float = GameState.distance
	for w in _waves:
		if not bool(w["spawned"]) and d >= float(w["m"]):
			# Defer (don't mark spawned) if the field is full, so a wave is never
			# silently lost wholesale — it spawns once room frees up. (With the MVP
			# schedule total < MAX_ENEMIES this never triggers, but it keeps the wave
			# logic correct in isolation for denser future levels.)
			if _enemies.size() >= MAX_ENEMIES:
				continue
			w["spawned"] = true
			_spawn_wave(w)


func _spawn_wave(w: Dictionary) -> void:
	var count: int = int(w["count"])
	var kind_name: String = String(w.get("kind", "glitch"))
	for i in count:
		if _enemies.size() >= MAX_ENEMIES:
			break
		var kind: int = _kind_from_string(kind_name)   # "mixed" re-rolls per enemy
		var start_y: float = -float(STATS[kind]["size"]) - float(i) * WAVE_STAGGER
		var e: Dictionary = _new_enemy(kind, start_y)
		var p: Vector2 = e["pos"]
		p.x = _wave_x(w, i, count)                      # world-x placement (NOT lanes)
		e["pos"] = p
		_enemies.append(e)


## World-x for enemy `i` of a `count`-wide wave. Clustered around `x` (± spread) if the
## wave authored one, else spread evenly across the playfield between the edge margins.
func _wave_x(w: Dictionary, i: int, count: int) -> float:
	if w.has("x"):
		if count <= 1:
			return float(w["x"])
		var spread: float = float(w.get("spread", WAVE_DEFAULT_SPREAD))
		var off: float = lerpf(-spread, spread, float(i) / float(count - 1))
		return clampf(float(w["x"]) + off, WAVE_EDGE_MARGIN, _design.x - WAVE_EDGE_MARGIN)
	if count <= 1:
		return _design.x * 0.5
	return lerpf(WAVE_EDGE_MARGIN, _design.x - WAVE_EDGE_MARGIN, float(i) / float(count - 1))


## HORDE continuous fodder spawn (#90, H2). No-op unless armed (set_horde) AND the run is active. Each
## frame accrues _horde_rate()*delta enemies into _horde_accum; whole units spawn this frame (the
## fraction carries) as KIND_GLITCH one-hit fodder at a RANDOM lane x clustered in the LEFT or RIGHT
## half-field (clear of CENTER_X). Respects MAX_ENEMIES — once the field is full we stop draining the
## accumulator (cap it at 1) so it doesn't build a huge backlog that floods the instant room frees.
func _spawn_horde(delta: float) -> void:
	if not _horde_active or not GameState.run_active:
		return
	# P3 designer knob: Enemies:Off suppresses the FODDER spawner only (the lane-boss path
	# _step_laneboss/_spawn_laneboss is intentionally NOT gated, so a boss still arrives).
	var dbg: Node = _debug_node()
	if dbg != null and dbg.has_method("enemies_on") and not bool(dbg.call("enemies_on")):
		return
	# Soft spawn cap (Debug.enemy_cap, UNBOUNDED) supersedes the MAX_ENEMIES const here so the
	# designer can push past 256 toward the perf wall (the MultiMesh HARD buffer is the real ceiling).
	var soft_cap: int = _enemy_soft_cap()
	_horde_accum += _horde_rate() * delta
	while _horde_accum >= 1.0:
		if _enemies.size() >= soft_cap:
			_horde_accum = minf(_horde_accum, 1.0)   # field full — hold (don't backlog)
			return
		_horde_accum -= 1.0
		_enemies.append(_new_horde_fodder())


## The live FODDER spawn cap. Defaults to MAX_ENEMIES; Debug.enemy_cap() overrides it when the
## autoload is present (UNBOUNDED — the designer can exceed 256). Null-safe for bare verifies.
func _enemy_soft_cap() -> int:
	var dbg: Node = _debug_node()
	if dbg != null and dbg.has_method("cap"):
		return int(dbg.call("cap"))
	return MAX_ENEMIES


## The fodder spawn rate (enemies/sec) for THIS frame: lerps HORDE_RATE_MIN -> HORDE_RATE_MAX across
## run progress (distance / level length), so the swarm thickens as the finite run advances. Scaled by
## Difficulty.spawn_density_mult when that autoload is present (a harder mode spawns denser). Pure +
## null-safe (a bare unit-test Targets with no Difficulty / no active_level falls back to MIN at p=0).
func _horde_rate() -> float:
	var base: float = lerpf(HORDE_RATE_MIN, HORDE_RATE_MAX, _run_progress())
	var diff: Node = _difficulty_node()
	if diff != null and diff.has_method("spawn_density_mult"):
		base *= float(diff.call("spawn_density_mult"))
	# P3 designer knob: density multiplier (NEUTRAL 1.0 = no change). Null-safe.
	var dbg: Node = _debug_node()
	if dbg != null and dbg.has_method("density_mult"):
		base *= float(dbg.call("density_mult"))
	return base


## Run progress 0..1 (distance / level length). Null-safe: 0.0 when there's no active level (the
## bare-instance verify drives step() directly without start_run, so it stays at MIN unless it
## injects a level) — the verify forces the ramp by faking distance via the active level instead.
func _run_progress() -> float:
	var lvl: Resource = GameState.active_level
	if lvl == null:
		return 0.0
	var length: float = float(lvl.get("length_m")) if lvl.get("length_m") != null else 0.0
	if length <= 0.0:
		return 0.0
	return clampf(GameState.distance / length, 0.0, 1.0)


## A single HORDE fodder enemy (#90, H2): KIND_GLITCH one-hit fodder entering from above the top, at a
## random x clustered into the LEFT or RIGHT half-field (a coin-flip), kept clear of CENTER_X by
## HORDE_CENTER_GAP and inside the screen by WAVE_EDGE_MARGIN. Both halves are reachable so the field
## fills on both sides of the firing boundary (the verify asserts enemies appear in BOTH halves).
func _new_horde_fodder() -> Dictionary:
	var e: Dictionary = _new_enemy(KIND_GLITCH, -float(STATS[KIND_GLITCH]["size"]))
	var left: bool = _rng.randf() < 0.5
	var x: float
	if left:
		x = _rng.randf_range(WAVE_EDGE_MARGIN, HORDE_CENTER_X - HORDE_CENTER_GAP)
	else:
		x = _rng.randf_range(HORDE_CENTER_X + HORDE_CENTER_GAP, _design.x - WAVE_EDGE_MARGIN)
	var p: Vector2 = e["pos"]
	p.x = x
	e["pos"] = p
	# P3 designer knobs (FODDER ONLY — the lane-boss path never routes through here): scale this
	# enemy's march speed and its hp/max_hp. Both NEUTRAL at 1.0 (byte-identical to today). Null-safe.
	var dbg: Node = _debug_node()
	if dbg != null:
		if dbg.has_method("speed_mult"):
			e["speed"] = float(e["speed"]) * float(dbg.call("speed_mult"))
		if dbg.has_method("strength_mult"):
			var sm: float = float(dbg.call("strength_mult"))
			e["hp"] = float(e["hp"]) * sm
			e["max_hp"] = float(e["max_hp"]) * sm
	return e


## HORDE 20-s LANE-BOSS timer (#90, H4). No-op unless HORDE is armed AND the run is active. Accrues
## step() time into _boss_accum; each whole LANEBOSS_INTERVAL spawns ONE KIND_LANEBOSS via
## _spawn_laneboss (carrying the fraction to the next frame, like the fodder accumulator), so a single
## frame can only ever spawn one (a frame ≪ 20 s). Inert for LEGACY/KINETIC/GEOM (gated on _is_horde +
## _horde_active so neither the live Settings path nor a forced-horde verify advances it off-mode).
func _step_laneboss(delta: float) -> void:
	if not _horde_active or not GameState.run_active or not _is_horde():
		return
	_boss_accum += delta
	while _boss_accum >= LANEBOSS_INTERVAL:
		_boss_accum -= LANEBOSS_INTERVAL
		_spawn_laneboss()


## Spawn ONE KIND_LANEBOSS at the next (alternating) lane's centre-x and emit lane_boss_spawned (#90,
## H4). The side flips each call so bosses alternate LEFT/RIGHT across the run. No-op once the field is
## full (a long run can't overflow the cap), but the side STILL flips so the alternation isn't desynced
## by a skipped spawn. It enters from above the top like a wave enemy and rides the existing
## MultiMesh/consume_volumes/_apply_damage/_kill path — no new collision or render code.
func _spawn_laneboss() -> void:
	var side: int = _boss_next_side
	_boss_next_side = 1 - _boss_next_side          # alternate even if we can't spawn this time
	# Boss is HORDE-only, so gate on the live SOFT cap (Debug.enemy_cap, UNBOUNDED, default 256) — not
	# the LEGACY MAX_ENEMIES const — so a dialed-up fodder field can't intermittently starve the boss.
	if _enemies.size() >= _enemy_soft_cap():
		return
	var e: Dictionary = _new_enemy(KIND_LANEBOSS, -float(STATS[KIND_LANEBOSS]["size"]))
	var p: Vector2 = e["pos"]
	p.x = _laneboss_x(side)
	e["pos"] = p
	_enemies.append(e)
	Events.lane_boss_spawned.emit(side, p)


## Centre-x of a divider side's half-field (0 LEFT / 1 RIGHT) for a lane-boss spawn: the midpoint of
## the playable span between the screen edge margin and the divider gap, so the boss lands cleanly in
## that half (never on CENTER_X). Pure — mirrors LaneArena's lane geometry without reaching for a node.
func _laneboss_x(side: int) -> float:
	var inner: float = HORDE_CENTER_X - HORDE_CENTER_GAP
	var outer: float = HORDE_CENTER_X + HORDE_CENTER_GAP
	if side == 0:
		return (WAVE_EDGE_MARGIN + inner) * 0.5                       # LEFT half centre
	return (outer + (_design.x - WAVE_EDGE_MARGIN)) * 0.5             # RIGHT half centre


func _kind_from_string(s: String) -> int:
	match s:
		"glitch": return KIND_GLITCH
		"rhombus": return KIND_RHOMBUS
		"fractal": return KIND_FRACTAL
		"fractling": return KIND_FRACTLING
		"mixed": return _pick_kind()
	return KIND_GLITCH


## Advance one frame. (0) spawn any scheduled wave now due; (1) batched damage — every
## enemy's hit volume resolved against the live bullets in ONE Fleet.consume_volumes
## call; (2) movement + lifecycle, rebuilding the live set so killed/breached/offscreen
## enemies are REMOVED (finite, no respawn) and Fractal splits add fractlings.
## Pure + GPU-free for headless.
func step(delta: float) -> void:
	# (0) Scheduled spawns (#13). No-op without a schedule or while the run is inactive.
	_spawn_due_waves()
	# (0a) HORDE continuous fodder (#90, H2). Only fires when set_horde(true) was called (HORDE mode)
	# and the run is active; ramps a fodder rate and spawns KIND_GLITCH into the half-fields. Inert
	# (early-returns) for LEGACY/KINETIC/GEOM, so their spawning is byte-for-byte unchanged.
	_spawn_horde(delta)
	# (0a2) HORDE 20-s LANE-BOSS (#90, H4). Only fires in HORDE while the run is active: a timer accrues
	# step() time and every LANEBOSS_INTERVAL spawns ONE KIND_LANEBOSS on the next (alternating) side.
	# Inert (early-returns) for LEGACY/KINETIC/GEOM, so their behaviour is byte-for-byte unchanged.
	_step_laneboss(delta)
	# (0b) Park occupants on any newly-hijacked gates (#53). No-op without a gate system.
	# HORDE (#90, P5): gates are PLAYER-only — enemies must NEVER hijack/occupy a gate. The HORDE schedule
	# authors no "hijack" sides, but suppress the park path here too so a stray pending hijack can never
	# spawn an occupant on a firepower-recovery gate. LEGACY/KINETIC/GEOM keep the #53 hijack intact.
	if _gates != null and not _is_horde():
		for h in _gates.call("take_pending_hijacks"):
			_spawn_hijacker(h)

	# (1) Batched projectile→enemy damage (#54). One pass over the bullets for ALL
	# enemies instead of one survivor-rebuild per enemy.
	#
	# HORDE far-side FILTER (#90, H1): the centre divider is a firing boundary — the fleet only
	# DAMAGES enemies on the SAME side of CENTER_X as the muzzle (_fleet.position.x). In HORDE we
	# therefore only feed the near-side enemies' volumes into consume_volumes, and keep an index map
	# (`idx_map`) so the returned hit counts re-align to the correct _enemies entry. Far-side enemies
	# still render/descend/breach — they just take no hits this frame. Outside HORDE idx_map is the
	# identity (every enemy fed) so LEGACY/KINETIC/GEOM behaviour is byte-for-byte unchanged.
	if _fleet != null and not _enemies.is_empty():
		var horde: bool = _is_horde()
		var fleet_side: int = _fleet_side() if horde else -1
		var positions := PackedVector2Array()
		var radii := PackedFloat32Array()
		var idx_map: PackedInt32Array = PackedInt32Array()   # fed-array index -> _enemies index
		for ei in _enemies.size():
			var e: Dictionary = _enemies[ei]
			if horde and _side_of(float((e["pos"] as Vector2).x)) != fleet_side:
				continue                                     # far-side: undamageable this frame
			positions.append(e["pos"])
			radii.append(_hit_radius(e))
			idx_map.append(ei)
		var hits: PackedInt32Array = _fleet.call("consume_volumes", positions, radii)
		# Per-hit damage WEIGHT + pierce flag of the current stance (#79), fetched ONCE per
		# frame. Null-safe: a bare unit-test Targets with no fleet falls back to SPRAY (1.0).
		var hw: float = float(_fleet.call("hit_weight")) if _fleet.has_method("hit_weight") else 1.0
		# Armor-crack eligibility uses a SEPARATE weight (#79 Efficiency fix): Efficiency lowers
		# damage-dealt (hit_weight) but must NOT strip LANCE's ability to crack a Rhombus, so the
		# crack threshold is tested against crack_weight() (LANCE × Tungsten, WITHOUT the Efficiency
		# burst penalty). Falls back to hit_weight, then to SPRAY 1.0, for an older/bare fleet.
		var cw: float = float(_fleet.call("crack_weight")) if _fleet.has_method("crack_weight") else hw
		var pierce: bool = bool(_fleet.call("is_piercing")) if _fleet.has_method("is_piercing") else false
		# Walk the FED set (== all enemies outside HORDE, the near-side subset in HORDE) and map each
		# hit count back to its real _enemies entry via idx_map. Far-side enemies (not fed) get no hit.
		for fi in idx_map.size():
			if hits[fi] > 0:
				_apply_damage(_enemies[idx_map[fi]], hits[fi], hw, pierce, cw)

	# (2) Movement + lifecycle. Rebuild the live set: survivors are kept, dead/breached/
	# offscreen are dropped (finite — no respawn), Fractal splits + multiply-through clones
	# push into to_add (added after the loop so we never mutate _enemies mid-iteration).
	var bands: Array = _gates.call("positive_gate_bands") if _gates != null else []
	var survivors: Array[Dictionary] = []
	var to_add: Array[Dictionary] = []
	for e in _enemies:
		e["flash"] = maxf(0.0, float(e["flash"]) - delta / FLASH_DECAY)
		# Gate-hijack occupant (#53): rides its gate instead of self-moving; never
		# breaches/leaves on its own. Resolved separately so the free-enemy logic stays clean.
		if bool(e.get("parked", false)):
			_step_parked(e, survivors)
			continue
		var p: Vector2 = e["pos"]
		p.y += float(e["speed"]) * delta
		e["pos"] = p
		# If the run has already ended this frame — e.g. an earlier enemy in THIS loop
		# breached and emptied the battery, failing the run synchronously — stop
		# scoring/breaching. Keep the enemy (frozen) so nothing is miscounted; the tree
		# pauses next frame so step() won't run again.
		if not GameState.run_active:
			survivors.append(e)
			continue
		if float(e["hp"]) <= 0.0:
			if _is_splitting_fractal(e):
				Events.enemy_split.emit(e["pos"])
				to_add.append(_fractling_at(p + Vector2(-46.0, -10.0)))
				to_add.append(_fractling_at(p + Vector2(46.0, -10.0)))
			else:
				_kill(e)                                  # score/burst/emit, then dropped
		elif p.y >= _breach_line:
			_breach(e)                                    # drain/emit, then dropped
		elif p.y > _design.y + float(e["size"]):
			pass                                          # offscreen — dropped (no respawn)
		else:
			_maybe_multiply(e, bands, to_add)             # multiply-through a + gate (#53)
			survivors.append(e)                           # alive, on-screen — keep
	# In HORDE the live ceiling is the SOFT cap (Debug.enemy_cap, UNBOUNDED) so a dialed-up field can
	# actually reach the dialed count (push past 256 toward the perf wall); LEGACY/KINETIC/GEOM keep
	# the MAX_ENEMIES const exactly as before.
	var add_ceiling: int = _enemy_soft_cap() if _is_horde() else MAX_ENEMIES
	for ne in to_add:
		if survivors.size() < add_ceiling:
			survivors.append(ne)
	_enemies = survivors

	# Age death bursts.
	var live_bursts: Array = []
	for b in _bursts:
		b["life"] = float(b["life"]) - delta
		if b["life"] > 0.0:
			live_bursts.append(b)
	_bursts = live_bursts


func live_count() -> int:
	return _enemies.size()


## Collision radius for an enemy, eroding slightly as its HP drops (so a battered
## enemy is a slightly smaller target — matches the shrinking visual).
func _hit_radius(e: Dictionary) -> float:
	var frac: float = clampf(float(e["hp"]) / float(e["max_hp"]), 0.0, 1.0)
	return float(e["size"]) * 0.5 * (0.55 + 0.45 * frac) + CONSUME_PAD


## Apply a frame's worth of bullet hits to an enemy (#79 per-hit FLOOR model). `hits` is the
## raw bullet COUNT from Fleet.consume_volumes; `hit_weight` is the DAMAGE of ONE bullet in the
## current stance (SPRAY 1.0, LANCE 6.0). Armor is now a per-hit QUALITY gate, not a count gate:
##   • UNARMORED (Glitch/Fractling/Fractal): full damage = hits * hit_weight * DAMAGE_PER_BULLET.
##   • ARMORED (Rhombus): each bullet must clear RHOMBUS_PER_HIT_FLOOR * armor_floor_mult to
##     CRACK it. A LANCE bullet (6.0) clears the floor -> full hits * hit_weight damage; a SPRAY
##     bullet (1.0) is SUB-THRESHOLD -> only a CHIP grind (ARMOR_CHIP_FRACTION per frame; #80
##     makes this mode-scaled, and a chip fraction of 0 == TRUE immunity). So a thin/light stream
##     can't crack armor by sheer count — you must focus into a LANCE — while a sustained SPRAY
##     still eventually grinds it down (no permanent lockout, #74).
## `crack_weight` is the weight that decides ARMOR-CRACK eligibility, kept SEPARATE from `hit_weight`
## (the damage-dealt weight) so Efficiency's burst tradeoff (#84 ph6) — which lowers hit_weight to 4.5,
## below the 5.0 floor — cannot strip LANCE's mandate as the armor-cracker. It defaults to -1.0, a
## sentinel meaning "use hit_weight" so verify_combat's existing direct _apply_damage(e, hits[, w]) calls
## behave EXACTLY as before. Defaulted args so those direct calls still pass.
func _apply_damage(e: Dictionary, hits: int, hit_weight: float = 1.0, _pierce: bool = false, crack_weight: float = -1.0) -> void:
	if hits <= 0:
		return
	var armor: int = int(e.get("armor", 0))
	var per_hit: float = hit_weight                          # damage weight of ONE bullet (damage DEALT)
	# Crack eligibility tests the SEPARATE crack weight (Efficiency-free); fall back to hit_weight when
	# the caller didn't supply one (sentinel < 0), preserving the legacy single-weight behaviour.
	var crack_per_hit: float = crack_weight if crack_weight >= 0.0 else hit_weight
	if armor > 0 and crack_per_hit < RHOMBUS_PER_HIT_FLOOR * armor_floor_mult:
		# Sub-threshold on an armored enemy: chip grind (no crack). chip_fraction == 0 (Hard,
		# #80) makes this a true 0 — full immunity until the player switches to a LANCE.
		e["hp"] = float(e["hp"]) - _armor_chip_fraction() * DAMAGE_PER_BULLET
	else:
		# Cracks (LANCE on armor) or any hit on an unarmored enemy: full weighted damage.
		e["hp"] = float(e["hp"]) - float(hits) * per_hit * DAMAGE_PER_BULLET
	e["flash"] = 1.0


## The sub-threshold armor chip fraction (#74/#80) — now MODE-SCALED via Difficulty. EASY 0.45
## chips faster (forgiving), MEDIUM 0.15 (== the ARMOR_CHIP_FRACTION const fallback), HARD 0.0
## = TRUE immunity (sub-threshold SPRAY does 0 damage → Lance mandatory to crack a Rhombus).
## Null-safe: a bare unit-test Targets with no autoload tree falls back to the MEDIUM const.
func _armor_chip_fraction() -> float:
	var diff: Node = _difficulty_node()
	if diff != null:
		return float(diff.call("armor_chip_fraction"))
	return ARMOR_CHIP_FRACTION


## --- HORDE far-side firing boundary (#90, H1) --------------------------------
## The centre-divider x that splits the playfield into a LEFT/RIGHT firing side. Mirrors
## LaneArena.CENTER_X (kept as a local const so the pure step()/render maths never reach for a
## node). An enemy is only DAMAGEABLE this frame if it shares its side with the fleet muzzle.
const HORDE_CENTER_X := 540.0
## How far down a far-side enemy's HDR colour is scaled in HORDE so it reads as un-shootable
## (well below the bloom threshold of 1.0 for the dimmed channels, but still visible/descending).
const HORDE_FARSIDE_DIM := 0.22

## Which side of the divider a world x is on: 0 == LEFT (x < CENTER_X), 1 == RIGHT. Pure —
## mirrors LaneArena.side_of so the filter + render dim key off one rule.
func _side_of(x: float) -> int:
	return 0 if x < HORDE_CENTER_X else 1


## True only when this run is in HORDE mode (Settings.poc_mode == HORDE == 3). The far-side firing
## filter + the far-side render dim are gated on this, so LEGACY/KINETIC/GEOM behave EXACTLY as
## before (the full enemy set is always damageable). Null-safe: a bare unit-test Targets with no
## autoload tree (or a fleet stub) reports false unless a test forces it via _force_horde.
func _is_horde() -> bool:
	if _force_horde:
		return true
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var s: Node = (loop as SceneTree).root.get_node_or_null("Settings")
		if s != null:
			return int(s.get("poc_mode")) == 3   # Settings.PocMode.HORDE
	return false


## Test seam (#90): force HORDE on for a bare-instance headless verify that has no Settings autoload
## in a HORDE state. Production never sets this — it reads the live Settings.poc_mode via _is_horde.
var _force_horde: bool = false
func set_force_horde(on: bool) -> void:
	_force_horde = on


## The fleet muzzle's side of the divider (0 LEFT / 1 RIGHT). The fleet's position.x IS the muzzle
## (run.gd mirrors steer x onto it). Defaults to LEFT when there's no fleet (pure unit tests).
func _fleet_side() -> int:
	if _fleet == null:
		return 0
	return _side_of(float(_fleet.position.x))


## Null-safe handle to the Difficulty autoload (mirrors the bare-instance test path). Returns
## null if the autoload tree isn't present (pure-logic unit tests new() a Targets directly).
func _difficulty_node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var r: Node = (loop as SceneTree).root
		return r.get_node_or_null("Difficulty")
	return null


## Null-safe handle on the Debug autoload (designer-tuning knobs, P3). Same trick as
## _difficulty_node: a bare-instance verify (no autoload tree) gets null and every reader below
## falls back to the NEUTRAL default — so an un-wired Targets behaves exactly like today.
func _debug_node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var r: Node = (loop as SceneTree).root
		return r.get_node_or_null("Debug")
	return null


## A 0-HP enemy that should SPLIT rather than die: a Fractal hit with insufficient
## firepower (swarm volume below the split tier). The two fractlings replace it.
## Stance interaction (#79, predicate UNCHANGED): SPRAY produces MORE hits per frame at a
## big swarm volume, so it naturally pushes the volume past FRACTAL_SPLIT_TIER and FEEDS the
## splitter via this existing gate; a LANCE's heavy single bullet can exceed the split tier's
## effective damage. We keep keying on GameState.projectile_count (not a stance/per-hit test)
## so the split path's behaviour is unchanged beyond the now weight-aware damage math (#54's
## open question of switching this predicate is DEFERRED).
func _is_splitting_fractal(e: Dictionary) -> bool:
	return int(e.get("kind", KIND_GLITCH)) == KIND_FRACTAL \
		and bool(e.get("split", true)) \
		and GameState.projectile_count < FRACTAL_SPLIT_TIER


func _fractling_at(pos: Vector2) -> Dictionary:
	var f := _new_enemy(KIND_FRACTLING, pos.y)
	f["pos"] = pos
	return f


# --- #53 cross-cutting gate interactions -------------------------------------

## Park an Entropy occupant on a freshly-hijacked gate (#53). A tough Rhombus so clearing
## it before the gate reaches the line takes real firepower; it rides the gate each step.
func _spawn_hijacker(h: Dictionary) -> void:
	if _enemies.size() >= MAX_ENEMIES:
		return
	var e := _new_enemy(KIND_RHOMBUS, -200.0)
	e["parked"] = true
	e["gate_id"] = int(h["id"])
	e["pos"] = Vector2(float(h["x"]), -200.0)   # snapped onto the gate next step (gate_info)
	_enemies.append(e)


## Advance a parked hijack occupant: it rides its gate (gate_info), is dropped if the gate
## recycled, and on death frees the splice (notify_hijack_cleared) + scores like any kill.
## Never breaches or leaves on its own. `survivors` is the live-set being rebuilt by step().
func _step_parked(e: Dictionary, survivors: Array[Dictionary]) -> void:
	if not GameState.run_active:
		survivors.append(e)                          # freeze if the run ended this frame
		return
	var info: Dictionary = _gates.call("gate_info", int(e["gate_id"])) if _gates != null else {"alive": false}
	if not bool(info.get("alive", false)):
		return                                       # gate gone (recycled) — drop the orphan
	e["pos"] = info["pos"]                            # ride the gate
	if float(e["hp"]) <= 0.0:
		if _gates != null:
			_gates.call("notify_hijack_cleared", int(e["gate_id"]))  # splice now claimable
		_kill(e)                                     # score/burst/emit, then dropped
	else:
		survivors.append(e)


## Multiply-through (#53): a free enemy whose y enters a POSITIVE gate band (within its
## x-span) DUPLICATES once — a fresh same-kind clone offset in x, itself flagged so it
## won't re-multiply at the same band. Clones land in `to_add` (capped by step()).
func _maybe_multiply(e: Dictionary, bands: Array, to_add: Array[Dictionary]) -> void:
	# HORDE (#90, P5): gates are a PLAYER firepower mechanic ONLY — enemies must NEVER multiply-through a
	# +/× gate band. Early-return so the swarm can't free-spawn clones at the player's recovery gates
	# (which would punish the player for steering toward firepower). No-op suppression for LEGACY/KINETIC/
	# GEOM (the #53 multiply-through stays intact there).
	if _is_horde():
		return
	if bands.is_empty() or bool(e.get("multiplied", false)):
		return
	var p: Vector2 = e["pos"]
	for band in bands:
		if p.x >= float(band["x_min"]) and p.x < float(band["x_max"]) \
				and absf(p.y - float(band["y"])) < MULTIPLY_BAND:
			e["multiplied"] = true
			var clone := _new_enemy(int(e["kind"]), p.y)
			clone["pos"] = p + Vector2(64.0, 0.0)
			clone["multiplied"] = true               # the copy is already "through" — no chain
			to_add.append(clone)
			Events.enemy_multiplied.emit(p)
			return


## An enemy died to the fleet: score it (combo), pop a burst, announce. The caller drops
## it from the live set (finite — no respawn).
func _kill(e: Dictionary) -> void:
	kills += 1
	var points: int = int(e.get("points", 100))
	GameState.register_kill(points)               # combo-multiplied scoring
	if _bursts.size() < MAX_BURSTS:
		_bursts.append({"pos": e["pos"], "life": BURST_LIFE, "col": _enemy_color(e)})
	Events.enemy_destroyed.emit(e["pos"], points)
	Events.trigger_grid_ripple.emit(e["pos"], false)   # the reactive grid warps under the kill
	Events.token_dropped.emit(e["pos"], _token_value(e))  # #78: spawn a collectable token bounty


## Token bounty for a killed enemy (#78): the meta currency a kill drops, distinct from score.
## Tougher archetypes pay more (Glitch/Fractling low, Fractal mid, Rhombus high), scaled by the
## player's drafted token-bounty multiplier. Null-safe: a bare unit-test Targets with no autoload
## tree (or no draft perks) gets the flat base bounty.
func _token_value(e: Dictionary) -> int:
	var base: int
	match int(e.get("kind", KIND_GLITCH)):
		KIND_RHOMBUS: base = 5
		KIND_FRACTAL: base = 3
		KIND_FRACTLING: base = 1
		_: base = 1                       # Glitch + default
	return int(round(float(base) * _bounty_mult()))


## Null-safe drafted token-bounty multiplier (#78). Reads SpliceLab.bounty_mult() when the
## autoload tree is present; falls back to 1.0 for pure-logic unit tests that new() a Targets.
func _bounty_mult() -> float:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var lab: Node = (loop as SceneTree).root.get_node_or_null("SpliceLab")
		if lab != null and lab.has_method("bounty_mult"):
			return float(lab.call("bounty_mult"))
	return 1.0


## An enemy reached the ship line: it breaches. In HORDE (#90, H3) FIREPOWER is the loss channel, so a
## breach removes `streams` of the swarm volume (GameState.drain_firepower → you die at 0). Outside HORDE
## it drains the Glow Battery by its `breach` cost as before (#55). Either way it emits enemy_breached
## (carrying the drained quantum for vfx/audio) and ripples the grid. Caller drops the enemy.
func _breach(e: Dictionary) -> void:
	breaches += 1
	if _is_horde():
		var streams: int = int(e.get("streams", 1))
		# P3 designer knob (GLOBAL — applies to a boss breach too, which is correct): scale the
		# firepower cost of a breach. NEUTRAL 1.0 = today; 0.0 → no firepower lost (round). Null-safe.
		var dbg: Node = _debug_node()
		if dbg != null and dbg.has_method("firepower_loss"):
			streams = int(round(float(streams) * float(dbg.call("firepower_loss"))))
		GameState.drain_firepower(streams)
		Events.enemy_breached.emit(e["pos"], float(streams))
	else:
		var dmg: float = float(e.get("breach", 6.0))
		GameState.drain_battery(dmg)
		Events.enemy_breached.emit(e["pos"], dmg)
	Events.trigger_grid_ripple.emit(e["pos"], true)    # heavier inward pulse on a breach


## Weighted archetype roll (#80 secondary): a harder mode biases the mix toward the armored
## Rhombus (rhombus_weight_bias is +0.10 on HARD, 0.0 on EASY/MEDIUM = today's weights — additive,
## so MEDIUM is a no-op vs the pre-#80 mix). Null-safe: a bare unit-test Targets falls back to 0.0.
func _pick_kind() -> int:
	var diff: Node = _difficulty_node()
	var rhombus_w: float = 0.15 + (float(diff.call("rhombus_weight_bias")) if diff != null else 0.0)
	var roll: float = _rng.randf()
	if roll < rhombus_w:
		return KIND_RHOMBUS
	elif roll < rhombus_w + 0.25:
		return KIND_FRACTAL
	return KIND_GLITCH


func _new_enemy(kind: int, start_y: float) -> Dictionary:
	var s: Dictionary = STATS[kind]
	var spd: Array = s["spd"]
	return {
		"kind": kind,
		"pos": Vector2(_rng.randf_range(120.0, _design.x - 120.0), start_y),
		"hp": float(s["hp"]), "max_hp": float(s["hp"]),
		"size": float(s["size"]), "speed": _rng.randf_range(spd[0], spd[1]),
		"armor": int(s["armor"]), "points": int(s["points"]),
		"breach": float(s["breach"]), "split": bool(s["split"]),
		"streams": int(s.get("streams", 1)),   # #90 H3: HORDE firepower cost of a breach (GLITCH fodder = 1)
		"flash": 0.0,
		# #53 interaction state (defaults = an ordinary free enemy):
		"parked": false,        # true = a gate-hijack occupant riding its gate
		"gate_id": -1,          # the hijacked gate it rides (parked only)
		"multiplied": false,    # already duplicated through a + gate (multiply-through, once)
	}


# --- Rendering ---------------------------------------------------------------

func _enemy_color(e: Dictionary) -> Color:
	match int(e.get("kind", KIND_GLITCH)):
		KIND_RHOMBUS: return Palette.ENEMY_RHOMBUS
		KIND_FRACTAL: return Palette.ENEMY_FRACTAL
		KIND_FRACTLING: return Palette.ENEMY_FRACTLING
		KIND_LANEBOSS: return Palette.ENEMY_RHOMBUS_CORE   # #90 H4: white-hot crimson — reads as the heavy threat
	return Palette.ENEMY_GLITCH


func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(BASE_QUAD, BASE_QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	# P3: GENEROUS HARD buffer (1024 enemies + bursts) sized once at build, so Debug.enemy_cap can be
	# pushed well past 256 to find the perf wall WITHOUT rebuilding the MultiMesh. visible_instance_count
	# still tracks the live count each _render (see below), so the over-size buffer costs nothing idle.
	mm.instance_count = MMI_HARD_MAX + MAX_BURSTS
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance2D.new()
	_mmi.name = "EnemyMultiMesh"
	_mmi.multimesh = mm
	_mmi.texture = _make_diamond_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mmi.material = mat
	add_child(_mmi)


func _render() -> void:
	if _mmi == null:
		return
	var mm := _mmi.multimesh
	# P3: clamp to the HARD MultiMesh buffer (1024), NOT MAX_ENEMIES — the live set can exceed 128 now
	# that Debug.enemy_cap drives the soft spawn cap, and every live enemy up to the buffer should render.
	var n: int = mini(_enemies.size(), MMI_HARD_MAX)
	var b_n: int = mini(_bursts.size(), MAX_BURSTS)
	mm.visible_instance_count = n + b_n
	# HORDE far-side DIM (#90, H1): enemies on the OPPOSITE side of the divider from the fleet muzzle
	# are un-shootable this frame, so we dim them (multiply the instance colour down) to read "can't
	# hit those" — the same per-instance-colour trick the armor tint uses, no extra draw call. Outside
	# HORDE every enemy is full-bright (render is byte-for-byte unchanged for LEGACY/KINETIC/GEOM).
	var horde_render: bool = _is_horde()
	var fleet_render_side: int = _fleet_side() if horde_render else -1
	for i in n:
		var e := _enemies[i]
		var p: Vector2 = e["pos"]
		var frac: float = clampf(float(e["hp"]) / float(e["max_hp"]), 0.0, 1.0)
		# Quad scale = archetype size relative to the base quad, eroding with HP.
		var s: float = (float(e["size"]) / BASE_QUAD) * (0.62 + 0.38 * frac)
		var col: Color = _enemy_color(e)
		# Armor tell (#88): a still-armored enemy blends toward the white-hot crimson core
		# and reads physically THICKER (bumped scale) so the rim looks plated. Per-instance
		# colour/scale only — no extra draw call, no second MultiMesh.
		var armor: int = int(e.get("armor", 0))
		if armor > 0:
			var a_w: float = clampf(0.18 * float(armor), 0.0, 0.6)  # armor-scaled blend toward the core
			col = col.lerp(Palette.ENEMY_RHOMBUS_CORE, a_w)
			s *= 1.0 + 0.06 * float(armor)                          # thicker rim while armored
		mm.set_instance_transform_2d(i, Transform2D(Vector2(s, 0), Vector2(0, s), p - position))
		var fl: float = float(e["flash"])
		if fl > 0.0:
			col = col.lerp(Palette.FLASH_WHITE, fl)  # per-impact pulse (punched up to full weight, #88)
		# HORDE far-side dim: an enemy across the divider from the muzzle reads dark (un-shootable).
		if horde_render and _side_of(float(p.x)) != fleet_render_side:
			col = Color(col.r * HORDE_FARSIDE_DIM, col.g * HORDE_FARSIDE_DIM, col.b * HORDE_FARSIDE_DIM, col.a)
		mm.set_instance_color(i, col)
	# Death bursts: a white-hot diamond (tinted by the kind) that expands and fades.
	for j in b_n:
		var burst: Dictionary = _bursts[j]
		var life: float = clampf(float(burst["life"]) / BURST_LIFE, 0.0, 1.0)
		var bs: float = 0.9 + (1.0 - life) * 2.6   # expands outward as it fades
		var blocal: Vector2 = burst["pos"] - position
		mm.set_instance_transform_2d(n + j, Transform2D(Vector2(bs, 0), Vector2(0, bs), blocal))
		var bcol: Color = burst.get("col", Palette.FLASH_WHITE)
		mm.set_instance_color(n + j, (bcol + Color(3.0, 3.0, 3.0, 0.0)) * life)


## HOLLOW vector-outline diamond (#90 P0): a bright additive/HDR RIM where the Manhattan distance is
## near `radius`, with a HARD alpha=0 interior — the glow-safe technique mirrored from
## gate.gd._make_frame_texture. The transparent core emits nothing additively, so the bloom only catches
## the rim (and the rim stays full-alpha white so the per-instance HDR tint still glows). White RGB so
## the per-instance armor tint / impact flash / far-side dim all multiply the same quad as before.
func _make_diamond_texture() -> ImageTexture:
	var img := Image.create(DIAMOND_TEX_SIZE, DIAMOND_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (DIAMOND_TEX_SIZE - 1) * 0.5
	var radius := c - 2.0
	var band := 5.0                                        # rim half-thickness (Manhattan px units)
	for y in DIAMOND_TEX_SIZE:
		for x in DIAMOND_TEX_SIZE:
			var manhattan: float = absf(x - c) + absf(y - c)   # diamond / rhombus iso-contours
			# Distance from the rim contour (manhattan == radius); brightest ON the rim, fading out by `band`.
			var d: float = absf(manhattan - radius)
			var a: float = clampf((band - d) / band, 0.0, 1.0)  # linear crisp rim, full alpha on-contour
			# Hard negative-space core: anything well INSIDE the diamond stays fully transparent so the
			# additive bloom leaves the centre crisp (a hollow vector outline, no glow bleed across the core).
			if manhattan < radius - band:
				a = 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
