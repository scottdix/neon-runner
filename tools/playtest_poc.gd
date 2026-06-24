extends SceneTree
## Integration PLAYTEST for the session-23 combat-redesign POCs (#86/#87/#88). Unlike the unit
## verifies (which assert pure mapping math), this wires the REAL components — Player, StanceController,
## WalledGauntlet — exactly as run.gd does, then time-steps each Settings.poc_mode through a scripted
## scenario and traces the live GameState over a simulated run. It's the closest thing to a "playtest"
## this headless box can do (no glow/FPS/touch — those are device-only). Verdict -> result file.
##
##   godot --headless -s res://tools/playtest_poc.gd --path .
##
const RESULT_PATH := "/tmp/playtest_poc_result.txt"
const DT := 1.0 / 60.0

# Loaded at RUNTIME (not top-level preload): these scripts reference autoload globals
# (Events/Settings/GameState), which aren't resolvable while THIS -s tool script compiles. load()
# inside the function defers their compile until the autoloads are registered (the documented gotcha).
var PlayerS: GDScript
var ControllerS: GDScript
var GauntletS: GDScript

var _lines: Array[String] = []
var _ok := true

func _initialize() -> void:
	await _run()
	_write()
	quit()

func _run() -> void:
	PlayerS = load("res://assets/player/player.gd")
	ControllerS = load("res://assets/player/stance_controller.gd")
	GauntletS = load("res://assets/obstacles/walled_gauntlet.gd")
	var GS: Node = root.get_node("GameState")
	var EV: Node = root.get_node("Events")
	var ST: Node = root.get_node("Settings")
	await _kinetic(GS, EV, ST)
	await _geom(GS, EV, ST)
	await _gauntlet(GS, EV, ST)

# A clean run boundary so each mode starts fresh.
func _fresh_run(GS: Node, ST: Node, mode: int) -> void:
	ST.set("poc_mode", mode)
	if GS.run_active:
		GS.call("fail_run")          # terminal -> run_active=false
	GS.call("start_run")             # emits game_started -> controller caches the mode

# ---------------------------------------------------------------------------
# POC 2 — KINETIC_CLUTCH: stance follows horizontal motion (move=SPRAY, brake=LANCE)
# ---------------------------------------------------------------------------
func _kinetic(GS: Node, EV: Node, ST: Node) -> void:
	_lines.append("=== POC 2 · KINETIC_CLUTCH (motion-driven stance) ===")
	var player: Node2D = PlayerS.new()
	root.add_child(player)
	var ctrl: Node = ControllerS.new()
	root.add_child(ctrl)
	await process_frame                          # let _ready fire (deferred under -s): bus + bounds
	ctrl.call("set_player", player)
	_fresh_run(GS, ST, ST.PocMode.KINETIC_CLUTCH)

	var timeline: Array[String] = []
	var last := -1
	# Scenario: sweep right (moving), then BRAKE (hold still >0.2s), then jab left (moving again).
	# segment = [target_x, frames]
	var script := [[900.0, 36], [900.0, 36], [150.0, 36]]   # move, brake-at-target, move
	var t := 0.0
	for seg in script:
		player.call("set_target_x", float(seg[0]))
		for _i in int(seg[1]):
			player.call("step", DT)              # derives velocity_x + emits player_steered
			ctrl.call("_process", DT)            # maps velocity -> GameState.set_stance
			t += DT
			var s: int = int(GS.stance)
			if s != last:
				var vx: float = float(player.call("velocity_x"))
				timeline.append("  t=%.2fs  vx=%+7.1f  -> %s" % [t, vx, _stance_name(GS, s)])
				last = s
	for ln in timeline:
		_lines.append(ln)
	# Expect at least: SPRAY (moving) -> LANCE (braked) -> SPRAY (moving). 3+ transitions.
	if timeline.size() >= 3:
		_lines.append("  KINETIC OK: motion flips SPRAY, a sustained brake commits LANCE, motion releases it")
	else:
		_lines.append("  KINETIC FAIL: expected move->brake->move to flip stance >=3 times, got %d" % timeline.size())
		_ok = false
	player.free(); ctrl.free()
	_lines.append("")

