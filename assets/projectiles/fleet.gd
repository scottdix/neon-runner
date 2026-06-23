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

var _volume: int = 0
var _proj: Array[Vector2] = []     # live projectile positions (top of the pool)
var _fire_accum: float = 0.0
var _rng := RandomNumberGenerator.new()
var _mmi: MultiMeshInstance2D
var _sparks: Array = []            # [{pos:Vector2, life:float}, ...] impact flashes


func _ready() -> void:
	_rng.seed = 0xF1EE7
	_build_multimesh()
	# React to swarm-volume changes from the economy (gates -> GameState -> Events).
	Events.projectile_count_changed.connect(set_volume)
	_volume = GameState.projectile_count   # autoload global; valid off-tree + headless


func _process(delta: float) -> void:
	step(delta)
	_render()


## Advance the stream one frame: fire on cadence, move projectiles up, recycle
## those past the top. Pure + GPU-free so headless tests drive it directly.
func step(delta: float) -> void:
	var rate: float = clampf(
		BASE_FIRE_RATE + float(_volume) * FIRE_RATE_PER_VOLUME, BASE_FIRE_RATE, MAX_FIRE_RATE)
	_fire_accum += rate * delta
	var shots := int(_fire_accum)
	if shots > 0:
		_fire_accum -= float(shots)
		_fire(shots)

	# March every live projectile straight up; drop the ones off the top.
	# (Targets call consume_near() to remove + spark + damage on contact.)
	var top_cutoff := -ORB_QUAD
	var survivors: Array[Vector2] = []
	for p in _proj:
		var np := Vector2(p.x, p.y - PROJ_SPEED * delta)
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


func _fire(shots: int) -> void:
	var spread: float = clampf(
		BASE_SPREAD + float(_volume) * SPREAD_PER_VOLUME, BASE_SPREAD, MAX_SPREAD)
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
	_volume = maxi(0, count)


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
	mm.visible_instance_count = n + spark_n
	# Instances are positioned in this node's local space; subtract our origin.
	for i in n:
		var local := _proj[i] - position
		mm.set_instance_transform_2d(i, Transform2D(0.0, local))
		# Gold HDR (>1, luminance-rich) so it clears the bloom threshold (POC #6).
		mm.set_instance_color(i, Color(3.4, 2.8, 0.9, 1.0))
	# Impact sparks: bigger white-hot flashes that pop then fade — the visual
	# "this bullet hit something" that connects the stream to the kills.
	for j in spark_n:
		var s: Dictionary = _sparks[j]
		var life: float = clampf(float(s["life"]) / SPARK_LIFE, 0.0, 1.0)
		var scale: float = 1.6 + (1.0 - life) * 1.6      # expands as it fades
		var slocal: Vector2 = s["pos"] - position
		mm.set_instance_transform_2d(n + j, Transform2D(Vector2(scale, 0), Vector2(0, scale), slocal))
		mm.set_instance_color(n + j, Color(5.5, 5.0, 3.2, 1.0) * life)


func _make_orb_texture() -> ImageTexture:
	var img := Image.create(ORB_TEX_SIZE, ORB_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (ORB_TEX_SIZE - 1) * 0.5
	for y in ORB_TEX_SIZE:
		for x in ORB_TEX_SIZE:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
