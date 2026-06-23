extends SceneTree
## Headless verification for the #53 cross-cutting enemy↔gate interactions:
##   - Gate-hijack            : a hijacked gate spawns a parked occupant; while it lives,
##                              crossing the line DENIES the splice (gate_hijack_blocked,
##                              no economy change). Destroy it first → the splice applies.
##   - Multiply-through       : a free enemy entering a POSITIVE gate band duplicates ONCE
##                              (enemy_multiplied); a NEGATIVE band never multiplies.
##
## Drives GateSpawner + Targets logic directly (no GPU): build_formations + the query API
## (take_pending_hijacks / positive_gate_bands / gate_info / notify_hijack_cleared) and
## Targets.step(). Run:
##   tools/run-headless.sh res://tools/verify_interactions.gd /tmp/verify_interactions_result.txt

const RESULT_PATH := "/tmp/verify_interactions_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if gs == null or ev == null:
		lines.append("RESULT=FAIL (autoloads missing)"); _write(lines); return
	gs.call("wire_events")

	var SpawnerS: GDScript = load("res://assets/gates/gate_spawner.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	if SpawnerS == null or TargetsS == null:
		lines.append("RESULT=FAIL (interaction scripts missing)"); _write(lines); return

	# === 1) GATE-HIJACK ======================================================
	# A hijacked left gate (×3). Build it, let Targets park an occupant, then test both
	# outcomes: blocked while alive, applied once cleared.
	var blocked := [0]
	var passed := [0]
	ev.connect("gate_hijack_blocked", func(_t, _at): blocked[0] += 1)
	ev.connect("gate_passed", func(_t, _v, _c): passed[0] += 1)

	var sp: Node2D = SpawnerS.new()
	sp.call("setup", 1680.0)
	sp.call("build_formations", [{"m": 10.0, "l": ["mul", 3.0], "r": ["div", 2.0], "hijack": "l"}])
	var pend: Array = sp.call("take_pending_hijacks")
	lines.append("hijack: pending occupants=%d (want 1, the ×3 left gate)" % pend.size())
	if pend.size() != 1:
		lines.append("hijack FAIL: hijacked gate did not queue an occupant"); ok = false

	# Re-queue the same hijack for Targets to consume (we drained it above to inspect).
	sp.call("build_formations", [{"m": 10.0, "l": ["mul", 3.0], "r": ["div", 2.0], "hijack": "l"}])
	gs.call("start_run")
	gs.call("set_projectile_count", 10)
	var tg: Node2D = TargetsS.new()
	tg.call("set_fleet", null)
	tg.call("set_gates", sp)
	tg.call("step", 1.0 / 60.0)                       # pulls the pending hijack → spawns occupant
	var parked := 0
	for e in tg.get("_enemies"):
		if bool(e.get("parked", false)):
			parked += 1
	lines.append("hijack: parked occupants after step=%d (want 1)" % parked)
	if parked != 1:
		lines.append("hijack FAIL: occupant not parked on the gate"); ok = false

	# --- 1a) NOT cleared: the gate crosses the line with the occupant alive → blocked.
	var count_before: int = gs.get("projectile_count")
	# Scroll the formation past the ship line (distance >= track_m) with the ship in the
	# LEFT span so the hijacked left gate is the one chosen.
	sp.call("update", 12.0, 280.0)
	lines.append("hijack blocked: blocked=%d passed=%d count %d->%d (want blocked=1,passed=0,unchanged)" % [
		blocked[0], passed[0], count_before, gs.get("projectile_count")])
	if blocked[0] != 1 or passed[0] != 0 or gs.get("projectile_count") != count_before:
		lines.append("hijack FAIL: live occupant did not deny the splice"); ok = false
	else:
		lines.append("hijack OK (blocked): a live occupant denies the splice, no economy change")

	# --- 1b) Cleared in time: rebuild, kill the occupant, then the splice applies (×3).
	blocked[0] = 0; passed[0] = 0
	var sp2: Node2D = SpawnerS.new()
	sp2.call("setup", 1680.0)
	sp2.call("build_formations", [{"m": 10.0, "l": ["mul", 3.0], "r": ["div", 2.0], "hijack": "l"}])
	gs.call("start_run")
	gs.call("set_projectile_count", 10)
	var tg2: Node2D = TargetsS.new()
	tg2.call("set_fleet", null)
	tg2.call("set_gates", sp2)
	tg2.call("step", 1.0 / 60.0)                      # spawn the occupant
	# Destroy it: zero its HP, step so _step_parked clears the hijack + scores the kill.
	for e in tg2.get("_enemies"):
		if bool(e.get("parked", false)):
			e["hp"] = 0.0
	var kills_b: int = tg2.get("kills")
	tg2.call("step", 1.0 / 60.0)
	var cnt_before2: int = gs.get("projectile_count")
	sp2.call("update", 12.0, 280.0)                   # gate crosses the line, now claimable
	lines.append("hijack cleared: kills+=%d blocked=%d passed=%d count %d->%d (want kill, passed=1, ×3)" % [
		tg2.get("kills") - kills_b, blocked[0], passed[0], cnt_before2, gs.get("projectile_count")])
	if tg2.get("kills") - kills_b != 1 or passed[0] != 1 or blocked[0] != 0 or gs.get("projectile_count") != cnt_before2 * 3:
		lines.append("hijack FAIL: clearing the occupant did not free the ×3 splice"); ok = false
	else:
		lines.append("hijack OK (cleared): destroying the occupant claims the upgrade (×3 applied)")

	# === 2) MULTIPLY-THROUGH =================================================
	var multiplied := [0]
	ev.connect("enemy_multiplied", func(_at): multiplied[0] += 1)
	gs.call("start_run")

	# Positive formation (+5 / +5). Position it mid-screen (no trigger) and read its band.
	var spp: Node2D = SpawnerS.new()
	spp.call("setup", 1680.0)
	spp.call("build_formations", [{"m": 20.0, "l": ["add", 5.0], "r": ["add", 5.0]}])
	spp.call("update", 5.0, 540.0)                    # y ≈ 690, mid-screen
	var bands: Array = spp.call("positive_gate_bands")
	lines.append("multiply: positive bands=%d (want 2 — both + gates)" % bands.size())
	if bands.size() != 2:
		lines.append("multiply FAIL: positive gate bands not exposed"); ok = false

	var tgm: Node2D = TargetsS.new()
	tgm.call("set_fleet", null)
	tgm.call("set_gates", spp)
	# Drop one free enemy right on the first band (inside its x-span, at its y).
	var band: Dictionary = bands[0]
	var en: Array = tgm.get("_enemies")
	var probe: Dictionary = tgm.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	probe["speed"] = 0.0                              # stay put so the band test is deterministic
	probe["pos"] = Vector2((float(band["x_min"]) + float(band["x_max"])) * 0.5, float(band["y"]))
	en.append(probe)
	tgm.call("step", 1.0 / 60.0)
	var after_one: int = tgm.call("live_count")
	tgm.call("step", 1.0 / 60.0)                      # step again — must NOT multiply a second time
	var after_two: int = tgm.call("live_count")
	lines.append("multiply: enemies 1 ->%d ->%d  events=%d (want 2 then 2, events=1)" % [
		after_one, after_two, multiplied[0]])
	if after_one != 2 or after_two != 2 or multiplied[0] != 1:
		lines.append("multiply FAIL: enemy didn't duplicate exactly once through a + gate"); ok = false
	else:
		lines.append("multiply OK: a free enemy duplicates once through a + gate band")

	# Negative band must NOT multiply.
	multiplied[0] = 0
	var spn: Node2D = SpawnerS.new()
	spn.call("setup", 1680.0)
	spn.call("build_formations", [{"m": 20.0, "l": ["sub", 5.0], "r": ["div", 2.0]}])
	spn.call("update", 5.0, 540.0)
	var nbands: Array = spn.call("positive_gate_bands")
	var tgn: Node2D = TargetsS.new()
	tgn.call("set_fleet", null)
	tgn.call("set_gates", spn)
	var en2: Array = tgn.get("_enemies")
	var probe2: Dictionary = tgn.call("_new_enemy", TargetsS.KIND_GLITCH, 0.0)
	probe2["speed"] = 0.0
	probe2["pos"] = Vector2(270.0, 690.0)             # in the left (negative) gate's span/area
	en2.append(probe2)
	tgn.call("step", 1.0 / 60.0)
	lines.append("multiply (negative): positive_bands=%d enemies=%d events=%d (want 0,1,0)" % [
		nbands.size(), tgn.call("live_count"), multiplied[0]])
	if nbands.size() != 0 or tgn.call("live_count") != 1 or multiplied[0] != 0:
		lines.append("multiply FAIL: a negative gate must not duplicate enemies"); ok = false
	else:
		lines.append("multiply OK: negative gates do not multiply enemies")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
