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
const CONSUME_PAD := 10.0           # collision radius = visible half-size + this
const FLASH_DECAY := 0.08           # seconds an impact flash-pulse lasts
const BURST_LIFE := 0.30            # seconds a death burst lives

## A Fractal hit while the swarm volume is below this "tier" splits instead of dying.
## Above it, the fleet has enough firepower to destroy it cleanly.
const FRACTAL_SPLIT_TIER := 60

## Per-archetype stat block. Looked up by kind; enemies carry a copy so test code can
## still inject bare dicts (they default to GLITCH behaviour via the get() fallbacks).
const STATS := {
	KIND_GLITCH:    {"hp": 40.0,  "size": 52.0,  "spd": [220.0, 320.0], "armor": 0, "points": 50,  "breach": 6.0,  "split": false},
	KIND_RHOMBUS:   {"hp": 320.0, "size": 108.0, "spd": [70.0, 120.0],  "armor": 3, "points": 250, "breach": 18.0, "split": false},
	KIND_FRACTAL:   {"hp": 110.0, "size": 78.0,  "spd": [130.0, 200.0], "armor": 0, "points": 120, "breach": 10.0, "split": true},
	KIND_FRACTLING: {"hp": 28.0,  "size": 42.0,  "spd": [280.0, 380.0], "armor": 0, "points": 40,  "breach": 4.0,  "split": false},
}

## Per-archetype HDR colour (RGB > 1 feeds the bloom; textured/additive path so it glows).
const COLORS := {
	KIND_GLITCH:    Color(3.0, 0.6, 2.6, 1.0),    # magenta
	KIND_RHOMBUS:   Color(3.4, 0.3, 1.2, 1.0),    # deep crimson-magenta (dense/dangerous)
	KIND_FRACTAL:   Color(3.2, 2.2, 0.5, 1.0),    # amber star
	KIND_FRACTLING: Color(3.0, 2.4, 0.9, 1.0),    # pale amber shard
}

@export var enemy_count := 7

var _design := Vector2(1080, 1920)
var _fleet: Node2D                  # injected by Run; queried for bullet hits
var _breach_line: float = 1.0e9     # disabled until Run injects the ship line (set_breach_line)
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
	spawn(enemy_count)


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


## Spawn a fresh wave as a weighted archetype mix (mostly glitches, some fractals,
## the occasional rhombus). Deterministic given the seed so headless runs are stable.
func spawn(n: int) -> void:
	_enemies.clear()
	for i in mini(n, MAX_ENEMIES):
		_enemies.append(_new_enemy(_pick_kind(), _rng.randf() * _design.y * 0.4))


## Advance one frame. Two passes: (1) batched damage — every enemy's hit volume is
## resolved against the live bullets in ONE Fleet.consume_volumes call; (2) movement
## + lifecycle (drift down, flash decay, death/split, breach, offscreen recycle).
## Pure + GPU-free for headless.
func step(delta: float) -> void:
	# (1) Batched projectile→enemy damage (#54). One pass over the bullets for ALL
	# enemies instead of one survivor-rebuild per enemy.
	if _fleet != null and not _enemies.is_empty():
		var positions := PackedVector2Array()
		var radii := PackedFloat32Array()
		for e in _enemies:
			positions.append(e["pos"])
			radii.append(_hit_radius(e))
		var hits: PackedInt32Array = _fleet.call("consume_volumes", positions, radii)
		for i in _enemies.size():
			if hits[i] > 0:
				_apply_damage(_enemies[i], hits[i])

	# (2) Movement + lifecycle. Splits append new fractlings; collect them and add
	# after the loop so we never mutate _enemies mid-iteration.
	var to_add: Array[Dictionary] = []
	for e in _enemies:
		var p: Vector2 = e["pos"]
		p.y += float(e["speed"]) * delta
		e["pos"] = p
		e["flash"] = maxf(0.0, float(e["flash"]) - delta / FLASH_DECAY)
		# If the run has already ended this frame — e.g. an earlier enemy in THIS loop
		# breached and emptied the battery, failing the run synchronously — stop
		# scoring/breaching. Otherwise a later kill here would bump `kills` + emit
		# enemy_destroyed while register_kill (run_active=false) awards nothing, so the
		# counter/signal/score would disagree on the failing frame. Movement above is
		# cosmetic and harmless. (Next frame the tree is paused, so step() won't run.)
		if not GameState.run_active:
			continue
		if float(e["hp"]) <= 0.0:
			_resolve_death(e, to_add)
		elif p.y >= _breach_line:
			_breach(e)
		elif p.y > _design.y + float(e["size"]):
			_respawn(e, -float(e["size"]))           # offscreen fallback (breach disabled)
	for ne in to_add:
		if _enemies.size() < MAX_ENEMIES:
			_enemies.append(ne)

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


