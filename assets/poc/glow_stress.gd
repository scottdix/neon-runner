extends Node2D
## POC glow scene + MultiMesh/collision stress test (#6).
##
## Proves the two feasibility bets in docs/design/GAME_SCOPE.md:
##   (1) thousands of additive neon "fleet" orbs in ONE MultiMesh draw call + HDR bloom
##       (the Geometry-Wars look) at 60fps on a real phone, and
##   (2) the batched projectile->enemy model (D3): CPU stays O(enemies), NOT O(fleet) —
##       the fleet is one rigidly-translated blob (GPU draws it); collision is a few
##       enemy AABBs vs one logical blob + a "beam/volume" DPS emitter.
##
## Headless asserts structure + logic timing (no GPU). The glow/FPS itself is confirmed
## over VNC or on-device (#47). Controls: drag = steer; UP/DOWN = fleet count; LEFT/RIGHT = enemies.

const ORB_TEX_SIZE := 32
const ORB_QUAD_SIZE := 26.0
const SHIP_MARGIN := 240.0            # ship sits this far above the bottom
const FLEET_SPREAD := Vector2(150, 520) # half-extents of the swarm cloud around the ship
const BEAM_HALF_WIDTH := 170.0        # horizontal reach of the fleet's damage column
const BASE_DPS := 40.0

@export var fleet_count := 4000
@export var enemy_count := 6

var _mmi: MultiMeshInstance2D
var _hud: Label
var _design := Vector2(1080, 1920)
var _ship := Vector2(540, 1680)
var _target_x := 540.0
var _time := 0.0
var _enemies: Array[Dictionary] = []
var _kills := 0
var _ship_hits := 0
var _logic_us_avg := 0.0              # running avg of per-frame CPU logic cost (microseconds)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0xBEEF                 # deterministic so headless runs are reproducible
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_ship = Vector2(_design.x * 0.5, _design.y - SHIP_MARGIN)
	_target_x = _ship.x
	_build_environment()
	_build_fleet()
	_build_hud()
	_spawn_enemies(enemy_count)


# --- Setup -------------------------------------------------------------------

func _build_environment() -> void:
	# HDR bloom is the core neon effect. Threshold at 1.0 means ONLY RGB>1 colors bloom
	# (orbs/enemies are pushed >1); HUD text stays <=1 so it does NOT bloom — the cheap
	# way to "exclude" the HUD from glow without a second viewport.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.04)
	env.glow_enabled = true
	env.glow_intensity = 1.4
	env.glow_strength = 1.0
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_fleet() -> void:
	var tex := _make_orb_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(ORB_QUAD_SIZE, ORB_QUAD_SIZE)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = fleet_count
	_populate_fleet_instances(mm)

	_mmi = MultiMeshInstance2D.new()
	_mmi.name = "FleetMultiMesh"
	_mmi.multimesh = mm
	_mmi.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive: overlapping orbs accumulate to white-hot
	_mmi.material = mat
	_mmi.position = _ship
	add_child(_mmi)


func _populate_fleet_instances(mm: MultiMesh) -> void:
	# Instance transforms are set ONCE, in the blob's LOCAL space (a comet-tail cloud
	# above the ship). Per-frame we only move the single MultiMeshInstance2D node, so CPU
	# cost is O(1) in fleet size. Gold HDR colors (>1) so bloom catches them.
	for i in mm.instance_count:
		var t := float(i) / float(max(mm.instance_count, 1))
		var off := Vector2(
			_rng.randfn(0.0, FLEET_SPREAD.x * 0.5),
			-_rng.randf() * FLEET_SPREAD.y - 8.0)
		mm.set_instance_transform_2d(i, Transform2D(0.0, off))
		var heat := 1.6 + (1.0 - t) * 2.0           # brighter near the ship
		mm.set_instance_color(i, Color(heat, heat * 0.82, heat * 0.28, 1.0))


