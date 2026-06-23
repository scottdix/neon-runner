extends Resource
class_name SpliceMod
## SpliceMod — a power-up modifier for the Splice Lab (#68, docs/design/SCREENS.md).
##
## A mod has a display name, an operator (`op`, e.g. "x2" / "+5"), the stat it touches
## (`stat`, e.g. "SPEED" / "SHOTS" / "RATE"), a magnitude, and an `accent` colour role.
## SpliceLab fuses two equipped mods into a spliced output.
##
## Mods can be authored as `.tres` instances, but SpliceLab seeds its default inventory in
## code via the static `make()` factory (no `.tres` needed for the starter set). Consumers
## preload this script by PATH (not the `class_name`) — the headless `-s` loop has no global
## class cache without `--import` — but the `class_name` stays so `.tres` files can type it.
##
## `accent` is one of {"cyan","magenta","gold","mint"}; `accent_color()` maps it to the
## matching Palette HUD token so the screen never hardcodes hex.

## Display name, e.g. "SPREAD FIRE".
@export var mod_name: String = ""
## Operator string, e.g. "x2" (multiply) or "+5" (add).
@export var op: String = ""
## The stat the mod modifies, e.g. "SPEED", "SHOTS", "RATE".
@export var stat: String = ""
## The operator's numeric magnitude (2.0 for "x2", 5.0 for "+5").
@export var magnitude: float = 0.0
## Colour role — one of {"cyan","magenta","gold","mint"}. See `accent_color()`.
@export var accent: String = "cyan"


## Factory: new a SpliceMod with all fields set. Lets SpliceLab seed an inventory in code
## without authoring `.tres` files.
static func make(p_name: String, p_op: String, p_stat: String, p_mag: float,
		p_accent: String) -> SpliceMod:
	var m := SpliceMod.new()
	m.mod_name = p_name
	m.op = p_op
	m.stat = p_stat
	m.magnitude = p_mag
	m.accent = p_accent
	return m


## Map this mod's `accent` role to the matching Palette HUD token. Unknown roles fall back
## to cyan (the primary accent). Colour stays out of the screen — Palette is the source.
func accent_color() -> Color:
	match accent:
		"magenta":
			return Palette.MENU_MAGENTA_HUD
		"gold":
			return Palette.MENU_GOLD_HUD
		"mint":
			return Palette.MENU_MINT_HUD
		_:
			return Palette.ACCENT_CYAN_HUD
