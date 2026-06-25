extends SceneTree
## Headless verification for HORDE P0 VISUALS (#90):
##   - The enemy diamond texture is now a HOLLOW vector outline: a TRANSPARENT centre pixel + an
##     OPAQUE rim pixel (the glow-safe technique — transparent core emits nothing additively).
##   - Targets._enemy_color returns the new HORDE hues: HOT PINK for GLITCH, NEON GREEN for RHOMBUS,
##     VIOLET still for FRACTAL (and all HDR > 1 so they bloom).
##   - LaneArena geometry still splits at CENTER_X after thinning BARRIER_HALF (lane_bounds_for /
##     side_of), and the divider is now the cool DIVIDER_CYAN (HDR, cyan-leaning).
##
## GPU-free: builds the textures on BARE `.new()` instances and reads pixels via get_image(); drives
## the pure colour/geometry helpers; writes a verdict file the runner polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_splice_visuals.gd /tmp/verify_splice_visuals_result.txt

const RESULT_PATH := "/tmp/verify_splice_visuals_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# Scripts load.
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var ArenaS: GDScript = load("res://assets/obstacles/lane_arena.gd")
	if TargetsS == null or ArenaS == null:
		lines.append("RESULT=FAIL (targets/lane_arena scripts missing)"); _write(lines); return

	var pal: Node = root.get_node_or_null("Palette")
	if pal == null:
		lines.append("RESULT=FAIL (Palette autoload missing)"); _write(lines); return

	# KIND enum (declared bare in targets.gd): GLITCH=0, RHOMBUS=1, FRACTAL=2, FRACTLING=3, LANEBOSS=4.
	var KIND_GLITCH := 0
	var KIND_RHOMBUS := 1
	var KIND_FRACTAL := 2

	var tg: Node2D = TargetsS.new()

	# ---- 1) Hollow diamond texture: transparent CENTRE + opaque RIM -----------------------------
	var dtex: Texture2D = tg.call("_make_diamond_texture")
	if dtex == null:
		lines.append("FAIL: _make_diamond_texture returned null"); ok = false
		lines.append("RESULT=FAIL"); _write(lines); tg.free(); return
	var dimg: Image = dtex.get_image()
	var dn: int = dimg.get_width()
	var dc: int = int((dn - 1) * 0.5)
	# Centre pixel must be fully TRANSPARENT (the hard negative-space core — hollow outline).
	var centre_a: float = dimg.get_pixel(dc, dc).a
	# Walk OUT along the +x axis from the centre to find the brightest (rim) alpha — it must be opaque.
	var max_rim_a := 0.0
	for x in range(dc, dn):
		var av: float = dimg.get_pixel(x, dc).a
		if av > max_rim_a:
			max_rim_a = av
	lines.append("1 hollow-diamond: tex=%dx%d centre.a=%.3f max_rim.a=%.3f (want centre~0, rim~1)" % [
		dn, dn, centre_a, max_rim_a])
	if centre_a > 0.001:
		lines.append("FAIL: diamond centre is not transparent — core not hollowed (would bloom-bleed)"); ok = false
	# The diamond rim contour (manhattan == radius, radius half-integer) falls between integer pixels, so
	# the brightest on-grid rim pixel tops out ~0.9 (never exactly 1.0) — a genuinely bright, opaque rim.
	if max_rim_a < 0.8:
		lines.append("FAIL: no bright rim pixel found — the outline rim is missing/too dim"); ok = false
	if ok:
		lines.append("1 OK: enemy diamond is a hollow vector outline (transparent core + opaque rim)")

	# ---- 2) Enemy colours: HOT PINK Glitch, NEON GREEN Rhombus, VIOLET Fractal (all HDR) --------
	var c_glitch: Color = tg.call("_enemy_color", {"kind": KIND_GLITCH})
	var c_rhomb: Color = tg.call("_enemy_color", {"kind": KIND_RHOMBUS})
	var c_fract: Color = tg.call("_enemy_color", {"kind": KIND_FRACTAL})
	lines.append("2 colours: glitch=%s rhombus=%s fractal=%s" % [str(c_glitch), str(c_rhomb), str(c_fract)])
	# GLITCH must equal the palette pink AND read as pink: high R + high B, low G.
	if c_glitch != pal.get("ENEMY_GLITCH"):
		lines.append("FAIL: GLITCH colour does not match Palette.ENEMY_GLITCH"); ok = false
	if not (c_glitch.r > 1.0 and c_glitch.b > 1.0 and c_glitch.g < 1.0):
		lines.append("FAIL: GLITCH is not a HDR hot-pink (need R>1, B>1, G<1)"); ok = false
	# RHOMBUS must equal the palette green AND read as green: high G, low R, low B.
	if c_rhomb != pal.get("ENEMY_RHOMBUS"):
		lines.append("FAIL: RHOMBUS colour does not match Palette.ENEMY_RHOMBUS"); ok = false
	if not (c_rhomb.g > 1.0 and c_rhomb.r < 1.0 and c_rhomb.b < 1.0):
		lines.append("FAIL: RHOMBUS is not a HDR neon-green (need G>1, R<1, B<1)"); ok = false
	# FRACTAL stays violet (high B, high-ish R, low G) and matches the (unchanged) palette const.
	if c_fract != pal.get("ENEMY_FRACTAL"):
		lines.append("FAIL: FRACTAL colour no longer matches Palette.ENEMY_FRACTAL (should be unchanged violet)"); ok = false
	if not (c_fract.b > 1.0 and c_fract.r > 1.0 and c_fract.g < 1.0):
		lines.append("FAIL: FRACTAL is not a HDR violet"); ok = false
	if ok:
		lines.append("2 OK: Glitch hot-pink, Rhombus neon-green, Fractal violet — all HDR, all match palette")
	tg.free()

	# ---- 3) Divider geometry still splits at CENTER_X after thinning ----------------------------
	var ar: Node2D = ArenaS.new()
	root.add_child(ar)                                     # _ready builds _design + the MultiMesh
	await process_frame                                    # _ready is deferred under -s
	var cx: float = ArenaS.CENTER_X
	var bh: float = ArenaS.BARRIER_HALF
	var gap: float = ArenaS.LANE_GAP
	lines.append("3 divider: CENTER_X=%.0f BARRIER_HALF=%.1f LANE_GAP=%.0f (thinned)" % [cx, bh, gap])
	if bh > 12.0:
		lines.append("FAIL: BARRIER_HALF not thinned to ~10 (still a fat wall)"); ok = false
	# side_of splits strictly at CENTER_X.
	var s_left: int = ArenaS.side_of(cx - 1.0)
	var s_right: int = ArenaS.side_of(cx + 1.0)
	if s_left != 0 or s_right != 1:
		lines.append("FAIL: side_of no longer splits at CENTER_X (%d / %d)" % [s_left, s_right]); ok = false
	# lane_bounds_for: LEFT lane ends inside the centre, RIGHT lane begins outside it, both held clear by
	# BARRIER_HALF + LANE_GAP off the centre — i.e. the split is anchored on CENTER_X.
	var lb: Vector2 = ar.call("lane_bounds_for", 0)
	var rb: Vector2 = ar.call("lane_bounds_for", 1)
	lines.append("3 lanes: left=%s right=%s (inner=%.0f outer=%.0f)" % [
		str(lb), str(rb), cx - (bh + gap), cx + (bh + gap)])
	if absf(lb.y - (cx - (bh + gap))) > 0.01 or absf(rb.x - (cx + (bh + gap))) > 0.01:
		lines.append("FAIL: lane_bounds_for is not anchored on CENTER_X after thinning"); ok = false
	if lb.y >= cx or rb.x <= cx:
		lines.append("FAIL: lanes do not straddle CENTER_X"); ok = false
	if ok:
		lines.append("3 OK: divider thinned but lane_bounds_for / side_of still split at CENTER_X")

	# ---- 4) Divider tint is the cool DIVIDER_CYAN (HDR, cyan-leaning) ---------------------------
	var dc_col: Color = pal.get("DIVIDER_CYAN")
	lines.append("4 divider-tint: DIVIDER_CYAN=%s (want cyan: B>1, G>1, R<1)" % str(dc_col))
	if not (dc_col.b > 1.0 and dc_col.g > 1.0 and dc_col.r < 1.0):
		lines.append("FAIL: DIVIDER_CYAN is not a HDR cool cyan/electric-blue"); ok = false
	else:
		lines.append("4 OK: divider is a HDR cool cyan — contrasts the pink/green enemies")
	ar.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
