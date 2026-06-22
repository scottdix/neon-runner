class_name Targets
extends Node2D
## Shootable targets / enemies (#52/#14), per-impact model: each enemy consumes
## the fleet's projectiles that reach it (Fleet.consume_near) and takes damage
## per consumed bullet, so a target dies ON a specific impact — the destruction
## is caused by the bullets, not a decoupled DPS timer. Swarm volume still scales
## firepower (more volume -> denser stream -> more impacts/sec).
##
## Collision is O(enemies × live-bullets) with both bounded (few enemies, fire-rate
## capped bullets) — cheap, keeping D3's perf intent without its DPS-emitter
## attribution (revisit at handoff). Rendered as glowing neon diamonds via a
## textured/additive MultiMesh (the only path that blooms). Sim is in `step()`
## so it runs/asserts headless with no GPU.

const MAX_ENEMIES := 32
const MAX_BURSTS := 16
const DIAMOND_TEX_SIZE := 48
const ENEMY_QUAD := 90.0

const ENEMY_HP := 120.0
const DAMAGE_PER_BULLET := 10.0
const CONSUME_PAD := 10.0           # collision radius = visible half-size + this
const FLASH_DECAY := 0.08           # seconds an impact flash-pulse lasts
const BURST_LIFE := 0.30            # seconds a death burst lives

@export var enemy_count := 6

var _design := Vector2(1080, 1920)
var _fleet: Node2D                  # injected by Run; queried for bullet hits
var _enemies: Array[Dictionary] = []
var _bursts: Array = []             # [{pos:Vector2, life:float}, ...] death pops
var _rng := RandomNumberGenerator.new()
var _mmi: MultiMeshInstance2D
var kills: int = 0


func _ready() -> void:
	_rng.seed = 0xDA77
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_build_multimesh()
	spawn(enemy_count)


func _process(delta: float) -> void:
	step(delta)
	_render()


## The fleet whose projectiles damage these targets (Run injects it; Fleet and
## Targets never reference each other directly).
func set_fleet(fleet: Node2D) -> void:
	_fleet = fleet


func spawn(n: int) -> void:
	_enemies.clear()
	for i in mini(n, MAX_ENEMIES):
		_enemies.append(_new_enemy(_rng.randf() * _design.y * 0.4))


## Advance one frame: drift down, take damage from bullets that reach each enemy,
## flash on impact, die (burst + score) or recycle. Pure + GPU-free for headless.
func step(delta: float) -> void:
	for e in _enemies:
		var p: Vector2 = e["pos"]
		p.y += float(e["speed"]) * delta
		e["pos"] = p
		e["flash"] = maxf(0.0, float(e["flash"]) - delta / FLASH_DECAY)
		if _fleet != null:
			var frac: float = clampf(float(e["hp"]) / float(e["max_hp"]), 0.0, 1.0)
			var radius: float = float(e["size"]) * 0.5 * (0.55 + 0.45 * frac) + CONSUME_PAD
			var hits: int = _fleet.consume_near(p, radius)
			if hits > 0:
				e["hp"] = float(e["hp"]) - float(hits) * DAMAGE_PER_BULLET
				e["flash"] = 1.0
		if float(e["hp"]) <= 0.0:
			_kill(e)
		elif p.y > _design.y + float(e["size"]):
			_respawn(e, -float(e["size"]))
	# Age death bursts.
	var live_bursts: Array = []
	for b in _bursts:
		b["life"] = float(b["life"]) - delta
		if b["life"] > 0.0:
			live_bursts.append(b)
	_bursts = live_bursts


func live_count() -> int:
	return _enemies.size()


func _kill(e: Dictionary) -> void:
	kills += 1
	var points := 100
	GameState.add_score(points)
	if _bursts.size() < MAX_BURSTS:
		_bursts.append({"pos": e["pos"], "life": BURST_LIFE})
	Events.enemy_destroyed.emit(e["pos"], points)
	_respawn(e, -float(e["size"]))


func _new_enemy(start_y: float) -> Dictionary:
	return {
		"pos": Vector2(_rng.randf_range(120.0, _design.x - 120.0), start_y),
		"hp": ENEMY_HP, "max_hp": ENEMY_HP,
		"size": 64.0, "speed": _rng.randf_range(120.0, 230.0),
		"flash": 0.0,
	}


func _respawn(e: Dictionary, start_y: float) -> void:
	var fresh := _new_enemy(start_y)
	for k in fresh:
		e[k] = fresh[k]


# --- Rendering ---------------------------------------------------------------

func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(ENEMY_QUAD, ENEMY_QUAD)
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
		var s: float = 0.55 + 0.45 * frac          # erodes as HP drops
		mm.set_instance_transform_2d(i, Transform2D(Vector2(s, 0), Vector2(0, s), p - position))
		var col := Color(3.0, 0.55, 2.6, 1.0)      # vivid magenta (textured/additive -> blooms)
		var fl: float = float(e["flash"])
		if fl > 0.0:
			col = col.lerp(Color(6.0, 5.5, 6.0, 1.0), fl * 0.8)  # per-impact pulse
		mm.set_instance_color(i, col)
	# Death bursts: a white-hot diamond that expands and fades — the destruction.
	for j in b_n:
		var burst: Dictionary = _bursts[j]
		var life: float = clampf(float(burst["life"]) / BURST_LIFE, 0.0, 1.0)
		var bs: float = 0.9 + (1.0 - life) * 2.6   # expands outward as it fades
		var blocal: Vector2 = burst["pos"] - position
		mm.set_instance_transform_2d(n + j, Transform2D(Vector2(bs, 0), Vector2(0, bs), blocal))
		mm.set_instance_color(n + j, Color(6.0, 4.6, 6.0, 1.0) * life)


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
