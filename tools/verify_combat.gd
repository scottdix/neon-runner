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

	# 3) Rhombus armor — UPDATED to the #79 per-hit WEIGHT FLOOR model (armor is now a quality
	#    gate, not a count gate). A SPRAY-weight (1.0, sub-floor) hit only CHIPS regardless of
	#    count; a LANCE-weight (6.0, ≥floor) hit CRACKS it for full weighted damage. A glitch
	#    (armor 0) takes full weighted damage either way. The old "hits above an int armor count"
	#    crack model is superseded by RHOMBUS_PER_HIT_FLOOR (#79).
	var rh: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
	var rh_hp0: float = rh["hp"]
	tg.call("_apply_damage", rh, 3, FleetS.SPRAY_HIT_WEIGHT)  # 3 spray bullets (1.0<floor) -> chip
	var rh_after_armor: float = rh["hp"]
	var rh_chip: float = rh_hp0 - rh_after_armor             # one sub-floor frame's chip
	tg.call("_apply_damage", rh, 1, FleetS.LANCE_HIT_WEIGHT)  # 1 lance bullet (6.0≥floor) -> -60
	var rh_after_crack: float = rh["hp"]
	var gl2: Dictionary = tg.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	var gl_hp0: float = gl2["hp"]
	tg.call("_apply_damage", gl2, 3)                        # armor 0, default weight 1.0 -> -30
	lines.append("armor: rhombus %.1f ->(spray)%.1f chip=%.1f ->(lance)%.1f | glitch %.0f ->(3hits)%.0f" % [
		rh_hp0, rh_after_armor, rh_chip, rh_after_crack, gl_hp0, gl2["hp"]])
	# A sub-floor (spray) frame must be negligible: it can't be ZERO (that was the lockout
	# bug, #74) but must stay a tiny fraction of the rhombus's HP (no thin-stream crack).
	if rh_chip <= 0.0:
		lines.append("armor FAIL: sub-floor frame did NO damage (the unkillable-rhombus lockout, #74)"); ok = false
	if rh_chip > rh_hp0 * 0.02:
		lines.append("armor FAIL: a single sub-floor frame chipped too much (%.1f of %.0f)" % [rh_chip, rh_hp0]); ok = false
	# A LANCE bullet clears the floor and cracks it for full weighted damage = 1*6*10 = 60.
	if absf(rh_after_crack - (rh_after_armor - 60.0)) > 0.01:
		lines.append("armor FAIL: a lance (above-floor) bullet did not crack at full weighted damage"); ok = false
	if absf(gl2["hp"] - (gl_hp0 - 30.0)) > 0.01:
		lines.append("armor FAIL: glitch (armor 0) did not take full damage"); ok = false
	if ok:
		lines.append("armor OK: rhombus chips on sub-floor (spray) hits, cracks on lance; glitch unarmored")

	# 3b) No permanent lockout (#74): a SUSTAINED sub-floor (spray) stream, applied over many
	#     frames, must eventually bring a Rhombus to <=0 hp — the regression guard for "large
	#     magenta enemies are unkillable". (One frame is negligible (3 above); the sum over a
	#     steady stream must still win, so SPRAY teaches-not-enforces the focus-into-LANCE.)
	var rh_sus: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
	var sus_frames := 0
	var sus_cap := 6000                                     # generous bound (~100s @60fps)
	while float(rh_sus["hp"]) > 0.0 and sus_frames < sus_cap:
		tg.call("_apply_damage", rh_sus, 1, FleetS.SPRAY_HIT_WEIGHT)  # sub-floor spray every frame
		sus_frames += 1
	lines.append("sustained sub-armor: rhombus dead after %d frames (cap %d)" % [sus_frames, sus_cap])
	if float(rh_sus["hp"]) > 0.0:
		lines.append("lockout FAIL: a sustained sub-armor stream never killed the rhombus (#74 unkillable)"); ok = false
	else:
		lines.append("lockout OK: a sustained thin stream eventually kills a rhombus — no permanent lockout")

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
	lines.append("fractal high-fp: enemies=%d (want 0, removed) kills=%d score+=%d splits+=%d" % [
		tg_hi.call("live_count"), tg_hi.get("kills"), gs.get("score") - score_b, split_seen[0] - splits_b])
	if int(tg_hi.call("live_count")) != 0 or int(tg_hi.get("kills")) != 1 or gs.get("score") <= score_b or split_seen[0] != splits_b:
		lines.append("clean-kill FAIL: enough firepower should kill (not split) a fractal, then remove it"); ok = false
	else:
		lines.append("clean-kill OK: enough firepower destroys a fractal outright + scores + removes it")

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
	# Breach left disabled — pure collision-cost stress, not a gameplay sim. Top the
	# enemy set back up to MAX each frame (they're finite now: killed/offscreen are
	# removed), re-fetching _enemies since step() reassigns it to the survivor array.
	var peak_live := 0
	for i in 600:
		var en_s: Array = tg_s.get("_enemies")
		while en_s.size() < 48:
			en_s.append(tg_s.call("_new_enemy", TargetsS.KIND_GLITCH, 400.0))
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

	# 8) #54 — collision/damage HARDENING against the #79 per-hit WEIGHT model. The batched
	#    layer (consume_volumes + _apply_damage) must honor stance weight end-to-end: a real
	#    Fleet in SPRAY (light, count-only) can't crack a Rhombus, the SAME Fleet flipped to
	#    LANCE (heavy per-hit) does, SPRAY still feeds a Fractal split, and a FAT boss-sized
	#    collider is resolved by the volume math with NO per-bullet bodies. These drive the
	#    REAL Fleet (not a hand-passed weight) so the wiring in step() is exercised.
	#    OUT OF SCOPE (device-only): real-FPS-on-phone acceptance — Intel UHD 630/MoltenVK
	#    can't read true FPS here (CLAUDE.md); this asserts LOGIC/conservation, not framerate.
	lines.append("--- #54 stance-weight collision hardening ---")

	# 8a) A SPRAY stream (real Fleet, default _stance) FAILS to crack a Rhombus: many light
	#     bullets land (sub-floor weight 1.0) but only chip — the armored enemy SURVIVES a
	#     burst that would obliterate an unarmored one. Drives the full step() damage path so
	#     the hit_weight() / is_piercing() fetch + _apply_damage wiring is exercised, not faked.
	gs.call("start_run")
	gs.call("set_projectile_count", 200)                    # dense, but SPRAY = light per-hit
	var fl_sp: Node2D = FleetS.new()
	fl_sp.position = Vector2(540.0, 1680.0)
	fl_sp.call("set_volume", 200)
	fl_sp.call("set_stance", 0)                             # 0 == Stance.SPRAY (explicit)
	var tg_sp: Node2D = TargetsS.new()
	tg_sp.call("set_fleet", fl_sp)
	var en_sp: Array = tg_sp.get("_enemies")
	var rh_real: Dictionary = tg_sp.call("_new_enemy", TargetsS.KIND_RHOMBUS, 1450.0)
	rh_real["pos"] = Vector2(540.0, 1450.0)                 # parked on the stream
	rh_real["speed"] = 0.0
	var rh_real_hp0: float = rh_real["hp"]
	en_sp.append(rh_real)
	var sp_hit_frames := 0
	for i in 90:                                            # 1.5s of sustained fire
		fl_sp.call("step", 1.0 / 60.0)
		tg_sp.call("step", 1.0 / 60.0)                      # batched damage runs here (real wiring)
		if int(fl_sp.call("spark_count")) > 0:              # sparks == bullets reached the volume
			sp_hit_frames += 1
	var rh_sp_alive: bool = tg_sp.get("_enemies").size() > 0
	var rh_sp_frac: float = (float(rh_real["hp"]) / rh_real_hp0) if rh_sp_alive else 0.0
	lines.append("8a spray-vs-rhombus: hits_landed_frames=%d rhombus_alive=%s hp_frac=%.2f kills=%d" % [
		sp_hit_frames, rh_sp_alive, rh_sp_frac, tg_sp.get("kills")])
	if sp_hit_frames <= 0:
		lines.append("8a FAIL: SPRAY stream never reached the rhombus volume (collision not wired)"); ok = false
	if not rh_sp_alive or int(tg_sp.get("kills")) != 0:
		lines.append("8a FAIL: a SPRAY burst cracked a Rhombus (sub-threshold floor must absorb)"); ok = false
	fl_sp.free()
	tg_sp.free()

	# 8b) The SAME setup flipped to LANCE cracks the Rhombus: heavy per-hit weight (6.0 ≥ floor)
	#     deals full weighted damage through the batched path, killing it within a short burst.
	gs.call("start_run")
	gs.call("set_projectile_count", 200)
	var fl_ln: Node2D = FleetS.new()
	fl_ln.position = Vector2(540.0, 1680.0)
	fl_ln.call("set_volume", 200)
	fl_ln.call("set_stance", 1)                             # 1 == Stance.LANCE (heavy + pierce)
	var tg_ln: Node2D = TargetsS.new()
	tg_ln.call("set_fleet", fl_ln)
	var en_ln: Array = tg_ln.get("_enemies")
	var rh_ln: Dictionary = tg_ln.call("_new_enemy", TargetsS.KIND_RHOMBUS, 1450.0)
	rh_ln["pos"] = Vector2(540.0, 1450.0); rh_ln["speed"] = 0.0
	en_ln.append(rh_ln)
	var ln_frames := 0
	while tg_ln.get("_enemies").size() > 0 and ln_frames < 600:
		fl_ln.call("step", 1.0 / 60.0)
		tg_ln.call("step", 1.0 / 60.0)
		ln_frames += 1
	lines.append("8b lance-vs-rhombus: dead_after=%d frames (cap 600) kills=%d" % [
		ln_frames, tg_ln.get("kills")])
	if tg_ln.get("_enemies").size() > 0 or int(tg_ln.get("kills")) != 1:
		lines.append("8b FAIL: a LANCE stream failed to crack/kill a Rhombus (per-hit floor not cleared)"); ok = false
	# The LANCE crack must be MUCH faster than the SPRAY chip would be — qualitative depth check.
	if ln_frames >= 90:
		lines.append("8b FAIL: LANCE took as long as a sub-floor chip would (per-hit weight not applied)"); ok = false
	if tg_ln.get("_enemies").size() == 0 and int(tg_ln.get("kills")) == 1 and ln_frames < 90:
		lines.append("8b OK: LANCE cracks the Rhombus quickly where SPRAY (8a) could not — stance gates armor")
	fl_ln.free()
	tg_ln.free()

	# 8c) SPRAY firepower (real Fleet, sub-split-tier volume) FEEDS a Fractal split — a Fractal
	#     reaching 0 hp below FRACTAL_SPLIT_TIER splits into 2 fractlings rather than dying. This
	#     re-asserts (6) through the real stance-weight path: SPRAY's light per-hit + low volume
	#     is exactly the "insufficient firepower" case the splitter feeds on (#54 predicate kept).
	var split_seen_c := [0]
	ev.connect("enemy_split", func(_at): split_seen_c[0] += 1)
	gs.call("start_run")
	gs.call("set_projectile_count", 10)                     # < FRACTAL_SPLIT_TIER (60)
	var fl_fc: Node2D = FleetS.new()
	fl_fc.call("set_stance", 0)                             # SPRAY
	var tg_fc: Node2D = TargetsS.new()
	tg_fc.call("set_fleet", fl_fc)
	var en_fc: Array = tg_fc.get("_enemies")
	var dying_c: Dictionary = tg_fc.call("_new_enemy", TargetsS.KIND_FRACTAL, 200.0)
	dying_c["hp"] = 0.0                                      # already at 0 — step resolves the split
	en_fc.append(dying_c)
	tg_fc.call("step", 1.0 / 60.0)
	var fc_count: int = tg_fc.call("live_count")
	var fc_all_fractlings := true
	for e in tg_fc.get("_enemies"):
		if int(e["kind"]) != TargetsS.KIND_FRACTLING:
			fc_all_fractlings = false
	lines.append("8c spray-feeds-split: enemies=%d (want 2) all_fractlings=%s kills=%d splits=%d" % [
		fc_count, fc_all_fractlings, tg_fc.get("kills"), split_seen_c[0]])
	if fc_count != 2 or not fc_all_fractlings or int(tg_fc.get("kills")) != 0 or split_seen_c[0] != 1:
		lines.append("8c FAIL: SPRAY (low volume) did not feed a Fractal split into 2 fractlings"); ok = false
	else:
		lines.append("8c OK: SPRAY at sub-split-tier volume feeds a Fractal split — no clean kill")
	fl_fc.free()
	tg_fc.free()

	# 8d) FAT boss-sized collider — a single very large damage volume (boss hull) is resolved by
	#     consume_volumes with NO per-bullet bodies: bullets inside the big radius are absorbed
	#     (SPRAY) or counted (LANCE), bullets outside are untouched, and the COUNT is exact. This
	#     is the property #82/#83 (boss) leans on — one fat volume, not thousands of Area2Ds.
	var fl_boss: Node2D = FleetS.new()
	fl_boss.position = Vector2(540.0, 1680.0)
	# Off-tree under -s, _ready() (which seeds _rng = 0xF1EE7) never fires, so the stream
	# spread would be time-seeded → non-deterministic. Seed it explicitly here so the exact
	# hull/decoy membership counts are reproducible run-to-run (this was the 8d flakiness:
	# a jittered bullet occasionally landing in the hull∕decoy x-band overlap, #54).
	(fl_boss.get("_rng") as RandomNumberGenerator).seed = 0xF1EE7
	fl_boss.call("set_volume", 400)
	fl_boss.call("set_stance", 0)                           # SPRAY (consume-on-hit, exact count)
	for i in 60:
		fl_boss.call("step", 1.0 / 60.0)
	var boss_live0: int = fl_boss.call("live_count")
	# Fat hull centred on the stream (radius 360 — boss-scale) + a decoy far in x (must cull).
	# The stream is hard-bounded to x ∈ [540 - MAX_SPREAD, 540 + MAX_SPREAD] = [410, 670] (the
	# spread clamp, RNG-independent). The decoy at x=40 r=360 has x-band [-320, 400], whose right
	# edge (400) sits BELOW the stream floor (410): its boss-scale band is wide yet still clears
	# the stream entirely, so the x-band cull MUST resolve it to zero hits no matter how the
	# stream jitters. (Previously the decoy at x=60 had band right-edge 420, overlapping the
	# stream's [410, 420] sliver, so ground-truth membership flipped 0↔1 with the RNG → flaky.)
	var boss_pos := PackedVector2Array([Vector2(540.0, 1400.0), Vector2(40.0, 1400.0)])
	var boss_rad := PackedFloat32Array([360.0, 360.0])
	# Ground truth: count bullets actually inside each circle BEFORE consuming (independent check).
	var proj_snapshot: Array = fl_boss.get("_proj")
	var truth_in := 0
	var truth_far := 0
	for p in proj_snapshot:
		if (p as Vector2).distance_to(boss_pos[0]) < boss_rad[0]:
			truth_in += 1
		if (p as Vector2).distance_to(boss_pos[1]) < boss_rad[1]:
			truth_far += 1
	var boss_hits: PackedInt32Array = fl_boss.call("consume_volumes", boss_pos, boss_rad)
	var boss_live1: int = fl_boss.call("live_count")
	lines.append("8d fat-collider: live %d->%d hull_hits=%d (truth %d) far_hits=%d (truth %d)" % [
		boss_live0, boss_live1, boss_hits[0], truth_in, boss_hits[1], truth_far])
	if boss_hits[0] != truth_in:
		lines.append("8d FAIL: fat hull hit-count (%d) != bullets inside the radius (%d)" % [boss_hits[0], truth_in]); ok = false
	if boss_hits[1] != truth_far or truth_far != 0:
		lines.append("8d FAIL: far decoy volume absorbed bullets (x-band cull broke at boss scale)"); ok = false
	if boss_live1 != boss_live0 - boss_hits[0]:
		lines.append("8d FAIL: fat-collider absorption not conserved (bullets lost/double-counted)"); ok = false
	if boss_hits[0] <= 0:
		lines.append("8d FAIL: a boss-scale volume absorbed NO bullets (radius math wrong)"); ok = false
	if ok:
		lines.append("8d OK: a fat boss-sized collider is resolved by the volume math — exact, conserved, culled")
	fl_boss.free()

	# 9) #84 ph5 Tungsten — the GLOBAL armor-cracking buff (GameState.lance_hit_weight_mult). It scales
	#    ONLY the LANCE branch of Fleet.hit_weight() (weight is the sole armor-crack lever — there is no
	#    per-bullet pierce count). Two claims:
	#      (a) hit_weight() rises with the buff in LANCE; SPRAY is untouched (it's the wide light wall).
	#      (b) the heavier LANCE weight cracks/kills a Rhombus in FEWER hits than the baseline LANCE,
	#          end-to-end through _apply_damage (tungsten = "crack faster").
	lines.append("--- #84 ph5 Tungsten armor-crack buff ---")
	gs.call("start_run")                                    # resets lance_hit_weight_mult -> 1.0 (baseline)

	# 9a) hit_weight() is buff-scaled in LANCE only. Capture the baseline LANCE/SPRAY weights, raise the
	#     Tungsten mult, and re-read: LANCE must rise by exactly the mult, SPRAY must NOT move at all.
	var fl_w: Node2D = FleetS.new()
	fl_w.call("set_stance", 1)                              # 1 == Stance.LANCE
	var lance_base: float = fl_w.call("hit_weight")
	fl_w.call("set_stance", 0)                              # 0 == Stance.SPRAY
	var spray_base: float = fl_w.call("hit_weight")
	var tung_mult := 2.0
	gs.set("lance_hit_weight_mult", tung_mult)             # buff claimed (Tungsten ×2)
	fl_w.call("set_stance", 1)
	var lance_buffed: float = fl_w.call("hit_weight")
	fl_w.call("set_stance", 0)
	var spray_buffed: float = fl_w.call("hit_weight")
	lines.append("9a tungsten weight: LANCE %.2f ->%.2f (×%.1f) | SPRAY %.2f ->%.2f (unchanged)" % [
		lance_base, lance_buffed, tung_mult, spray_base, spray_buffed])
	if lance_buffed <= lance_base:
		lines.append("9a FAIL: Tungsten did not raise the LANCE hit weight"); ok = false
	if absf(lance_buffed - lance_base * tung_mult) > 0.001:
		lines.append("9a FAIL: LANCE weight did not scale by exactly the Tungsten mult"); ok = false
	if absf(spray_buffed - spray_base) > 0.001:
		lines.append("9a FAIL: Tungsten leaked into SPRAY (weight must be untouched)"); ok = false
	if ok:
		lines.append("9a OK: Tungsten lifts LANCE hit weight by its mult; SPRAY (light wall) unaffected")
	fl_w.free()

	# 9b) A buffed LANCE cracks a Rhombus in FEWER hits than the baseline LANCE — the tungsten "crack
	#     faster" payoff, driven through the real _apply_damage path. Count single-bullet LANCE hits to
	#     kill at baseline (mult 1.0), then with the buff (mult >1); the buffed count must be strictly
	#     smaller. Both clear RHOMBUS_PER_HIT_FLOOR, so both crack — the buff only deepens each crack.
	gs.set("lance_hit_weight_mult", 1.0)                   # baseline LANCE (no buff)
	var rh_base: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
	var base_hits := 0
	var base_cap := 1000
	while float(rh_base["hp"]) > 0.0 and base_hits < base_cap:
		tg.call("_apply_damage", rh_base, 1, FleetS.LANCE_HIT_WEIGHT)
		base_hits += 1
	gs.set("lance_hit_weight_mult", tung_mult)             # Tungsten ×2 — the heavier crack
	var rh_buff: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
	var buff_weight: float = FleetS.LANCE_HIT_WEIGHT * tung_mult  # what Fleet.hit_weight() would feed
	var buff_hits := 0
	while float(rh_buff["hp"]) > 0.0 and buff_hits < base_cap:
		tg.call("_apply_damage", rh_buff, 1, buff_weight)
		buff_hits += 1
	gs.set("lance_hit_weight_mult", 1.0)                   # restore neutral for any later check
	lines.append("9b tungsten crack-speed: baseline LANCE kills rhombus in %d hits, buffed (×%.1f) in %d" % [
		base_hits, tung_mult, buff_hits])
	if base_hits >= base_cap or buff_hits >= base_cap:
		lines.append("9b FAIL: a LANCE stream failed to crack the rhombus at all (floor not cleared)"); ok = false
	if buff_hits >= base_hits:
		lines.append("9b FAIL: Tungsten did not crack the rhombus FASTER than the baseline LANCE"); ok = false
	if ok:
		lines.append("9b OK: Tungsten cracks/kills a Rhombus in fewer LANCE hits — armor-crack buff lands")

	# 9c) #84 ph6 Efficiency must NOT remove LANCE's ability to crack armor. Efficiency sets
	#     burst_damage_mult = 0.75, which would drop the LANCE per-hit DAMAGE weight to 6.0*0.75 = 4.5,
	#     BELOW RHOMBUS_PER_HIT_FLOOR (5.0). The fix decouples crack-eligibility (Fleet.crack_weight(),
	#     Tungsten-aware but Efficiency-free) from damage-dealt (hit_weight()). This drives the real
	#     batched path (Fleet.step + Targets.step) with Efficiency claimed and asserts a LANCE still
	#     kills the Rhombus — the regression the old 9b (mult 2.0 only) never exercised.
	lines.append("--- #84 ph6 Efficiency must not strip LANCE armor-crack ---")
	gs.call("start_run")                                    # resets buff mults to neutral
	gs.call("_fx_efficiency", {"drain_mult": 0.6, "burst_mult": 0.75})  # Efficiency claimed
	var eff_crack: float = 0.0
	gs.call("set_projectile_count", 200)
	var fl_eff: Node2D = FleetS.new()
	fl_eff.position = Vector2(540.0, 1680.0)
	fl_eff.call("set_volume", 200)
	fl_eff.call("set_stance", 1)                            # 1 == Stance.LANCE
	eff_crack = float(fl_eff.call("crack_weight"))          # must stay >= the floor despite Efficiency
	var eff_dmg: float = float(fl_eff.call("hit_weight"))   # damage-dealt IS lowered by Efficiency
	var tg_eff: Node2D = TargetsS.new()
	tg_eff.call("set_fleet", fl_eff)
	var rh_eff: Dictionary = tg_eff.call("_new_enemy", TargetsS.KIND_RHOMBUS, 1450.0)
	rh_eff["pos"] = Vector2(540.0, 1450.0); rh_eff["speed"] = 0.0
	tg_eff.get("_enemies").append(rh_eff)
	var eff_frames := 0
	while tg_eff.get("_enemies").size() > 0 and eff_frames < 1200:
		fl_eff.call("step", 1.0 / 60.0)
		tg_eff.call("step", 1.0 / 60.0)
		eff_frames += 1
	lines.append("9c efficiency: crack_weight=%.2f (floor %.2f) hit_weight=%.2f dead_after=%d frames kills=%d" % [
		eff_crack, TargetsS.RHOMBUS_PER_HIT_FLOOR, eff_dmg, eff_frames, tg_eff.get("kills")])
	if eff_crack < TargetsS.RHOMBUS_PER_HIT_FLOOR:
		lines.append("9c FAIL: Efficiency dropped LANCE crack_weight below the Rhombus floor"); ok = false
	if eff_dmg >= FleetS.LANCE_HIT_WEIGHT:
		lines.append("9c FAIL: Efficiency did not lower the LANCE damage weight (burst tradeoff missing)"); ok = false
	if tg_eff.get("_enemies").size() > 0 or int(tg_eff.get("kills")) != 1:
		lines.append("9c FAIL: an Efficiency-buffed LANCE could not crack/kill a Rhombus"); ok = false
	if ok:
		lines.append("9c OK: Efficiency lowers LANCE damage but LANCE still cracks Rhombus armor")
	gs.call("_reset_phase_buffs")                           # restore neutral
	fl_eff.free()
	tg_eff.free()

	tg.free()
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
