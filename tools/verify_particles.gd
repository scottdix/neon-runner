extends SceneTree
## Headless verification for SLICE A — PARTICLES (#19 explosion, #20 collect/multiply).
##
## EffectLayer keeps every which-emitter / which-colour / where decision in PURE methods so we
## can assert them with NO GPU (the pooled GPUParticles2D are only built in _ready, which is
## DEFERRED under `-s` and never fires here — so _emit's GPU restart() is a guarded no-op and the
## bus handlers run clean on a bare .new()). We assert:
##   - _resolve_burst maps gate ops to the right Palette HDR colour buckets (positive add/multiply
##     → GATE_ADD/GATE_MULTIPLY collect; negative subtract/divide → GATE_NEGATIVE decimate) and the
##     enemy/explosion path → ENEMY_ROSE.
##   - _next_emitter_index() advances and WRAPS at POOL_SIZE.
##   - the enemy_destroyed / gate_passed / spawn_particles handlers run without error and select a
##     burst (pool-less → no GPU touched).
## Run:
##   tools/run-headless.sh res://tools/verify_particles.gd /tmp/verify_particles_result.txt

const RESULT_PATH := "/tmp/verify_particles_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	var pal: Node = root.get_node_or_null("Palette")
	if ev == null or pal == null:
		lines.append("RESULT=FAIL (autoloads missing: Events/Palette)"); _write(lines); return

	var EffectS: GDScript = load("res://assets/effects/effect_layer.gd")
	if EffectS == null:
		lines.append("RESULT=FAIL (effect_layer.gd missing)"); _write(lines); return

	var fx: Node2D = EffectS.new()   # bare .new(): no _ready, no pool, no GPU

	# === 1) _resolve_burst colour buckets ====================================
	# Positive ops → upward collect, gate-family colours.
	var b_mul: Dictionary = fx.call("_resolve_burst", EffectS.KIND_COLLECT, "multiply")
	var b_add: Dictionary = fx.call("_resolve_burst", EffectS.KIND_COLLECT, "add")
	# Negative op → red downward decimate puff.
	var b_dec: Dictionary = fx.call("_resolve_burst", EffectS.KIND_DECIMATE, "divide")
	# Enemy kill → radial rose explosion.
	var b_exp: Dictionary = fx.call("_resolve_burst", EffectS.KIND_EXPLOSION)

	lines.append("resolve multiply: color==GATE_MULTIPLY=%s up=%s (want true,true)" % [
		b_mul["color"] == Palette.GATE_MULTIPLY, b_mul["up"]])
	if b_mul["color"] != Palette.GATE_MULTIPLY or not bool(b_mul["up"]) or bool(b_mul["radial"]):
		lines.append("resolve FAIL: multiply collect not an upward GATE_MULTIPLY pop"); ok = false

	lines.append("resolve add: color==GATE_ADD=%s up=%s (want true,true)" % [
		b_add["color"] == Palette.GATE_ADD, b_add["up"]])
	if b_add["color"] != Palette.GATE_ADD or not bool(b_add["up"]):
		lines.append("resolve FAIL: add collect not an upward GATE_ADD pop"); ok = false

	lines.append("resolve decimate: color==GATE_NEGATIVE=%s up=%s (want true,false)" % [
		b_dec["color"] == Palette.GATE_NEGATIVE, b_dec["up"]])
	if b_dec["color"] != Palette.GATE_NEGATIVE or bool(b_dec["up"]):
		lines.append("resolve FAIL: negative gate not a red downward decimate puff"); ok = false

	lines.append("resolve explosion: color==ENEMY_ROSE=%s radial=%s (want true,true)" % [
		b_exp["color"] == Palette.ENEMY_ROSE, b_exp["radial"]])
	if b_exp["color"] != Palette.ENEMY_ROSE or not bool(b_exp["radial"]):
		lines.append("resolve FAIL: enemy kill not a radial ENEMY_ROSE explosion"); ok = false

	# Positive vs negative buckets must be DISTINCT colours (gain reads different from loss).
	if b_add["color"] == b_dec["color"] or b_mul["color"] == b_dec["color"]:
		lines.append("resolve FAIL: positive and negative bursts share a colour"); ok = false

	# Unknown type falls back to explosion (no silent nothing for spawn_particles).
	var b_unknown: Dictionary = fx.call("_resolve_burst", "garbage")
	if b_unknown["kind"] != EffectS.KIND_EXPLOSION:
		lines.append("resolve FAIL: unknown type did not fall back to explosion"); ok = false

	# === 2) _next_emitter_index advances + wraps =============================
	var seen: Array[int] = []
	for i in EffectS.POOL_SIZE:
		seen.append(int(fx.call("_next_emitter_index")))
	var wrap: int = int(fx.call("_next_emitter_index"))   # one past the pool → wraps to seen[0]
	var monotonic := true
	for i in EffectS.POOL_SIZE:
		if seen[i] != i:
			monotonic = false
	lines.append("index: first=%d last=%d wrap=%d (want 0, %d, 0)" % [
		seen[0], seen[EffectS.POOL_SIZE - 1], wrap, EffectS.POOL_SIZE - 1])
	if not monotonic or seen[0] != 0 or seen[EffectS.POOL_SIZE - 1] != EffectS.POOL_SIZE - 1 or wrap != 0:
		lines.append("index FAIL: emitter index did not advance/wrap across the pool"); ok = false

	# === 3) handlers run clean (pool-less → guarded no-op on the GPU path) ====
	# set_crossing_y + the steer track feed the gate-crossing position; the handlers must select a
	# burst and reach the guarded _emit without erroring (no pool → nothing fired, no crash).
	fx.call("set_crossing_y", 1680.0)
	fx.call("_on_player_steered", 720.0, 0.66)        # move ship x
	fx.call("_on_enemy_destroyed", Vector2(300, 400), 50)
	fx.call("_on_gate_passed", "multiply", 2.0, 20)
	fx.call("_on_gate_passed", "subtract", 5.0, 12)
	fx.call("_on_spawn_particles", Vector2(540, 960), EffectS.KIND_EXPLOSION)
	fx.call("_on_spawn_particles", Vector2(540, 960), "garbage")
	lines.append("handlers: enemy_destroyed/gate_passed(+/-)/spawn_particles ran without error (no GPU)")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
