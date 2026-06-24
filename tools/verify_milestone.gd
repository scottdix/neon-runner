extends SceneTree
## Headless verification for #28 — MILESTONE CELEBRATION (milestone_banner.gd).
##
## The banner keeps its only decision — which milestones a count jump crossed — in a PURE method
## (_crossed) callable on a bare .new() with NO tree/GPU/Engine touch. The banner Label + the
## Engine.time_scale slow-mo are guarded behind _is_live (set true only in _ready, which is DEFERRED
## under `-s` and never fires here), so a .new() emits the contract signal but mutates nothing global.
## We assert:
##   - _crossed math: single-cross, off-by-one boundary (prev<m<=now), multi-cross in one jump, and
##     a decline ⇒ empty.
##   - driving _on_projectile_count_changed through a rising-with-noise sequence emits each milestone
##     EXACTLY once (repeats + a dip never re-fire it), counted off a real Events.milestone_reached
##     listener.
##   - game_started RESETS so the same milestone can fire a second time in a fresh run.
##   - _is_live stayed false on the bare .new() (no banner/time_scale path was taken).
## Run:
##   tools/run-headless.sh res://tools/verify_milestone.gd /tmp/verify_milestone_result.txt

const RESULT_PATH := "/tmp/verify_milestone_result.txt"

# Listener tallies (milestone value -> emit count) captured off the real Events bus.
var _emits: Dictionary = {}


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	var pal: Node = root.get_node_or_null("Palette")
	if ev == null or pal == null:
		lines.append("RESULT=FAIL (autoloads missing: Events/Palette)"); _write(lines); return

	var BannerS: GDScript = load("res://assets/effects/milestone_banner.gd")
	if BannerS == null:
		lines.append("RESULT=FAIL (milestone_banner.gd missing)"); _write(lines); return

	var mb: CanvasLayer = BannerS.new()   # bare .new(): no _ready ⇒ _is_live false, no GPU/time_scale

	# Real bus listener so we count CONTRACT emissions, not internal state. Use the fetched
	# `ev` node ref, NOT a bare `Events` identifier: the `-s` main script is compiled before the
	# autoload globals register, so a bare `Events` here is a compile error (it resolves fine
	# inside later-loaded classes like the banner). Palette.* works because it's const resolution.
	ev.connect("milestone_reached", _on_milestone_reached)

	# === 1) _crossed PURE math ===============================================
	var c1: Array = mb.call("_crossed", 20, 100)      # exactly reaches 100 (m <= now boundary)
	var c2: Array = mb.call("_crossed", 99, 101)      # off-by-one boundary around 100
	var c3: Array = mb.call("_crossed", 480, 1200)    # one jump vaults past 500 AND 1000, in order
	var c4: Array = mb.call("_crossed", 600, 300)     # a decline crosses nothing
	var c5: Array = mb.call("_crossed", 1000, 1000)   # holding AT a milestone re-crosses nothing

	lines.append("_crossed(20,100)=%s (want [100])" % str(c1))
	if c1 != [100]:
		lines.append("crossed FAIL: did not catch the m<=now boundary at 100"); ok = false
	lines.append("_crossed(99,101)=%s (want [100])" % str(c2))
	if c2 != [100]:
		lines.append("crossed FAIL: off-by-one around 100"); ok = false
	lines.append("_crossed(480,1200)=%s (want [500,1000])" % str(c3))
	if c3 != [500, 1000]:
		lines.append("crossed FAIL: multi-cross not returned in ascending order"); ok = false
	lines.append("_crossed(600,300)=%s (want [])" % str(c4))
	if c4 != []:
		lines.append("crossed FAIL: a decline crossed something"); ok = false
	lines.append("_crossed(1000,1000)=%s (want [])" % str(c5))
	if c5 != []:
		lines.append("crossed FAIL: holding at a milestone re-crossed it"); ok = false

	# === 2) handler fires each milestone EXACTLY once across noise ============
	# Rising sequence with repeats AND a dip; each of 100/500/1000 must emit once and only once.
	_emits.clear()
	var seq: Array[int] = [50, 100, 100, 120, 90, 130, 480, 520, 520, 700, 999, 1000, 1100, 1000, 1300]
	for n in seq:
		mb.call("_on_projectile_count_changed", n)
	lines.append("emits after rising-with-noise run: 100=%d 500=%d 1000=%d (want 1,1,1)" % [
		int(_emits.get(100, 0)), int(_emits.get(500, 0)), int(_emits.get(1000, 0))])
	if int(_emits.get(100, 0)) != 1 or int(_emits.get(500, 0)) != 1 or int(_emits.get(1000, 0)) != 1:
		lines.append("once FAIL: a milestone fired ≠ once across repeats/declines"); ok = false
	if _emits.size() != 3:
		lines.append("once FAIL: an unexpected milestone value emitted (%s)" % str(_emits.keys())); ok = false

	# === 3) game_started RESETS → same milestones can fire again =============
	mb.call("_on_game_started")
	_emits.clear()
	# A single jump in the fresh run vaults past all three at once.
	mb.call("_on_projectile_count_changed", 1200)
	lines.append("after reset, one jump to 1200 re-fires: 100=%d 500=%d 1000=%d (want 1,1,1)" % [
		int(_emits.get(100, 0)), int(_emits.get(500, 0)), int(_emits.get(1000, 0))])
	if int(_emits.get(100, 0)) != 1 or int(_emits.get(500, 0)) != 1 or int(_emits.get(1000, 0)) != 1:
		lines.append("reset FAIL: game_started did not re-arm the milestones"); ok = false

	# === 4) bare .new() stayed headless-safe (no live banner/time_scale) =====
	if bool(mb.get("_is_live")):
		lines.append("live FAIL: _is_live true on a bare .new() (would touch GPU/time_scale)"); ok = false
	if not is_equal_approx(Engine.time_scale, 1.0):
		lines.append("live FAIL: Engine.time_scale was mutated headless (=%f)" % Engine.time_scale); ok = false
	lines.append("headless-safe: _is_live=%s, Engine.time_scale=%f (want false, 1.0)" % [
		bool(mb.get("_is_live")), Engine.time_scale])

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _on_milestone_reached(count: int) -> void:
	_emits[count] = int(_emits.get(count, 0)) + 1


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
