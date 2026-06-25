extends SceneTree
## Headless verification for the MVP core-loop slice (#9/#10/#52):
## analog steer (Player) + always-on fire (Fleet) + economy (GameState).
##
## GPU-free: asserts parse + structure + simulation LOGIC by driving each
## system's pure `step()` directly. Writes its verdict to an ABSOLUTE path via
## FileAccess (flushed before quit) and the runner polls for it — see
## tools/run-headless.sh and CLAUDE.md "environment gotchas".
##
##   tools/run-headless.sh res://tools/verify_run.gd /tmp/verify_run_result.txt

const RESULT_PATH := "/tmp/verify_run_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# 1) All new scripts parse + load as GDScript.
	for path in [
		"res://autoload/game_state.gd", "res://assets/player/player.gd",
		"res://assets/projectiles/fleet.gd", "res://assets/levels/run.gd"]:
		var scr: Variant = load(path)
		if scr == null or not (scr is GDScript):
			lines.append("load %s = FAIL" % path); ok = false
		else:
			lines.append("load %s = OK" % path)

	# 2) Events bus exposes the analog-steer + fire signals.
	var ev: Object = (load("res://autoload/events.gd") as GDScript).new()
	for sig in ["player_steered", "projectile_count_changed", "fleet_fired"]:
		if not ev.has_signal(sig):
			lines.append("signal %s = MISSING" % sig); ok = false
	(ev as Node).free()

	# 3) Autoloads registered (CLAUDE.md: they DO load under -s).
	var gs: Node = root.get_node_or_null("GameState")
	lines.append("autoload Events=%s GameState=%s" % [
		root.get_node_or_null("Events") != null, gs != null])
	if gs == null:
		lines.append("RESULT=FAIL (GameState autoload missing)")
		_write(lines); return
	# Under `-s`, autoload _ready is deferred past _initialize, so do the engine's
	# normal wiring explicitly: connect GameState to the gate bus (gate effects are
	# applied by GameState, not the spawner — review-debt decoupling).
	gs.call("wire_events")

	# This slice verifies the LEGACY economy core: 20-volume seed, −/÷ gates, and battery
	# drain-on-negative-gate. The game is now locked to forced-HORDE (firepower-as-health,
	# +/×-only gates, inert battery, 40-volume seed), which parks all of that. Drive the global
	# Settings autoload back to LEGACY so production's poc_mode reads run the parked path. Set the
	# field directly (not set_poc_mode, which persists).
	var settings_node: Node = root.get_node_or_null("Settings")
	if settings_node:
		settings_node.set("poc_mode", 0)   # 0 = PocMode.LEGACY

	# 4) GameState economy: start_run seeds the swarm; clamp never goes negative.
	gs.call("start_run")
	var seeded: int = gs.get("projectile_count")
	var active: bool = gs.get("run_active")
	lines.append("GameState start_run: active=%s projectile_count=%d" % [active, seeded])
	if not active or seeded <= 0:
		ok = false
	gs.call("add_projectiles", -9999)
	if gs.get("projectile_count") != 0:
		lines.append("clamp FAIL: projectile_count=%d (expected 0)" % gs.get("projectile_count")); ok = false
	else:
		lines.append("clamp OK: projectile_count floored at 0")

	# 5) Player analog steer: clamps to bounds + lerps toward target.
	var PlayerS: GDScript = load("res://assets/player/player.gd")
	var p: Node2D = PlayerS.new()
	p.position.x = 540.0
	p.call("set_target_x", 99999.0)         # way past the right edge
	for i in 90:
		p.call("step", 1.0 / 60.0)
	var px: float = p.position.x
	# default bounds (no _ready): _min_x=80, _max_x=1000
	if px > 1000.001 or px <= 540.0:
		lines.append("steer-right FAIL: x=%.1f (want >540, <=1000)" % px); ok = false
	else:
		lines.append("steer-right OK: x=%.1f clamped within [80,1000]" % px)
	p.call("set_target_x", -99999.0)
	for i in 90:
		p.call("step", 1.0 / 60.0)
	if p.position.x < 79.999:
		lines.append("steer-left FAIL: x=%.1f (want >=80)" % p.position.x); ok = false
	else:
		lines.append("steer-left OK: x=%.1f clamped at left edge" % p.position.x)
	p.free()

	# 6) Fleet always-on fire: produces live projectiles, and swarm volume drives
	#    rate of fire (more volume => denser stream over the same sim time).
	var live_lo := _sim_fleet(0, 0.30)
	var live_hi := _sim_fleet(220, 0.30)
	lines.append("fleet fire: volume0 -> %d live, volume220 -> %d live" % [live_lo, live_hi])
	if live_lo <= 0:
		lines.append("fire FAIL: base stream produced no projectiles"); ok = false
	if live_hi <= live_lo:
		lines.append("volume-scaling FAIL: more volume did not increase fire"); ok = false
	else:
		lines.append("volume-scaling OK: volume increases stream density")

	# 7) Fleet.consume_near: removes projectiles near a point, sparks, returns count.
	var FleetS2: GDScript = load("res://assets/projectiles/fleet.gd")
	var fb: Node2D = FleetS2.new()
	fb.position = Vector2(540.0, 1680.0)
	fb.call("set_volume", 120)
	for i in 40:
		fb.call("step", 1.0 / 60.0)         # build up a stream
	var before_live: int = fb.call("live_count")
	var consumed: int = fb.call("consume_near", Vector2(540.0, 1450.0), 320.0)
	var after_live: int = fb.call("live_count")
	var sparks: int = fb.call("spark_count")
	lines.append("consume_near: live %d -> %d, consumed=%d, sparks=%d" % [
		before_live, after_live, consumed, sparks])
	if consumed <= 0 or after_live >= before_live or sparks <= 0:
		lines.append("consume FAIL: projectiles not consumed/sparked"); ok = false
	else:
		lines.append("consume OK: bullets removed + sparked on contact")
	fb.free()

	# 8) Targets per-impact: an enemy in the stream is destroyed by bullet hits and
	#    scores + bursts; an enemy off to the side (no bullets reach it) survives.
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var fl: Node2D = FleetS2.new()
	fl.position = Vector2(540.0, 1680.0)
	fl.call("set_volume", 160)              # dense stream straight up from x=540
	var tg: Node2D = TargetsS.new()
	tg.call("set_fleet", fl)
	var en: Array = tg.get("_enemies")
	en.append({"pos": Vector2(540, 1300), "hp": 120.0, "max_hp": 120.0, "size": 64.0, "speed": 0.0, "flash": 0.0})
	en.append({"pos": Vector2(70, 1300), "hp": 120.0, "max_hp": 120.0, "size": 64.0, "speed": 0.0, "flash": 0.0})
	var score_before: int = gs.get("score")
	for i in 240:
		fl.call("step", 1.0 / 60.0)         # fire + march bullets up through x=540
		tg.call("step", 1.0 / 60.0)         # enemies consume the bullets that reach them
	var kills: int = tg.get("kills")
	var side_hp: float = en[1]["hp"]
	lines.append("targets: kills=%d  score+=%d  off-stream hp=%.0f" % [
		kills, gs.get("score") - score_before, side_hp])
	if kills < 1:
		lines.append("impact-kill FAIL: enemy in the stream not destroyed"); ok = false
	if gs.get("score") <= score_before:
		lines.append("score FAIL: kills did not add score"); ok = false
	if side_hp < 119.9:
		lines.append("off-stream FAIL: enemy with no bullets took damage"); ok = false
	if ok:
		lines.append("targets OK: in-stream killed + scored, off-stream safe")
	tg.free(); fl.free()

	# 9) Finite level / finish line (#51): the LevelDef + .tres load, start_run seeds
	#    distance 0, tick_run integrates distance and fires distance_changed, and
	#    crossing length trips the WIN (run_completed, run_active=false, run_won).
	var LevelS: GDScript = load("res://resources/level_def.gd")
	var lvl_tres: Resource = load("res://data/level_01.tres")
	lines.append("level load: script=%s  level_01.tres=%s" % [
		LevelS != null, lvl_tres != null])
	if LevelS == null or lvl_tres == null:
		lines.append("level FAIL: LevelDef/.tres did not load"); ok = false

	# Capture the bus signals via a by-reference Array (lambdas can't rebind locals).
	var ev_auto: Object = root.get_node_or_null("Events")
	var seen := [0, false, 0.0]   # [distance_changed count, run_completed?, final distance]
	ev_auto.connect("distance_changed", func(_d, _p): seen[0] += 1)
	ev_auto.connect("run_completed", func(_s, d): seen[1] = true; seen[2] = d)

	gs.call("start_run")
	# This test exercises the BOSSLESS auto-complete branch (win at the finish line). The shipped
	# level now ends in a boss (#82/#83) where run.gd owns the WIN, so force the loaded level to the
	# bossless path here; the boss-arm-past-finish branch has its own assertion in verify_boss.
	gs.get("active_level").set("has_boss", false)
	var d0: float = gs.get("distance")
	var len_m: float = gs.get("active_level").length_m
	var dist_mid := 0.0
	for i in 6000:                       # bounded; 320 m / 8 mps = 40 s = 2400 frames
		gs.call("tick_run", 1.0 / 60.0)
		if i == 600:
			dist_mid = gs.get("distance")
		if not gs.get("run_active"):
			break
	var d_final: float = gs.get("distance")
	var won: bool = gs.get("run_won")
	var still_active: bool = gs.get("run_active")
	lines.append("finite-level: start_dist=%.1f mid_dist=%.1f final_dist=%.1f len=%.0f won=%s active=%s dist_emits=%d completed=%s" % [
		d0, dist_mid, d_final, len_m, won, still_active, seen[0], seen[1]])
	if d0 != 0.0:
		lines.append("distance FAIL: start_run did not reset distance to 0"); ok = false
	if dist_mid <= 0.0:
		lines.append("scroll FAIL: distance did not accumulate while running"); ok = false
	if seen[0] < 2:
		lines.append("signal FAIL: distance_changed did not fire per tick"); ok = false
	if not seen[1] or not won or still_active:
		lines.append("win FAIL: crossing the finish line did not complete the run"); ok = false
	if absf(d_final - len_m) > 0.001:
		lines.append("clamp FAIL: final distance %.2f not pinned to finish %.0f" % [d_final, len_m]); ok = false
	# tick_run after completion is a no-op (no further distance / double-win).
	var emits_before: int = seen[0]
	gs.call("tick_run", 1.0 / 60.0)
	if gs.get("distance") != d_final or seen[0] != emits_before:
		lines.append("post-win FAIL: tick_run advanced after the run ended"); ok = false
	else:
		lines.append("finite-level OK: distance scrolls, finish wins, post-win is inert")

	# Finish-line visual parses + connects to the bus without a GPU.
	var FinishS: GDScript = load("res://assets/levels/finish_line.gd")
	if FinishS == null:
		lines.append("finish-line FAIL: finish_line.gd did not load"); ok = false
	else:
		lines.append("finish-line OK: finish_line.gd loads")

	# 10) Gates (#11/#56): math ops + display text + single-trigger, and the spawner
	#     fires the gate the SHIP'S X picks at the crossing line, mutating the swarm.
	var GateS: GDScript = load("res://assets/gates/gate.gd")
	var SpawnerS: GDScript = load("res://assets/gates/gate_spawner.gd")
	var TrackS: GDScript = load("res://assets/levels/track.gd")
	lines.append("gate load: gate=%s spawner=%s track=%s" % [
		GateS != null, SpawnerS != null, TrackS != null])
	if GateS == null or SpawnerS == null or TrackS == null:
		lines.append("gate FAIL: gate/spawner/track scripts did not load"); ok = false
		lines.append("RESULT=FAIL"); _write(lines); return

	var O = GateS.Operation
	# apply() across all four ops on a base count of 10.
	var cases := [[O.ADD, 8.0, 18, "+8"], [O.SUBTRACT, 5.0, 5, "-5"],
		[O.MULTIPLY, 2.0, 20, "×2"], [O.DIVIDE, 2.0, 5, "÷2"]]
	var math_ok := true
	for c in cases:
		var g: Node2D = GateS.new()
		g.call("configure", c[0], c[1], 0.0, 540.0, 270.0)
		var got: int = g.call("apply", 10)
		var txt: String = g.call("get_display_text")
		if got != c[2] or txt != c[3]:
			lines.append("gate-math FAIL: op=%d apply(10)=%d (want %d), text=%s (want %s)" % [
				c[0], got, c[2], txt, c[3]]); math_ok = false; ok = false
		g.free()
	if math_ok:
		lines.append("gate-math OK: +8/-5/×2/÷2 apply + display correct")

	# Single-trigger: trigger() emits gate_passed once, flips has_been_triggered,
	# and a second trigger is a no-op.
	var gp := [0]
	ev_auto.connect("gate_passed", func(_t, _v, _n): gp[0] += 1)
	var gt: Node2D = GateS.new()
	gt.call("configure", O.MULTIPLY, 2.0, 0.0, 540.0, 270.0)
	var first: int = gt.call("trigger", 10)
	var was_flagged: bool = gt.get("has_been_triggered")
	var second: int = gt.call("trigger", 10)
	lines.append("gate-trigger: first=%d second=%d flagged=%s emits=%d" % [
		first, second, was_flagged, gp[0]])
	if first != 20 or not was_flagged or second != 10 or gp[0] != 1:
		lines.append("gate-trigger FAIL: re-trigger not idempotent / no emit"); ok = false
	else:
		lines.append("gate-trigger OK: fires once, emits gate_passed, then inert")
	gt.free()

	# TrackView: an object authored at track_m sits exactly on the trigger line
	# when distance == track_m (the crossing condition the spawner keys on).
	var y_at: float = TrackS.screen_y(135.0, 135.0, 1680.0)
	if absf(y_at - 1680.0) > 0.001:
		lines.append("track FAIL: screen_y at distance==track_m = %.1f (want 1680)" % y_at); ok = false
	else:
		lines.append("track OK: track_m maps onto the trigger line at its distance")

	# Spawner: steer LEFT into formation 1 (×2) then RIGHT into formation 2's right
	# gate (-5). Volume: 20 ->(×2) 40 ->(-5) 35; the unchosen gates never fire.
	var sp: Node2D = SpawnerS.new()
	sp.call("setup", 1680.0)
	gs.call("start_run")                         # reseed projectile_count = 20 + load the level
	sp.call("build_formations", gs.get("active_level").gate_formations)
	sp.call("update", 45.0, 200.0)               # formation @45m crossing, ship on the left
	var after_left: int = gs.get("projectile_count")
	sp.call("update", 90.0, 900.0)               # formation @90m crossing, ship on the right
	var after_right: int = gs.get("projectile_count")
	var trig: int = sp.get("triggers")
	lines.append("spawner: vol 20 ->%d (left ×2) ->%d (right -5), triggers=%d" % [
		after_left, after_right, trig])
	if after_left != 40 or after_right != 35 or trig != 2:
		lines.append("spawner FAIL: wrong gate fired / volume not mutated by ship_x"); ok = false
	else:
		lines.append("spawner OK: ship_x picks the gate; swarm volume reacts")
	sp.free()

	# 11) Glow Battery (#55): start_run charges it to max + emits; drain announces
	#     and clamps; emptying it FAILS the run (run_won=false, grid_collapsed);
	#     and a negative gate drains the battery while a positive one does not.
	var bat := [0, false]            # [glow_battery_changed count, grid_collapsed?]
	ev_auto.connect("glow_battery_changed", func(_v, _m): bat[0] += 1)
	ev_auto.connect("grid_collapsed", func(): bat[1] = true)

	gs.call("start_run")
	var bat_full: float = gs.get("glow_battery")
	var bat_max := 100.0             # GameState.MAX_GLOW_BATTERY (consts aren't get()-able)
	gs.call("drain_battery", 30.0)
	var bat_after: float = gs.get("glow_battery")
	gs.call("drain_battery", 9999.0)           # empty it -> loss
	var bat_zero: float = gs.get("glow_battery")
	var failed_active: bool = gs.get("run_active")
	var failed_won: bool = gs.get("run_won")
	lines.append("battery: full=%.0f/%.0f drain30->%.0f empty->%.0f active=%s won=%s emits=%d collapsed=%s" % [
		bat_full, bat_max, bat_after, bat_zero, failed_active, failed_won, bat[0], bat[1]])
	if bat_full != bat_max or bat_after != bat_max - 30.0:
		lines.append("battery FAIL: start did not charge to max / drain wrong"); ok = false
	if bat_zero != 0.0 or failed_active or failed_won or not bat[1]:
		lines.append("battery FAIL: emptying did not fail the run / collapse the grid"); ok = false
	if bat[0] < 3:                              # start + 2 drains
		lines.append("battery FAIL: glow_battery_changed not emitted on changes"); ok = false
	# Drain after the loss is inert (no further emit / negative battery).
	var emits_pre: int = bat[0]
	gs.call("drain_battery", 10.0)
	if gs.get("glow_battery") != 0.0 or bat[0] != emits_pre:
		lines.append("battery FAIL: drain advanced after the run ended"); ok = false
	else:
		lines.append("battery OK: charge/drain/emit + loss-at-0 + inert post-loss")

	# Negative gate drains the battery; positive gate leaves it full.
	var sp2: Node2D = SpawnerS.new()
	sp2.call("setup", 1680.0)
	gs.call("start_run")                        # battery -> 100, vol -> 20 + load the level
	sp2.call("build_formations", gs.get("active_level").gate_formations)
	sp2.call("update", 45.0, 200.0)             # @45m left = ×2 (positive): vol 40, bat 100
	var bat_pos: float = gs.get("glow_battery")
	sp2.call("update", 90.0, 900.0)             # @90m right = -5 (negative): vol 35, bat drains
	var bat_neg: float = gs.get("glow_battery")
	var vol_neg: int = gs.get("projectile_count")
	lines.append("gate-drain: after +gate bat=%.0f, after -gate bat=%.0f vol=%d" % [
		bat_pos, bat_neg, vol_neg])
	if bat_pos != 100.0 or bat_neg != 75.0 or vol_neg != 35:
		lines.append("gate-drain FAIL: negative gate did not drain (or positive did)"); ok = false
	else:
		lines.append("gate-drain OK: −/÷ gate costs battery, +/× gate does not")
	sp2.free()

	# 12) Glow Battery HUD placement (#75): _build_hud builds the BatteryTrack + BatteryFill,
	#     _on_battery_changed tracks the fill width to the battery fraction, and the battery
	#     strip no longer overlaps the SCORE readout (the green bar was "very much in the way"
	#     on build #11 — now pinned to the top edge, above the SCORE/COMBO row).
	var RunS: GDScript = load("res://assets/levels/run.gd")
	var run: Node2D = RunS.new()
	root.add_child(run)                          # _build_hud add_child()s onto Run
	run.call("_build_hud")
	var hud: CanvasLayer = run.get_node_or_null("HUD")
	var track_n: ColorRect = hud.get_node_or_null("BatteryTrack") if hud else null
	var fill_n: ColorRect = hud.get_node_or_null("BatteryFill") if hud else null
	lines.append("battery-hud: HUD=%s track=%s fill=%s" % [
		hud != null, track_n != null, fill_n != null])
	if hud == null or track_n == null or fill_n == null:
		lines.append("battery-hud FAIL: track/fill ColorRects not built"); ok = false
		lines.append("RESULT=FAIL"); run.free(); _write(lines); return

	# Fill width tracks the battery fraction on glow_battery_changed (full -> half -> empty).
	var bar_w: float = track_n.size.x
	run.call("_on_battery_changed", 100.0, 100.0)
	var w_full: float = fill_n.size.x
	run.call("_on_battery_changed", 50.0, 100.0)
	var w_half: float = fill_n.size.x
	run.call("_on_battery_changed", 0.0, 100.0)
	var w_zero: float = fill_n.size.x
	lines.append("battery-fill: bar_w=%.0f full=%.0f half=%.0f empty=%.0f" % [
		bar_w, w_full, w_half, w_zero])
	if absf(w_full - bar_w) > 0.5 or absf(w_half - bar_w * 0.5) > 0.5 or absf(w_zero) > 0.5:
		lines.append("battery-fill FAIL: fill width does not track the 0..1 fraction"); ok = false
	else:
		lines.append("battery-fill OK: fill tracks the battery fraction across the bar")

	# Non-overlap with SCORE: the battery strip's vertical band must sit entirely ABOVE the
	# SCORE caption (top-left at y=70 in _build_hud) so it never collides with the readout.
	var bat_top: float = track_n.position.y
	var bat_bottom: float = track_n.position.y + track_n.size.y
	var score_cap: Label = null
	for child in hud.get_children():
		if child is Label and child.text == "SCORE":
			score_cap = child
			break
	var score_top: float = score_cap.position.y if score_cap else 70.0
	lines.append("battery-vs-score: bat_band=[%.0f,%.0f] score_top=%.0f" % [
		bat_top, bat_bottom, score_top])
	if score_cap == null:
		lines.append("battery-vs-score FAIL: SCORE label not found in HUD"); ok = false
	elif bat_bottom > score_top:
		lines.append("battery-vs-score FAIL: battery strip overlaps the SCORE readout"); ok = false
	else:
		lines.append("battery-vs-score OK: battery strip clears the SCORE rect")
	run.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## Drive a fresh Fleet at a given swarm volume for `seconds` and return live count.
func _sim_fleet(volume: int, seconds: float) -> int:
	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	var f: Node2D = FleetS.new()
	f.position = Vector2(540.0, 1680.0)     # ship near the bottom, like Run
	f.call("set_volume", volume)
	var dt := 1.0 / 60.0
	var steps := int(seconds / dt)
	for i in steps:
		f.call("step", dt)
	var n: int = f.call("live_count")
	f.free()
	return n


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
