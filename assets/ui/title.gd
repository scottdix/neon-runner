extends Control
## 02 · TITLE — main menu (#41, docs/design/SCREENS.md). Logo + tagline, a hovering ship,
## the big PLAY button, and the secondary row (HOW TO PLAY / SETTINGS) plus the Garage /
## Splice branches. BEST score (top-right) comes from Settings. All buttons route through
## SceneManager.

const UI := preload("res://assets/ui/ui_kit.gd")


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	add_child(UI.backdrop(Settings.amoled_mode))
	_build()


func _build() -> void:
	var cyan := Palette.ACCENT_CYAN_HUD
	var cx := UI.DESIGN.x * 0.5

	var ring := UI.ring(560.0, UI.fade(cyan, 0.10))
	ring.position = Vector2(cx - 280.0, 980.0 - 280.0)
	add_child(ring)

	# BEST (top-right) — the persisted high score.
	var best_label := UI.text("BEST", Fonts.arcade, 18, Palette.TEXT_DIM_HUD, HORIZONTAL_ALIGNMENT_RIGHT)
	best_label.size.x = 300.0
	best_label.position = Vector2(UI.DESIGN.x - 340.0, 70.0)
	add_child(best_label)
	var best_val := UI.text(UI.commafy(Settings.best_score), Fonts.arcade, 30,
		Palette.COMBO_ORANGE_HUD, HORIZONTAL_ALIGNMENT_RIGHT)
	best_val.size.x = 300.0
	best_val.position = Vector2(UI.DESIGN.x - 340.0, 108.0)
	add_child(best_val)

	var logo := UI.logo(160)
	UI.center_x(logo, 300.0)
	add_child(logo)
	var tag := UI.text("RUN THE GATES · GROW THE SWARM", Fonts.mono, 30,
		Palette.TEXT_MUTED_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	tag.size.x = UI.DESIGN.x
	tag.position = Vector2(0.0, 700.0)
	add_child(tag)

	# Idle gold orbs + hovering ship (the swarm hint).
	add_child(_place(UI.orb(11.0), Vector2(cx - 70.0, 860.0)))
	add_child(_place(UI.orb(8.0), Vector2(cx + 60.0, 840.0)))
	var ship := UI.ship_mark(cyan, 7.0)
	ship.position = Vector2(cx, 980.0)
	add_child(ship)

	# PLAY — primary.
	var play := UI.glow_button("PLAY", cyan, Vector2(660.0, 180.0), 70)
	UI.center_x(play, 1200.0)
	add_child(play)
	UI.hit_overlay(play).pressed.connect(SceneManager.start_run)

	# Secondary row: HOW TO PLAY / SETTINGS.
	var how := UI.outline_button("HOW TO\nPLAY", cyan, Vector2(315.0, 130.0), 26)
	how.position = Vector2(cx - 330.0, 1420.0)
	add_child(how)
	UI.hit_overlay(how).pressed.connect(SceneManager.goto_how_to_play)
	var settings := UI.outline_button("SETTINGS", cyan, Vector2(315.0, 130.0), 26)
	settings.position = Vector2(cx + 15.0, 1420.0)
	add_child(settings)
	UI.hit_overlay(settings).pressed.connect(SceneManager.goto_settings)

	# Branch row: GARAGE / SPLICE (design's Title branches).
	var garage := UI.outline_button("GARAGE", Palette.MENU_GOLD_HUD, Vector2(315.0, 120.0), 26)
	garage.position = Vector2(cx - 330.0, 1570.0)
	add_child(garage)
	UI.hit_overlay(garage).pressed.connect(SceneManager.goto_garage)
	var splice := UI.outline_button("SPLICE LAB", Palette.MENU_MAGENTA_HUD, Vector2(315.0, 120.0), 24)
	splice.position = Vector2(cx + 15.0, 1570.0)
	add_child(splice)
	UI.hit_overlay(splice).pressed.connect(SceneManager.goto_splice)

	var badge := UI.text("NO ADS · EVER · ONE-TIME UNLOCK", Fonts.mono, 26,
		Palette.TEXT_DIM_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	badge.size.x = UI.DESIGN.x
	badge.position = Vector2(0.0, 1800.0)
	add_child(badge)


func _place(c: Control, pos: Vector2) -> Control:
	c.position = pos
	return c
