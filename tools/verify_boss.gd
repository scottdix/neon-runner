extends SceneTree
## Headless verification for the boss framework (#82) + the Singularity (#83):
##   - Phase ladder      : TELEGRAPH -> ARMORED -> ADD_SWARM -> DEFEATED in ORDER, each
##                         boss_phase_changed emitted EXACTLY ONCE, on the right HP/time thresholds.
##   - Telegraph invuln  : the wind-up phase takes NO damage (a warn-up grace window).
##   - Armored per-hit floor : a SPRAY-weight (sub-floor) bullet only CHIPS the hull; a LANCE-weight
##                         (above-floor) bullet CRACKS it for full damage (reuses Rhombus #79 semantics).
##   - ADD_SWARM adds    : entering the open phase QUEUES adds for run.gd to hand to Targets.
##   - Fat-hull collision: a real Fleet's bullets inside the hull volume damage the boss via the
##                         single consume_volumes path (no per-bullet bodies, #54.8d).
##   - boss_defeated once : fires EXACTLY ONCE when HP hits 0 (the run's WIN terminal).
##   - Singularity gravity: the field INVERTS the economy — a projectile on a + gate is deflected OFF
##                         it (toward the core), and the ship is pulled TOWARD a − gate (toward the core).
##
## GPU-free: drives each system's pure logic on bare instances + writes a verdict file the runner
## polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_boss.gd /tmp/verify_boss_result.txt

