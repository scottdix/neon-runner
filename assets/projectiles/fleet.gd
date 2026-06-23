class_name Fleet
extends Node2D
## The ship's always-on fire stream (#52, D1 LOCKED): the gold-orb swarm are REAL
## projectiles the ship continuously fires upward — not cosmetic followers. There
## is no fire button; firing is automatic. `GameState.projectile_count` (the
## "swarm volume", spiked/decimated by gates) drives both the rate of fire and
## the spread, so a bigger swarm reads as a denser wall of bullets.
##
## Rendering follows the one-draw-call batching plan (CLAUDE.md): every live
## projectile is one instance in a single MultiMesh, additive + HDR gold so the
## overlapping cores bloom white-hot (validated on device, POC #6). All the
## simulation is in `step()` so it runs/asserts headless with no GPU.

const MAX_PROJECTILES := 2000      # hard pool cap (MultiMesh instance budget)
const PROJ_SPEED := 1700.0         # px/sec, straight up (-y)
const ORB_QUAD := 22.0
const ORB_TEX_SIZE := 32

## Shots/sec as a function of swarm volume (denser stream reads better + drives
## the per-impact damage rate, so swarm volume still scales firepower).
const BASE_FIRE_RATE := 26.0
const FIRE_RATE_PER_VOLUME := 0.8
const MAX_FIRE_RATE := 160.0
## Horizontal spread (px) grows with volume so the stream widens into a wall.
const BASE_SPREAD := 10.0
const SPREAD_PER_VOLUME := 0.45
const MAX_SPREAD := 130.0

var muzzle_offset: Vector2 = Vector2(0, -28)  # relative to this node's position

const SPARK_LIFE := 0.12           # seconds an impact flash lives

## --- Projectile tier evolution (#57) ----------------------------------------
## As the swarm volume grows the orbs evolve through 5 PRESENTATION tiers (T0 round/cool
## gold .. T4 max white-hot). This is COSMETIC ONLY — tiers vary per-instance colour + scale
## in `_render()`, they NEVER touch the sim (fire count / movement), so verify_combat's
## live_count/spark asserts are unaffected. TIER_VOLUME[t] is the swarm-volume at/above which
## tier `t` is reached (T0 is the implicit floor, so 4 cutoffs → 5 tiers).
const TIER_VOLUME: Array[int] = [12, 30, 60, 110]   # T0 below 12; T1≥12; T2≥30; T3≥60; T4≥110
const TIER_COUNT := 5
## Per-tier colour the orbs read as (HDR, gold→white-hot family). Hotter/brighter per tier so a
## bigger swarm reads punchier. T0 is the base SWARM_GOLD; the top tiers push toward white.
const TIER_COLORS: Array[Color] = [
	Palette.SWARM_GOLD,                 # T0 — base gold
	Color(4.0, 3.3, 0.7, 1.0),          # T1 — brighter gold
	Color(4.6, 3.9, 1.3, 1.0),          # T2 — gold/amber, warming
	Color(5.2, 4.5, 2.2, 1.0),          # T3 — pale gold pushing white
	Color(5.8, 5.4, 3.6, 1.0),          # T4 — near white-hot
]
## Per-tier instance scale multiplier — higher tiers render fatter orbs.
const TIER_SCALE: Array[float] = [1.0, 1.08, 1.18, 1.30, 1.45]
## How long a tier-down shatter shard lives (a one-frame-ish cosmetic pop, like a spark).
const SHATTER_LIFE := 0.18

var _volume: int = 0
var _proj: Array[Vector2] = []     # live projectile positions (top of the pool)
var _fire_accum: float = 0.0
var _rng := RandomNumberGenerator.new()
var _mmi: MultiMeshInstance2D
var _sparks: Array = []            # [{pos:Vector2, life:float}, ...] impact flashes
## Tier-down SHATTER shards: when a gate decimates the swarm and the visual tier DROPS, we
## pop a one-shot burst of the lost tier's colour (rendered like sparks). Self-contained — no
## Events signal (events.gd isn't in this slice). [{pos:Vector2, life:float, color:Color}, ...]
var _shatter: Array = []

## --- Splice consumption (#68) ------------------------------------------------
## The equipped Splice (SpliceLab.active_modifiers()) is read ONCE at run start and folded into
## the effective fire-rate / spread / projectile-speed + the starting swarm. NEUTRAL by default
## so a run with nothing spliced behaves EXACTLY as today (verify_combat invariant).
var _splice_rate_mult: float = 1.0
var _splice_spread_mult: float = 1.0
var _splice_speed_mult: float = 1.0


