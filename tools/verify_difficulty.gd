extends SceneTree
## Headless verification for the #80 Easy/Medium/Hard difficulty slice:
##   - Profile DATA layer  : the three DifficultyProfiles differ (armor chip / drain / spawn /
##                           rhombus bias) and MEDIUM mirrors today's constants (no-op default).
##   - Difficulty readers  : the autoload caches the active profile from Settings.difficulty and
##                           re-reads it on Events.difficulty_changed (live mode switch).
##   - Rhombus FLOOR scales: the SUB-THRESHOLD spray chip differs across modes — EASY chips,
##                           MEDIUM chips less, HARD deals TRUE 0 (full immunity, Lance mandatory),
##                           driven through the REAL Targets._apply_damage on a real Rhombus.
##   - LANCE still cracks   : a heavy LANCE bullet cracks the Rhombus on every mode (the floor
##                           gate is mode-invariant; only the sub-threshold grind scales).
##   - Settings round-trip  : Settings.difficulty persists through save_settings -> load_settings.
##   - Drain scale          : a negative gate drains the battery harder on HARD than EASY (#80).
##
## GPU-free: drives each system's pure logic + writes a verdict file the runner polls for
## (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_difficulty.gd /tmp/verify_difficulty_result.txt

const RESULT_PATH := "/tmp/verify_difficulty_result.txt"

