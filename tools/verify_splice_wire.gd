extends SceneTree
## Headless verification for HORDE P3 — WIRE THE DEBUG KNOBS (behind NEUTRAL defaults).
##
## Proves every Debug dial is wired into the FODDER path (never the boss path) + the breach cost +
## the token drop, AND that the NEUTRAL defaults are byte-identical to today:
##   1) Neutral Debug: fodder ramp/count over N frames == the analytic baseline (rate unchanged), and
##      a fodder enemy's speed/hp == a baseline enemy's (multipliers are 1.0 no-ops).
##   2) Enemies:Off → _spawn_horde produces ZERO fodder, BUT _spawn_laneboss still spawns a boss at
##      FULL hp/speed (the boss path is intentionally never gated by enemies_on).
##   3) Density high → the fodder rate scales up (faster ramp), and the live set is capped at enemy_cap
##      (the soft cap supersedes MAX_ENEMIES so the designer can exceed 128/256).
##   4) Speed/Strength scale a FODDER enemy's speed/hp, but a LANE-BOSS spawned via _spawn_laneboss is
##      UNAFFECTED (full STATS speed/hp).
##   5) firepower_loss_mult scales the breach cost on GameState (round; 0.0 → no firepower lost).
##   6) Tokens:Off → a token-drop produces NO live token (the layer early-returns).
##
## GPU-free: drives the pure spawn/step helpers on a BARE Targets/TokenLayer, flips the LIVE Debug
## autoload's fields, reads GameState through root, writes a verdict file (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_splice_wire.gd /tmp/verify_splice_wire_result.txt

