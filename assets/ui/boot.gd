extends Control
## 01 · BOOT — cold-start logo + asset load (#48, docs/design/SCREENS.md). The flow's
## entry scene (project main_scene). Shows the NEON SPLICE mark, a loading bar, and the
## paymium NO ADS badge, then auto-advances to Title when loading finishes.
##
## Headless: the auto-advance is skipped (no DisplayServer) so the verify suite can
## instantiate this scene to smoke-test the build without it trying to change scenes.

const UI := preload("res://assets/ui/ui_kit.gd")
const LOAD_TIME := 1.8

var _bar_fill: ColorRect


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	add_child(UI.backdrop(Settings.amoled_mode))
	_build()
	if DisplayServer.get_name() == "headless":
		return
	_run_loading()


func _build() -> void:
	var cyan := Palette.ACCENT_CYAN_HUD
	var cx := UI.DESIGN.x * 0.5

	for d in [380.0, 640.0]:
		var r := UI.ring(d, UI.fade(cyan, 0.10))
		r.position = Vector2(cx - d * 0.5, 760.0 - d * 0.5)
		add_child(r)

	var version := UI.text("v0.2.0", Fonts.mono, 28, Palette.TEXT_DIM_HUD)
	version.position = Vector2(UI.DESIGN.x - 200.0, 70.0)
	version.size.x = 160.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)

	var ship := UI.ship_mark(cyan, 6.0)
	ship.position = Vector2(cx, 560.0)
	add_child(ship)

	var logo := UI.logo(150)
	UI.center_x(logo, 700.0)
	add_child(logo)

	# Loading bar: dark track + bright fill (animated on device).
	var track := ColorRect.new()
	track.color = UI.fade(cyan, 0.12)
	track.size = Vector2(600.0, 14.0)
	UI.center_x(track, 1320.0)
	add_child(track)
	_bar_fill = ColorRect.new()
	_bar_fill.color = cyan
	_bar_fill.position = track.position
	_bar_fill.size = Vector2(36.0, 14.0)
	add_child(_bar_fill)

	var loading := UI.text("LOADING ASSETS", Fonts.arcade, 22, Palette.TEXT_DIM_HUD,
		HORIZONTAL_ALIGNMENT_CENTER)
	loading.size.x = UI.DESIGN.x
	loading.position = Vector2(0.0, 1360.0)
	add_child(loading)

	# Paymium badge ([[monetization-no-ads]]).
	var no_ads := UI.text("NO ADS · EVER", Fonts.arcade, 24, cyan, HORIZONTAL_ALIGNMENT_CENTER)
	no_ads.size.x = UI.DESIGN.x
	no_ads.position = Vector2(0.0, 1660.0)
	add_child(no_ads)
	var unlock := UI.text("ONE-TIME UNLOCK · PLAY FOREVER", Fonts.mono, 26,
		Palette.TEXT_MUTED_HUD, HORIZONTAL_ALIGNMENT_CENTER)
	unlock.size.x = UI.DESIGN.x
	unlock.position = Vector2(0.0, 1710.0)
	add_child(unlock)


func _run_loading() -> void:
	var tween := create_tween()
	tween.tween_property(_bar_fill, "size:x", 600.0, LOAD_TIME).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(SceneManager.goto_title)
