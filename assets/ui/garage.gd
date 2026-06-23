extends Control
## 05 · GARAGE (#67, docs/design/SCREENS.md) — vector ship customization, reached from
## Title. Circular grid plate with the ship preview, then HULL COLOR / TRAIL STYLE / ENGINE
## selectors and EQUIP. The screen is now driven by the Loadout autoload: it renders the
## current selection, persists each tap (Loadout setters save immediately), and recolours the
## preview off the Events bus. EQUIP just returns to Title — nothing to save by then.

const UI := preload("res://assets/ui/ui_kit.gd")
# Preload by PATH (not class_name) — the global class cache isn't built under -s
# (CLAUDE.md headless idiom). #72: the Garage preview is built from Player's SHARED
# ship-render path so the build screen shows the literal vessel the run flies.
const PlayerScript := preload("res://assets/player/player.gd")

var _ship: Node2D
# Selectable controls kept so highlights can be re-rendered after a tap.
var _hull_swatches: Array[Panel] = []
var _trail_chips: Array[Panel] = []
var _engine_chips: Array[Panel] = []


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	add_child(UI.backdrop(Settings.amoled_mode))
	Events.loadout_changed.connect(_on_loadout_changed)
	_build()


func _build() -> void:
	var cyan := Palette.ACCENT_CYAN_HUD
	add_child(UI.back_button(SceneManager.goto_title))
	add_child(UI.screen_title("SHIP GARAGE"))

	# Circular grid plate + orbit ring + ship preview.
	var cx := UI.DESIGN.x * 0.5
	var plate := UI.ring(620.0, UI.fade(cyan, 0.3), 2.0)
	plate.position = Vector2(cx - 310.0, 700.0 - 310.0)
	add_child(plate)
	var orbit := UI.ring(520.0, UI.fade(cyan, 0.18), 2.0)
	orbit.position = Vector2(cx - 260.0, 700.0 - 260.0)
	add_child(orbit)
	# #72: render the EXACT in-run ship (Player's shared textured-additive-HDR path) so
	# "what I build" == "what I fly". The preview uses the same HDR glow colour the run
	# does, and the menu WorldEnvironment blooms it the same way.
	_ship = PlayerScript.build_ship_preview(Loadout.hull_color_hdr())
	_ship.position = Vector2(cx, 700.0)
	# Scale the 96px ship quad up to fill the orbit plate as the build-screen hero.
	_ship.scale = Vector2(2.6, 2.6)
	add_child(_ship)

	# Tuning sheet.
	var sheet := UI.panel(Vector2(UI.DESIGN.x - 120.0, 760.0), cyan, 0.04, 1.0, 26)
	sheet.position = Vector2(60.0, 1080.0)
	add_child(sheet)

	_section("HULL COLOR", 1130.0)
	var hull_colors := Loadout.hull_colors()
	for i in hull_colors.size():
		var sw := UI.orb(34.0, hull_colors[i])
		sw.position = Vector2(110.0 + i * 110.0, 1200.0)
		add_child(sw)
		_hull_swatches.append(sw)
		var idx := i
		UI.hit_overlay(sw).pressed.connect(func() -> void: Loadout.set_hull(idx))

	_section("TRAIL STYLE", 1340.0)
	_trail_chips = _chip_row(Loadout.TRAILS, 1410.0, 0, Loadout.set_trail)

	_section("ENGINE", 1540.0)
	_engine_chips = _chip_row(Loadout.ENGINES, 1610.0, 1, Loadout.set_engine)

	# Reflect the loaded selection (ring-highlight the active swatch + chips).
	_refresh_highlights()

	var equip := UI.glow_button("EQUIP", cyan, Vector2(UI.DESIGN.x - 120.0, 100.0), 44)
	equip.position = Vector2(60.0, 1730.0)
	add_child(equip)
	UI.hit_overlay(equip).pressed.connect(SceneManager.goto_title)


func _section(label_text: String, y: float) -> void:
	var l := UI.text(label_text, Fonts.arcade, 24, Palette.TEXT_DIM_HUD)
	l.position = Vector2(110.0, y)
	add_child(l)


## A row of mutually-exclusive option chips. `accent_idx` picks the highlight colour
## (0 cyan, 1 gold) to echo the design's per-row accents; tapping a chip calls `on_pick`
## with its index. Returns the chip Panels so the caller can re-highlight them.
func _chip_row(labels: Array, y: float, accent_idx: int, on_pick: Callable) -> Array[Panel]:
	var w := (UI.DESIGN.x - 120.0 - 40.0) / float(labels.size())
	var chips: Array[Panel] = []
	for i in labels.size():
		var chip := UI.panel(Vector2(w - 16.0, 100.0), Palette.ACCENT_CYAN_HUD, 0.0, 2.0, 8)
		chip.position = Vector2(110.0 + i * w, y)
		var cl := UI.text(labels[i], Fonts.arcade, 22, Palette.TEXT_MUTED_HUD,
			HORIZONTAL_ALIGNMENT_CENTER)
		cl.set_anchors_preset(PRESET_FULL_RECT)
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.name = "Label"
		chip.add_child(cl)
		chip.set_meta("accent_idx", accent_idx)
		add_child(chip)
		chips.append(chip)
		var idx := i
		UI.hit_overlay(chip).pressed.connect(func() -> void: on_pick.call(idx))
	return chips


# --- Highlighting ------------------------------------------------------------

## Re-paint every selector to match the current Loadout selection: a bright ring around
## the active hull swatch, and a filled/bright chip for the active trail + engine.
func _refresh_highlights() -> void:
	for i in _hull_swatches.size():
		_style_swatch(_hull_swatches[i], i == Loadout.hull_index)
	for i in _trail_chips.size():
		_style_chip(_trail_chips[i], i == Loadout.trail_index)
	for i in _engine_chips.size():
		_style_chip(_engine_chips[i], i == Loadout.engine_index)


## Ring-highlight a hull swatch when selected (a child Panel border drawn around the orb).
func _style_swatch(sw: Panel, selected: bool) -> void:
	var existing := sw.get_node_or_null("SelRing")
	if existing != null:
		existing.queue_free()
	if not selected:
		return
	var d := sw.size.x + 28.0
	var halo := UI.ring(d, UI.TEXT_BRIGHT, 3.0)
	halo.name = "SelRing"
	halo.position = Vector2((sw.size.x - d) * 0.5, (sw.size.y - d) * 0.5)
	sw.add_child(halo)


## Fill + brighten a chip when selected, dim it otherwise. Uses the row's stored accent.
func _style_chip(chip: Panel, selected: bool) -> void:
	var accent: Color = Palette.ACCENT_CYAN_HUD if int(chip.get_meta("accent_idx", 0)) == 0 \
		else Palette.MENU_GOLD_HUD
	var border: Color = accent if selected else UI.fade(accent, 0.25)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.fade(accent, 0.16 if selected else 0.0)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(8)
	chip.add_theme_stylebox_override("panel", sb)
	var label := chip.get_node_or_null("Label") as Label
	if label != null:
		label.modulate = UI.TEXT_BRIGHT if selected else Palette.TEXT_MUTED_HUD


## Loadout changed (any axis) — re-paint highlights and recolour the ship preview live
## off the Events bus, exactly as the in-run ship recolours (#72).
func _on_loadout_changed() -> void:
	_refresh_highlights()
	_recolor_ship(Loadout.hull_color_hdr())


## Re-tint the shared ship-preview node to the new HDR hull glow (same call the run uses).
func _recolor_ship(c: Color) -> void:
	PlayerScript.tint_ship_preview(_ship as MultiMeshInstance2D, c)
