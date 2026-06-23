extends Node2D
## Effect layer (#19 explosion, #20 collection/multiply) — the GPU-particle bursts that
## punctuate the run, wired through the Events bus only. Run instantiates ONE of these and
## add_child()s it; it self-connects to the bus and fires one-shot GPUParticles2D emitters.
##
## DESIGN / GOTCHA notes:
##   - Bloom ONLY catches the textured / MultiMesh / GPUParticles2D additive-HDR path. So every
##     burst is a GPUParticles2D with a CanvasItemMaterial BLEND_MODE_ADD + a soft round texture,
##     modulated by an HDR (>1.0) Palette colour so it actually blooms. (A draw_*/Line2D burst
##     would never glow — confirmed on device twice.)
##   - Colour is ALWAYS a Palette HDR const (the in-bloom family), never a literal.
##   - HEADLESS determinism: every which-emitter / which-colour / where decision lives in a PURE
##     method (_resolve_burst / _next_emitter_index) callable on a bare .new() with NO GPU. The
##     only GPU-touching step is emitter.restart()/emitting — guarded so a failed-to-build pooled
##     emitter (or a headless run where _ready never fired) just no-ops.
##
## Bus inputs (READ-ONLY for this layer — it only listens, never re-emits run state):
##   enemy_destroyed(at, points)   → #19 explosion in the enemy rose family at the kill point.
##   gate_passed(type, value, cnt) → #20 collect pop / decimate puff at the GATE CROSSING POINT.
##                                   gate_passed carries no position; crossings happen on the ship
##                                   line, so Run feeds us the ship-line y via set_crossing_y() and
##                                   we track ship x off player_steered. Positive op = upward green/
##                                   magenta collect; negative op = red decimate puff.
##   spawn_particles(pos, type)    → generic entry point (revives that previously-dead signal);
##                                   `type` selects explosion vs collect at an explicit position.

# --- Burst kinds (the PURE vocabulary _resolve_burst speaks in) ---------------
const KIND_EXPLOSION := "explosion"   # #19 enemy kill — radial rose blast
const KIND_COLLECT := "collect"       # #20 positive gate — upward collect pop
const KIND_DECIMATE := "decimate"     # #20 negative gate — red downward puff

# Pool size: round-robined so concurrent kills/crossings don't stomp each other mid-emit.
const POOL_SIZE := 14
const PARTICLE_TEX_SIZE := 24

# Where a gate crossing visually happens: the ship line y. Run overrides this via
# set_crossing_y(); the design default keeps the layer sane if it's ever used standalone.
var _crossing_y: float = 1680.0
# Ship x, tracked off player_steered so the collect pop lands under the swarm muzzle.
var _ship_x: float = 540.0

var _pool: Array[GPUParticles2D] = []
var _next: int = 0
var _shared_tex: Texture2D


func _ready() -> void:
	# Build the emitter pool + self-connect to the bus. NOTE: under headless `-s`, _ready is
	# DEFERRED and may not fire before a tool's _initialize — that's fine, the PURE methods
	# (_resolve_burst / _next_emitter_index) don't need the pool, and the GPU restart() is
	# guarded so a pool-less instance no-ops instead of erroring.
	_shared_tex = _make_particle_texture()
	for i in POOL_SIZE:
		var p := _make_emitter()
		add_child(p)
		_pool.append(p)

	Events.enemy_destroyed.connect(_on_enemy_destroyed)
	Events.gate_passed.connect(_on_gate_passed)
	Events.player_steered.connect(_on_player_steered)
	Events.spawn_particles.connect(_on_spawn_particles)


# --- Run-facing setters ------------------------------------------------------

## Run calls this with ship_pos.y so gate-crossing bursts land on the ship line (gate_passed
## carries no position). Pure state set; safe to call before _ready.
func set_crossing_y(y: float) -> void:
	_crossing_y = y


# --- Bus handlers (thin: resolve PURE, then fire) ----------------------------

func _on_player_steered(x: float, _x_norm: float) -> void:
	_ship_x = x


## #19: an enemy died — radial rose explosion at the kill point, scaled a touch by points so a
## fat kill reads bigger. `points` is informational; the colour bucket is fixed (rose family).
func _on_enemy_destroyed(at: Vector2, points: int) -> void:
	var burst := _resolve_burst(KIND_EXPLOSION)
	var scale: float = clampf(1.0 + float(points) / 200.0, 1.0, 2.0)
	_emit(at, burst, scale)


## #20: a gate fired. gate_passed has no position, so the crossing is the ship line: x = the
## tracked ship x, y = the crossing line. Positive op pops up (green add / magenta multiply);
## negative op puffs red. _resolve_burst owns the op→kind→colour decision (PURE).
func _on_gate_passed(gate_type: String, _value: float, _new_count: int) -> void:
	var kind: String = KIND_COLLECT if _is_positive_op(gate_type) else KIND_DECIMATE
	var burst := _resolve_burst(kind, gate_type)
	_emit(Vector2(_ship_x, _crossing_y), burst, 1.0)


## Generic entry point — revives the long-dead Events.spawn_particles signal so anything can
## ask for a burst at an explicit position. `type` selects the burst kind (defaults to explosion
## for any unknown string so a caller can't silently get nothing).
func _on_spawn_particles(position: Vector2, type: String) -> void:
	var burst := _resolve_burst(type)
	_emit(position, burst, 1.0)


