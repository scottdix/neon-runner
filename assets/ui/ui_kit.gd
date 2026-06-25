extends RefCounted
## UIKit — shared neon-UI builders for the 6-screen flow (docs/design/SCREENS.md).
##
## All six menu screens (Boot/Title/Results/Garage/Splice/Settings) are built in code
## on a CanvasLayer, and they repeat the same handful of primitives: the phone-screen
## backdrop, faint rings, bordered panels, glow buttons, the ship vector mark, gold orbs,
## and typed labels. Centralising them here keeps the screens consistent and short, and
## means a styling tweak is one edit.
##
## Usage (screens preload by PATH, not class_name, so they parse in the headless `-s`
## loop where the class cache isn't built):
##   const UI := preload("res://assets/ui/ui_kit.gd")
##   add_child(UI.backdrop())
##   add_child(UI.glow_button("PLAY", Palette.ACCENT_CYAN_HUD, Vector2(660, 180)))
##
## Colours come from Palette (the menu screens use the LDR `_HUD` tokens — crisp, out of
## the bloom; the soft neon halo is a device-validated enhancement, #47/#64).

const DESIGN := Vector2(1080.0, 1920.0)

# Default body/button text colour (design's #eaffff — near-white with a cool tint).
const TEXT_BRIGHT := Color(0.92, 1.0, 1.0)


