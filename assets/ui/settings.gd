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

	add_child(_difficulty_row(460.0))
	add_child(_toggle_row("AMOLED / LOW POWER", Settings.amoled_mode, 660.0,
		func(on: bool) -> void: Settings.set_amoled_mode(on)))
	add_child(_toggle_row("HAPTICS", Settings.haptics_enabled, 820.0,
		func(on: bool) -> void: Settings.set_haptics_enabled(on)))
	add_child(_toggle_row("PERF OVERLAY", Settings.perf_overlay_enabled, 980.0,
		func(on: bool) -> void: Settings.set_perf_overlay_enabled(on)))
	# HORDE locked as core game (reversible — restore _poc_mode_row + this add_child to bring back
	# the COMBAT (POC) mode switcher). The _poc_mode_row helper is removed alongside it.


## A 3-segment DIFFICULTY selector (#80): EASY / MED / HARD. Tapping a segment commits via
## Settings.set_difficulty (which persists + announces); the active segment lights in the mode's
## accent colour. The label under it shows the active mode name pulled from the Difficulty autoload.
func _difficulty_row(y: float) -> Control:
	var row := Control.new()
	row.position = Vector2(90.0, y)
	row.size = Vector2(UI.DESIGN.x - 180.0, 160.0)

	var lab := UI.text("DIFFICULTY", Fonts.ui, 44, Palette.TEXT_MUTED_HUD)
	lab.position = Vector2(0.0, 0.0)
	row.add_child(lab)

	var seg_labels := ["EASY", "MED", "HARD"]
	var seg_w: float = (row.size.x - 2.0 * 16.0) / 3.0
	var seg_y := 70.0
	var pills: Array[Panel] = []

	# paint() relights every segment so only the active mode glows in its accent.
	var paint := func() -> void:
		var active: int = int(Settings.difficulty)
		for i in pills.size():
			var on: bool = (i == active)
			var accent: Color = Difficulty.profile_for(i).accent_color()
			var sb := pills[i].get_theme_stylebox("panel") as StyleBoxFlat
			sb.bg_color = UI.fade(accent, 0.22 if on else 0.05)
			sb.border_color = accent if on else Palette.TEXT_DIM_HUD
			var seg_lbl := pills[i].get_child(0) as Label
			seg_lbl.modulate = accent if on else Palette.TEXT_MUTED_HUD

	for i in seg_labels.size():
		var pill := UI.panel(Vector2(seg_w, 84.0), Palette.ACCENT_CYAN_HUD, 0.05, 2.0, 14)
		pill.position = Vector2(float(i) * (seg_w + 16.0), seg_y)
		var pl := UI.text(seg_labels[i], Fonts.arcade, 28, UI.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
		pl.set_anchors_preset(PRESET_FULL_RECT)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.add_child(pl)
		row.add_child(pill)
		pills.append(pill)
		var mode := i
		UI.hit_overlay(pill).pressed.connect(func() -> void:
			Settings.set_difficulty(mode)
			paint.call())

	paint.call()
	return row


## A labelled ON/OFF pill row at design-x `(90, y)`. Thin wrapper over the promoted UI.toggle_row
## (now shared with the Debug menu) that just positions it on the Settings screen.
func _toggle_row(label_text: String, initial: bool, y: float, on_change: Callable) -> Control:
	var row := UI.toggle_row(label_text, initial, on_change)
	row.position = Vector2(90.0, y)
	return row
