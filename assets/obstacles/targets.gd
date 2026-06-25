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

enum { KIND_GLITCH, KIND_RHOMBUS, KIND_FRACTAL, KIND_FRACTLING }

const MAX_ENEMIES := 48
const MAX_BURSTS := 24
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
const STATS := {
	KIND_GLITCH:    {"hp": 40.0,  "size": 52.0,  "spd": [220.0, 320.0], "armor": 0, "points": 50,  "breach": 6.0,  "split": false},
	KIND_RHOMBUS:   {"hp": 320.0, "size": 108.0, "spd": [70.0, 120.0],  "armor": 3, "points": 250, "breach": 18.0, "split": false},
	KIND_FRACTAL:   {"hp": 110.0, "size": 78.0,  "spd": [130.0, 200.0], "armor": 0, "points": 120, "breach": 10.0, "split": true},
	KIND_FRACTLING: {"hp": 28.0,  "size": 42.0,  "spd": [280.0, 380.0], "armor": 0, "points": 40,  "breach": 4.0,  "split": false},
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
	# (0b) Park occupants on any newly-hijacked gates (#53). No-op without a gate system.
	if _gates != null:
		for h in _gates.call("take_pending_hijacks"):
			_spawn_hijacker(h)

	# (1) Batched projectile→enemy damage (#54). One pass over the bullets for ALL
	# enemies instead of one survivor-rebuild per enemy.
	if _fleet != null and not _enemies.is_empty():
		var positions := PackedVector2Array()
		var radii := PackedFloat32Array()
		for e in _enemies:
			positions.append(e["pos"])
			radii.append(_hit_radius(e))
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
		for i in _enemies.size():
			if hits[i] > 0:
				_apply_damage(_enemies[i], hits[i], hw, pierce, cw)

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
	for ne in to_add:
		if survivors.size() < MAX_ENEMIES:
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


## Null-safe handle to the Difficulty autoload (mirrors the bare-instance test path). Returns
## null if the autoload tree isn't present (pure-logic unit tests new() a Targets directly).
func _difficulty_node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var r: Node = (loop as SceneTree).root
		return r.get_node_or_null("Difficulty")
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


## An enemy reached the ship line: it breaches, draining the Glow Battery by its breach
## cost (the loss pressure that makes shooting matter, #55). Caller drops it.
func _breach(e: Dictionary) -> void:
	breaches += 1
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
	return Palette.ENEMY_GLITCH


func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(BASE_QUAD, BASE_QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_ENEMIES + MAX_BURSTS
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
	var n: int = mini(_enemies.size(), MAX_ENEMIES)
	var b_n: int = mini(_bursts.size(), MAX_BURSTS)
	mm.visible_instance_count = n + b_n
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


func _make_diamond_texture() -> ImageTexture:
	var img := Image.create(DIAMOND_TEX_SIZE, DIAMOND_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (DIAMOND_TEX_SIZE - 1) * 0.5
	var radius := c - 2.0
	for y in DIAMOND_TEX_SIZE:
		for x in DIAMOND_TEX_SIZE:
			var manhattan: float = absf(x - c) + absf(y - c)   # diamond / rhombus
			var a: float = clampf((radius - manhattan) / 6.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
