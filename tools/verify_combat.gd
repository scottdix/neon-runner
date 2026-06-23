extends SceneTree
## Headless verification for the v0.2.0 combat-depth slice (#53/#54/#14 + combo):
##   - Fleet.consume_volumes  : batched, single-pass projectile→enemy collision (#54)
##                              with an x-band cull (#14).
##   - Enemy archetypes       : Glitch / Rhombus / Fractal distinct stats (#53).
##   - Rhombus armor          : a thin stream can't crack it; enough firepower does.
##   - Fractal split          : low firepower splits it into fractlings; high kills it.
##   - Breach → Glow Battery  : an enemy reaching the ship line drains the battery (#55).
##   - Kill combo             : register_kill ramps the multiplier; a lull decays it.
##
## GPU-free: drives each system's pure logic directly and writes a verdict file the
## runner polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_combat.gd /tmp/verify_combat_result.txt

const RESULT_PATH := "/tmp/verify_combat_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# Scripts load.
	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	for pair in [["fleet", FleetS], ["targets", TargetsS]]:
		if pair[1] == null:
			lines.append("load %s = FAIL" % pair[0]); ok = false
	if FleetS == null or TargetsS == null:
		lines.append("RESULT=FAIL (combat scripts missing)"); _write(lines); return

	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if gs == null or ev == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return
	gs.call("wire_events")

	# 1) Fleet.consume_volumes — batched collision + x-band cull. Build a stream from
	#    x=540, then resolve two volumes: one ON the stream, one far in x (must cull
	#    to 0). Bullets are consumed exactly once and only by the near volume.
	var fl: Node2D = FleetS.new()
	fl.position = Vector2(540.0, 1680.0)
	fl.call("set_volume", 160)
	for i in 40:
		fl.call("step", 1.0 / 60.0)
	var before_live: int = fl.call("live_count")
	var positions := PackedVector2Array([Vector2(540.0, 1450.0), Vector2(100.0, 1450.0)])
	var radii := PackedFloat32Array([90.0, 90.0])
	var hits: PackedInt32Array = fl.call("consume_volumes", positions, radii)
	var after_live: int = fl.call("live_count")
	lines.append("consume_volumes: live %d->%d  near_hits=%d far_hits=%d" % [
		before_live, after_live, hits[0], hits[1]])
	if hits[0] <= 0:
		lines.append("batched FAIL: near volume absorbed no bullets"); ok = false
	if hits[1] != 0:
		lines.append("x-band FAIL: far volume (culled) absorbed %d bullets" % hits[1]); ok = false
	if after_live != before_live - hits[0]:
		lines.append("conservation FAIL: bullets not consumed exactly once"); ok = false
	if ok:
		lines.append("consume_volumes OK: batched single-pass + x-band cull, each bullet once")
	fl.free()

	# 2) Archetype stats are distinct (#53). Glitch is small/fragile, Rhombus is
	#    big/dense/armored, Fractal can split.
	var tg: Node2D = TargetsS.new()
	var g: Dictionary = tg.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	var r: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
	var fr: Dictionary = tg.call("_new_enemy", TargetsS.KIND_FRACTAL, 0.0)
	lines.append("archetypes: glitch hp=%.0f size=%.0f armor=%d | rhombus hp=%.0f size=%.0f armor=%d | fractal split=%s" % [
		g["hp"], g["size"], g["armor"], r["hp"], r["size"], r["armor"], fr["split"]])
	if not (g["hp"] < r["hp"] and g["size"] < r["size"] and int(r["armor"]) > 0 and bool(fr["split"])):
		lines.append("archetype FAIL: stats not distinct as designed"); ok = false
	else:
		lines.append("archetype OK: glitch<rhombus, rhombus armored, fractal splits")

	# 3) Rhombus armor — _apply_damage absorbs hits up to armor; only the excess hurts.
	#    A glitch (armor 0) takes the full hit.
	var rh: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
	var rh_hp0: float = rh["hp"]
	tg.call("_apply_damage", rh, int(rh["armor"]))          # hits == armor -> no damage
	var rh_after_armor: float = rh["hp"]
	tg.call("_apply_damage", rh, int(rh["armor"]) + 7)      # 7 effective -> -70
	var rh_after_crack: float = rh["hp"]
	var gl2: Dictionary = tg.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	var gl_hp0: float = gl2["hp"]
	tg.call("_apply_damage", gl2, 3)                        # armor 0 -> -30
	lines.append("armor: rhombus %.0f ->(thin)%.0f ->(crack)%.0f | glitch %.0f ->(3hits)%.0f" % [
		rh_hp0, rh_after_armor, rh_after_crack, gl_hp0, gl2["hp"]])
	if rh_after_armor != rh_hp0:
		lines.append("armor FAIL: thin stream cracked the rhombus"); ok = false
	if absf(rh_after_crack - (rh_hp0 - 70.0)) > 0.01:
		lines.append("armor FAIL: excess hits did not chip past armor"); ok = false
	if absf(gl2["hp"] - (gl_hp0 - 30.0)) > 0.01:
		lines.append("armor FAIL: glitch (armor 0) did not take full damage"); ok = false
	if ok:
		lines.append("armor OK: rhombus shrugs off ≤armor hits, cracks above; glitch unarmored")

	# 4) Fractal split vs clean kill, gated on swarm volume (firepower tier).
	var split_seen := [0]
	ev.connect("enemy_split", func(_at): split_seen[0] += 1)
	# Low firepower -> split into 2 fractlings, no kill, no score.
	gs.call("start_run")
	gs.call("set_projectile_count", 10)                     # < FRACTAL_SPLIT_TIER
	var tg_lo: Node2D = TargetsS.new()
	tg_lo.call("set_fleet", null)
	var en_lo: Array = tg_lo.get("_enemies")
	var dying: Dictionary = tg_lo.call("_new_enemy", TargetsS.KIND_FRACTAL, 200.0)
	dying["hp"] = 0.0
	en_lo.append(dying)
	tg_lo.call("step", 1.0 / 60.0)
	var lo_count: int = tg_lo.call("live_count")
	var lo_kinds_frac := true
	for e in tg_lo.get("_enemies"):
		if int(e["kind"]) != TargetsS.KIND_FRACTLING:
			lo_kinds_frac = false
	lines.append("fractal low-fp: enemies=%d (want 2) all_fractlings=%s kills=%d splits=%d" % [
		lo_count, lo_kinds_frac, tg_lo.get("kills"), split_seen[0]])
	if lo_count != 2 or not lo_kinds_frac or int(tg_lo.get("kills")) != 0 or split_seen[0] != 1:
		lines.append("split FAIL: low firepower did not split into 2 fractlings"); ok = false
	else:
		lines.append("split OK: insufficient firepower splits a fractal into fractlings")
	# High firepower -> clean kill (no split), scores, slot recycles.
	gs.call("start_run")
	gs.call("set_projectile_count", 120)                    # >= FRACTAL_SPLIT_TIER
	var tg_hi: Node2D = TargetsS.new()
	tg_hi.call("set_fleet", null)
	var en_hi: Array = tg_hi.get("_enemies")
	var dying2: Dictionary = tg_hi.call("_new_enemy", TargetsS.KIND_FRACTAL, 200.0)
	dying2["hp"] = 0.0
	en_hi.append(dying2)
	var score_b: int = gs.get("score")
	var splits_b: int = split_seen[0]
	tg_hi.call("step", 1.0 / 60.0)
	lines.append("fractal high-fp: enemies=%d (want 1) kills=%d score+=%d splits+=%d" % [
		tg_hi.call("live_count"), tg_hi.get("kills"), gs.get("score") - score_b, split_seen[0] - splits_b])
	if int(tg_hi.call("live_count")) != 1 or int(tg_hi.get("kills")) != 1 or gs.get("score") <= score_b or split_seen[0] != splits_b:
		lines.append("clean-kill FAIL: enough firepower should kill (not split) a fractal"); ok = false
	else:
		lines.append("clean-kill OK: enough firepower destroys a fractal outright + scores")

	# 5) Breach — an enemy crossing the ship line drains the Glow Battery + emits.
	var breach_seen := [0, 0.0]
	ev.connect("enemy_breached", func(_at, dmg): breach_seen[0] += 1; breach_seen[1] = dmg)
	gs.call("start_run")                                    # battery -> 100
	var tg_b: Node2D = TargetsS.new()
	tg_b.call("set_fleet", null)
	tg_b.call("set_breach_line", 1680.0)
	var en_b: Array = tg_b.get("_enemies")
	var crosser: Dictionary = tg_b.call("_new_enemy", TargetsS.KIND_GLITCH, 1675.0)
	crosser["pos"] = Vector2(540.0, 1675.0)
	crosser["speed"] = 600.0                                # 600/60 = 10 px -> crosses 1680
	en_b.append(crosser)
	var bat_b: float = gs.get("glow_battery")
	tg_b.call("step", 1.0 / 60.0)
	lines.append("breach: battery %.0f ->%.0f  breaches=%d  emit_dmg=%.0f (glitch breach 6)" % [
		bat_b, gs.get("glow_battery"), tg_b.get("breaches"), breach_seen[1]])
	if int(tg_b.get("breaches")) != 1 or absf(gs.get("glow_battery") - (bat_b - 6.0)) > 0.01 or breach_seen[0] != 1:
		lines.append("breach FAIL: crossing the ship line did not drain the battery / emit"); ok = false
	else:
		lines.append("breach OK: enemy at the ship line drains the Glow Battery + emits")

	# 6) Kill combo — consecutive kills ramp the multiplier; a lull (tick_run past the
	#    window with no kill) resets it to 1×.
	var combo_seen := [0, 1.0]
	ev.connect("combo_updated", func(c): combo_seen[0] = c)
	ev.connect("multiplier_changed", func(m): combo_seen[1] = m)
	gs.call("start_run")
	var p1: int = gs.call("register_kill", 100)            # combo 1, ×1.0 -> 100
	var p2: int = gs.call("register_kill", 100)            # combo 2, ×1.1 -> 110
	var p3: int = gs.call("register_kill", 100)            # combo 3, ×1.2 -> 120
	lines.append("combo ramp: pts %d/%d/%d  combo=%d mult=%.2f" % [
		p1, p2, p3, gs.get("combo"), gs.get("combo_multiplier")])
	if p1 != 100 or p2 != 110 or p3 != 120 or int(gs.get("combo")) != 3 or absf(float(gs.get("combo_multiplier")) - 1.2) > 0.001:
		lines.append("combo FAIL: multiplier did not ramp with consecutive kills"); ok = false
	gs.call("tick_run", 3.0)                                # > COMBO_WINDOW (2.5) -> decay
	lines.append("combo decay: combo=%d mult=%.2f signal_combo=%d signal_mult=%.2f" % [
		gs.get("combo"), gs.get("combo_multiplier"), combo_seen[0], combo_seen[1]])
	if int(gs.get("combo")) != 0 or absf(float(gs.get("combo_multiplier")) - 1.0) > 0.001 or combo_seen[0] != 0:
		lines.append("combo FAIL: chain did not decay after the window"); ok = false
	else:
		lines.append("combo OK: ramps on consecutive kills, decays to 1× after a lull")

	# 6b) Run-over guard (code-review fix): if a breach empties the battery and fails
	#     the run mid-step, a LATER 0-HP enemy in the same loop must NOT be counted as a
	#     phantom kill (register_kill would award nothing while kills++/enemy_destroyed
	#     fired). Order matters: index 0 breaches+fails; index 1 is already dead.
	gs.call("start_run")
	gs.call("drain_battery", 94.0)                          # battery -> 6; a glitch breach (6) empties it
	var tg_f: Node2D = TargetsS.new()
	tg_f.call("set_fleet", null)
	tg_f.call("set_breach_line", 1680.0)
	var en_f: Array = tg_f.get("_enemies")
	var breacher: Dictionary = tg_f.call("_new_enemy", TargetsS.KIND_GLITCH, 1675.0)
	breacher["pos"] = Vector2(540.0, 1675.0); breacher["speed"] = 600.0
	en_f.append(breacher)
	var already_dead: Dictionary = tg_f.call("_new_enemy", TargetsS.KIND_GLITCH, 500.0)
	already_dead["hp"] = 0.0; already_dead["pos"] = Vector2(300.0, 500.0); already_dead["speed"] = 0.0
	en_f.append(already_dead)
	tg_f.call("step", 1.0 / 60.0)
	lines.append("run-over guard: run_active=%s breaches=%d kills=%d (want active=false, kills=0)" % [
		gs.get("run_active"), tg_f.get("breaches"), tg_f.get("kills")])
	if gs.get("run_active") or int(tg_f.get("breaches")) != 1 or int(tg_f.get("kills")) != 0:
		lines.append("run-over FAIL: a kill was processed after the run ended this frame"); ok = false
	else:
		lines.append("run-over OK: no phantom kill after a battery-failing breach mid-step")

	# 7) Scale / bounded cost (#14): max enemies + an extreme swarm volume, driven for
	#    many frames. The batched collision must resolve every frame and the live
	#    bullet pool must settle to a BOUNDED steady state (fire-rate capped), not grow
	#    without limit — the property that keeps cost flat as fire volume scales.
	gs.call("start_run")
	gs.call("set_projectile_count", 2000)
	var fl_s: Node2D = FleetS.new()
	fl_s.position = Vector2(540.0, 1680.0)
	fl_s.call("set_volume", 2000)
	var tg_s: Node2D = TargetsS.new()
	tg_s.call("set_fleet", fl_s)
	tg_s.call("set_breach_line", 1680.0)
	tg_s.call("spawn", 48)
	var peak_live := 0
	for i in 600:
		fl_s.call("step", 1.0 / 60.0)
		tg_s.call("step", 1.0 / 60.0)
		peak_live = maxi(peak_live, int(fl_s.call("live_count")))
	var live_end: int = fl_s.call("live_count")
	var enemies_end: int = tg_s.call("live_count")
	var max_pool: int = FleetS.MAX_PROJECTILES
	lines.append("scale: peak_live=%d end_live=%d (pool cap %d)  enemies=%d (cap %d)  kills=%d" % [
		peak_live, live_end, max_pool, enemies_end, TargetsS.MAX_ENEMIES, tg_s.get("kills")])
	if peak_live >= max_pool:
		lines.append("scale FAIL: bullet pool hit its hard cap (unbounded growth)"); ok = false
	if peak_live >= 500:
		lines.append("scale FAIL: live bullets not bounded by fire-rate cap (peak %d)" % peak_live); ok = false
	if enemies_end > TargetsS.MAX_ENEMIES:
		lines.append("scale FAIL: enemy count exceeded its cap (splits unbounded)"); ok = false
	if int(tg_s.get("kills")) <= 0:
		lines.append("scale FAIL: dense swarm vs max enemies produced no kills"); ok = false
	if ok:
		lines.append("scale OK: batched collision holds; bullets + enemies stay bounded at scale")
	fl_s.free()
	tg_s.free()

	tg.free()
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