## "84200" -> "84,200" — grouped thousands for BEST / score readouts.
static func commafy(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


## The same colour at a new alpha — for faint rings, panel fills, dim borders.
static func fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Full-rect screen background. Near-black neon (or pitch black in AMOLED/low-power).
static func backdrop(amoled := false) -> ColorRect:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Palette.BG_AMOLED if amoled else Palette.BG_STANDARD
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## A typed label. `font` is a Fonts role (may be null pre-import → engine fallback).
static func text(s: String, font: FontFile, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = s
	l.modulate = color
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	Fonts.apply(l, font, size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The NEON SPLICE wordmark (Orbitron 900, two lines, centred). `width` lets the caller
## centre it across the screen; default spans the design width.
static func logo(font_size := 150, color := TEXT_BRIGHT, width := DESIGN.x) -> Label:
	var l := text("NEON\nSPLICE", Fonts.display, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.size.x = width
	return l


## A bordered translucent panel (the design's neon-outlined cards / sheets).
static func panel(sz: Vector2, accent: Color, fill_alpha := 0.10,
		border := 2.0, radius := 16) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = sz
	p.size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, fill_alpha)
	sb.set_border_width_all(int(border))
	sb.border_color = accent
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	return p


## A thin ring outline (faint pulsing background circles). Rendered as a borderless,
## centre-less rounded panel so we avoid a custom _draw.
static func ring(diameter: float, color: Color, width := 2.0) -> Panel:
	var p := Panel.new()
	p.size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(int(width))
	sb.border_color = color
	sb.set_corner_radius_all(int(diameter / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	return p


## A small glowing orb (the gold swarm dot / confetti / hull swatch). Circular panel.
static func orb(radius: float, color := Palette.MENU_GOLD_HUD) -> Panel:
	var p := Panel.new()
	p.size = Vector2(radius * 2.0, radius * 2.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	p.add_theme_stylebox_override("panel", sb)
	return p


## Primary glow button: filled + bright border + centred arcade label. Returns the Panel;
## the caller wires input (gui_input / a transparent Button overlay) and positions it.
static func glow_button(label_text: String, accent: Color, sz: Vector2,
		font_size := 46) -> Panel:
	var p := panel(sz, accent, 0.22, 2.0, 12)
	p.name = "GlowButton"
	var l := text(label_text, Fonts.arcade, font_size, TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Secondary outline button: faint fill, dim border, muted label.
static func outline_button(label_text: String, accent: Color, sz: Vector2,
		font_size := 22) -> Panel:
	var dim := Color(accent.r, accent.g, accent.b, 0.4)
	var p := panel(sz, dim, 0.05, 2.0, 10)
	p.name = "OutlineButton"
	var l := text(label_text, Fonts.arcade, font_size, Color(0.62, 0.85, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## A transparent full-rect Button laid over a panel so the whole card is tappable while the
## panel keeps the neon styling. Returns the Button (connect its `pressed`).
static func hit_overlay(over: Control) -> Button:
	var b := Button.new()
	b.flat = true
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.focus_mode = Control.FOCUS_NONE
	# Invisible: we only want the click target + press animation, not chrome.
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	over.add_child(b)
	return b


## Top-left back chevron (the design's sub-screen header control). Connects `on_press`.
static func back_button(on_press: Callable) -> Panel:
	var b := panel(Vector2(96.0, 96.0), Palette.ACCENT_CYAN_HUD, 0.05, 2.0, 12)
	b.name = "BackButton"
	b.position = Vector2(60.0, 140.0)
	var l := text("<", Fonts.arcade, 40, Palette.ACCENT_CYAN_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	hit_overlay(b).pressed.connect(on_press)
	return b


## A sub-screen title (Orbitron) centred across the screen at `y`.
static func screen_title(s: String, y := 150.0) -> Label:
	var t := text(s, Fonts.display, 70, TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	t.size.x = DESIGN.x
	t.position = Vector2(0.0, y)
	return t


## The ship vector mark (the cyan arrow from every screen). A Node2D so it can sit on a
## Control screen at an explicit position; built from filled polygons + a bright outline.
## Points are the design SVG (48px viewBox) recentred on the origin and scaled by `s`.
static func ship_mark(color := Palette.ACCENT_CYAN_HUD, s := 3.0) -> Node2D:
	var root := Node2D.new()
	root.name = "ShipMark"
	var hull_pts := PackedVector2Array([
		Vector2(24, 3), Vector2(43, 41), Vector2(24, 31), Vector2(5, 41)])
	var pts := PackedVector2Array()
	for v in hull_pts:
		pts.append((v - Vector2(24, 22)) * s)
	var fill := Polygon2D.new()
	fill.polygon = pts
	fill.color = Color(color.r, color.g, color.b, 0.18)
	root.add_child(fill)
	var outline := Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = maxf(2.0, s * 0.9)
	outline.default_color = color
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	root.add_child(outline)
	# Cockpit chevron.
	var cock_src := PackedVector2Array([
		Vector2(24, 7), Vector2(30, 26), Vector2(24, 21), Vector2(18, 26)])
	var cock := PackedVector2Array()
	for v in cock_src:
		cock.append((v - Vector2(24, 22)) * s)
	var cockpit := Polygon2D.new()
	cockpit.polygon = cock
	cockpit.color = TEXT_BRIGHT
	root.add_child(cockpit)
	return root


## Centre a control horizontally on the design width at vertical `y`. Sets position and
## returns the node (chainable). The control should already have its final width.
static func center_x(c: Control, y: float, width := DESIGN.x) -> Control:
	c.position = Vector2((width - c.size.x) * 0.5, y)
	return c


## A labelled ON/OFF pill row (promoted from settings.gd so the Debug menu reuses it). `on_change`
## is called with the new bool on each tap; the pill recolours to track state. `initial` seeds the
## display. `width` is the row's content width (label left, pill right). Returns the row Control.
static func toggle_row(label_text: String, initial: bool, on_change: Callable,
		width := DESIGN.x - 180.0) -> Control:
	var row := Control.new()
	row.size = Vector2(width, 120.0)

	var lab := text(label_text, Fonts.ui, 44, Palette.TEXT_MUTED_HUD)
	lab.position = Vector2(0.0, 30.0)
	row.add_child(lab)

	var state := {"on": initial}
	var pill := panel(Vector2(180.0, 84.0), Palette.ACCENT_CYAN_HUD, 0.0, 2.0, 42)
	pill.position = Vector2(row.size.x - 180.0, 18.0)
	var pl := text("", Fonts.arcade, 26, TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	pl.set_anchors_preset(Control.PRESET_FULL_RECT)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(pl)
	row.add_child(pill)

	var paint := func() -> void:
		var on: bool = state["on"]
		var accent: Color = Palette.MENU_MINT_HUD if on else Palette.TEXT_DIM_HUD
		var sb := pill.get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = fade(accent, 0.22 if on else 0.06)
		sb.border_color = accent
		pl.text = "ON" if on else "OFF"
		pl.modulate = accent if on else Palette.TEXT_MUTED_HUD
	paint.call()

	hit_overlay(pill).pressed.connect(func() -> void:
		state["on"] = not state["on"]
		paint.call()
		on_change.call(state["on"]))
	return row


## A numeric "− value +" stepper row for the Debug knobs. Holds a float `value`, tapping − / +
## nudges it by `step` (clamped to [min_v, max_v]) and calls `on_change(new_value)`; the centre
## label repaints via `fmt(value) -> String` so callers control int vs ×mult display. Pass
## max_v = INF for an UNBOUNDED-upward knob (density / cap). Returns the row Control.
static func stepper_row(label_text: String, initial: float, step: float,
		min_v: float, max_v: float, fmt: Callable, on_change: Callable,
		width := DESIGN.x - 180.0) -> Control:
	var row := Control.new()
	row.size = Vector2(width, 120.0)

	var lab := text(label_text, Fonts.ui, 44, Palette.TEXT_MUTED_HUD)
	lab.position = Vector2(0.0, 30.0)
	row.add_child(lab)

	var state := {"v": clampf(initial, min_v, max_v)}
	var btn_w := 84.0
	var val_w := 220.0
	var group_w := btn_w * 2.0 + val_w
	var group_x := row.size.x - group_w

	var minus := panel(Vector2(btn_w, 84.0), Palette.ACCENT_CYAN_HUD, 0.08, 2.0, 14)
	minus.position = Vector2(group_x, 18.0)
	var ml := text("−", Fonts.arcade, 40, Palette.ACCENT_CYAN_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	ml.set_anchors_preset(Control.PRESET_FULL_RECT)
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	minus.add_child(ml)
	row.add_child(minus)

	var val := text("", Fonts.arcade, 30, TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	val.position = Vector2(group_x + btn_w, 18.0)
	val.size = Vector2(val_w, 84.0)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val)

	var plus := panel(Vector2(btn_w, 84.0), Palette.ACCENT_CYAN_HUD, 0.08, 2.0, 14)
	plus.position = Vector2(group_x + btn_w + val_w, 18.0)
	var pl := text("+", Fonts.arcade, 40, Palette.ACCENT_CYAN_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	pl.set_anchors_preset(Control.PRESET_FULL_RECT)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_child(pl)
	row.add_child(plus)

	var paint := func() -> void:
		val.text = fmt.call(state["v"])
	paint.call()

	var nudge := func(dir: float) -> void:
		var nv: float = clampf(state["v"] + dir * step, min_v, max_v)
		if is_equal_approx(nv, state["v"]):
			return
		state["v"] = nv
		paint.call()
		on_change.call(nv)

	hit_overlay(minus).pressed.connect(func() -> void: nudge.call(-1.0))
	hit_overlay(plus).pressed.connect(func() -> void: nudge.call(1.0))
	return row