func _ready() -> void:
	_rng.seed = 0xF1EE7
	_build_multimesh()
	# Seed the live volume FIRST so apply_splice()'s SHOTS-bonus seeding uses the real
	# starting spread (it reads _effective_spread() → _volume), not a stale 0.
	_volume = GameState.projectile_count   # autoload global; valid off-tree + headless
	# Read the equipped Splice ONCE at run start, BEFORE the first shot, so a SHOTS bonus
	# lands on the starting swarm and the rate/spread/speed mults are live from frame one.
	apply_splice()
	# React to swarm-volume changes from the economy (gates -> GameState -> Events).
	Events.projectile_count_changed.connect(set_volume)


## Read the equipped Splice (SpliceLab.active_modifiers()) and fold it into the run's effective
## fire-rate / spread / projectile-speed + the starting swarm volume (#68). Idempotent enough to
## call at run start; NEUTRAL (no-op) when nothing is spliced so today's behaviour is preserved.
## SpliceLab is a global autoload (valid headless, no node ref needed). Safe if it's absent.
func apply_splice() -> void:
	var lab: Object = _splice_lab_node()
	if lab == null or not lab.has_method("active_modifiers"):
		return
	var fx: Dictionary = lab.active_modifiers()
	_splice_rate_mult = float(fx.get("rate_mult", 1.0))
	_splice_spread_mult = float(fx.get("spread_mult", 1.0))
	_splice_speed_mult = float(fx.get("speed_mult", 1.0))
	var bonus: int = int(fx.get("start_projectiles_bonus", 0))
	if bonus > 0:
		# Seed the starting swarm denser. These are real bullets at the muzzle band.
		var muzzle := position + muzzle_offset
		var spread: float = _effective_spread()
		for i in bonus:
			if _proj.size() >= MAX_PROJECTILES:
				break
			var dx := _rng.randf_range(-spread, spread)
			_proj.append(Vector2(muzzle.x + dx, muzzle.y))


## Resolve the SpliceLab autoload as a /root child. Looked up via the main loop's root (instead
## of the bare `SpliceLab` global) so this is safe for a bare `Fleet.new()` in a headless test
## where the global class identifier may not be bound. Returns null when it isn't registered.
func _splice_lab_node() -> Object:
	var tree := Engine.get_main_loop()
	if tree is SceneTree and (tree as SceneTree).root != null:
		return (tree as SceneTree).root.get_node_or_null("SpliceLab")
	return null


func _process(delta: float) -> void:
	step(delta)
	_render()


## Advance the stream one frame: fire on cadence, move projectiles up, recycle
## those past the top. Pure + GPU-free so headless tests drive it directly.
func step(delta: float) -> void:
	var rate: float = _effective_fire_rate(_volume)
	_fire_accum += rate * delta
	var shots := int(_fire_accum)
	if shots > 0:
		_fire_accum -= float(shots)
		_fire(shots)

	# March every live projectile straight up; drop the ones off the top.
	# (Targets call consume_near() to remove + spark + damage on contact.)
	var top_cutoff := -ORB_QUAD
	var survivors: Array[Vector2] = []
	var step_speed: float = PROJ_SPEED * _splice_speed_mult
	for p in _proj:
		var np := Vector2(p.x, p.y - step_speed * delta)
		if np.y > top_cutoff:
			survivors.append(np)
	_proj = survivors

	# Age impact sparks.
	var live_sparks: Array = []
	for s in _sparks:
		s["life"] = float(s["life"]) - delta
		if s["life"] > 0.0:
			live_sparks.append(s)
	_sparks = live_sparks

	# Age tier-down shatter shards (cosmetic; same lifecycle as sparks).
	var live_shatter: Array = []
	for s in _shatter:
		s["life"] = float(s["life"]) - delta
		if s["life"] > 0.0:
			live_shatter.append(s)
	_shatter = live_shatter


func _fire(shots: int) -> void:
	var spread: float = _effective_spread()
	var muzzle := position + muzzle_offset
	var fired := 0
	for i in shots:
		if _proj.size() >= MAX_PROJECTILES:
			break
		var dx := _rng.randf_range(-spread, spread)
		_proj.append(Vector2(muzzle.x + dx, muzzle.y))
		fired += 1
	if fired > 0:
		Events.fleet_fired.emit(fired)


