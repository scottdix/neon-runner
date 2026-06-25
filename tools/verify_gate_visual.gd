extends SceneTree
## Headless verification for the #86 gate FAMILY visual taxonomy (Gate, assets/gates/gate.gd):
##   - OP → FAMILY mapping  : Add/Mul math gates derive SPRAY_AUG, Sub/Div derive LANCE_AUG
##                            (_family_for_op), and the map is STABLE across re-derivation.
##   - explicit-family gate : configure_effect(eid, params, fam) keeps its authored family through
##                            _ready (it does NOT get re-derived from an op like a math gate).
##   - family colour guard  : the five _family_color() hues are pairwise DISTINCT, and EVERY one sits
##                            OUTSIDE the enemy RED→MAGENTA→VIOLET danger band (cross-checked against
##                            the Palette.ENEMY_* constants) — a gate/enemy colour-collision guard.
##   - ghosting             : set_ghosted(true) lowers a gate panel's EFFECTIVE brightness AND
##                            saturation vs the un-ghosted family hue (appearance only).
##
## GPU-free where possible (static _family_color + bare-instance math); the ghost check needs the
## panel built, so the gate is add_child()ed and we await its deferred _ready before asserting.
## Scripts are loaded by PATH (no class_name cache under -s). Run:
##   tools/run-headless.sh res://tools/verify_gate_visual.gd /tmp/verify_gate_visual_result.txt

