extends SceneTree
## Headless verification for #23 — FeedbackManager (camera trauma-shake + full-screen colour flash).
##
## FeedbackManager keeps every magnitude/displacement decision in PURE methods so we can assert them
## with NO Camera/CanvasLayer/tree (those are only built in _ready, which is DEFERRED under `-s` and
## never fires here — so _process's camera.offset / rect.modulate are guarded no-ops and every bus
## handler runs clean on a bare .new()). We assert:
##   - _shake_offset is ~Vector2.ZERO at trauma 0 and stays within ±MAX_OFFSET for trauma 1 across
##     several t (deterministic bounded pseudo-noise).
##   - _flash_alpha is 1.0 at elapsed 0, 0.0 at/after duration, clamped into 0..1, and monotonically
##     non-increasing.
##   - add_trauma clamps the accumulator to 1.0; a decay _process step lowers it.
##   - every consumed bus handler (trigger_screen_shake/flash, enemy_destroyed, enemy_breached,
##     gate_hijack_blocked, grid_collapsed, gate_passed +/-) runs on a bare .new() without error.
## Run:
##   tools/run-headless.sh res://tools/verify_feedback.gd /tmp/verify_feedback_result.txt

const RESULT_PATH := "/tmp/verify_feedback_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	if ev == null:
		lines.append("RESULT=FAIL (autoload missing: Events)"); _write(lines); return

	var FeedbackS: GDScript = load("res://assets/effects/feedback_manager.gd")
	if FeedbackS == null:
		lines.append("RESULT=FAIL (feedback_manager.gd missing)"); _write(lines); return

	var fb: Node2D = FeedbackS.new()   # bare .new(): no _ready, no camera, no flash rect, no GPU

	# === 1) _shake_offset: zero at trauma 0, bounded at trauma 1 ==============
	var max_off: Vector2 = FeedbackS.MAX_OFFSET
	# At trauma 0 the offset must be ~ZERO for every t (shake = 0*0 = 0).
	var zero_ok := true
	for t in [0.0, 0.13, 1.7, 9.42, 123.4]:
		var o0: Vector2 = fb.call("_shake_offset", 0.0, t)
		if absf(o0.x) > 0.0001 or absf(o0.y) > 0.0001:
			zero_ok = false
	lines.append("shake zero@trauma0: %s (want true)" % zero_ok)
	if not zero_ok:
		lines.append("shake FAIL: nonzero offset at trauma 0"); ok = false

	# At trauma 1 the offset must always stay within ±MAX_OFFSET (|sin| <= 1, shake = 1).
	var bounds_ok := true
	var saw_nonzero := false   # sanity: it actually moves somewhere across the sample
	for i in 40:
		var t := float(i) * 0.137
		var o1: Vector2 = fb.call("_shake_offset", 1.0, t)
		if absf(o1.x) > max_off.x + 0.001 or absf(o1.y) > max_off.y + 0.001:
			bounds_ok = false
		if absf(o1.x) > 0.5 or absf(o1.y) > 0.5:
			saw_nonzero = true
	lines.append("shake bounds@trauma1: within=%s moved=%s (want true,true)" % [bounds_ok, saw_nonzero])
	if not bounds_ok:
		lines.append("shake FAIL: offset exceeded MAX_OFFSET at trauma 1"); ok = false
	if not saw_nonzero:
		lines.append("shake FAIL: offset never moved at trauma 1 (dead shake)"); ok = false

	# === 2) _flash_alpha: endpoints, clamp, monotonic ========================
	var dur := 0.4
	var a_start: float = fb.call("_flash_alpha", 0.0, dur)
	var a_mid: float = fb.call("_flash_alpha", dur * 0.5, dur)
	var a_end: float = fb.call("_flash_alpha", dur, dur)
	var a_over: float = fb.call("_flash_alpha", dur * 2.0, dur)   # past the end → clamps to 0
	lines.append("flash alpha: start=%.3f mid=%.3f end=%.3f over=%.3f (want 1, ~0.5, 0, 0)" % [
		a_start, a_mid, a_end, a_over])
	if absf(a_start - 1.0) > 0.0001:
		lines.append("flash FAIL: alpha at elapsed 0 != 1.0"); ok = false
	if a_end > 0.0001 or a_over > 0.0001:
		lines.append("flash FAIL: alpha not 0 at/after duration"); ok = false
	if a_mid < 0.0 or a_mid > 1.0 or a_start > 1.0 or a_over < 0.0:
		lines.append("flash FAIL: alpha escaped 0..1 clamp"); ok = false

	# Monotonically non-increasing across the flash lifetime.
	var monotonic := true
	var prev := 2.0
	for i in 20:
		var e := dur * (float(i) / 12.0)   # walks from 0 to past duration
		var av: float = fb.call("_flash_alpha", e, dur)
		if av > prev + 0.0001:
			monotonic = false
		prev = av
	lines.append("flash monotonic non-increasing: %s (want true)" % monotonic)
	if not monotonic:
		lines.append("flash FAIL: alpha not monotonic"); ok = false

	# === 3) add_trauma clamps to 1.0; a decay step lowers it =================
	fb.set("_trauma", 0.0)
	fb.call("add_trauma", 0.4)
	var t_after_one: float = fb.get("_trauma")
	fb.call("add_trauma", 5.0)                  # overshoot → must clamp to 1.0
	var t_clamped: float = fb.get("_trauma")
	lines.append("trauma: after_add=%.3f clamped=%.3f (want 0.4, 1.0)" % [t_after_one, t_clamped])
	if absf(t_after_one - 0.4) > 0.0001 or absf(t_clamped - 1.0) > 0.0001:
		lines.append("trauma FAIL: add_trauma did not accumulate/clamp to 1.0"); ok = false

	# A _process step (no camera/rect → guarded) must DECAY trauma toward 0.
	fb.call("_process", 0.1)
	var t_decayed: float = fb.get("_trauma")
	lines.append("trauma decay: %.3f -> %.3f (want lower)" % [t_clamped, t_decayed])
	if t_decayed >= t_clamped:
		lines.append("trauma FAIL: _process did not decay trauma"); ok = false

	# === 4) every bus handler runs clean on a bare .new() (no camera/rect) ====
	# wire() connects the bus so an EMIT would route here too; either path (direct call OR emit) must
	# survive with no camera and no flash rect (guarded). We call the handlers directly to be explicit.
	fb.call("wire")
	fb.call("_on_trigger_screen_shake", 0.6, 0.3)
	fb.call("_on_trigger_screen_flash", Color(1, 1, 1, 0.7), 0.4)
	fb.call("_on_enemy_destroyed", Vector2(300, 400), 50)
	fb.call("_on_enemy_breached", Vector2(540, 1680), 12.0)
	fb.call("_on_gate_hijack_blocked", "multiply", Vector2(540, 1200))
	fb.call("_on_grid_collapsed")
	fb.call("_on_gate_passed", "add", 2.0, 20)       # positive → kick only
	fb.call("_on_gate_passed", "divide", 2.0, 10)    # negative → kick + faint red flash
	# Drive a couple of _process frames now that flash fields are set — still no rect/camera, guarded.
	fb.call("_process", 0.016)
	fb.call("_process", 0.5)
	lines.append("handlers: shake/flash/destroyed/breached/hijack/collapse/gate(+/-) ran without error (no camera/rect)")

	# _is_positive_op vocabulary sanity (matches effect_layer / gate.gd).
	var pos_ok: bool = bool(fb.call("_is_positive_op", "add")) and bool(fb.call("_is_positive_op", "multiply")) \
		and not bool(fb.call("_is_positive_op", "subtract")) and not bool(fb.call("_is_positive_op", "divide"))
	lines.append("is_positive_op: add/multiply true, subtract/divide false = %s" % pos_ok)
	if not pos_ok:
		lines.append("positivity FAIL: _is_positive_op vocabulary wrong"); ok = false

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
