extends Control
## 07 · HOW TO PLAY — the rules card (#69, docs/design/SCREENS.md). A Title branch: back
## chevron + HOW TO PLAY title over a vertically stacked list of the five core mechanics,
## each an arcade caption + a one-line description in its accent colour. No interaction
## beyond the back button (→ Title); pure reference. Same screen pattern as the other menu
## screens — built in code on a full-rect Control over the shared backdrop.

const UI := preload("res://assets/ui/ui_kit.gd")


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	add_child(UI.backdrop(Settings.amoled_mode))
	_build()


func _build() -> void:
	add_child(UI.back_button(SceneManager.goto_title))
	add_child(UI.screen_title("HOW TO PLAY"))

	# The five core mechanics, each in its locked accent. ENTROPY (the rose enemy faction)
	# uses the LDR loss-red HUD token: Palette.ENEMY_ROSE is HDR (RGB > 1) and would clip to
	# white off the bloom, so the menu label reads the crisp <=1 rose-red instead.
	var rows := [
		["STEER", "Drag to move. Analog — no lanes.", Palette.ACCENT_CYAN_HUD],
		["FIRE", "Always on. The swarm IS your firepower.", Palette.MENU_GOLD_HUD],
		["GATES", "Steer through x / + gates to grow. Dodge - / div.", Palette.MENU_MAGENTA_HUD],
		["ENTROPY", "Kill the rose enemies before they breach.", Palette.LOSS_RED_HUD],
		["FINISH", "Reach the finish line to complete the run.", Palette.MENU_MINT_HUD],
	]
	var y := 460.0
	for row in rows:
		add_child(_rule_row(row[0], row[1], row[2], y))
		y += 240.0


## One mechanic row: an arcade caption in the accent colour, a Rajdhani one-line description
## under it, and a hairline divider — mirrors the spacing of the Results stat rows.
func _rule_row(caption: String, desc: String, accent: Color, y: float) -> Control:
	var row := Control.new()
	row.position = Vector2(90.0, y)
	row.size = Vector2(UI.DESIGN.x - 180.0, 200.0)
	var cap := UI.text(caption, Fonts.arcade, 44, accent)
	cap.position = Vector2(0.0, 0.0)
	row.add_child(cap)
	var body := UI.text(desc, Fonts.ui, 38, UI.TEXT_BRIGHT)
	body.size.x = row.size.x
	body.position = Vector2(0.0, 78.0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(body)
	var rule := ColorRect.new()
	rule.color = Color(1.0, 1.0, 1.0, 0.07)
	rule.size = Vector2(row.size.x, 2.0)
	rule.position = Vector2(0.0, 196.0)
	row.add_child(rule)
	return row