# ---------------------------------------------------------------------------
# POC 4 — GEOM_OVERDRIVE: triple-tap burns kill-fed charge for a LANCE smart-bomb
# ---------------------------------------------------------------------------
func _geom(GS: Node, EV: Node, ST: Node) -> void:
	_lines.append("=== POC 4 · GEOM_OVERDRIVE (resource-fueled overdrive) ===")
	var ctrl: Node = ControllerS.new()
	root.add_child(ctrl)
	await process_frame
	_fresh_run(GS, ST, ST.PocMode.GEOM_OVERDRIVE)

	_lines.append("  default: stance=%s overdrive=%s charge=%.0f" % [
		_stance_name(GS, int(GS.stance)), GS.overdrive_active, float(GS.geom_charge)])

	# Kills feed the gauge.
	GS.call("add_geom", 100.0)
	_lines.append("  after kills feed: charge=%.0f" % float(GS.geom_charge))

	# Triple-tap fires the overdrive toggle (Player emits this; we hit the bus directly).
	EV.call("emit_signal", "overdrive_toggle_requested")
	_lines.append("  TRIPLE-TAP -> stance=%s overdrive=%s (LANCE smart-bomb engaged)" % [
		_stance_name(GS, int(GS.stance)), GS.overdrive_active])
	if not GS.overdrive_active or int(GS.stance) != GS.Stance.LANCE:
		_lines.append("  GEOM FAIL: triple-tap with charge did not enter LANCE overdrive"); _ok = false

	# Burn it down: drain 40/s should empty ~2.5s and auto-revert to SPRAY.
	var t := 0.0; var reverted_at := -1.0; var ticks := 0
	while ticks < 600:                            # cap 10s
		ctrl.call("_process", DT); t += DT; ticks += 1
		if ticks % 30 == 0 and GS.overdrive_active:
			_lines.append("  t=%.2fs  charge=%.1f  stance=%s" % [t, float(GS.geom_charge), _stance_name(GS, int(GS.stance))])
		if not GS.overdrive_active:
			reverted_at = t; break
	if reverted_at > 0.0 and int(GS.stance) == GS.Stance.SPRAY:
		_lines.append("  drained @t=%.2fs -> auto-revert to SPRAY (expected ~2.5s)" % reverted_at)
	else:
		_lines.append("  GEOM FAIL: overdrive did not auto-revert on empty"); _ok = false

	# Early manual exit: refill, on, off.
	GS.call("add_geom", 100.0)
	EV.call("emit_signal", "overdrive_toggle_requested")     # on
	var on_stance := int(GS.stance)
	EV.call("emit_signal", "overdrive_toggle_requested")     # off (second triple-tap)
	_lines.append("  manual: tap-on stance=%s -> tap-off stance=%s overdrive=%s" % [
		_stance_name(GS, on_stance), _stance_name(GS, int(GS.stance)), GS.overdrive_active])
	if GS.overdrive_active or int(GS.stance) != GS.Stance.SPRAY:
		_lines.append("  GEOM FAIL: a second triple-tap did not exit overdrive early"); _ok = false
	else:
		_lines.append("  GEOM OK: charge-gated entry, timed burn, auto-revert, manual early-exit")
	ctrl.free()
	_lines.append("")