const RESULT_PATH := "/tmp/verify_gate_visual_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var GateS: GDScript = load("res://assets/gates/gate.gd")
	if GateS == null:
		lines.append("RESULT=FAIL (gate.gd missing)"); _write(lines); return

	var pal: Node = root.get_node_or_null("Palette")
	if pal == null:
		lines.append("RESULT=FAIL (Palette autoload missing)"); _write(lines); return

	# Mirror Gate.Operation / Gate.Family ordinals (enums, by contract).
	var ADD := 0
	var SUBTRACT := 1
	var MULTIPLY := 2
	var DIVIDE := 3
	var SPRAY_AUG := 0
	var LANCE_AUG := 1
	var GEOM := 2
	var UTILITY := 3
	var DEVIL := 4

	# 1) Math OP → FAMILY mapping via _family_for_op() on bare instances (logic-only, no _ready).
	var map_ok := true
	var cases := [[ADD, SPRAY_AUG, "+"], [MULTIPLY, SPRAY_AUG, "×"], [SUBTRACT, LANCE_AUG, "−"], [DIVIDE, LANCE_AUG, "÷"]]
	for c in cases:
		var g: Node2D = GateS.new()
		g.set("operation", c[0])
		var fam: int = int(g.call("_family_for_op"))
		# Re-derive: the pure helper must be STABLE (same op → same family every call).
		var fam_again: int = int(g.call("_family_for_op"))
		lines.append("op-map %s: family=%d again=%d (want %d)" % [c[2], fam, fam_again, c[1]])
		if fam != c[1] or fam_again != c[1]:
			map_ok = false
		g.free()
	if not map_ok:
		lines.append("op-map FAIL: Add/Mul must be SPRAY_AUG, Sub/Div must be LANCE_AUG (stable)"); ok = false
	else:
		lines.append("op-map OK: Add/Mul→SPRAY_AUG, Sub/Div→LANCE_AUG, stable across calls")

	# 2) Explicit-family effect gate keeps its family through _ready (NOT re-derived from the op).
	#    Build visuals so _ready runs its family branch; await the deferred _ready first.
	var eg: Node2D = GateS.new()
	eg.call("configure_effect", "overdrive_cache", {}, DEVIL)
	# Steer it to a positive op so a (buggy) re-derive would flip it to SPRAY_AUG — proves it doesn't.
	eg.set("operation", MULTIPLY)
	var fam_before: int = int(eg.get("family"))
	root.add_child(eg)
	await process_frame
	var fam_after: int = int(eg.get("family"))
	lines.append("effect-family: before=%d after-_ready=%d (want %d both)" % [fam_before, fam_after, DEVIL])
	if fam_before != DEVIL or fam_after != DEVIL:
		lines.append("effect-family FAIL: an explicit-family gate must keep its family (no op re-derive)"); ok = false
	else:
		lines.append("effect-family OK: configure_effect family survives _ready")

	# 3) Family colours: all five DISTINCT, and each OUTSIDE the enemy danger band.
	var fams := [SPRAY_AUG, LANCE_AUG, GEOM, UTILITY, DEVIL]
	var names := ["SPRAY", "LANCE", "GEOM", "UTILITY", "DEVIL"]
	var cols: Array[Color] = []
	for f in fams:
		cols.append(GateS.call("_family_color", f))
	# Distinctness: no two family hues equal.
	var distinct_ok := true
	for i in cols.size():
		for j in range(i + 1, cols.size()):
			if cols[i].is_equal_approx(cols[j]):
				lines.append("colour DUP: %s == %s" % [names[i], names[j]]); distinct_ok = false
	if distinct_ok:
		lines.append("colour OK: all 5 family hues pairwise distinct")
	else:
		ok = false

	# Enemy danger band = the reserved RED→MAGENTA→VIOLET hue range the Palette enemies live in.
	# Derive the band empirically from the Palette.ENEMY_* constants (no magic numbers): take the
	# min/max HUE across the enemy set and assert NO family hue lands inside it.
	var enemy_cols := [
		Color(pal.get("ENEMY_ROSE")), Color(pal.get("ENEMY_GLITCH")),
		Color(pal.get("ENEMY_RHOMBUS")), Color(pal.get("ENEMY_RHOMBUS_CORE")),
		Color(pal.get("ENEMY_FRACTAL")), Color(pal.get("ENEMY_FRACTLING")),
	]
	var ehmin := 1.0
	var ehmax := 0.0
	for ec in enemy_cols:
		var h: float = ec.h
		ehmin = minf(ehmin, h)
		ehmax = maxf(ehmax, h)
	lines.append("enemy band: hue [%.3f, %.3f]" % [ehmin, ehmax])
	var band_ok := true
	for i in cols.size():
		var fh: float = cols[i].h
		var inside: bool = fh >= ehmin and fh <= ehmax
		lines.append("  %s hue=%.3f inside-enemy-band=%s" % [names[i], fh, inside])
		if inside:
			band_ok = false
	if band_ok:
		lines.append("band OK: no gate-family hue collides with the enemy danger band")
	else:
		lines.append("band FAIL: a gate family shares the enemy RED→MAGENTA→VIOLET hue band"); ok = false

	# 4) Ghosting lowers EFFECTIVE brightness + saturation vs the un-ghosted family hue.
	#    Needs the panel built — add_child a math gate and await its _ready.
	var gg: Node2D = GateS.new()
	gg.set("operation", ADD)             # SPRAY_AUG green, a saturated bright HDR hue
	root.add_child(gg)
	await process_frame
	var panel: Node = gg.get_node_or_null("Panel")
	if panel == null:
		lines.append("ghost FAIL: panel not built after _ready"); ok = false
	else:
		# Un-ghosted baseline = the family hue the _ready setter applied.
		var lit: Color = Color(panel.get("modulate"))
		gg.call("set_ghosted", true)
		var dim: Color = Color(panel.get("modulate"))
		var lit_v: float = lit.v
		var dim_v: float = dim.v
		var lit_s: float = lit.s
		var dim_s: float = dim.s
		lines.append("ghost: brightness %.2f->%.2f  saturation %.2f->%.2f" % [lit_v, dim_v, lit_s, dim_s])
		if dim_v >= lit_v:
			lines.append("ghost FAIL: ghosting did not lower effective brightness"); ok = false
		if dim_s >= lit_s:
			lines.append("ghost FAIL: ghosting did not lower saturation"); ok = false
		if dim_v < lit_v and dim_s < lit_s:
			lines.append("ghost OK: set_ghosted(true) dims + desaturates the panel")
	gg.free()
	eg.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