const RESULT_PATH := "/tmp/verify_boss_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# Scripts load.
	var BossS: GDScript = load("res://assets/bosses/boss.gd")
	var SingS: GDScript = load("res://assets/bosses/singularity.gd")
	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	if BossS == null or SingS == null or FleetS == null:
		lines.append("RESULT=FAIL (boss/singularity/fleet scripts missing)"); _write(lines); return

	var ev: Node = root.get_node_or_null("Events")
	var gs: Node = root.get_node_or_null("GameState")
	if ev == null or gs == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return
	# HORDE is now force-locked, which disables the gate->stance coupling (the boss-arena stance
	# gates in section 6 only flip stance under the LEGACY POC). This verify exercises that parked
	# LEGACY stance-gate behaviour, so set the global Settings.poc_mode to LEGACY (0) for the test.
	# Set the field directly (NOT set_poc_mode, which persists) so production's Settings read sees LEGACY.
	var settings: Node = root.get_node_or_null("Settings")
	if settings:
		settings.set("poc_mode", 0)   # 0 = PocMode.LEGACY
	# GameState.Stance enum values (SPRAY=0, LANCE=1 by contract) — bare `GameState` doesn't compile
	# in the -s main tool script (use the literals, mirroring verify_stance.gd).
	var GS_SPRAY := 0
	var GS_LANCE := 1
	# GameState.wire_events() connects gate_passed -> _on_gate_passed (under -s autoload _ready is
	# deferred, so the gate-driven stance flip wouldn't fire without this). Idempotent.
	gs.call("wire_events")

	# ---- 1) Phase ladder + emit-once, driven by HP/time thresholds --------------
	# Listen to boss_phase_changed; record the ORDER + a count per phase so we can assert each
	# transition fires exactly once and in sequence.
	var phase_log: Array = []
	ev.connect("boss_phase_changed", func(p, _name): phase_log.append(p))
	var defeated_log: Array = []
	ev.connect("boss_defeated", func(name, at): defeated_log.append({"name": name, "at": at}))
	var spawned_log: Array = []
	ev.connect("boss_spawned", func(name, mhp): spawned_log.append({"name": name, "max_hp": mhp}))

	var boss: Node2D = BossS.new()
	boss.position = Vector2(540.0, 700.0)
	boss.set("boss_name", "TESTBOSS")
	boss.set("max_hp", 1000.0)
	boss.call("arm")
	# arm() emits boss_spawned + the initial TELEGRAPH phase.
	lines.append("arm: spawned=%d phase_log=%s phase=%d (want TELEGRAPH=0)" % [
		spawned_log.size(), str(phase_log), boss.call("current_phase")])
	if spawned_log.size() != 1 or float(spawned_log[0]["max_hp"]) != 1000.0:
		lines.append("FAIL: boss_spawned not emitted once with max_hp"); ok = false
	if phase_log != [BossS.PHASE_TELEGRAPH] or int(boss.call("current_phase")) != BossS.PHASE_TELEGRAPH:
		lines.append("FAIL: boss did not start in TELEGRAPH"); ok = false
	# arm() is idempotent — a second call must NOT re-emit.
	boss.call("arm")
	if spawned_log.size() != 1:
		lines.append("FAIL: arm() re-emitted boss_spawned (not idempotent)"); ok = false

	# 1a) TELEGRAPH is invulnerable: applying hits during the wind-up does NOTHING to HP.
	var hp_before_tele: float = boss.get("hp")
	boss.call("_apply_hits", 50, FleetS.LANCE_HIT_WEIGHT)   # heavy fire mid-telegraph
	if absf(float(boss.get("hp")) - hp_before_tele) > 0.001:
		lines.append("FAIL: boss took damage during the invulnerable TELEGRAPH wind-up"); ok = false
	else:
		lines.append("telegraph-invuln OK: no damage taken during the wind-up")

	# 1b) Telegraph timer elapses -> ARMORED (and ONLY one ARMORED transition).
	boss.call("step", BossS.TELEGRAPH_TIME + 0.1)
	lines.append("after telegraph: phase_log=%s phase=%d (want +ARMORED=1)" % [
		str(phase_log), boss.call("current_phase")])
	if int(boss.call("current_phase")) != BossS.PHASE_ARMORED:
		lines.append("FAIL: telegraph timer did not advance to ARMORED"); ok = false

	# 1c) ARMORED per-hit FLOOR: a SPRAY-weight (sub-floor 1.0) hit only CHIPS; a LANCE-weight
	#     (above-floor 6.0) hit deals full count*weight damage. (Reuses Rhombus #79 semantics.)
	var hp_arm0: float = boss.get("hp")
	boss.call("_apply_hits", 10, FleetS.SPRAY_HIT_WEIGHT)   # 10 light bullets — sub-floor, chip only
	var chip: float = hp_arm0 - float(boss.get("hp"))
	var hp_arm1: float = boss.get("hp")
	boss.call("_apply_hits", 5, FleetS.LANCE_HIT_WEIGHT)    # 5 heavy bullets — crack: 5*6*10 = 300
	var crack: float = hp_arm1 - float(boss.get("hp"))
	lines.append("armored: chip(10 spray)=%.2f  crack(5 lance)=%.1f (want crack=300)" % [chip, crack])
	if chip <= 0.0:
		lines.append("FAIL: a sub-floor SPRAY frame did NO damage to the armored hull (#74 lockout)"); ok = false
	if chip > float(boss.get("max_hp")) * 0.02:
		lines.append("FAIL: a single sub-floor SPRAY frame chipped too much (armor floor not enforced)"); ok = false
	if absf(crack - 300.0) > 0.01:
		lines.append("FAIL: a LANCE (above-floor) hit did not crack the hull for full weighted damage"); ok = false
	if ok:
		lines.append("armored-floor OK: SPRAY chips, LANCE cracks — the boss FORCES a LANCE")

	# 1d) Drive HP down past ADD_SWARM_HP_FRAC with LANCE crack hits -> ADD_SWARM (open phase),
	#     which must QUEUE adds for Targets, and fire boss_phase_changed for ADD_SWARM ONCE.
	var armored_count_before := 0
	for p in phase_log:
		if int(p) == BossS.PHASE_ADD_SWARM:
			armored_count_before += 1
	var guard := 0
	while int(boss.call("current_phase")) == BossS.PHASE_ARMORED and guard < 2000:
		boss.call("_apply_hits", 4, FleetS.LANCE_HIT_WEIGHT)   # crack damage
		boss.call("step", 1.0 / 60.0)
		guard += 1
	lines.append("to add_swarm: phase=%d pending_adds=%d phase_log=%s" % [
		boss.call("current_phase"), boss.call("pending_add_count"), str(phase_log)])
	if int(boss.call("current_phase")) != BossS.PHASE_ADD_SWARM:
		lines.append("FAIL: HP below the threshold did not open the ADD_SWARM phase"); ok = false
	if int(boss.call("pending_add_count")) <= 0:
		lines.append("FAIL: ADD_SWARM did not queue any adds for Targets"); ok = false
	# drain the queue (run.gd does this) and confirm the shape.
	var adds: Array = boss.call("take_pending_adds")
	if adds.is_empty() or not adds[0].has("kind") or not adds[0].has("x"):
		lines.append("FAIL: queued adds are not {kind,x} dicts for Targets"); ok = false
	if int(boss.call("pending_add_count")) != 0:
		lines.append("FAIL: take_pending_adds did not clear the queue"); ok = false
	else:
		lines.append("add_swarm OK: opens, queues {kind,x} adds, drains cleanly")
	# ADD_SWARM drips MORE adds over time.
	boss.call("step", BossS.ADD_SPAWN_INTERVAL + 0.01)
	if int(boss.call("pending_add_count")) <= 0:
		lines.append("FAIL: ADD_SWARM did not drip a second add wave over time"); ok = false

	# 1e) HP to 0 -> DEFEATED, boss_defeated fires EXACTLY ONCE. Phase order overall is
	#     TELEGRAPH, ARMORED, ADD_SWARM, DEFEATED with no phase repeated.
	boss.call("_apply_hits", 100000, FleetS.LANCE_HIT_WEIGHT)   # overkill -> 0
	boss.call("step", 1.0 / 60.0)
	# Step a few more frames — boss_defeated must NOT fire again.
	for i in 5:
		boss.call("step", 1.0 / 60.0)
	lines.append("defeat: phase=%d defeated_emits=%d phase_log=%s" % [
		boss.call("current_phase"), defeated_log.size(), str(phase_log)])
	if int(boss.call("current_phase")) != BossS.PHASE_DEFEATED:
		lines.append("FAIL: HP<=0 did not reach DEFEATED"); ok = false
	if defeated_log.size() != 1:
		lines.append("FAIL: boss_defeated fired %d times (want exactly 1)" % defeated_log.size()); ok = false
	# Assert the full ordered ladder, each phase exactly once.
	var want_order: Array = [BossS.PHASE_TELEGRAPH, BossS.PHASE_ARMORED, BossS.PHASE_ADD_SWARM, BossS.PHASE_DEFEATED]
	if phase_log != want_order:
		lines.append("FAIL: phase order %s != %s (each once, in sequence)" % [str(phase_log), str(want_order)]); ok = false
	else:
		lines.append("phase-ladder OK: TELEGRAPH->ARMORED->ADD_SWARM->DEFEATED, each once, defeated once")
	boss.free()

	# ---- 2) Fat-hull collision via a REAL Fleet (consume_volumes, no per-bullet bodies) --------
	# A real SPRAY Fleet firing into the boss's hull volume must damage it through _absorb_hits ->
	# consume_volumes (one fat circle), with bullets consumed. Drive past TELEGRAPH first (invuln).
	var boss2: Node2D = BossS.new()
	boss2.position = Vector2(540.0, 700.0)
	boss2.set("max_hp", 5000.0); boss2.set("hp", 5000.0)
	boss2.call("arm")
	boss2.call("step", BossS.TELEGRAPH_TIME + 0.1)             # -> ARMORED
	var fl: Node2D = FleetS.new()
	fl.position = Vector2(540.0, 1680.0)
	(fl.get("_rng") as RandomNumberGenerator).seed = 0xB055     # deterministic stream off-tree
	fl.call("set_volume", 300)
	fl.call("set_stance", 1)                                    # LANCE so the armored hull actually takes damage
	boss2.call("set_fleet", fl)
	# Build a stream, then march bullets up to the boss's y so some sit inside the 360px hull.
	for i in 50:
		fl.call("step", 1.0 / 60.0)
	var hp_pre: float = boss2.get("hp")
	var absorbed_any := false
	for i in 120:                                              # ~2s — bullets reach the hull band
		fl.call("step", 1.0 / 60.0)
		boss2.call("step", 1.0 / 60.0)
		if float(boss2.get("hp")) < hp_pre:
			absorbed_any = true
	lines.append("fat-hull: hp %.0f->%.0f via consume_volumes (LANCE) absorbed_any=%s" % [
		hp_pre, boss2.get("hp"), absorbed_any])
	if not absorbed_any or float(boss2.get("hp")) >= hp_pre:
		lines.append("FAIL: real Fleet fire never damaged the boss via the fat-hull volume"); ok = false
	else:
		lines.append("fat-hull OK: bullets inside the single hull volume damage the boss (no per-bullet bodies)")
	fl.free()
	boss2.free()

	# ---- 3) Singularity gravity field: INVERTS the economy (pure math) --------------------------
	# The vortex core sits at the boss position. (a) A projectile sitting ON a positive (+/×) gate is
	# dragged OFF it toward the core; (b) the ship is pulled TOWARD a negative (−/÷) gate when the core
	# sits over that gate. Both checked via the pure helpers (no GPU). Bare Singularity: _init seeds
	# HP/name; we set position + force a non-zero pulse so the field is active deterministically.
	var sing: Node2D = SingS.new()
	# Vortex core sits high-centre over the playfield.
	sing.position = Vector2(540.0, 600.0)
	sing.set("_pulse", 1.0)                                    # force full pulse (off-tree, no _step_mechanic ran)
	lines.append("singularity: name=%s max_hp=%.0f field_radius=%.0f" % [
		sing.get("boss_name"), sing.get("max_hp"), SingS.FIELD_RADIUS])
	if String(sing.get("boss_name")) != SingS.BOSS_NAME or float(sing.get("max_hp")) != SingS.SING_MAX_HP:
		lines.append("FAIL: Singularity did not seed its name/HP in _init"); ok = false

	# (3a) Projectile pulled OFF a POSITIVE gate. Put a + gate band to the LEFT of the core; a bullet
	# sitting on that gate should be deflected toward the core (i.e. to the RIGHT, +x → off the gate).
	var pos_gate_x := 300.0                                    # + gate band centre x (left of core x=540)
	var proj := Vector2(pos_gate_x, 600.0)                    # bullet sitting on the + gate
	var dv_proj: Vector2 = sing.call("gravity_on_projectile", proj, 1.0 / 60.0)
	lines.append("3a proj-off-+gate: gate_x=%.0f proj.x=%.0f dv=(%.2f,%.2f) (want dv.x>0 toward core)" % [
		pos_gate_x, proj.x, dv_proj.x, dv_proj.y])
	# The core is at x=540 > 300, so the pull's x must be POSITIVE (toward the core), dragging the
	# bullet to the right — OFF the +gate band centred at 300. Magnitude must be non-trivial.
	if dv_proj.x <= 0.0 or dv_proj.length() <= 0.0:
		lines.append("FAIL: a projectile on a + gate was not pulled toward the vortex core (off the gate)"); ok = false
	else:
		lines.append("3a OK: a projectile on a + gate is dragged toward the core — off the positive gate")

	# (3b) Ship pulled TOWARD a NEGATIVE gate. Put the core OVER a − gate to the RIGHT of the ship; the
	# ship's pull must point toward that gate (+x, toward the core/gate) — fighting the player's dodge.
	var ship := Vector2(540.0, 600.0)                         # ship below; place core to its right
	sing.position = Vector2(820.0, 600.0)                     # core sits ON the − gate (right of the ship)
	var dv_ship: Vector2 = sing.call("pull_on_ship", ship, 1.0 / 60.0)
	lines.append("3b ship-toward--gate: ship.x=%.0f neg_gate/core.x=%.0f dv=(%.2f,%.2f) (want dv.x>0 toward gate)" % [
		ship.x, 820.0, dv_ship.x, dv_ship.y])
	if dv_ship.x <= 0.0 or dv_ship.length() <= 0.0:
		lines.append("FAIL: the ship was not pulled toward the negative gate (economy not inverted)"); ok = false
	else:
		lines.append("3b OK: the ship is dragged toward the − gate the core sits on — the economy is inverted")

	# (3c) Falloff: a point OUTSIDE FIELD_RADIUS gets ZERO pull (the field is bounded).
	sing.position = Vector2(540.0, 600.0)
	var far := Vector2(540.0, 600.0 + SingS.FIELD_RADIUS + 50.0)
	var dv_far: Vector2 = sing.call("gravity_on_projectile", far, 1.0 / 60.0)
	if dv_far.length() > 0.0001:
		lines.append("FAIL: the gravity field is not bounded (pull non-zero beyond FIELD_RADIUS)"); ok = false
	else:
		lines.append("3c OK: the field is bounded — no pull beyond FIELD_RADIUS")

	# (3d) The Singularity REUSES Events.gravity_shift (no boss-specific signal): _step_mechanic emits it.
	var grav_log: Array = []
	ev.connect("gravity_shift", func(dir, strength): grav_log.append({"dir": dir, "strength": strength}))
	sing.call("_step_mechanic", 1.0 / 60.0)
	lines.append("3d gravity_shift emits=%d (Singularity reuses the shared signal)" % grav_log.size())
	if grav_log.size() != 1 or float(grav_log[0]["strength"]) <= 0.0:
		lines.append("FAIL: Singularity did not emit gravity_shift with a positive strength"); ok = false
	else:
		lines.append("3d OK: Singularity reuses Events.gravity_shift (no boss-specific gravity signal)")
	sing.free()

	# ---- 4) ARMING RACE fix: a BOSS level does NOT auto-complete on the finish-line crossing ----
	# Reproduce run.gd's _process ORDERING: arm the boss at progress>=0.999 (pre-finish) BEFORE
	# GameState.tick_run integrates the frame, then tick. With LevelDef.has_boss the crossing frame
	# must NOT complete the run (the climax stays live); the WIN is owned by boss_defeated.
	gs.call("start_run")
	var lvl: Resource = gs.get("active_level")
	lvl.set("has_boss", true)                                  # this run ends in a boss
	var len_m: float = float(lvl.get("length_m"))
	# Fast-forward to JUST before the finish (progress ~0.999) without crossing it.
	var guard4 := 0
	while gs.get("distance") < len_m * 0.999 and guard4 < 100000:
		gs.call("tick_run", 1.0 / 60.0)
		guard4 += 1
	var pre_progress: float = clampf(float(gs.get("distance")) / len_m, 0.0, 1.0)
	var completed4 := [false]
	ev.connect("run_completed", func(_s, _d): completed4[0] = true)
	# run.gd arms the boss here (progress>=BOSS_ARM_PROGRESS) BEFORE the tick that crosses length_m.
	var armed_run := false
	if pre_progress >= 0.999:
		armed_run = true
		gs.set("boss_active", true)
	# Now integrate frames PAST length_m — the boss level must stay active (no auto-complete).
	for i in 600:
		gs.call("tick_run", 1.0 / 60.0)
	lines.append("arm-race: dist=%.1f len=%.0f active=%s completed=%s armed=%s (want active=true, completed=false)" % [
		float(gs.get("distance")), len_m, gs.get("run_active"), completed4[0], armed_run])
	if completed4[0] or not bool(gs.get("run_active")) or not armed_run:
		lines.append("FAIL: a boss level auto-completed on the finish crossing (arming race not fixed)"); ok = false
	else:
		lines.append("arm-race OK: a boss level scrolls past length_m WITHOUT auto-completing — the boss owns the WIN")
	# And boss_defeated is what actually wins: simulate run.gd's _on_boss_defeated.
	gs.set("boss_active", false)
	gs.call("complete_run")
	if bool(gs.get("run_active")) or not bool(gs.get("run_won")):
		lines.append("FAIL: boss_defeated -> complete_run did not WIN the boss run"); ok = false
	else:
		lines.append("arm-race OK: boss_defeated -> complete_run() is the run's WIN terminal")
	# Sanity: a BOSSLESS level still auto-completes on the crossing (the other branch).
	gs.call("start_run")
	gs.get("active_level").set("has_boss", false)
	var guard4b := 0
	while bool(gs.get("run_active")) and guard4b < 100000:
		gs.call("tick_run", 1.0 / 60.0)
		guard4b += 1
	if bool(gs.get("run_active")) or not bool(gs.get("run_won")):
		lines.append("FAIL: a bossless level did not auto-complete at the finish line"); ok = false
	else:
		lines.append("arm-race OK: a bossless level still wins on the finish-line crossing")

	# ---- 5) GRAVITY FIELD wired into GAMEPLAY (not dead code): a real Fleet's bullet on a + gate
	#         band actually LEAVES the band, and the ship/muzzle DRIFTS toward the core. ----------
	var sing2: Node2D = SingS.new()
	sing2.position = Vector2(540.0, 600.0)                     # vortex core high-centre
	sing2.set("_pulse", 1.0)
	var fl5: Node2D = FleetS.new()
	# Put the muzzle (ship line) to the LEFT of the core so pull_on_ship drags it RIGHT toward core.
	fl5.position = Vector2(360.0, 900.0)
	(fl5.get("_rng") as RandomNumberGenerator).seed = 0xC0FFEE
	# Inject ONE bullet sitting on a + gate band to the LEFT of the core (x=300); the bias must drag
	# it toward the core (+x), off the gate band. Drive the bias for a few frames and watch x climb.
	var proj_arr: Array = fl5.get("_proj")
	proj_arr.clear()
	proj_arr.append(Vector2(300.0, 600.0))                    # on the + gate band, in-field
	var bullet_x0: float = (fl5.get("_proj")[0] as Vector2).x
	for i in 30:
		fl5.call("apply_gravity_bias", sing2, 1.0 / 60.0)
	var bullet_x1: float = (fl5.get("_proj")[0] as Vector2).x
	lines.append("5a bullet-off-+gate: x %.1f -> %.1f (want climb toward core x=540)" % [bullet_x0, bullet_x1])
	if bullet_x1 <= bullet_x0 + 0.5:
		lines.append("FAIL: gravity bias did NOT drag a bullet off the + gate band (field is dead code)"); ok = false
	else:
		lines.append("5a OK: a live bullet on a + gate band is dragged toward the core — economy inversion is WIRED")
	# Ship/muzzle pull: the muzzle x must drift toward the core under repeated pull_on_ship nudges
	# (mirrors run.gd._apply_boss_gravity applying pull.x*delta to _fleet.position.x).
	var muzzle_x0: float = fl5.position.x
	for i in 30:
		var pull5: Vector2 = sing2.call("pull_on_ship", fl5.position, 1.0 / 60.0)
		fl5.position.x += pull5.x * (1.0 / 60.0)
	var muzzle_x1: float = fl5.position.x
	lines.append("5b ship-toward-core: muzzle.x %.1f -> %.1f (want climb toward core x=540)" % [muzzle_x0, muzzle_x1])
	if muzzle_x1 <= muzzle_x0 + 0.5:
		lines.append("FAIL: the ship/muzzle was not pulled toward the core in live gameplay"); ok = false
	else:
		lines.append("5b OK: the ship/muzzle drifts toward the vortex core — the steer inversion is WIRED")
	fl5.free()
	sing2.free()

	# ---- 6) PERSISTENT boss-arena STANCE GATES (#82/#83): the only way to switch stance mid-boss.
	# run.gd injects two parked gates (SPRAY '+' left, LANCE '÷' right) the player steers through. They
	# RE-ARM as the ship leaves + re-enters, so the player flips stance freely all fight. Drive the
	# spawner's pure update(distance, ship_x) and assert the gate_passed ops flip GameState's stance.
	var GateSpawnerS: GDScript = load("res://assets/gates/gate_spawner.gd")
	if GateSpawnerS == null:
		lines.append("FAIL: gate_spawner.gd missing for boss-stance-gate test"); ok = false
	else:
		var gsp: Node2D = GateSpawnerS.new()
		gsp.call("setup", 1680.0)
		root.add_child(gsp)                                    # _ready builds _design + connects steer
		gsp.call("spawn_boss_stance_gates")
		lines.append("6 boss-gates: count=%d (want 2)" % int(gsp.call("boss_gate_count")))
		if int(gsp.call("boss_gate_count")) != 2:
			lines.append("FAIL: spawn_boss_stance_gates did not park exactly 2 gates"); ok = false
		# Start in SPRAY; steer into the LANCE (right-flank) band → stance must flip to LANCE.
		gs.call("set_stance", GS_SPRAY)
		gsp.call("update", 0.0, 940.0)                        # ship at the right flank (LANCE gate band)
		lines.append("6 after LANCE-flank: stance=%d (want LANCE=%d)" % [int(gs.get("stance")), GS_LANCE])
		if int(gs.get("stance")) != GS_LANCE:
			lines.append("FAIL: steering into the right flank did not flip to LANCE"); ok = false
		# Steer back to centre (out of both bands) so the gates RE-ARM, then into the SPRAY flank → SPRAY.
		gsp.call("update", 0.0, 540.0)                        # out of both bands (re-arms)
		gsp.call("update", 0.0, 140.0)                        # ship at the left flank (SPRAY gate band)
		lines.append("6 after SPRAY-flank: stance=%d (want SPRAY=%d)" % [int(gs.get("stance")), GS_SPRAY])
		if int(gs.get("stance")) != GS_SPRAY:
			lines.append("FAIL: steering into the left flank did not flip back to SPRAY (re-arm failed)"); ok = false
		# And one more round-trip to LANCE proves the gates persist (re-trigger), not a one-shot.
		gsp.call("update", 0.0, 540.0)
		gsp.call("update", 0.0, 940.0)
		if int(gs.get("stance")) != GS_LANCE:
			lines.append("FAIL: boss stance gates did not persist for a second round-trip"); ok = false
		else:
			lines.append("6 OK: parked SPRAY/LANCE gates flip stance both ways + persist for the whole fight")
		gsp.free()

	# ---- 7) HP RE-TUNE (#82/#83): the Singularity is a TENSE-but-winnable climax, not a 40s sponge.
	# Assert the new HP is in a sane band, and that a healthy LANCE swarm cracks the ARMORED half
	# (100%->50%) in a reasonable number of frames once the player switches to LANCE.
	var sing3: Node2D = SingS.new()
	lines.append("7 hp-tune: SING_MAX_HP=%.0f" % float(sing3.get("max_hp")))
	if float(sing3.get("max_hp")) > 6000.0:
		lines.append("FAIL: Singularity HP still a sponge wall (>6000) after the re-tune"); ok = false
	if float(sing3.get("max_hp")) < 2000.0:
		lines.append("FAIL: Singularity HP dropped too low (<2000) — the climax would be trivial"); ok = false
	# Simulate the ARMORED half with a healthy LANCE swarm: ~12 bullets/frame in the hull at weight 6.
	sing3.call("arm")
	sing3.call("step", BossS.TELEGRAPH_TIME + 0.1)            # -> ARMORED
	var armored_frames := 0
	while int(sing3.call("current_phase")) == BossS.PHASE_ARMORED and armored_frames < 6000:
		sing3.call("_apply_hits", 12, FleetS.LANCE_HIT_WEIGHT) # healthy LANCE swarm in the hull
		sing3.call("step", 1.0 / 60.0)
		armored_frames += 1
	var armored_secs: float = armored_frames / 60.0
	lines.append("7 armored-clear: %d frames (%.1fs) to crack the armored half with LANCE (want <30s)" % [
		armored_frames, armored_secs])
	if int(sing3.call("current_phase")) == BossS.PHASE_ARMORED:
		lines.append("FAIL: a healthy LANCE swarm never cracked the ARMORED half (still spongy)"); ok = false
	elif armored_secs > 30.0:
		lines.append("FAIL: the ARMORED phase took >30s with LANCE — still a wall, re-tune more"); ok = false
	else:
		lines.append("7 OK: LANCE cracks the armored half in a tense-but-winnable time")
	sing3.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