func _make_orb_texture() -> ImageTexture:
	# Soft radial falloff so additive blending reads as round glowing orbs.
	var img := Image.create(ORB_TEX_SIZE, ORB_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (ORB_TEX_SIZE - 1) * 0.5
	for y in ORB_TEX_SIZE:
		for x in ORB_TEX_SIZE:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a                                # tighter core
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _build_hud() -> void:
	# Separate CanvasLayer keeps the readout pinned; modulate <=1 so it stays out of bloom.
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(28, 28)
	_hud.modulate = Color(0.85, 0.95, 1.0)
	layer.add_child(_hud)


func _spawn_enemies(n: int) -> void:
	_enemies.clear()
	for i in n:
		_enemies.append(_new_enemy(_rng.randf() * _design.y * 0.5))


func _new_enemy(start_y: float) -> Dictionary:
	return {
		"pos": Vector2(_rng.randf_range(120, _design.x - 120), start_y),
		"hp": 100.0,
		"max_hp": 100.0,
		"size": 64.0,
		"speed": _rng.randf_range(120, 220),
	}


# --- Per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()

	# Steer: drag the ship's x toward the touch/mouse, fleet blob follows (one node move).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_target_x = get_viewport().get_mouse_position().x
	_ship.x = lerpf(_ship.x, clampf(_target_x, 80, _design.x - 80), 1.0 - pow(0.001, delta))
	_time += delta
	if _mmi:
		_mmi.position = Vector2(_ship.x, _ship.y + sin(_time * 2.0) * 12.0)  # cheap bob

	_update_enemies(delta)

	# Logic-cost EMA (the number that must stay flat as fleet_count grows).
	var us := float(Time.get_ticks_usec() - t0)
	_logic_us_avg = lerpf(_logic_us_avg, us, 0.05) if _logic_us_avg > 0.0 else us

	queue_redraw()
	if _hud:
		_hud.text = "FPS %d\nfleet %d (1 draw call)\nenemies %d  kills %d  ship-hits %d\nlogic %.1f us/frame  (O(enemies), not O(fleet))" % [
			Engine.get_frames_per_second(), fleet_count, _enemies.size(), _kills, _ship_hits, _logic_us_avg]


func _update_enemies(delta: float) -> void:
	# Batched damage (D3): the fleet is a DPS "beam/volume" over a horizontal column ahead
	# of the ship. We test a few enemy AABBs against that column + the ship — O(enemies).
	var beam_x := _ship.x
	for e in _enemies:
		var p: Vector2 = e["pos"]
		p.y += e["speed"] * delta
		# Fleet damage: enemy within the column and above the ship takes DPS.
		if absf(p.x - beam_x) < BEAM_HALF_WIDTH and p.y < _ship.y:
			e["hp"] -= BASE_DPS * delta * _tier_factor()
		# Ship collision (the one-logical-blob survivability check).
		if p.distance_to(_ship) < (e["size"] * 0.5 + 36.0):
			_ship_hits += 1
			e["hp"] = -1.0
		if e["hp"] <= 0.0 or p.y > _design.y + e["size"]:
			if e["hp"] <= 0.0:
				_kills += 1
			var fresh := _new_enemy(-e["size"])
			e["pos"] = fresh["pos"]; e["hp"] = fresh["max_hp"]; e["max_hp"] = fresh["max_hp"]
			e["size"] = fresh["size"]; e["speed"] = fresh["speed"]
		else:
			e["pos"] = p


func _draw() -> void:
	# Enemies as neon rhombi (HDR magenta so they bloom). A handful — cheap.
	for e in _enemies:
		var p: Vector2 = e["pos"]
		var s: float = e["size"] * 0.5
		var pts := PackedVector2Array([
			p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
		var frac: float = clampf(e["hp"] / e["max_hp"], 0.0, 1.0)
		var col := Color(2.2, 0.3 + frac * 0.4, 1.8)   # >1 -> blooms
		draw_colored_polygon(pts, col)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(2.6, 1.4, 2.4), 2.0)
	# Ship marker (cyan vector chevron).
	var sp := _ship
	draw_polyline(PackedVector2Array([
		sp + Vector2(-34, 30), sp + Vector2(0, -34), sp + Vector2(34, 30), sp + Vector2(0, 14), sp + Vector2(-34, 30)]),
		Color(0.5, 3.2, 3.6), 3.0)


func _tier_factor() -> float:
	# Stand-in for projectile tier evolution: more fleet => more firepower.
	return 1.0 + float(fleet_count) / 4000.0


# --- Stress controls + debug -------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:    set_fleet_count(fleet_count + 1000)
			KEY_DOWN:  set_fleet_count(max(500, fleet_count - 1000))
			KEY_RIGHT: _spawn_enemies(_enemies.size() + 2)
			KEY_LEFT:  _spawn_enemies(max(1, _enemies.size() - 2))


func set_fleet_count(n: int) -> void:
	fleet_count = n
	if _mmi and _mmi.multimesh:
		_mmi.multimesh.instance_count = n
		_populate_fleet_instances(_mmi.multimesh)


## Consumed by tools/verify_poc.gd (headless can't render, but can assert structure + cost).
func get_debug_stats() -> Dictionary:
	return {
		"fleet_count": fleet_count,
		"mm_instances": (_mmi.multimesh.instance_count if _mmi and _mmi.multimesh else -1),
		"draw_calls_for_fleet": 1,
		"enemies": _enemies.size(),
		"kills": _kills,
		"logic_us_avg": _logic_us_avg,
		"has_world_environment": _has_world_env(),
	}


func _has_world_env() -> bool:
	for c in get_children():
		if c is WorldEnvironment:
			return true
	return false
