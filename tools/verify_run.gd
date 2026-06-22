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
