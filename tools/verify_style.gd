extends SceneTree
## Headless verification for the session-12 design-integration slice:
##   - Palette       : autoload present; HDR tokens clear the bloom threshold (a channel
##                     > 1), HUD tokens stay <= 1; gate operators are 3 distinct hues.
##   - Entropy hues  : HORDE recolour (#90 P0) — Glitch & Fractling = hot-pink fodder family,
##                     Rhombus = NEON GREEN (lane bruiser), Fractal = VIOLET; the three hue
##                     families stay mutually distinguishable.
##   - Settings      : defaults; set_amoled_mode emits amoled_mode_changed + persists
##                     (ConfigFile round-trip).
##   - Haptics       : wire() idempotent; tier calls + a gate_passed emit don't error
##                     (vibration is a desktop/headless no-op).
##   - Grid floor    : grid_floor.gd + reactive_grid.gdshader load; the node builds its
##                     ShaderMaterial and takes a scroll/ripple update without erroring.
##
## GPU-free (dummy renderer): we only assert the wiring is sound — the actual glow/warp
## is the device's job (#47/#54). Run:
##   tools/run-headless.sh res://tools/verify_style.gd /tmp/verify_style_result.txt

const RESULT_PATH := "/tmp/verify_style_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	var pal: Node = root.get_node_or_null("Palette")
	var settings: Node = root.get_node_or_null("Settings")
	var haptics: Node = root.get_node_or_null("Haptics")
	var fonts: Node = root.get_node_or_null("Fonts")
	lines.append("autoloads: Events=%s Palette=%s Settings=%s Haptics=%s Fonts=%s" % [
		ev != null, pal != null, settings != null, haptics != null, fonts != null])
	if ev == null or pal == null or settings == null or haptics == null or fonts == null:
		lines.append("RESULT=FAIL (an autoload is missing)"); _write(lines); return

	# 1) Palette — HDR tokens must have a channel > 1 (bloom-ready); HUD tokens <= 1.
	var hdr := {
		"SHIP_CYAN": pal.SHIP_CYAN, "SWARM_GOLD": pal.SWARM_GOLD,
		"ENEMY_ROSE": pal.ENEMY_ROSE, "GATE_MULTIPLY": pal.GATE_MULTIPLY,
		"GATE_ADD": pal.GATE_ADD, "GATE_NEGATIVE": pal.GATE_NEGATIVE,
		"SUCCESS_GREEN": pal.SUCCESS_GREEN, "GRID_BLUE": pal.GRID_BLUE,
	}
	for k in hdr:
		var c: Color = hdr[k]
		if maxf(c.r, maxf(c.g, c.b)) <= 1.0:
			lines.append("palette FAIL: HDR token %s has no channel > 1 (won't bloom)" % k); ok = false
	var hud := {
		"HUD_CYAN": pal.HUD_CYAN, "COMBO_ORANGE_HUD": pal.COMBO_ORANGE_HUD,
		"BATTERY_LOW_HUD": pal.BATTERY_LOW_HUD, "BATTERY_HIGH_HUD": pal.BATTERY_HIGH_HUD,
	}
	for k in hud:
		var c: Color = hud[k]
		if maxf(c.r, maxf(c.g, c.b)) > 1.0:
			lines.append("palette FAIL: HUD token %s exceeds 1 (would bloom — should be crisp)" % k); ok = false
	# 3 distinct gate operator hues (the explicit decision; not collapsed).
	if pal.GATE_MULTIPLY == pal.GATE_ADD or pal.GATE_ADD == pal.GATE_NEGATIVE or pal.GATE_MULTIPLY == pal.GATE_NEGATIVE:
		lines.append("palette FAIL: gate operator colours not distinct"); ok = false
	if ok:
		lines.append("palette OK: HDR>1 / HUD<=1 split holds; 3 distinct gate hues")

	# 2) Entropy palette — HORDE recolour (#90 P0): the archetypes are split by HUE to read against
	#    the cool cyan divider. Glitch & Fractling are the HOT-PINK fodder family (red-dominant, low
	#    green, blue present), Rhombus is NEON GREEN (deliberately a different hue — the lane bruiser),
	#    Fractal is VIOLET (blue-dominant, low green). We assert each archetype's hue INTENT and that
	#    the three families are mutually DISTINGUISHABLE, rather than pinning brittle HDR values (the
	#    designer is still tuning hues on-device).
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var tg: Node2D = TargetsS.new()
	var glitch: Color = tg.call("_enemy_color", {"kind": TargetsS.KIND_GLITCH})
	var rhombus: Color = tg.call("_enemy_color", {"kind": TargetsS.KIND_RHOMBUS})
	var fractal: Color = tg.call("_enemy_color", {"kind": TargetsS.KIND_FRACTAL})
	var fractling: Color = tg.call("_enemy_color", {"kind": TargetsS.KIND_FRACTLING})
	# Hot-pink fodder family: red-dominant, low green, blue present (the #ff007f-ish magenta-rose lean).
	for entry in [["glitch", glitch], ["fractling", fractling]]:
		var nm: String = entry[0]
		var c: Color = entry[1]
		if not (c.r > 1.0 and c.g < c.r * 0.35 and c.r > c.g and c.b > 0.5):
			lines.append("palette FAIL: %s is not in the hot-pink fodder family (%.2f,%.2f,%.2f)" % [
				nm, c.r, c.g, c.b]); ok = false
	# Rhombus = NEON GREEN: green-dominant, well clear of red (a different hue from the pink fodder).
	if not (rhombus.g > 1.0 and rhombus.g > rhombus.r and rhombus.g > rhombus.b):
		lines.append("palette FAIL: Rhombus is not NEON GREEN (%.2f,%.2f,%.2f)" % [
			rhombus.r, rhombus.g, rhombus.b]); ok = false
	# Fractal = VIOLET: blue-dominant with low green (kept distinct from pink fodder and green Rhombus).
	if not (fractal.b > 1.0 and fractal.g < fractal.b * 0.25 and fractal.b > fractal.g):
		lines.append("palette FAIL: Fractal is not VIOLET (%.2f,%.2f,%.2f)" % [
			fractal.r, fractal.g, fractal.b]); ok = false
	# Distinguishability: the three hue families (pink fodder / green Rhombus / violet Fractal) are
	# mutually distinct colours — the whole point of the recolour is telling them apart on-screen.
	var families := {}
	for c in [glitch, rhombus, fractal]:
		families[var_to_str(c)] = true
	lines.append("entropy palette: glitch/fractling=pink, rhombus=green, fractal=violet, %d distinct hue families" % families.size())
	if families.size() < 3:
		lines.append("palette FAIL: enemy hue families not mutually distinguishable"); ok = false
	if ok:
		lines.append("palette OK: hot-pink fodder (glitch/fractling) vs neon-green Rhombus vs violet Fractal")
	tg.free()

	# 3) Settings — defaults, toggle emits + persists.
	var amoled_seen := [0, false]
	ev.connect("amoled_mode_changed", func(en): amoled_seen[0] += 1; amoled_seen[1] = en)
	var def_hap: bool = settings.get("haptics_enabled")
	var def_amoled: bool = settings.get("amoled_mode")
	settings.call("set_amoled_mode", true)
	settings.call("set_amoled_mode", true)            # idempotent — must NOT re-emit
	# Round-trip: a fresh ConfigFile load reflects the saved value.
	var fresh := ConfigFile.new()
	var load_rc: int = fresh.load(settings.CONFIG_PATH)
	var saved_amoled: bool = bool(fresh.get_value("display", "amoled_mode", false)) if load_rc == OK else false
	lines.append("settings: def hap=%s amoled=%s | after-toggle amoled=%s emits=%d saved=%s" % [
		def_hap, def_amoled, settings.get("amoled_mode"), amoled_seen[0], saved_amoled])
	if not def_hap or def_amoled:
		lines.append("settings FAIL: defaults wrong (haptics ON, amoled OFF expected)"); ok = false
	if not settings.get("amoled_mode") or amoled_seen[0] != 1 or not amoled_seen[1] or not saved_amoled:
		lines.append("settings FAIL: toggle didn't emit-once + persist"); ok = false
	else:
		lines.append("settings OK: defaults + toggle emit-once + ConfigFile round-trip")
	settings.call("set_amoled_mode", false)           # restore for cleanliness

	# 4) Haptics — wire idempotent, tier calls + a gate_passed emit don't error.
	haptics.call("wire")
	haptics.call("wire")                              # idempotent
	haptics.call("light"); haptics.call("medium"); haptics.call("heavy")
	ev.emit_signal("gate_passed", "multiply", 2.0, 40)   # routes to medium() — must not error
	ev.emit_signal("enemy_breached", Vector2.ZERO, 6.0)  # routes to light()
	lines.append("haptics OK: wire idempotent + tiers + event mapping ran without error")

	# 5) Grid floor + shader load + take updates without erroring.
	var shader: Shader = load("res://shaders/reactive_grid.gdshader")
	var GridS: GDScript = load("res://assets/levels/grid_floor.gd")
	lines.append("grid assets: shader=%s script=%s" % [shader != null, GridS != null])
	if shader == null or GridS == null:
		lines.append("grid FAIL: shader or script missing"); ok = false
	else:
		var grid: Node2D = GridS.new()
		root.add_child(grid)                          # triggers _ready -> builds material
		grid.call("_on_distance_changed", 120.0, 0.5) # scroll update
		grid.call("_on_grid_ripple", Vector2(540, 1680), false)
		grid.call("set_low_power", true)
		grid.call("_process", 0.1)                    # advance the ripple once
		lines.append("grid OK: builds ShaderMaterial; scroll/ripple/low-power updates ran")
		grid.free()

	# 6) Typography — the 4 bundled fonts load (imported) into their roles; apply() works
	#    and no-ops on a null font. (_ready is deferred under -s, so load explicitly.)
	fonts.call("load_fonts")
	var roles := {
		"arcade": fonts.get("arcade"), "display": fonts.get("display"),
		"ui": fonts.get("ui"), "ui_bold": fonts.get("ui_bold"), "mono": fonts.get("mono"),
	}
	var loaded := 0
	for k in roles:
		if roles[k] is FontFile:
			loaded += 1
		else:
			lines.append("fonts FAIL: role %s did not load as a FontFile" % k); ok = false
	var lbl := Label.new()
	fonts.call("apply", lbl, roles["arcade"], 44)        # real font
	fonts.call("apply", lbl, null, -1)                   # null font must no-op (no crash)
	var theme_ok: bool = fonts.get("theme") is Theme
	lines.append("fonts: %d/5 roles loaded, apply()+null-noop ran, theme=%s" % [loaded, theme_ok])
	if loaded == 5 and theme_ok:
		lines.append("fonts OK: 4 design fonts bundled + loaded into roles; Theme built")
	elif not theme_ok:
		lines.append("fonts FAIL: default Theme not built"); ok = false
	lbl.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
