extends SceneTree
## Headless structural + cost check for the glow POC (#6).
##
## Headless has no GPU, so this does NOT prove the glow looks right or the real frame
## rate (that's VNC / on-device #47). It DOES prove: the scene instantiates without
## parse/runtime errors; the fleet is one MultiMesh with the requested instance count;
## and the per-frame CPU logic stays ~flat when the fleet scales 10x (the D3 claim that
## cost is O(enemies), not O(fleet)). Verdict -> /tmp/verify_poc_result.txt.

const RESULT_PATH := "/tmp/verify_poc_result.txt"
const SCENE := "res://assets/poc/glow_stress.tscn"

var _scene: Node = null
var _frame := 0
var _phase := 0
var _small_us := 0.0
var _big_us := 0.0
var _lines: Array[String] = []
var _ok := true

func _initialize() -> void:
	var packed: Variant = load(SCENE)
	if packed == null:
		_fail("scene_load=FAIL (could not load %s)" % SCENE)
		return
	_scene = packed.instantiate()
	if _scene == null:
		_fail("scene_instantiate=FAIL")
		return
	root.add_child(_scene)
	_lines.append("scene_load=OK")

func _process(_delta: float) -> bool:
	if _scene == null:
		return true
	_frame += 1
	if _frame < 8:
		return false   # let it warm up / settle the logic EMA

	if not _scene.has_method("get_debug_stats"):
		_fail("get_debug_stats=MISSING")
		return true
	var s: Dictionary = _scene.get_debug_stats()

	if _phase == 0:
		_check("world_environment", s.get("has_world_environment", false) == true)
		_check("fleet_one_draw_call", s.get("draw_calls_for_fleet", -1) == 1)
		_check("mm_instances_match", s.get("mm_instances", -1) == s.get("fleet_count", -2))
		_small_us = s.get("logic_us_avg", 0.0)
		_lines.append("small: fleet=%d logic=%.1fus" % [s.get("fleet_count", -1), _small_us])
		_scene.call("set_fleet_count", 40000)   # 10x stress
		_phase = 1
		_frame = 0
		return false
	else:
		_check("mm_instances_40k", s.get("mm_instances", -1) == 40000)
		_big_us = s.get("logic_us_avg", 0.0)
		_lines.append("big:   fleet=%d logic=%.1fus" % [s.get("fleet_count", -1), _big_us])
		# Logic cost must not scale with fleet: allow generous 3x headroom for noise.
		var flat := _big_us <= maxf(_small_us * 3.0, _small_us + 250.0)
		_check("logic_cost_flat_across_10x_fleet", flat)
		_finish()
		return true
	return false

func _check(label: String, cond: bool) -> void:
	_lines.append("%s=%s" % [label, "OK" if cond else "FAIL"])
	if not cond:
		_ok = false

func _fail(msg: String) -> void:
	_lines.append(msg)
	_ok = false
	_finish()

func _finish() -> void:
	_lines.append("RESULT=%s" % ("PASS" if _ok else "FAIL"))
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("\n".join(_lines))
	quit(0 if _ok else 1)
