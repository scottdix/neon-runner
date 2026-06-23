extends CanvasLayer
## PAUSE overlay (#43, docs/design/SCREENS.md). Raised by the Run scene over live gameplay
## — NOT a full scene swap, so the run state is preserved underneath. Runs with
## PROCESS_MODE_ALWAYS so its buttons respond while the tree is paused. RESUME unfreezes
## via SceneManager; QUIT abandons the run back to Title.
##
## Run creates this once (hidden) and calls `open()` to pause; the overlay handles its own
## RESUME/QUIT. Layer 10 keeps it above the HUD.

const UI := preload("res://assets/ui/ui_kit.gd")


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


## Pause the run and show the menu. Idempotent (SceneManager.pause_run no-ops if not RUN).
func open() -> void:
	SceneManager.pause_run()
	visible = true


func _build() -> void:
	var cyan := Palette.ACCENT_CYAN_HUD
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var title := UI.text("PAUSED", Fonts.arcade, 70, cyan, HORIZONTAL_ALIGNMENT_CENTER)
	title.size.x = UI.DESIGN.x
	title.position = Vector2(0.0, 760.0)
	add_child(title)

	var resume := UI.glow_button("RESUME", cyan, Vector2(660.0, 160.0), 50)
	UI.center_x(resume, 1000.0)
	add_child(resume)
	UI.hit_overlay(resume).pressed.connect(_on_resume)

	var quit := UI.outline_button("QUIT TO MENU", cyan, Vector2(660.0, 120.0), 28)
	UI.center_x(quit, 1190.0)
	add_child(quit)
	UI.hit_overlay(quit).pressed.connect(SceneManager.goto_title)


func _on_resume() -> void:
	visible = false
	SceneManager.resume_run()