const RESULT_PATH := "/tmp/verify_splice_wire_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var TokenS: GDScript = load("res://assets/economy/token_layer.gd")
	if TargetsS == null or TokenS == null:
		lines.append("RESULT=FAIL (targets/token_layer scripts missing)"); _write(lines); return

	var dbg: Node = root.get_node_or_null("Debug")
	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if dbg == null or gs == null or ev == null:
		lines.append("RESULT=FAIL (Debug/GameState/Events autoload missing)"); _write(lines); return

	# Reset every Debug field to its NEUTRAL default up front (a stale user://debug.cfg must not skew
	# the byte-identical baseline). Set the fields DIRECTLY (setters would persist; we only want live).
	_reset_debug(dbg)

	# KIND enum (bare in targets.gd): GLITCH=0, ..., LANEBOSS=4.
	var KIND_GLITCH := 0
	var KIND_LANEBOSS := 4
	# STATS sanity for the boss (full-strength reference).
	var BOSS_HP := 600.0          # STATS[KIND_LANEBOSS].hp
	var BOSS_SPD_MIN := 90.0      # STATS[KIND_LANEBOSS].spd[0]
	var BOSS_SPD_MAX := 110.0

	# A run must be "active" for _spawn_horde/_step_laneboss to advance.
	gs.set("run_active", true)
	gs.set("active_level", null)   # _run_progress → 0.0 → rate pinned at HORDE_RATE_MIN (p=0 baseline)

	# ---- 1) NEUTRAL: fodder ramp/count byte-identical to baseline -------------------------------
	# Drive _spawn_horde for N frames at a fixed delta; with neutral Debug the rate is HORDE_RATE_MIN
	# (p=0), so the count == floor(MIN * total_time). Compare against the analytic expectation.
	var dt := 1.0 / 60.0
	var frames := 120
	var tg_a: Node2D = TargetsS.new()
	tg_a.set("_rng", _seeded_rng(0xDA77))
	tg_a.call("set_force_horde", true)
	tg_a.call("set_horde", true)
	for i in frames:
		tg_a.call("_spawn_horde", dt)
	var count_neutral: int = (tg_a.get("_enemies") as Array).size()
	# Baseline = the SAME per-frame accumulator simulated WITHOUT the Debug hooks (rate pinned at
	# HORDE_RATE_MIN since p=0). Mirror the exact float accumulation so we compare like-for-like (a
	# closed-form floor() drifts vs the repeated-add accumulator). This is the true "today" behaviour.
	var rate_min := 2.0           # HORDE_RATE_MIN at p=0
	var baseline := 0
	var accum := 0.0
	for i in frames:
		accum += rate_min * dt
		while accum >= 1.0:
			accum -= 1.0
			baseline += 1
	lines.append("1 neutral: fodder=%d baseline=%d (rate=MIN p=0, all mults 1.0)" % [count_neutral, baseline])
	if count_neutral != baseline:
		lines.append("FAIL: neutral fodder count drifted from the baseline accumulator"); ok = false
	# A neutral fodder enemy must carry the RAW un-multiplied STATS: hp == GLITCH hp (40), speed in the
	# GLITCH spd band [220,320] (mults are 1.0 → no scaling applied).
	var GLITCH_HP := 40.0
	var GLITCH_SPD_MIN := 220.0
	var GLITCH_SPD_MAX := 320.0
	var tg_neu: Node2D = TargetsS.new()
	tg_neu.set("_rng", _seeded_rng(0xBEEF))
	tg_neu.call("set_force_horde", true)
	var neu_e: Dictionary = tg_neu.call("_new_horde_fodder")
	lines.append("1 neutral-enemy: hp=%.4f (want %.0f) speed=%.4f (want %.0f-%.0f)" % [
		float(neu_e["hp"]), GLITCH_HP, float(neu_e["speed"]), GLITCH_SPD_MIN, GLITCH_SPD_MAX])
	if not is_equal_approx(float(neu_e["hp"]), GLITCH_HP) \
			or not is_equal_approx(float(neu_e["max_hp"]), GLITCH_HP):
		lines.append("FAIL: a neutral fodder enemy's hp/max_hp drifted from raw STATS (mults not 1.0?)"); ok = false
	if float(neu_e["speed"]) < GLITCH_SPD_MIN - 0.01 or float(neu_e["speed"]) > GLITCH_SPD_MAX + 0.01:
		lines.append("FAIL: a neutral fodder enemy's speed left the raw STATS band (speed_mult not 1.0?)"); ok = false
	if ok:
		lines.append("1 OK: neutral Debug is byte-identical to today (count + raw-STATS per-enemy values)")
	tg_neu.free()

	# ---- 2) Enemies:Off → fodder=0 BUT a lane-boss still spawns at FULL hp/speed ----------------
	dbg.set("enemies_enabled", false)
	var tg_off: Node2D = TargetsS.new()
	tg_off.set("_rng", _seeded_rng(0xDA77))
	tg_off.call("set_force_horde", true)
	tg_off.call("set_horde", true)
	for i in frames:
		tg_off.call("_spawn_horde", dt)
	var fodder_off: int = (tg_off.get("_enemies") as Array).size()
	# The boss path is NOT gated by enemies_on — spawn one directly.
	tg_off.call("_spawn_laneboss")
	var after_boss: Array = tg_off.get("_enemies")
	var boss: Dictionary = after_boss[after_boss.size() - 1] if not after_boss.is_empty() else {}
	var boss_kind: int = int(boss.get("kind", -1))
	var boss_hp: float = float(boss.get("hp", -1.0))
	var boss_spd: float = float(boss.get("speed", -1.0))
	lines.append("2 enemies-off: fodder=%d boss_kind=%d boss_hp=%.1f boss_spd=%.1f" % [
		fodder_off, boss_kind, boss_hp, boss_spd])
	if fodder_off != 0:
		lines.append("FAIL: Enemies:Off did not suppress the fodder spawner"); ok = false
	if boss_kind != KIND_LANEBOSS or not is_equal_approx(boss_hp, BOSS_HP) \
			or boss_spd < BOSS_SPD_MIN - 0.01 or boss_spd > BOSS_SPD_MAX + 0.01:
		lines.append("FAIL: lane-boss missing or not at full STATS hp/speed while Enemies:Off"); ok = false
	if ok:
		lines.append("2 OK: Enemies:Off kills fodder only — a full-strength lane-boss still arrives")
	dbg.set("enemies_enabled", true)
	tg_off.free()

	# ---- 3) Density high → faster ramp, capped at enemy_cap -------------------------------------
	dbg.set("enemy_density_mult", 3.0)
	var tg_dense: Node2D = TargetsS.new()
	tg_dense.set("_rng", _seeded_rng(0xDA77))
	tg_dense.call("set_force_horde", true)
	tg_dense.call("set_horde", true)
	for i in frames:
		tg_dense.call("_spawn_horde", dt)
	var count_dense: int = (tg_dense.get("_enemies") as Array).size()
	lines.append("3 density×3: fodder=%d (neutral was %d) — must be denser" % [count_dense, count_neutral])
	if count_dense <= count_neutral:
		lines.append("FAIL: density multiplier did not increase the fodder ramp"); ok = false
	tg_dense.free()
	# Soft cap: enormous density but a tiny enemy_cap → the live set is held at enemy_cap.
	dbg.set("enemy_density_mult", 50.0)
	dbg.set("enemy_cap", 12)
	var tg_cap: Node2D = TargetsS.new()
	tg_cap.set("_rng", _seeded_rng(0xDA77))
	tg_cap.call("set_force_horde", true)
	tg_cap.call("set_horde", true)
	for i in frames:
		tg_cap.call("_spawn_horde", dt)
	var count_cap: int = (tg_cap.get("_enemies") as Array).size()
	lines.append("3 soft-cap: fodder=%d with enemy_cap=12 (density×50)" % count_cap)
	if count_cap != 12:
		lines.append("FAIL: the soft enemy_cap did not bound the live fodder set"); ok = false
	if ok:
		lines.append("3 OK: density scales the ramp; enemy_cap is the live soft ceiling")
	tg_cap.free()
	_reset_debug(dbg)

	# ---- 4) Speed/Strength scale a FODDER enemy but NOT the lane-boss ---------------------------
	dbg.set("enemy_speed_mult", 2.0)
	dbg.set("enemy_strength_mult", 4.0)
	var tg_sc: Node2D = TargetsS.new()
	tg_sc.set("_rng", _seeded_rng(0xBEEF))
	tg_sc.call("set_force_horde", true)
	var scaled_e: Dictionary = tg_sc.call("_new_horde_fodder")
	# Same-seed neutral reference for the SAME enemy.
	_reset_debug(dbg)
	var tg_base: Node2D = TargetsS.new()
	tg_base.set("_rng", _seeded_rng(0xBEEF))
	tg_base.call("set_force_horde", true)
	var base_e: Dictionary = tg_base.call("_new_horde_fodder")
	lines.append("4 fodder scale: speed %.3f→%.3f (×2) hp %.3f→%.3f (×4)" % [
		float(base_e["speed"]), float(scaled_e["speed"]), float(base_e["hp"]), float(scaled_e["hp"])])
	if not is_equal_approx(float(scaled_e["speed"]), float(base_e["speed"]) * 2.0):
		lines.append("FAIL: speed_mult did not scale a fodder enemy's speed"); ok = false
	if not is_equal_approx(float(scaled_e["hp"]), float(base_e["hp"]) * 4.0) \
			or not is_equal_approx(float(scaled_e["max_hp"]), float(base_e["max_hp"]) * 4.0):
		lines.append("FAIL: strength_mult did not scale a fodder enemy's hp/max_hp"); ok = false
	# Now prove the BOSS path ignores those mults: re-enable big mults, spawn a boss, assert full STATS.
	dbg.set("enemy_speed_mult", 2.0)
	dbg.set("enemy_strength_mult", 4.0)
	var tg_bsc: Node2D = TargetsS.new()
	tg_bsc.set("_rng", _seeded_rng(0xDA77))
	tg_bsc.call("set_force_horde", true)
	tg_bsc.call("set_horde", true)
	tg_bsc.call("_spawn_laneboss")
	var bl: Array = tg_bsc.get("_enemies")
	var bz: Dictionary = bl[bl.size() - 1] if not bl.is_empty() else {}
	lines.append("4 boss-unscaled: hp=%.1f (want %.1f) spd=%.1f (want %.0f-%.0f)" % [
		float(bz.get("hp", -1.0)), BOSS_HP, float(bz.get("speed", -1.0)), BOSS_SPD_MIN, BOSS_SPD_MAX])
	if not is_equal_approx(float(bz.get("hp", -1.0)), BOSS_HP) \
			or float(bz.get("speed", -1.0)) < BOSS_SPD_MIN - 0.01 \
			or float(bz.get("speed", -1.0)) > BOSS_SPD_MAX + 0.01:
		lines.append("FAIL: a lane-boss was scaled by the FODDER speed/strength mults (must be exempt)"); ok = false
	if ok:
		lines.append("4 OK: speed/strength scale fodder only — the lane-boss stays full STATS")
	tg_sc.free(); tg_base.free(); tg_bsc.free()
	_reset_debug(dbg)

	# ---- 5) firepower_loss_mult scales the breach cost (0 → no loss) ----------------------------
	# A GLITCH fodder breach drains `streams`=1. Set firepower budget, breach, read the delta.
	var tg_br: Node2D = TargetsS.new()
	tg_br.call("set_force_horde", true)
	# loss × 1.0 (neutral): 1 stream drained.
	gs.set("run_active", true)
	gs.call("set_projectile_count", 100)
	tg_br.call("_breach", {"pos": Vector2(540, 1680), "streams": 1})
	var after_neutral: int = int(gs.get("projectile_count"))
	# loss × 3.0: a 1-stream breach drains 3.
	dbg.set("firepower_loss_mult", 3.0)
	gs.call("set_projectile_count", 100)
	tg_br.call("_breach", {"pos": Vector2(540, 1680), "streams": 1})
	var after_x3: int = int(gs.get("projectile_count"))
	# loss × 0.0: NO firepower lost.
	dbg.set("firepower_loss_mult", 0.0)
	gs.call("set_projectile_count", 100)
	tg_br.call("_breach", {"pos": Vector2(540, 1680), "streams": 1})
	var after_zero: int = int(gs.get("projectile_count"))
	lines.append("5 breach cost: neutral 100→%d (−1) ×3 100→%d (−3) ×0 100→%d (−0)" % [
		after_neutral, after_x3, after_zero])
	if after_neutral != 99:
		lines.append("FAIL: neutral breach did not drain exactly 1 stream"); ok = false
	if after_x3 != 97:
		lines.append("FAIL: firepower_loss_mult×3 did not triple the breach cost"); ok = false
	if after_zero != 100:
		lines.append("FAIL: firepower_loss_mult=0 still drained firepower (should be no loss)"); ok = false
	if ok:
		lines.append("5 OK: firepower_loss_mult scales the breach cost; 0 = no loss")
	tg_br.free()
	_reset_debug(dbg)

	# ---- 6) Tokens:Off → a token-drop produces NO live token -----------------------------------
	var tl: Node2D = TokenS.new()
	root.add_child(tl)
	await process_frame                          # _ready (wire_events) is deferred under -s
	# Neutral (Tokens ON): a drop spawns a live token.
	ev.emit_signal("token_dropped", Vector2(300, 200), 5)
	var live_on: int = int(tl.call("live_count"))
	# Tokens OFF: a drop is suppressed.
	dbg.set("tokens_enabled", false)
	ev.emit_signal("token_dropped", Vector2(300, 200), 5)
	var live_off: int = int(tl.call("live_count"))
	lines.append("6 tokens: ON→live=%d (drop banked), OFF→live=%d (no new drop)" % [live_on, live_off])
	if live_on < 1:
		lines.append("FAIL: a neutral (Tokens ON) drop produced no live token"); ok = false
	if live_off != live_on:
		lines.append("FAIL: Tokens:Off still spawned a token"); ok = false
	if ok:
		lines.append("6 OK: Tokens:Off suppresses the drop (neutral default still drops)")
	dbg.set("tokens_enabled", true)
	tl.free()

	gs.set("run_active", false)
	tg_a.free()
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## A fresh deterministic RNG (the bare Targets has no _ready to seed _rng).
func _seeded_rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## Force every live Debug field back to its NEUTRAL default (direct set — no persistence side-effect).
func _reset_debug(dbg: Node) -> void:
	dbg.set("tokens_enabled", true)
	dbg.set("enemies_enabled", true)
	dbg.set("gates_enabled", true)
	dbg.set("enemy_density_mult", 1.0)
	dbg.set("enemy_speed_mult", 1.0)
	dbg.set("enemy_strength_mult", 1.0)
	dbg.set("firepower_loss_mult", 1.0)
	dbg.set("enemy_cap", 256)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