## Apply a frame's worth of bullet hits to an enemy, honoring its armor: a RHOMBUS
## only takes the hits ABOVE its armor value, so a thin stream (few hits/frame) never
## cracks it — you need a swarm dense enough to overwhelm the armor. Always flashes.
func _apply_damage(e: Dictionary, hits: int) -> void:
	var armor: int = int(e.get("armor", 0))
	var effective: int = maxi(0, hits - armor)
	if effective > 0:
		e["hp"] = float(e["hp"]) - float(effective) * DAMAGE_PER_BULLET
	e["flash"] = 1.0


## An enemy hit 0 HP. A FRACTAL with insufficient firepower (swarm volume below the
## split tier) SPLITS into two fractlings instead of dying — no score, more threats.
## Otherwise it dies: score (combo), burst, recycle.
func _resolve_death(e: Dictionary, to_add: Array[Dictionary]) -> void:
	var kind: int = int(e.get("kind", KIND_GLITCH))
	if kind == KIND_FRACTAL and bool(e.get("split", true)) and GameState.projectile_count < FRACTAL_SPLIT_TIER:
		Events.enemy_split.emit(e["pos"])
		var base_pos: Vector2 = e["pos"]
		var shard := _new_enemy(KIND_FRACTLING, base_pos.y)
		shard["pos"] = base_pos + Vector2(-46.0, -10.0)
		# Reuse this slot as the first fractling; queue the second.
		for k in shard:
			e[k] = shard[k]
		var shard2 := _new_enemy(KIND_FRACTLING, base_pos.y)
		shard2["pos"] = base_pos + Vector2(46.0, -10.0)
		to_add.append(shard2)
	else:
		_kill(e)


func _kill(e: Dictionary) -> void:
	kills += 1
	var points: int = int(e.get("points", 100))
	GameState.register_kill(points)               # combo-multiplied scoring
	if _bursts.size() < MAX_BURSTS:
		_bursts.append({"pos": e["pos"], "life": BURST_LIFE, "col": _enemy_color(e)})
	Events.enemy_destroyed.emit(e["pos"], points)
	_respawn(e, -float(e["size"]))


## An enemy reached the ship line: it breaches, draining the Glow Battery by its
## breach cost (the loss pressure that makes shooting matter, #55), then recycles.
func _breach(e: Dictionary) -> void:
	breaches += 1
	var dmg: float = float(e.get("breach", 6.0))
	GameState.drain_battery(dmg)
	Events.enemy_breached.emit(e["pos"], dmg)
	_respawn(e, -float(e["size"]))


func _pick_kind() -> int:
	var roll: float = _rng.randf()
	if roll < 0.15:
		return KIND_RHOMBUS
	elif roll < 0.40:
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
	}


## Recycle a dead/offscreen slot into a fresh enemy at the top (endless waves for the
## MVP; the finite, scheduled spawner is #13). Re-rolls the archetype.
func _respawn(e: Dictionary, start_y: float) -> void:
	var fresh := _new_enemy(_pick_kind(), start_y)
	for k in fresh:
		e[k] = fresh[k]
	# Keep the slot keyed even if a bare (test-injected) dict lacked some fields.


# --- Rendering ---------------------------------------------------------------

func _enemy_color(e: Dictionary) -> Color:
	return COLORS.get(int(e.get("kind", KIND_GLITCH)), COLORS[KIND_GLITCH])


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
		mm.set_instance_transform_2d(i, Transform2D(Vector2(s, 0), Vector2(0, s), p - position))
		var col: Color = _enemy_color(e)
		var fl: float = float(e["flash"])
		if fl > 0.0:
			col = col.lerp(Color(6.0, 5.5, 6.0, 1.0), fl * 0.8)  # per-impact pulse
		mm.set_instance_color(i, col)
	# Death bursts: a white-hot diamond (tinted by the kind) that expands and fades.
	for j in b_n:
		var burst: Dictionary = _bursts[j]
		var life: float = clampf(float(burst["life"]) / BURST_LIFE, 0.0, 1.0)
		var bs: float = 0.9 + (1.0 - life) * 2.6   # expands outward as it fades
		var blocal: Vector2 = burst["pos"] - position
		mm.set_instance_transform_2d(n + j, Transform2D(Vector2(bs, 0), Vector2(0, bs), blocal))
		var bcol: Color = burst.get("col", Color(6.0, 4.6, 6.0, 1.0))
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
