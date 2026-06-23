extends Control
## 04 · RESULTS — round complete, win or loss (#44, docs/design/SCREENS.md). Replaces the
## inline overlay that used to live in run.gd; SceneManager swaps here on a run terminal.
## Reads the finalised run from GameState (run_won, score, peaks, distance, is_new_best).
## RETRY restarts the run; MENU returns to Title.

const UI := preload("res://assets/ui/ui_kit.gd")


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	add_child(UI.backdrop(Settings.amoled_mode))
	_build()


func _build() -> void:
	var cyan := Palette.ACCENT_CYAN_HUD
	var won: bool = GameState.run_won
	var header_color: Color = Palette.MENU_MINT_HUD if won else Palette.LOSS_RED_HUD
	var header_text := "RUN COMPLETE" if won else "GRID COLLAPSE"

	var ring := UI.ring(640.0, UI.fade(cyan, 0.09))
	ring.position = Vector2(UI.DESIGN.x * 0.5 - 320.0, 620.0 - 320.0)
	add_child(ring)

	var header := UI.text(header_text, Fonts.arcade, 48, header_color, HORIZONTAL_ALIGNMENT_CENTER)
	header.size.x = UI.DESIGN.x
	header.position = Vector2(0.0, 240.0)
	add_child(header)

	if GameState.is_new_best:
		var badge := UI.panel(Vector2(220.0, 64.0), Palette.COMBO_ORANGE_HUD, 0.9, 0.0, 8)
		badge.position = Vector2(UI.DESIGN.x - 300.0, 360.0)
		badge.rotation = deg_to_rad(7.0)
		var bl := UI.text("NEW BEST", Fonts.arcade, 22, Color(0.1, 0.07, 0.02),
			HORIZONTAL_ALIGNMENT_CENTER)
		bl.set_anchors_preset(PRESET_FULL_RECT)
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(bl)
		add_child(badge)

	var score_cap := UI.text("FINAL SCORE", Fonts.arcade, 24, Palette.TEXT_DIM_HUD,
		HORIZONTAL_ALIGNMENT_CENTER)
	score_cap.size.x = UI.DESIGN.x
	score_cap.position = Vector2(0.0, 440.0)
	add_child(score_cap)
	var score := UI.text(UI.commafy(GameState.score), Fonts.display, 150, UI.TEXT_BRIGHT,
		HORIZONTAL_ALIGNMENT_CENTER)
	score.size.x = UI.DESIGN.x
	score.position = Vector2(0.0, 500.0)
	add_child(score)

	# Stats grid.
	var rows := [
		["PEAK MULTIPLIER", "×%.1f" % GameState.peak_multiplier, Palette.MENU_MAGENTA_HUD],
		["FLEET PEAK", str(GameState.peak_fleet), Palette.MENU_GOLD_HUD],
		["DISTANCE", "%dm" % int(GameState.distance), cyan],
		["BEST COMBO", "×%d" % GameState.best_combo, Palette.COMBO_ORANGE_HUD],
	]
	var y := 800.0
	for row in rows:
		add_child(_stat_row(row[0], row[1], row[2], y))
		y += 110.0

	# RETRY (primary) / MENU (outline).
	var retry := UI.glow_button("RETRY", cyan, Vector2(680.0, 160.0), 56)
	UI.center_x(retry, 1500.0)
	add_child(retry)
	UI.hit_overlay(retry).pressed.connect(SceneManager.start_run)
	var menu := UI.outline_button("MENU", cyan, Vector2(680.0, 120.0), 30)
	UI.center_x(menu, 1690.0)
	add_child(menu)
	UI.hit_overlay(menu).pressed.connect(SceneManager.goto_title)


## One stat line: muted label left, bright value right, hairline divider under it.
func _stat_row(label_text: String, value_text: String, value_color: Color, y: float) -> Control:
	var row := Control.new()
	row.position = Vector2(90.0, y)
	row.size = Vector2(UI.DESIGN.x - 180.0, 96.0)
	var lab := UI.text(label_text, Fonts.ui, 38, Palette.TEXT_MUTED_HUD)
	lab.position = Vector2(0.0, 24.0)
	row.add_child(lab)
	var val := UI.text(value_text, Fonts.arcade, 40, value_color, HORIZONTAL_ALIGNMENT_RIGHT)
	val.size.x = row.size.x
	val.position = Vector2(0.0, 20.0)
	row.add_child(val)
	var rule := ColorRect.new()
	rule.color = Color(1.0, 1.0, 1.0, 0.07)
	rule.size = Vector2(row.size.x, 2.0)
	rule.position = Vector2(0.0, 94.0)
	row.add_child(rule)
	return row
