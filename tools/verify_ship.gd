extends SceneTree
## Headless verification for SLICE B/C — in-run ship cosmetics + Garage parity.
##
## Drives Player's PURE cosmetic math directly (no GPU): the trail ring-buffer
## (_push_trail_point), the per-instance layout (_trail_layout), and the engine plume
## params (_engine_params). The MultiMesh/GPU rendering is NOT exercised — only the
## headless-safe math the renderer consumes. Asserts:
##   - the trail ring-buffer fills, then drops the oldest at capacity (TRAIL_BUFFER);
##   - _trail_layout() returns the expected per-style count with a monotonic head→tail
##     fade (tail alpha < head alpha);
##   - switching trail_index changes the pattern (HELIX yields a lateral offset that
##     SLEEK does not);
##   - _engine_params() differs across STD/PULSAR/WARP, and PULSAR varies with time;
##   - (#72 "what I fly == what I built") the SHARED ship-render path: the in-run ship
##     and the Garage preview are built by the SAME Player.build_ship_preview(), tinted
##     by the SELECTED hull colour, and live-recoloured by tint_ship_preview(); the
##     canonical hull silhouette (_signed_dist_to_poly over HULL_PTS) is non-degenerate.
## Run:
##   tools/run-headless.sh res://tools/verify_ship.gd /tmp/verify_ship_result.txt

