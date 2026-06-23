extends Node
## Fonts — typography design tokens (autoload singleton: `Fonts`).
##
## The second half of the design-token foundation (DESIGN_SPEC "Typography"): the four
## bundled Google Fonts (OFL, shipped in assets/fonts/ — mobile builds must ship fonts,
## not link them) exposed as named roles, plus a default Theme scenes can adopt.
##
##   arcade  — Press Start 2P   : scores, combos, HUD readouts, button labels, gate digits
##   display — Orbitron (VF)     : logo wordmark, big final-score number
##   ui      — Rajdhani Medium   : default UI sans (labels, subtitles)
##   ui_bold — Rajdhani Bold     : emphasis
##   mono    — Share Tech Mono   : mono captions, taglines, debug readouts
##
## Loading is DEFENSIVE: if a font isn't imported yet (e.g. a headless `-s` run before
## `--import`), the role is left null and `apply()` simply no-ops that override — text
## falls back to the engine default instead of crashing. `ResourceLoader.exists` keeps a
## missing import from spamming a load error (which the verify runner would treat as a fail).

const ARCADE_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const DISPLAY_PATH := "res://assets/fonts/Orbitron-VF.ttf"
const UI_PATH := "res://assets/fonts/Rajdhani-Medium.ttf"
const UI_BOLD_PATH := "res://assets/fonts/Rajdhani-Bold.ttf"
const MONO_PATH := "res://assets/fonts/ShareTechMono-Regular.ttf"

var arcade: FontFile
var display: FontFile
var ui: FontFile
var ui_bold: FontFile
var mono: FontFile

## A default Theme (Rajdhani UI sans) for Control trees that want to set `theme` once
## rather than per-label overrides. Built only if the UI font loaded.
var theme: Theme


func _ready() -> void:
	load_fonts()


func load_fonts() -> void:
	arcade = _font(ARCADE_PATH)
	display = _font(DISPLAY_PATH)
	ui = _font(UI_PATH)
	ui_bold = _font(UI_BOLD_PATH)
	mono = _font(MONO_PATH)
	if ui != null:
		theme = Theme.new()
		theme.default_font = ui
		theme.default_font_size = 36


func _font(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		return null
	var r: Resource = load(path)
	return r if r is FontFile else null


## Apply a font role (and optional size) to a Label/Control, no-op for a null font so it
## is safe before import. Keeps callers to a single line.
func apply(ctrl: Control, font: FontFile, size: int = -1) -> void:
	if ctrl == null:
		return
	if font != null:
		ctrl.add_theme_font_override("font", font)
	if size > 0:
		ctrl.add_theme_font_size_override("font_size", size)
