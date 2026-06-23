extends Control
## SETTINGS (#45, docs/design/SCREENS.md) — the player options screen, reached from Title.
## Wires the two persisted toggles to the Settings autoload (AMOLED low-power display +
## Haptics). Back returns to Title. More options land as the feature set grows.

const UI := preload("res://assets/ui/ui_kit.gd")


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	add_child(UI.backdrop(Settings.amoled_mode))
	_build()


func _build() -> void:
	add_child(UI.back_button(SceneManager.goto_title))
	add_child(UI.screen_title("SETTINGS"))

	add_child(_toggle_row("AMOLED / LOW POWER", Settings.amoled_mode, 460.0,
		func(on: bool) -> void: Settings.set_amoled_mode(on)))
	add_child(_toggle_row("HAPTICS", Settings.haptics_enabled, 620.0,
		func(on: bool) -> void: Settings.set_haptics_enabled(on)))


## A labelled ON/OFF pill row. `on_change` is called with the new bool on each tap; the pill
## recolours to track state. Stored so the closure can flip the label/colour in place.
func _toggle_row(label_text: String, initial: bool, y: float, on_change: Callable) -> Control:
	var row := Control.new()
	row.position = Vector2(90.0, y)
	row.size = Vector2(UI.DESIGN.x - 180.0, 120.0)

	var lab := UI.text(label_text, Fonts.ui, 44, Palette.TEXT_MUTED_HUD)
	lab.position = Vector2(0.0, 30.0)
	row.add_child(lab)

	var state := {"on": initial}
	var pill := UI.panel(Vector2(180.0, 84.0), Palette.ACCENT_CYAN_HUD, 0.0, 2.0, 42)
	pill.position = Vector2(row.size.x - 180.0, 18.0)
	var pl := UI.text("", Fonts.arcade, 26, UI.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	pl.set_anchors_preset(PRESET_FULL_RECT)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(pl)
	row.add_child(pill)

	var paint := func() -> void:
		var on: bool = state["on"]
		var accent: Color = Palette.MENU_MINT_HUD if on else Palette.TEXT_DIM_HUD
		var sb := pill.get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = UI.fade(accent, 0.22 if on else 0.06)
		sb.border_color = accent
		pl.text = "ON" if on else "OFF"
		pl.modulate = accent if on else Palette.TEXT_MUTED_HUD
	paint.call()

	UI.hit_overlay(pill).pressed.connect(func() -> void:
		state["on"] = not state["on"]
		paint.call()
		on_change.call(state["on"]))
	return row
