extends SceneTree
## Headless verification for enemy READABILITY — the four Entropy archetypes must stay
## visually tellable apart, and the armor tell must read as a distinct colour (#88).
##
## Direction (HORDE recolour, #90): the archetypes split by HUE so they read against the cool
## cyan divider — Glitch = HOT PINK, Rhombus = NEON GREEN (the lane bruiser), Fractal = VIOLET,
## and Fractling is a PALER SIBLING of the Glitch pink (same hot-pink fodder family). This verify
## is the regression GUARD: it pins the pink fodder family apart from the green/violet archetypes
## by a minimum hue distance so a future Palette edit can't silently merge the green or violet back
## into the pink, pins the two same-family pinks (Glitch/Fractling) apart by INTENSITY so the
## fodder shard stays tellable from its parent, and pins the armored render path to a DIFFERENT
## colour than the unarmored base.
##
## GPU-free: pure colour math on the real Palette constants + a bare Targets instance, then
## writes a verdict file the runner polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_readability.gd /tmp/verify_readability_result.txt
##
## Asserts:
##   1. The pink fodder family (Glitch/Fractling) is hue-separated from the non-pink archetypes
##      (Rhombus green, Fractal violet) beyond a hue-distance threshold (regression guard against
##      a palette re-merge); Glitch vs Fractling — the SAME pink family — are guarded by INTENSITY
##      instead, since they share a hue by design. HDR colours (RGB > 1.0) are normalised to LDR
##      before .h, since hue of an unclamped HDR colour is meaningless — the screen sees the
##      tone-mapped/clamped hue.
##   2. Targets._enemy_color returns the distinct Palette constant per kind (the four kinds
##      map to four different colours, matching the per-kind constants).
##   3. The armored render path (armor > 0) produces a DIFFERENT colour than armor == 0 of
##      the same base — replicating _render()'s lerp toward ENEMY_RHOMBUS_CORE.

const RESULT_PATH := "/tmp/verify_readability_result.txt"

## Minimum pairwise hue separation (in normalised hue units, 0..1 wrapping). The four
## archetypes are deliberately one rose/magenta family, so this is intentionally modest —
## it only has to catch a future edit that collapses two of them to the SAME hue.
const HUE_SEPARATION_MIN := 0.015

## Minimum intensity (max-channel HDR brightness) gap between Glitch and its Fractling shard.
## They share a hue by design (Fractling = "a paler sibling of the Glitch pink" — palette.gd), so
## this is the axis that keeps them tellable apart. Glitch peaks at 3.9, Fractling at 3.4 (gap 0.5);
## the threshold is set to that gap so it still catches an edit that equalised their intensity.
const INTENSITY_SEPARATION_MIN := 0.5