# ---------------------------------------------------------------------------
# Walled Gauntlet (#86): 7-s lane-commitment corridor
# ---------------------------------------------------------------------------
func _gauntlet(GS: Node, EV: Node, ST: Node) -> void:
	_lines.append("=== WALLED GAUNTLET (#86 · 7-second lane commitment) ===")
	# Stub injection targets that just count what the gauntlet spawns into each lane.
	var spawns := {"add": 0, "split": 0, "kinds": []}
	var targets := _SpawnSpy.new(); targets.log_ref = spawns
	var gates := _GateSpy.new(); gates.log_ref = spawns
	var g: Node2D = GauntletS.new()
	g.call("set_targets", targets)
	g.call("set_gates", gates)
	g.call("set_ship_line", 1680.0)
	g.call("set_start_m", 80.0)
	root.add_child(g)
	await process_frame

	# Record lane-clamp emissions.
	var clamps: Array = []
	EV.connect("lane_clamp_changed", func(mn: float, mx: float) -> void: clamps.append(Vector2(mn, mx)))

	_fresh_run(GS, ST, ST.PocMode.LEGACY)
	# Ship sits LEFT of centre (x=200) when the wall hits -> should commit the LEFT lane.
	EV.call("emit_signal", "player_steered", 200.0, 0.1)

	# Simulate the scroll: feed distance 0 -> 150 m and step the gauntlet each frame.
	var len_m: float = g.LEN_M
	var engaged_at := -1.0; var released_at := -1.0
	var d := 0.0
	while d <= 80.0 + len_m + 10.0:
		GS.set("distance", d)
		g.call("_step", d, 200.0)
		if engaged_at < 0.0 and bool(g.call("is_trapping")):
			engaged_at = d
			_lines.append("  ENGAGE @ %.0f m  committed_lane=%s" % [d, _lane_name(int(g.call("committed_lane")))])
		if engaged_at > 0.0 and released_at < 0.0 and not bool(g.call("is_trapping")) and int(g.call("committed_lane")) == -1:
			released_at = d
		d += 8.0 * DT * 4.0          # 8 m/s, ×4 to keep the loop short (sampling, not real-time)

	var trap_m: float = (released_at - engaged_at) if released_at > 0.0 else -1.0
	var trap_secs: float = trap_m / 8.0
	_lines.append("  trap span: %.0f m  (= %.1f s at 8 m/s; spec = 7.0 s)" % [trap_m, trap_secs])
	_lines.append("  barrier height: %.0f px  (LEN_M %.0f × PPM)" % [float(g.call("barrier_height_px")), len_m])
	_lines.append("  occupants spawned: %d enemies %s | lane gates: %d" % [
		spawns["add"], str(spawns["kinds"]), spawns["split"]])
	if clamps.size() >= 2:
		_lines.append("  lane clamp: trap=[%.0f..%.0f]  release=[%.0f..%.0f]" % [
			clamps[0].x, clamps[0].y, clamps[-1].x, clamps[-1].y])

	var pass_trap: bool = absf(trap_secs - 7.0) < 0.6
	var pass_spawn: bool = int(spawns["add"]) == 5 and int(spawns["split"]) == 1
	var pass_lane: bool = clamps.size() >= 2 and clamps[0].x == 0.0 and clamps[-1].y == 1080.0
	if pass_trap and pass_spawn and pass_lane:
		_lines.append("  GAUNTLET OK: ~7s trap, LEFT-lane clamp + release, 4 glitch + 1 rhombus + 1 split gate")
	else:
		_lines.append("  GAUNTLET FAIL: trap=%s spawn=%s lane=%s" % [pass_trap, pass_spawn, pass_lane]); _ok = false
	g.free()
	_lines.append("")

# --- helpers ---------------------------------------------------------------
func _stance_name(GS: Node, s: int) -> String:
	return "SPRAY" if s == GS.Stance.SPRAY else "LANCE"

func _lane_name(l: int) -> String:
	return "LEFT" if l == 0 else ("RIGHT" if l == 1 else "none")

func _write() -> void:
	_lines.append("RESULT=%s" % ("PASS" if _ok else "FAIL"))
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("\n".join(_lines))

# Spy stand-ins for Targets / GateSpawner that just record the gauntlet's spawn calls.
class _SpawnSpy extends Node2D:
	var log_ref: Dictionary
	func spawn_add(cfg: Dictionary) -> void:
		log_ref["add"] += 1
		log_ref["kinds"].append(cfg.get("kind", "?"))

class _GateSpy extends Node2D:
	var log_ref: Dictionary
	func spawn_split(_m: float, _a: String, _av: float, _b: String, _bv: float) -> void:
		log_ref["split"] += 1