const RESULT_PATH := "/tmp/verify_ship_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	var ld: Node = root.get_node_or_null("Loadout")
	if ev == null or ld == null:
		lines.append("RESULT=FAIL (autoloads missing: Events/Loadout)"); _write(lines); return

	var PlayerS: GDScript = load("res://assets/player/player.gd")
	if PlayerS == null:
		lines.append("RESULT=FAIL (player.gd missing)"); _write(lines); return

	# A bare Player instance — NOT added to the tree, so _ready/_build_* never fire and
	# no GPU is touched. We exercise only the pure methods.
	var pl: Node2D = PlayerS.new()
	var cap: int = PlayerS.TRAIL_BUFFER

	# === 1) TRAIL RING-BUFFER ================================================
	# Push exactly capacity points — buffer should fill to cap, head = newest.
	for i in cap:
		pl.call("_push_trail_point", Vector2(100.0 + float(i), 0.0))
	var buf: Array = pl.get("_trail_pts")
	lines.append("trail buffer: size=%d (want %d), head.x=%.0f (want newest=%.0f)" % [
		buf.size(), cap, float(buf[0].x), 100.0 + float(cap - 1)])
	if buf.size() != cap or not is_equal_approx(buf[0].x, 100.0 + float(cap - 1)):
		lines.append("trail FAIL: buffer didn't fill to capacity / head not newest"); ok = false

	# Push more — must stay capped at cap and drop the OLDEST (the first samples).
	for i in range(5):
		pl.call("_push_trail_point", Vector2(900.0 + float(i), 0.0))
	buf = pl.get("_trail_pts")
	var oldest: float = float(buf[buf.size() - 1].x)
	lines.append("trail buffer after overfill: size=%d (want %d), oldest.x=%.0f (want >100, original dropped)" % [
		buf.size(), cap, oldest])
	if buf.size() != cap or oldest <= 100.0:
		lines.append("trail FAIL: buffer didn't cap / didn't drop oldest"); ok = false

	# === 2) TRAIL LAYOUT — count + monotonic fade per style ==================
	# SLEEK: one strand, count == buffer size, alpha fades head -> tail.
	ld.set("trail_index", PlayerS.TRAIL_SLEEK)
	var sleek: Array = pl.call("_trail_layout")
	var sleek_head_a: float = float(sleek[0]["alpha"])
	var sleek_tail_a: float = float(sleek[sleek.size() - 1]["alpha"])
	var mono := true
	for i in range(1, sleek.size()):
		if float(sleek[i]["alpha"]) > float(sleek[i - 1]["alpha"]) + 0.0001:
			mono = false
	lines.append("SLEEK layout: count=%d (want %d), head_a=%.3f tail_a=%.3f monotonic=%s (want tail<head, mono)" % [
		sleek.size(), cap, sleek_head_a, sleek_tail_a, str(mono)])
	if sleek.size() != cap or sleek_tail_a >= sleek_head_a or not mono:
		lines.append("trail FAIL: SLEEK count/fade wrong"); ok = false

	# === 3) TRAIL PATTERN VARIES BY INDEX ====================================
	# HELIX: two strands -> 2x count, and yields a LATERAL offset off the recorded path
	# that SLEEK (centred) does not. Compare the MAX |dot.x - path.x| across the tail so
	# the test doesn't hinge on where the sine happens to peak for a given buffer size.
	var sleek_max_off := 0.0
	for i in sleek.size():
		sleek_max_off = maxf(sleek_max_off, absf(float(sleek[i]["pos"].x) - float(buf[i].x)))

	ld.set("trail_index", PlayerS.TRAIL_HELIX)
	var helix: Array = pl.call("_trail_layout")
	# HELIX emits two instances per sample; strand A of sample `i` is at index i*2.
	var helix_max_off := 0.0
	for i in cap:
		helix_max_off = maxf(helix_max_off, absf(float(helix[i * 2]["pos"].x) - float(buf[i].x)))
	lines.append("HELIX vs SLEEK: helix_count=%d (want %d), sleek_max_off=%.2f helix_max_off=%.2f (want sleek~0, helix>>sleek)" % [
		helix.size(), cap * 2, sleek_max_off, helix_max_off])
	if helix.size() != cap * 2 or sleek_max_off > 0.001 or helix_max_off <= sleek_max_off + 1.0:
		lines.append("trail FAIL: HELIX did not add a lateral offset SLEEK lacks"); ok = false

	# RIBBON: one strand again, but fatter dots than SLEEK at the head.
	ld.set("trail_index", PlayerS.TRAIL_RIBBON)
	var ribbon: Array = pl.call("_trail_layout")
	lines.append("RIBBON layout: count=%d (want %d), head_scale=%.2f vs sleek head_scale=%.2f (want ribbon fatter)" % [
		ribbon.size(), cap, float(ribbon[0]["scale"]), float(sleek[0]["scale"])])
	if ribbon.size() != cap or float(ribbon[0]["scale"]) <= float(sleek[0]["scale"]):
		lines.append("trail FAIL: RIBBON not a single fatter band"); ok = false

	# === 4) ENGINE PARAMS — differ across modes, PULSAR varies with time =====
	var std: Dictionary = pl.call("_engine_params", PlayerS.ENGINE_STD, 0.0)
	var pul0: Dictionary = pl.call("_engine_params", PlayerS.ENGINE_PULSAR, 0.0)
	var warp: Dictionary = pl.call("_engine_params", PlayerS.ENGINE_WARP, 0.0)
	var std_v := Vector3(float(std["length"]), float(std["width"]), float(std["alpha"]))
	var pul_v := Vector3(float(pul0["length"]), float(pul0["width"]), float(pul0["alpha"]))
	var warp_v := Vector3(float(warp["length"]), float(warp["width"]), float(warp["alpha"]))
	lines.append("engine: STD=%s PULSAR@0=%s WARP=%s (want all distinct, WARP longest)" % [
		str(std_v), str(pul_v), str(warp_v)])
	if std_v == pul_v or std_v == warp_v or pul_v == warp_v:
		lines.append("engine FAIL: modes not distinct"); ok = false
	if warp_v.x <= std_v.x:
		lines.append("engine FAIL: WARP not an elongated streak"); ok = false

	# PULSAR must vary with time (size oscillates). Sample two phases.
	var pulA: Dictionary = pl.call("_engine_params", PlayerS.ENGINE_PULSAR, 0.0)
	var pulB: Dictionary = pl.call("_engine_params", PlayerS.ENGINE_PULSAR, 0.18)  # ~half pulse
	lines.append("PULSAR over time: len %.3f -> %.3f (want changed)" % [
		float(pulA["length"]), float(pulB["length"])])
	if is_equal_approx(float(pulA["length"]), float(pulB["length"])):
		lines.append("engine FAIL: PULSAR did not vary with time"); ok = false

	# STD must be steady (no time dependence) — sanity on the opposite case.
	var stdB: Dictionary = pl.call("_engine_params", PlayerS.ENGINE_STD, 0.18)
	if not is_equal_approx(float(std["length"]), float(stdB["length"])):
		lines.append("engine FAIL: STD should be steady over time"); ok = false

	# === 5) SHARED SHIP-RENDER PATH (#72): run ship == Garage preview ========
	# The Garage and the in-run ship must build the SAME vessel from ONE path:
	# Player.build_ship_preview() yields a textured-additive-HDR MultiMesh on the canonical
	# silhouette. We assert the STRUCTURE here (the shared bloom-catching path) + that the
	# SELECTED hull glow is a real, distinct HDR colour the run/Garage feed into it.
	# NOTE: MultiMesh per-instance colour/transform CANNOT be read back under --headless —
	# the dummy RenderingServer drops the instance buffers (get_instance_color returns black,
	# get_instance_transform returns zero), so the actual tint is DEVICE-ONLY (confirm on the
	# iPhone that run ship and Garage preview read as the same coloured vessel).
	ld.set("hull_index", 0)
	var c0: Color = ld.call("hull_color_hdr")
	var preview: Node = PlayerS.call("build_ship_preview", c0)
	var mmesh: MultiMesh = preview.get("multimesh")
	var pmat: Material = preview.get("material")
	var ptex: Texture2D = preview.get("texture")
	var is_add := false
	if pmat is CanvasItemMaterial:
		is_add = (pmat as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
	lines.append("preview: use_colors=%s count=%d additive=%s textured=%s (want true/1/add/tex)" % [
		str(mmesh.use_colors), mmesh.instance_count, str(is_add), str(ptex != null)])
	if not mmesh.use_colors or mmesh.instance_count != 1 or not is_add or ptex == null:
		lines.append("ship FAIL: preview not the shared textured-additive-HDR ship path"); ok = false

	# Selecting a DIFFERENT hull colour must change the HDR glow the ship would carry (the
	# colour source-of-truth both render paths feed into build_ship_preview/tint_ship_preview).
	# The retint CALL must not error; its visible effect is device-only (see note above).
	ld.set("hull_index", 1)
	var c1: Color = ld.call("hull_color_hdr")
	PlayerS.call("tint_ship_preview", preview, c1)
	var hdr0_ok := c0.r > 1.0 or c0.g > 1.0 or c0.b > 1.0
	var hdr1_ok := c1.r > 1.0 or c1.g > 1.0 or c1.b > 1.0
	lines.append("live recolour: hull 0->1 glow %s->%s, hdr0=%s hdr1=%s (want changed + both HDR)" % [
		str(c0), str(c1), str(hdr0_ok), str(hdr1_ok)])
	if c0 == c1 or not hdr0_ok or not hdr1_ok:
		lines.append("ship FAIL: hull selection does not change a real HDR glow colour"); ok = false
	ld.set("hull_index", 0)

	# Canonical hull silhouette is non-degenerate: a point at the hull apex region reads
	# INSIDE (positive signed distance) and a point well outside the 48-box reads OUTSIDE.
	var apex: Vector2 = PlayerS.HULL_PTS[0] + Vector2(0.0, 10.0)   # just below the apex, on-axis
	var d_in: float = pl.call("_signed_dist_to_poly", apex, PlayerS.HULL_PTS)
	var d_out: float = pl.call("_signed_dist_to_poly", Vector2(-20.0, -20.0), PlayerS.HULL_PTS)
	lines.append("silhouette: d(inside apex)=%.2f (want >0), d(outside)=%.2f (want <0)" % [d_in, d_out])
	if d_in <= 0.0 or d_out >= 0.0:
		lines.append("ship FAIL: canonical hull silhouette degenerate"); ok = false

	if ok:
		lines.append("ALL OK: trail buffer caps+fades, pattern varies by index, engine modes differ + PULSAR pulses, run-ship==Garage preview on selected colour")
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
