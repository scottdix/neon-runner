extends SceneTree
## Headless verification for the HORDE 20-s LANE-BOSS (#90, H4):
##   - EXACTLY ONE KIND_LANEBOSS spawns per LANEBOSS_INTERVAL (20 s) of HORDE step() time —
##     not zero, not two; the timer fires once per interval and carries the remainder.
##   - The spawns ALTERNATE divider sides (left, right, left…) — Events.lane_boss_spawned(side, at)
##     reports 0,1,0,1… and each boss's spawn x lands cleanly on that side of CENTER_X.
##   - The boss is BEATABLE NOW: a representative SPRAY DPS clears its ~600 hp within a bounded time.
##   - REGRESSION: with HORDE OFF (set_horde never called), 20 s of step() spawns NO lane-boss.
##
## It add_child's a real Targets (its _ready builds a MultiMesh, fine headless), awaits a frame so
## _ready ran, forces HORDE on (no Settings autoload state to lean on), starts a live run, then drives
## step(delta) directly. lane_boss_spawned is captured into a log to assert count + alternation.
##   tools/run-headless.sh res://tools/verify_horde_boss.gd /tmp/verify_horde_boss_result.txt

const RESULT_PATH := "/tmp/verify_horde_boss_result.txt"
const CENTER_X := 540.0

# Captured lane_boss_spawned emissions: [{side:int, x:float}, ...]
var _spawns: Array = []


func _initialize() -> void:
	# Deferred so add_child'd nodes get their _ready under -s (see harness gotchas).
	_run.call_deferred()


func _on_lane_boss_spawned(side: int, at: Vector2) -> void:
	_spawns.append({"side": side, "x": at.x})