# --- PURE decision logic (headless-safe; the verify script asserts on these) --

## Map a burst kind (or a gate_type, for the gate path) to a render recipe: which Palette HDR
## colour, how radial the spread reads, and the directional bias. NO GPU — returns a plain Dict
## so the verify script can assert the colour buckets without a renderer.
##   { "kind": String, "color": Color, "radial": bool, "up": bool }
func _resolve_burst(type: String, gate_type: String = "") -> Dictionary:
	match type:
		KIND_COLLECT:
			# Positive gate collect pop — upward. Multiply reads magenta, add reads green; both
			# are GATE_* HDR consts so the pop blooms in the gate's own colour family.
			var col: Color = Palette.GATE_MULTIPLY if gate_type == "multiply" else Palette.GATE_ADD
			return {"kind": KIND_COLLECT, "color": col, "radial": false, "up": true}
		KIND_DECIMATE:
			# Negative gate (subtract/divide) — a red downward decimate puff, distinct from the
			# upward collect so the two read as gain vs loss at a glance.
			return {"kind": KIND_DECIMATE, "color": Palette.GATE_NEGATIVE, "radial": false, "up": false}
		KIND_EXPLOSION, _:
			# #19 default: radial rose blast cored with flash-white so the centre reads white-hot.
			return {"kind": KIND_EXPLOSION, "color": Palette.ENEMY_ROSE, "radial": true, "up": false}


## Round-robin the pool: hand out the next index and advance (wrapping at POOL_SIZE) so back-to-
## back bursts use different emitters and don't cut each other off mid-emit. PURE — no GPU; the
## verify script asserts it advances and wraps. Returns -1 if the pool is empty (headless / no
## _ready), which _emit treats as a no-op.
func _next_emitter_index() -> int:
	if POOL_SIZE <= 0:
		return -1
	var idx := _next
	_next = (_next + 1) % POOL_SIZE
	return idx


## Positive economy op? add / multiply grow the swarm (collect pop); subtract / divide shrink it
## (decimate puff). Matches gate.gd's _op_string() vocabulary ("add"/"subtract"/"multiply"/"divide").
func _is_positive_op(gate_type: String) -> bool:
	return gate_type == "add" or gate_type == "multiply"


# --- GPU-touching fire (the ONLY non-pure part; guarded) ---------------------

## Fire a resolved burst at `pos`. Picks the next pooled emitter, retints/repoints/reshapes it
## from the recipe, and restarts it as a one-shot. Guarded: a -1 index (empty pool) or a null/
## un-built emitter no-ops, so a headless `.new()` instance survives this path untouched.
func _emit(pos: Vector2, burst: Dictionary, scale: float) -> void:
	var idx := _next_emitter_index()
	if idx < 0 or idx >= _pool.size():
		return
	var p: GPUParticles2D = _pool[idx]
	if p == null:
		return
	p.position = pos
	p.modulate = burst["color"]
	p.scale = Vector2(scale, scale)
	var pm: ParticleProcessMaterial = p.process_material as ParticleProcessMaterial
	if pm != null:
		if bool(burst["radial"]):
			# Radial blast — full 360°, no gravity, even outward push.
			pm.direction = Vector3(0.0, -1.0, 0.0)
			pm.spread = 180.0
			pm.gravity = Vector3.ZERO
		else:
			# Directional pop/puff — biased up (collect) or down (decimate), light gravity so it
			# arcs and settles instead of reading as a second radial blast.
			var up: bool = bool(burst["up"])
			pm.direction = Vector3(0.0, -1.0 if up else 1.0, 0.0)
			pm.spread = 55.0
			pm.gravity = Vector3(0.0, 380.0 if up else 220.0, 0.0)
	p.restart()
	p.emitting = true


# --- Emitter / texture construction (GPU resources; built in _ready only) -----

## One pooled one-shot emitter. Additive CanvasItemMaterial + soft round texture so the burst
## feeds the WorldEnvironment bloom (the immediate-draw path would never glow). Colour is set
## per-fire via modulate; this just lays out the shape/lifetime.
func _make_emitter() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.texture = _shared_tex
	p.one_shot = true
	p.explosiveness = 1.0          # all particles at t=0 — a single punch, not a stream
	p.amount = 24
	p.lifetime = 0.55
	p.emitting = false             # idle until _emit restarts it
	p.local_coords = false         # particles live in world space so they don't ride a re-pointed emitter

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive → overlapping cores bloom white-hot
	p.material = mat

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 6.0
	pm.spread = 180.0
	pm.initial_velocity_min = 140.0
	pm.initial_velocity_max = 460.0
	pm.damping_min = 120.0
	pm.damping_max = 240.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	# Fade + shrink over life so the burst dissolves into the bloom instead of popping out.
	var scale_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	scale_curve.curve = curve
	pm.scale_curve = scale_curve
	p.process_material = pm
	return p


## Soft round dot (bright core, alpha falloff to the edge) — the per-particle sprite. Same recipe
## as the fleet/poc orb so the bursts share the swarm's visual language. Additive blending turns
## overlapping dots white-hot at the burst core.
func _make_particle_texture() -> ImageTexture:
	var img := Image.create(PARTICLE_TEX_SIZE, PARTICLE_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (PARTICLE_TEX_SIZE - 1) * 0.5
	for y in PARTICLE_TEX_SIZE:
		for x in PARTICLE_TEX_SIZE:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