## Replicates Targets._render()'s armor-tell blend weight: a_w = clampf(0.18 * armor, 0, 0.6).
const ARMOR_BLEND_PER := 0.18
const ARMOR_BLEND_MAX := 0.6


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var PaletteS: GDScript = load("res://autoload/palette.gd")
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	if PaletteS == null or TargetsS == null:
		lines.append("RESULT=FAIL (palette or targets script missing)"); _write(lines); return
	var pal: Node = root.get_node_or_null("Palette")
	if pal == null:
		lines.append("RESULT=FAIL (Palette autoload missing)"); _write(lines); return

	# The four archetype hues, by name, read off the live Palette autoload.
	var hues := {
		"GLITCH": pal.get("ENEMY_GLITCH"),
		"RHOMBUS": pal.get("ENEMY_RHOMBUS"),
		"FRACTAL": pal.get("ENEMY_FRACTAL"),
		"FRACTLING": pal.get("ENEMY_FRACTLING"),
	}

	# --- 1) Archetype separation (regression guard) -----------------------------
	# The palette tells the four archetypes apart on TWO axes, not one (HORDE recolour #90): the three
	# colour FAMILIES — Glitch PINK, Rhombus GREEN, Fractal VIOLET — are DISTINCT hues, while FRACTLING
	# is deliberately the GLITCH PINK at LOWER INTENSITY (a "paler sibling of the Glitch pink" —
	# palette.gd), i.e. same hue family, different brightness. So the guard is split: (a) the three
	# distinct-hue families must stay pairwise hue-separated (Fractling counted in the pink family via
	# Glitch), and (b) Glitch vs Fractling must stay separated by brightness/value (their hue distance
	# is ~0 by design). Normalise each HDR colour to LDR before reading .h: an unclamped HDR Color's
	# hue is not what the screen shows (bloom tone-maps it), so divide by the max channel first.
	var names: Array = hues.keys()
	for i in names.size():
		var ci: float = _hue_of(hues[names[i]])
		lines.append("hue %s = %.3f (normalised)" % [names[i], ci])
	# (a) Hue separation across the three DISTINCT-hue families. Fractling is excluded as its own
	# entry — it shares the Glitch pink hue on purpose (guarded by intensity below) — but Glitch
	# stands in for the whole pink family, so a green/violet that drifted onto the pink hue is caught.
	var hue_names: Array = ["GLITCH", "RHOMBUS", "FRACTAL"]
	var min_pair := ""
	var min_dist := 2.0
	for i in hue_names.size():
		for j in range(i + 1, hue_names.size()):
			var hi: float = _hue_of(hues[hue_names[i]])
			var hj: float = _hue_of(hues[hue_names[j]])
			var d: float = _hue_dist(hi, hj)
			if d < min_dist:
				min_dist = d
				min_pair = "%s/%s" % [hue_names[i], hue_names[j]]
	lines.append("closest distinct-hue pair %s at hue-dist %.4f (min allowed %.4f)" % [
		min_pair, min_dist, HUE_SEPARATION_MIN])
	if min_dist < HUE_SEPARATION_MIN:
		lines.append("separation FAIL: two distinct-hue families share ~the same hue — a palette edit re-merged them"); ok = false
	else:
		lines.append("separation OK: Glitch(pink)/Rhombus(green)/Fractal(violet) hues are pairwise distinct")
	# (b) Glitch vs Fractling: same pink hue by design, so they must instead read apart by INTENSITY
	# (max-channel brightness). Guards the "paler sibling" relationship — a palette edit that
	# equalised their intensity would collapse them on screen even though their hue is shared.
	var glitch_v: float = _intensity(hues["GLITCH"])
	var fractling_v: float = _intensity(hues["FRACTLING"])
	var v_gap: float = absf(glitch_v - fractling_v)
	lines.append("Glitch vs Fractling intensity %.2f vs %.2f (gap %.2f, min allowed %.2f)" % [
		glitch_v, fractling_v, v_gap, INTENSITY_SEPARATION_MIN])
	if v_gap < INTENSITY_SEPARATION_MIN:
		lines.append("intensity FAIL: Fractling is no longer a paler shade of the Glitch pink — they read alike"); ok = false
	else:
		lines.append("intensity OK: Fractling reads as a paler sibling of the Glitch pink")

	# The four constants must also be FOUR DISTINCT Color values (a guard against an edit
	# that aliases two constants to the identical RGB even at equal hue/intensity).
	var seen: Dictionary = {}
	for nm in names:
		seen[str(hues[nm])] = true
	if seen.size() != names.size():
		lines.append("distinct FAIL: the four archetype colour constants are not 4 distinct values (%d)" % seen.size()); ok = false
	else:
		lines.append("distinct OK: four archetype colour constants are four distinct Color values")

	# --- 2) Targets._enemy_color returns the distinct per-kind constant ----------
	var tg: Node2D = TargetsS.new()
	var KIND := {
		"GLITCH": int(TargetsS.KIND_GLITCH),
		"RHOMBUS": int(TargetsS.KIND_RHOMBUS),
		"FRACTAL": int(TargetsS.KIND_FRACTAL),
		"FRACTLING": int(TargetsS.KIND_FRACTLING),
	}
	var color_map := {}
	for nm in names:
		var c: Color = tg.call("_enemy_color", {"kind": KIND[nm]})
		color_map[nm] = c
		var want: Color = hues[nm]
		if not c.is_equal_approx(want):
			lines.append("_enemy_color FAIL: %s returned %s, want Palette.ENEMY_%s %s" % [nm, c, nm, want]); ok = false
	# All four returned colours must themselves be distinct (the function fans the four kinds
	# out to four different constants, not a shared fallback).
	var ec_seen: Dictionary = {}
	for nm in names:
		ec_seen[str(color_map[nm])] = true
	if ec_seen.size() != names.size():
		lines.append("_enemy_color FAIL: the four kinds did not map to four distinct colours (%d)" % ec_seen.size()); ok = false
	else:
		lines.append("_enemy_color OK: each kind returns its distinct Palette constant")

	# --- 3) Armored render path differs from the unarmored base -----------------
	# Replicate _render()'s armor tell: an armored enemy's instance colour is the base lerped
	# toward ENEMY_RHOMBUS_CORE by a_w = clampf(0.18 * armor, 0, 0.6). armor == 0 leaves the
	# base untouched; armor > 0 must yield a measurably different colour, so the plated rim
	# reads on screen.
	var core: Color = pal.get("ENEMY_RHOMBUS_CORE")
	var base_rhombus: Color = hues["RHOMBUS"]
	var rhombus_armor: int = int(TargetsS.STATS[KIND["RHOMBUS"]]["armor"])
	var unarmored: Color = base_rhombus                       # armor == 0: base, no blend
	var armored: Color = _armored_color(base_rhombus, rhombus_armor, core)
	var dist: float = _color_dist(unarmored, armored)
	lines.append("armor tell: Rhombus armor=%d  base=%s  armored=%s  rgb-dist=%.3f" % [
		rhombus_armor, unarmored, armored, dist])
	if rhombus_armor <= 0:
		lines.append("armor FAIL: Rhombus STATS armor is not > 0 — the armored render path is never exercised"); ok = false
	elif armored.is_equal_approx(unarmored) or dist < 0.05:
		lines.append("armor FAIL: armor > 0 did not shift the colour away from the base — no armor tell"); ok = false
	else:
		lines.append("armor OK: armor > 0 blends toward ENEMY_RHOMBUS_CORE -> a distinct colour from armor == 0")

	# A higher armor count must blend FURTHER toward the core than a lower one (the tell scales
	# with armor, capped at the blend max), guarding the per-armor weighting in _render().
	var a1: Color = _armored_color(base_rhombus, 1, core)
	var a3: Color = _armored_color(base_rhombus, 3, core)
	var d1: float = _color_dist(unarmored, a1)
	var d3: float = _color_dist(unarmored, a3)
	lines.append("armor scaling: armor1 dist=%.3f < armor3 dist=%.3f (tell deepens with armor)" % [d1, d3])
	if not (d3 > d1 + 0.001):
		lines.append("armor-scale FAIL: more armor did not blend further toward the core"); ok = false
	else:
		lines.append("armor-scale OK: the armor tell deepens as armor rises")

	tg.free()
	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## On-screen hue of an HDR Color: normalise by the max channel (the tone-mapped chroma
## direction) before reading .h, since an unclamped HDR colour's hue is not meaningful.
func _hue_of(c: Color) -> float:
	var m: float = maxf(maxf(c.r, c.g), maxf(c.b, 1e-6))
	return Color(c.r / m, c.g / m, c.b / m, 1.0).h


## On-screen INTENSITY of an HDR Color: the max channel (what drives the bloom/brightness the eye
## reads), used to separate two same-hue archetypes by how bright they glow.
func _intensity(c: Color) -> float:
	return maxf(maxf(c.r, c.g), c.b)


## Wrap-around distance between two normalised hues (0..1, hue is circular).
func _hue_dist(a: float, b: float) -> float:
	var d: float = absf(a - b)
	return minf(d, 1.0 - d)


## RGB euclidean distance between two colours (alpha ignored).
func _color_dist(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


## Replicate Targets._render()'s armored instance colour: base lerped toward the core by
## a_w = clampf(ARMOR_BLEND_PER * armor, 0, ARMOR_BLEND_MAX).
func _armored_color(base: Color, armor: int, core: Color) -> Color:
	var a_w: float = clampf(ARMOR_BLEND_PER * float(armor), 0.0, ARMOR_BLEND_MAX)
	return base.lerp(core, a_w)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