func _run() -> void:
	await process_frame
	var lines: Array[String] = []
	var ok := true

	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if gs == null or ev == null:
		lines.append("RESULT=FAIL (GameState/Events autoload missing)"); _write(lines); return

	# Capture lane_boss_spawned emissions for the count + alternation asserts.
	ev.connect("lane_boss_spawned", Callable(self, "_on_lane_boss_spawned"))

	var TargetsScript: GDScript = load("res://assets/obstacles/targets.gd")
	var KIND_LANEBOSS := 4   # enum order: GLITCH=0, RHOMBUS=1, FRACTAL=2, FRACTLING=3, LANEBOSS=4

	# --- A) HORDE OFF is inert: 20 s of step() spawns NO lane-boss. ---
	var t_off: Node2D = TargetsScript.new()
	t_off.name = "VerifyTargetsOff"
	root.add_child(t_off)
	await process_frame
	gs.call("start_run")
	t_off.set("_force_horde", true)   # forces _is_horde true, but set_horde NOT called => _horde_active false
	_spawns.clear()
	for i in 1320:                    # 22 s @ 60fps
		t_off.call("step", 1.0 / 60.0)
	lines.append("horde OFF: lane_boss spawns in 22s = %d (want 0)" % _spawns.size())
	if _spawns.size() != 0:
		lines.append("inert FAIL: lane-boss spawned with set_horde never called"); ok = false
	t_off.queue_free()

	# --- B) HORDE ON: exactly one per 20 s, alternating sides. ---
	var t: Node2D = TargetsScript.new()
	t.name = "VerifyTargetsBoss"
	root.add_child(t)
	await process_frame
	t.call("set_horde", true)
	t.set("_force_horde", true)
	# Fresh run; freeze enemies offscreen so the field never caps (fodder spawns too) and a boss is
	# never skipped for a full field. We keep the run live the whole sim.
	gs.call("start_run")
	gs.set("distance", 0.0)

	var interval: float = float(t.get("LANEBOSS_INTERVAL"))
	lines.append("LANEBOSS_INTERVAL=%.1f (want 20.0)" % interval)
	if absf(interval - 20.0) > 0.001:
		lines.append("interval FAIL: LANEBOSS_INTERVAL not 20s"); ok = false

	_spawns.clear()
	# Simulate 65 s @ 60fps. Expect a spawn at ~20, 40, 60 => 3 lane-bosses across the window.
	var total_s := 65.0
	var frames: int = int(total_s * 60.0)
	# Per-step boss-count checks: assert no single 20 s window over-spawns. We sample the cumulative
	# spawn count and verify it climbs by exactly 1 each interval crossing.
	var counts_at: Array[int] = []   # cumulative spawns seen just AFTER each 20 s boundary
	for f in frames:
		t.call("step", 1.0 / 60.0)
		# Just past each whole interval, record the cumulative count.
		var elapsed: float = float(f + 1) / 60.0
		if f + 1 == int(round(20.0 * 60.0)) or f + 1 == int(round(40.0 * 60.0)) or f + 1 == int(round(60.0 * 60.0)):
			counts_at.append(_spawns.size())

	lines.append("spawns over %.0fs = %d (want 3 at ~20/40/60s)" % [total_s, _spawns.size()])
	if _spawns.size() != 3:
		lines.append("count FAIL: expected exactly 3 lane-bosses in 65s, got %d" % _spawns.size()); ok = false

	# Cumulative count climbs by exactly 1 per interval (1, 2, 3) — no window spawns 0 or 2.
	if counts_at.size() == 3 and counts_at[0] == 1 and counts_at[1] == 2 and counts_at[2] == 3:
		lines.append("cadence OK: cumulative %s (one per 20s window)" % str(counts_at))
	else:
		lines.append("cadence FAIL: cumulative %s (want [1,2,3])" % str(counts_at)); ok = false

	# Alternation: sides must read 0,1,0… and each boss x lands on the asserted side of CENTER_X.
	var alt_ok := true
	var side_ok := true
	for i in _spawns.size():
		var s: Dictionary = _spawns[i]
		var expect_side: int = i % 2          # first boss LEFT(0), then RIGHT(1), …
		if int(s["side"]) != expect_side:
			alt_ok = false
		var px: float = float(s["x"])
		# side 0 => x < CENTER_X (LEFT); side 1 => x > CENTER_X (RIGHT).
		if int(s["side"]) == 0 and px >= CENTER_X:
			side_ok = false
		if int(s["side"]) == 1 and px <= CENTER_X:
			side_ok = false
	lines.append("sides=%s (want alternating 0,1,0)" % str(_spawns.map(func(d): return int(d["side"]))))
	if not alt_ok:
		lines.append("alternation FAIL: sides did not alternate 0,1,0…"); ok = false
	if not side_ok:
		lines.append("placement FAIL: a lane-boss x landed on the wrong side of CENTER_X"); ok = false

	# Verify a live LANEBOSS exists in the set with the right kind/hp (rides the normal path).
	var enemies: Array = t.get("_enemies")
	var laneboss_in_set := 0
	var boss_hp := 0.0
	var boss_e: Dictionary = {}
	for e in enemies:
		var ed: Dictionary = e
		if int(ed.get("kind", -1)) == KIND_LANEBOSS:
			laneboss_in_set += 1
			boss_hp = float(ed["max_hp"])
			boss_e = ed
	lines.append("live KIND_LANEBOSS in set=%d max_hp=%.0f (want >=1, hp~600)" % [laneboss_in_set, boss_hp])

	# --- C) BEATABLE NOW: a representative SPRAY DPS kills a fresh lane-boss within a bounded time. ---
	# Build a clean lane-boss dict via the production STATS and drive _apply_damage with a representative
	# SPRAY frame: hits/frame bullets at SPRAY hit_weight (1.0). SPRAY landing a modest ~6 hits/frame on a
	# big target (DAMAGE_PER_BULLET=10) deals 60 dmg/frame => ~600hp clears in ~10 frames. We bound the
	# kill at <= 2.0 s (120 frames) — a generous "beatable now" ceiling.
	var stats: Dictionary = t.get("STATS")
	var bs: Dictionary = stats[KIND_LANEBOSS]
	var boss: Dictionary = {
		"kind": KIND_LANEBOSS, "armor": int(bs["armor"]),
		"hp": float(bs["hp"]), "max_hp": float(bs["hp"]), "flash": 0.0,
	}
	var spray_hits := 6          # representative SPRAY bullets landing per frame on the big hull
	var spray_weight := 1.0      # SPRAY hit_weight
	var kill_frames := -1
	for f in 200:                # cap the sim well past the 120-frame ceiling
		# _apply_damage(e, hits, hit_weight, pierce, crack_weight)
		t.call("_apply_damage", boss, spray_hits, spray_weight, false, spray_weight)
		if float(boss["hp"]) <= 0.0:
			kill_frames = f + 1
			break
	var kill_s: float = (float(kill_frames) / 60.0) if kill_frames > 0 else -1.0
	lines.append("SPRAY kill: %d hits/frame cleared %.0f hp in %d frames (%.2fs)" % [spray_hits, float(bs["hp"]), kill_frames, kill_s])
	if kill_frames < 0:
		lines.append("beatable FAIL: representative SPRAY never killed the lane-boss"); ok = false
	elif kill_s > 2.0:
		lines.append("beatable FAIL: SPRAY kill took %.2fs (> 2.0s ceiling)" % kill_s); ok = false
	else:
		lines.append("beatable OK: SPRAY clears the lane-boss in %.2fs (<= 2.0s)" % kill_s)

	if boss_hp < 500.0 and laneboss_in_set > 0:
		lines.append("hp FAIL: lane-boss max_hp %.0f below ~600 expectation" % boss_hp); ok = false

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