func set_volume(count: int) -> void:
	var prev_volume: int = _volume
	var new_volume: int = maxi(0, count)
	var prev_tier: int = _tier_for_volume(prev_volume)
	var new_tier: int = _tier_for_volume(new_volume)
	_volume = new_volume
	# Tier DROP (a gate decimated the swarm): pop a one-shot shatter of the lost tier so the
	# downgrade reads on screen. One shard per tier-step lost, scattered at the muzzle band.
	if new_tier < prev_tier:
		_queue_shatter(prev_tier, new_tier)


## --- Tier evolution (#57), all PURE / headless-testable ----------------------

## The presentation tier (0..TIER_COUNT-1) for a given swarm volume. PURE: walks the cutoff
## TABLE so the boundaries are the single source of truth. Tiers NEVER affect the sim.
func _tier_for_volume(v: int) -> int:
	var t := 0
	for cutoff in TIER_VOLUME:
		if v >= cutoff:
			t += 1
		else:
			break
	return t


## The swarm's current presentation tier (derived from live volume).
func _current_tier() -> int:
	return _tier_for_volume(_volume)


## Queue a tier-down SHATTER: one shard per tier-step lost (prev_tier → new_tier), each the
## lost tier's colour, scattered across the muzzle band. Cosmetic only (rendered like sparks);
## an observable `shatter_count()` lets the headless test assert the downward crossing fired.
func _queue_shatter(prev_tier: int, new_tier: int) -> void:
	var muzzle := position + muzzle_offset
	var lost := prev_tier
	while lost > new_tier:
		var col: Color = TIER_COLORS[clampi(lost, 0, TIER_COUNT - 1)]
		var dx := _rng.randf_range(-MAX_SPREAD, MAX_SPREAD)
		_shatter.append({"pos": Vector2(muzzle.x + dx, muzzle.y), "life": SHATTER_LIFE, "color": col})
		lost -= 1


## Number of live shatter shards — the value the headless tier test asserts on after a
## downward volume change.
func shatter_count() -> int:
	return _shatter.size()


## --- Effective sim values (splice-folded, PURE / headless-testable) ----------

## Fire-rate (shots/sec) for a given volume, with the equipped Splice's rate_mult folded in
## (#68). With NO splice _splice_rate_mult is 1.0, so this equals today's formula exactly
## (verify_combat invariant). The clamp still bounds the result to the design rate window.
func _effective_fire_rate(volume: int) -> float:
	var base := BASE_FIRE_RATE + float(volume) * FIRE_RATE_PER_VOLUME
	return clampf(base * _splice_rate_mult, BASE_FIRE_RATE, MAX_FIRE_RATE * maxf(1.0, _splice_rate_mult))


## Stream spread (px) for the current volume, with the Splice spread_mult folded in. Neutral
## (mult 1.0) reproduces today's clamp window exactly.
func _effective_spread() -> float:
	var base := clampf(
		BASE_SPREAD + float(_volume) * SPREAD_PER_VOLUME, BASE_SPREAD, MAX_SPREAD)
	return base * _splice_spread_mult


## Consume (remove + spark) projectiles within `radius` of a single world point and
## return how many were hit. Thin wrapper over the batched consume_volumes() (one
## volume) so there is ONE collision implementation to maintain. Each absorbed bullet
## IS the damage — impact and damage are the same event (connected hit feel).
func consume_near(world_pos: Vector2, radius: float) -> int:
	return consume_volumes(PackedVector2Array([world_pos]), PackedFloat32Array([radius]))[0]