const EASY := 0
const MEDIUM := 1
const HARD := 2


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ProfileS: GDScript = load("res://resources/difficulty_profile.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	if ProfileS == null or TargetsS == null or FleetS == null:
		lines.append("RESULT=FAIL (difficulty scripts missing)"); _write(lines); return

	var diff: Node = root.get_node_or_null("Difficulty")
	var settings: Node = root.get_node_or_null("Settings")
	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if diff == null or settings == null or gs == null or ev == null:
		lines.append("RESULT=FAIL (autoloads missing: Difficulty/Settings/GameState/Events)"); _write(lines); return
	diff.call("wire_events")
	gs.call("wire_events")

	# 1) The DATA layer — the three profiles differ, MEDIUM is the no-op default.
	var pe: Resource = diff.call("profile_for", EASY)
	var pm: Resource = diff.call("profile_for", MEDIUM)
	var ph: Resource = diff.call("profile_for", HARD)
	lines.append("profiles: chip E=%.2f M=%.2f H=%.2f | drain E=%.2f M=%.2f H=%.2f | rhombus_bias E=%.2f H=%.2f" % [
		pe.armor_chip_fraction, pm.armor_chip_fraction, ph.armor_chip_fraction,
		pe.drain_mult, pm.drain_mult, ph.drain_mult, pe.rhombus_weight_bias, ph.rhombus_weight_bias])
	if not (pe.armor_chip_fraction > pm.armor_chip_fraction and pm.armor_chip_fraction > ph.armor_chip_fraction):
		lines.append("profiles FAIL: chip fraction not strictly EASY > MEDIUM > HARD"); ok = false
	if absf(ph.armor_chip_fraction) > 0.0001:
		lines.append("profiles FAIL: HARD chip fraction must be TRUE 0 (full immunity)"); ok = false
	if absf(pm.armor_chip_fraction - TargetsS.ARMOR_CHIP_FRACTION) > 0.0001:
		lines.append("profiles FAIL: MEDIUM chip must mirror the legacy ARMOR_CHIP_FRACTION const (%.2f)" % TargetsS.ARMOR_CHIP_FRACTION); ok = false
	if not (pe.drain_mult < pm.drain_mult and pm.drain_mult < ph.drain_mult):
		lines.append("profiles FAIL: drain_mult not strictly EASY < MEDIUM < HARD"); ok = false
	if not (pm.drain_mult == 1.0 and pm.spawn_density_mult == 1.0 and pm.rhombus_weight_bias == 0.0):
		lines.append("profiles FAIL: MEDIUM is not a no-op (all mults must be 1.0 / bias 0.0)"); ok = false
	if ok:
		lines.append("profiles OK: chip EASY>MED>HARD, HARD=true 0, MEDIUM mirrors today's balance")

	# 2) The active reader tracks Settings.difficulty over difficulty_changed.
	settings.call("set_difficulty", EASY)
	var chip_e: float = diff.call("armor_chip_fraction")
	var drain_e: float = diff.call("drain_mult")
	settings.call("set_difficulty", HARD)
	var chip_h: float = diff.call("armor_chip_fraction")
	var drain_h: float = diff.call("drain_mult")
	settings.call("set_difficulty", MEDIUM)
	var chip_m: float = diff.call("armor_chip_fraction")
	lines.append("active reader: chip easy=%.2f med=%.2f hard=%.2f (tracks Settings.difficulty)" % [chip_e, chip_m, chip_h])
	if not (chip_e == pe.armor_chip_fraction and chip_h == ph.armor_chip_fraction and chip_m == pm.armor_chip_fraction):
		lines.append("active FAIL: Difficulty.armor_chip_fraction() did not track Settings.difficulty"); ok = false
	else:
		lines.append("active OK: the autoload re-reads its profile on difficulty_changed")

	# 3) The Rhombus FLOOR sub-threshold chip SCALES with mode — through the REAL Targets path.
	#    Same sub-threshold SPRAY bullet (weight 1.0 < floor 5.0): EASY chips most, HARD does 0.
	var tg: Node = TargetsS.new()
	root.add_child(tg)               # parented so Targets._difficulty_node() finds /root/Difficulty
	var chip_for := func(mode: int) -> float:
		settings.call("set_difficulty", mode)
		var rh: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
		var hp0: float = rh["hp"]
		tg.call("_apply_damage", rh, 3, FleetS.SPRAY_HIT_WEIGHT, false)   # 3 spray bullets, sub-floor
		return hp0 - float(rh["hp"])
	var damage_easy: float = chip_for.call(EASY)
	var damage_med: float = chip_for.call(MEDIUM)
	var damage_hard: float = chip_for.call(HARD)
	lines.append("rhombus sub-floor SPRAY chip: easy=%.2f med=%.2f hard=%.2f (want easy>med>0, hard=0)" % [
		damage_easy, damage_med, damage_hard])
	if not (damage_easy > damage_med and damage_med > 0.0):
		lines.append("floor-scale FAIL: EASY should chip more than MEDIUM, both > 0"); ok = false
	if absf(damage_hard) > 0.0001:
		lines.append("floor-scale FAIL: HARD sub-threshold SPRAY must deal TRUE 0 (Lance mandatory)"); ok = false
	if ok:
		lines.append("floor-scale OK: sub-floor SPRAY chips on Easy/Med, FULLY ABSORBED on Hard")

	# 3b) LANCE still cracks the Rhombus on EVERY mode (the floor gate is mode-invariant).
	var lance_cracks := true
	for mode in [EASY, MEDIUM, HARD]:
		settings.call("set_difficulty", mode)
		var rh2: Dictionary = tg.call("_new_enemy", TargetsS.KIND_RHOMBUS, 0.0)
		var hp0b: float = rh2["hp"]
		tg.call("_apply_damage", rh2, 1, FleetS.LANCE_HIT_WEIGHT, true)   # 1*6*10 = 60 full damage
		if absf((hp0b - float(rh2["hp"])) - 60.0) > 0.01:
			lance_cracks = false
	lines.append("lance crack across modes: %s (want full 60 dmg on every mode)" % lance_cracks)
	if not lance_cracks:
		lines.append("lance FAIL: a LANCE bullet must crack the Rhombus on all difficulties"); ok = false
	else:
		lines.append("lance OK: LANCE clears the floor on Easy/Med/Hard alike — only the grind scales")
	tg.queue_free()

	# 4) Settings.difficulty round-trips through save/load.
	settings.call("set_difficulty", HARD)
	settings.call("save_settings")
	settings.set("difficulty", MEDIUM)            # scribble over it
	settings.call("load_settings")
	var loaded: int = int(settings.get("difficulty"))
	lines.append("round-trip: saved HARD(%d), scribbled MED, reloaded -> %d (want %d)" % [HARD, loaded, HARD])
	if loaded != HARD:
		lines.append("round-trip FAIL: Settings.difficulty did not persist through save/load"); ok = false
	else:
		lines.append("round-trip OK: difficulty persists in settings.cfg PROGRESS")

	# 5) Negative-gate drain scales with mode (EASY gentler than HARD) — through GameState.
	var drain_under := func(mode: int) -> float:
		settings.call("set_difficulty", mode)
		gs.call("start_run")
		var before: float = float(gs.get("glow_battery"))
		gs.call("_on_gate_passed", "subtract", 2.0, 18)   # negative gate -> drain * mode mult
		return before - float(gs.get("glow_battery"))
	var d_easy: float = drain_under.call(EASY)
	var d_hard: float = drain_under.call(HARD)
	lines.append("neg-gate drain: easy=%.1f hard=%.1f (want easy < hard)" % [d_easy, d_hard])
	if not (d_easy < d_hard and d_easy > 0.0):
		lines.append("drain FAIL: a negative gate did not drain harder on HARD than EASY"); ok = false
	else:
		lines.append("drain OK: HARD bleeds the Glow Battery faster on a negative gate")

	settings.call("set_difficulty", MEDIUM)       # restore the default for any later run
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
