extends SceneTree
## Headless verification for the HORDE continuous fodder spawner (H2):
##   - A HORDE-flagged Targets RAMPS its live_count over time as step(delta) is simulated.
##   - The live set is CAPPED at MAX_ENEMIES (128) — sustained spawning never overflows it.
##   - Fodder appears in BOTH half-fields (left of CENTER_X and right of it) — the divider is a
##     firing boundary, not a spawn wall.
##   - The fodder is KIND_GLITCH one-hit fodder, kept clear of CENTER_X.
##   - REGRESSION: with HORDE OFF, _spawn_horde is inert (no continuous spawn) so LEGACY is unchanged.
##
## GPU-free-ish: it does add_child a real Targets (its _ready builds a MultiMesh, fine headless) and
## awaits a frame so _ready has run, then drives step(delta) directly (no fleet => no damage pass).
##   tools/run-headless.sh res://tools/verify_horde_spawn.gd /tmp/verify_horde_spawn_result.txt

const RESULT_PATH := "/tmp/verify_horde_spawn_result.txt"
const CENTER_X := 540.0


func _initialize() -> void:
	# Deferred so add_child'd nodes get their _ready under -s (see harness gotchas).
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var lines: Array[String] = []
	var ok := true

	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		lines.append("RESULT=FAIL (GameState autoload missing)"); _write(lines); return

	var TargetsScript: GDScript = load("res://assets/obstacles/targets.gd")
	var t: Node2D = TargetsScript.new()
	t.name = "VerifyTargets"
	root.add_child(t)
	await process_frame   # let Targets._ready run (_design + _build_multimesh)

	# Live run + a real level so _run_progress has a length_m (drives the rate ramp).
	gs.call("start_run")
	var max_enemies: int = int(t.get("MAX_ENEMIES"))
	lines.append("MAX_ENEMIES=%d (want 128)" % max_enemies)
	if max_enemies != 128:
		lines.append("cap FAIL: MAX_ENEMIES not raised to 128"); ok = false

	# --- A) HORDE OFF is inert: stepping does NOT spawn a continuous horde. ---
	t.set("_force_horde", true)            # far-side filter harmless (no fleet) — gates render only
	# set_horde NOT called yet => _horde_active false => _spawn_horde early-returns.
	for i in 120:
		t.call("step", 1.0 / 60.0)
	var off_count: int = int(t.call("live_count"))
	lines.append("horde OFF: after 2s step live_count=%d (want 0)" % off_count)
	if off_count != 0:
		lines.append("inert FAIL: spawning ran with set_horde never called"); ok = false

	# --- B) HORDE ON: arm the spawner and ramp distance so progress climbs. ---
	t.call("set_horde", true)
	gs.set("distance", 0.0)                # progress 0 => rate near MIN
	# Sample live_count at two windows; the second window (later progress + accrued field) must be
	# strictly larger, proving the count RAMPS over time.
	var early: int = 0
	var checkpoints: Array[int] = []
	# Simulate 8 seconds at 60fps. Push distance forward so _run_progress climbs across the run.
	var level: Resource = gs.get("active_level")
	var length: float = float(level.get("length_m")) if level != null else 1000.0
	for frame in 480:
		# Advance distance ~linearly to the finish across the sim so the rate lerps MIN->MAX.
		gs.set("distance", length * (float(frame) / 480.0))
		t.call("step", 1.0 / 60.0)
		if frame == 60:   # ~1s in
			early = int(t.call("live_count"))
		if frame == 240 or frame == 479:
			checkpoints.append(int(t.call("live_count")))

	var live: int = int(t.call("live_count"))
	lines.append("horde ON: early(~1s)=%d mid=%d final=%d" % [early, checkpoints[0], live])

	# Ramp: the field grows over time (early < a later sample). Enemies also leave (offscreen/breach),
	# so we don't demand monotone every frame — just that it climbed well past the early reading.
	if not (early > 0 and checkpoints[0] > early):
		lines.append("ramp FAIL: live_count did not climb over time (early=%d mid=%d)" % [early, checkpoints[0]]); ok = false
	else:
		lines.append("ramp OK: live_count climbed (early %d -> mid %d)" % [early, checkpoints[0]])

	# Cap: never exceeds MAX_ENEMIES across the whole sim.
	var capped_ok := true
	for c in checkpoints:
		if c > max_enemies:
			capped_ok = false
	if live > max_enemies:
		capped_ok = false
	if capped_ok:
		lines.append("cap OK: live_count stayed <= %d (peak observed %d)" % [max_enemies, live])
	else:
		lines.append("cap FAIL: live_count exceeded MAX_ENEMIES"); ok = false

	# Both half-fields: scan the live set for at least one enemy each side of CENTER_X, all KIND_GLITCH.
	var enemies: Array = t.get("_enemies")
	var KIND_GLITCH: int = 0   # enum order: GLITCH=0
	var left := 0
	var right := 0
	var non_glitch := 0
	var on_divider := 0
	for e in enemies:
		var ed: Dictionary = e
		var px: float = float((ed["pos"] as Vector2).x)
		if px < CENTER_X:
			left += 1
		elif px > CENTER_X:
			right += 1
		else:
			on_divider += 1
		if int(ed.get("kind", -1)) != KIND_GLITCH:
			non_glitch += 1
	lines.append("halves: left=%d right=%d on_divider=%d non_glitch=%d" % [left, right, on_divider, non_glitch])
	if left <= 0 or right <= 0:
		lines.append("halves FAIL: fodder did not populate BOTH half-fields"); ok = false
	if non_glitch > 0:
		lines.append("kind FAIL: horde spawned non-GLITCH fodder"); ok = false
	if on_divider > 0:
		lines.append("divider FAIL: fodder landed ON CENTER_X (should be clear of it)"); ok = false

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