## Batched collision (#54/#14): resolve MANY enemy "damage volumes" against the live
## bullets in a SINGLE pass, instead of one consume_near() call (and one survivor-array
## rebuild) per enemy. `positions[i]`/`radii[i]` describe enemy i's hit volume; returns
## a PackedInt32Array of bullets absorbed by each, aligned to the input. Each bullet is
## consumed by at most one volume (first match, nearest-first not needed — enemies rarely
## overlap). An x-band cull (|dx| > radius → skip) keeps this near O(bullets) when enemies
## are spread out, holding D3's perf intent without per-bullet Area2D bodies. The compiled
## beam-emitter path (PerfBullets) remains the escape hatch if GDScript ever caps out.
func consume_volumes(positions: PackedVector2Array, radii: PackedFloat32Array) -> PackedInt32Array:
	var n: int = positions.size()
	var hits := PackedInt32Array()
	hits.resize(n)
	if n == 0:
		return hits
	var r2: PackedFloat32Array = PackedFloat32Array()
	r2.resize(n)
	for i in n:
		r2[i] = radii[i] * radii[i]
	var survivors: Array[Vector2] = []
	for p in _proj:
		var absorbed := false
		for i in n:
			if absf(p.x - positions[i].x) > radii[i]:
				continue                                    # x-band cull (cheap reject)
			if p.distance_squared_to(positions[i]) < r2[i]:
				hits[i] += 1
				_sparks.append({"pos": p, "life": SPARK_LIFE})
				absorbed = true
				break
		if not absorbed:
			survivors.append(p)
	_proj = survivors
	return hits


## Number of live projectiles — the value headless tests assert on.
func live_count() -> int:
	return _proj.size()


## Number of live impact sparks — asserted by the headless absorption test.
func spark_count() -> int:
	return _sparks.size()


# --- Rendering (skipped under headless; logic above is the source of truth) ---

func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(ORB_QUAD, ORB_QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_PROJECTILES
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance2D.new()
	_mmi.name = "ProjectileMultiMesh"
	_mmi.multimesh = mm
	_mmi.texture = _make_orb_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # overlapping cores -> white-hot bloom
	_mmi.material = mat
	add_child(_mmi)


func _render() -> void:
	if _mmi == null:
		return
	var mm := _mmi.multimesh
	var n: int = mini(_proj.size(), MAX_PROJECTILES)
	var spark_n: int = mini(_sparks.size(), MAX_PROJECTILES - n)
	var shatter_n: int = mini(_shatter.size(), MAX_PROJECTILES - n - spark_n)
	mm.visible_instance_count = n + spark_n + shatter_n
	# Per-tier presentation (#57): the whole swarm reads hotter + fatter as volume climbs.
	# Cosmetic only — colour + per-instance scale, no effect on the sim.
	var tier: int = clampi(_current_tier(), 0, TIER_COUNT - 1)
	var tier_col: Color = TIER_COLORS[tier]
	var tier_scale: float = TIER_SCALE[tier]
	# Instances are positioned in this node's local space; subtract our origin.
	for i in n:
		var local := _proj[i] - position
		mm.set_instance_transform_2d(
			i, Transform2D(Vector2(tier_scale, 0), Vector2(0, tier_scale), local))
		# Tier-graded gold→white HDR (>1, luminance-rich) so it clears the bloom threshold.
		mm.set_instance_color(i, tier_col)
	# Impact sparks: bigger white-hot flashes that pop then fade — the visual
	# "this bullet hit something" that connects the stream to the kills.
	for j in spark_n:
		var s: Dictionary = _sparks[j]
		var life: float = clampf(float(s["life"]) / SPARK_LIFE, 0.0, 1.0)
		var scale: float = 1.6 + (1.0 - life) * 1.6      # expands as it fades
		var slocal: Vector2 = s["pos"] - position
		mm.set_instance_transform_2d(n + j, Transform2D(Vector2(scale, 0), Vector2(0, scale), slocal))
		mm.set_instance_color(n + j, Palette.SWARM_SPARK * life)
	# Tier-down shatter shards: a one-shot burst of the LOST tier's colour when a gate
	# decimates the swarm and the tier drops — the downgrade "breaks apart" on screen.
	var base_i: int = n + spark_n
	for k in shatter_n:
		var sh: Dictionary = _shatter[k]
		var shlife: float = clampf(float(sh["life"]) / SHATTER_LIFE, 0.0, 1.0)
		var shscale: float = 1.2 + (1.0 - shlife) * 2.2  # expands outward as it fades
		var shlocal: Vector2 = sh["pos"] - position
		mm.set_instance_transform_2d(
			base_i + k, Transform2D(Vector2(shscale, 0), Vector2(0, shscale), shlocal))
		mm.set_instance_color(base_i + k, Color(sh["color"]) * shlife)


func _make_orb_texture() -> ImageTexture:
	var img := Image.create(ORB_TEX_SIZE, ORB_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (ORB_TEX_SIZE - 1) * 0.5
	for y in ORB_TEX_SIZE:
		for x in ORB_TEX_SIZE:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
