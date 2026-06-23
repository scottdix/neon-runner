extends Node
## Loadout (autoload `Loadout`, #67) — the player's ship cosmetics + their persistence.
##
## Holds the three customization axes shown in the Garage (docs/design/SCREENS.md 05):
## hull colour, trail style, and engine. State is a small set of indices into fixed
## option lists; this is the single source of truth the Garage drives and the in-run ship
## reads. Mutations persist immediately to `user://loadout.cfg` and announce themselves on
## the Events bus (`loadout_changed`) so any listener (the Garage preview, the live ship)
## recolours without anyone holding a direct reference (CLAUDE.md decoupling).
##
## Colour lives in two spaces (see Palette): the HUD/LDR swatches for the menu UI
## (`hull_colors`), and the matching HDR ship-glow colours that clear the bloom threshold
## in-run (`hull_colors_hdr`). The two arrays are index-aligned: swatch i ↔ glow i.
##
## Only depends on Events + Palette. Both are plain `const`/`signal` containers, so the
## class is safe under the headless `-s` loop (no other autoload _ready ordering needed).

## Trail-style option labels (Garage chip row). Compile-time constant — no Palette here.
const TRAILS := ["SLEEK", "HELIX", "RIBBON"]
## Engine option labels (Garage chip row).
const ENGINES := ["STD", "PULSAR", "WARP"]

const SAVE_PATH := "user://loadout.cfg"
const SAVE_SECTION := "loadout"

## Selected hull-colour index (into `hull_colors()` / `hull_colors_hdr()`).
var hull_index := 0
## Selected trail-style index (into `TRAILS`).
var trail_index := 0
## Selected engine index (into `ENGINES`).
var engine_index := 0


func _ready() -> void:
	load_loadout()


## The HUD/LDR swatch colours shown in the Garage hull-colour row (crisp, out of bloom).
## Built at runtime because Palette is an autoload, not a compile-time constant.
func hull_colors() -> Array[Color]:
	return [
		Palette.ACCENT_CYAN_HUD, Palette.MENU_MAGENTA_HUD,
		Palette.MENU_MINT_HUD, Palette.COMBO_ORANGE_HUD,
	]


## The HDR ship-glow colours for the in-run ship, index-aligned to `hull_colors()`.
## These are pushed > 1.0 so the WorldEnvironment bloom catches them (the neon effect).
func hull_colors_hdr() -> Array[Color]:
	return [
		Palette.SHIP_CYAN, Palette.GATE_MULTIPLY,
		Palette.SUCCESS_GREEN, Color(3.8, 1.6, 0.4, 1.0),
	]


## The currently selected HUD swatch colour (for the Garage preview / menu UI).
func hull_color() -> Color:
	var colors := hull_colors()
	return colors[clampi(hull_index, 0, colors.size() - 1)]


## The currently selected HDR ship-glow colour (for the in-run ship).
func hull_color_hdr() -> Color:
	var colors := hull_colors_hdr()
	return colors[clampi(hull_index, 0, colors.size() - 1)]


## Select a hull colour by index. Clamped to the option count; a no-op if unchanged,
## otherwise assigns, persists, and announces `Events.loadout_changed`.
func set_hull(i: int) -> void:
	var clamped := clampi(i, 0, hull_colors().size() - 1)
	if clamped == hull_index:
		return
	hull_index = clamped
	save_loadout()
	Events.loadout_changed.emit()


## Select a trail style by index (see `set_hull` for the persist/emit contract).
func set_trail(i: int) -> void:
	var clamped := clampi(i, 0, TRAILS.size() - 1)
	if clamped == trail_index:
		return
	trail_index = clamped
	save_loadout()
	Events.loadout_changed.emit()


## Select an engine by index (see `set_hull` for the persist/emit contract).
func set_engine(i: int) -> void:
	var clamped := clampi(i, 0, ENGINES.size() - 1)
	if clamped == engine_index:
		return
	engine_index = clamped
	save_loadout()
	Events.loadout_changed.emit()


## Best-effort restore from `user://loadout.cfg`. A missing file or absent key keeps the
## default (0) for that axis; indices are re-clamped in case the option lists shrank.
func load_loadout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	hull_index = clampi(int(cfg.get_value(SAVE_SECTION, "hull", hull_index)),
		0, hull_colors().size() - 1)
	trail_index = clampi(int(cfg.get_value(SAVE_SECTION, "trail", trail_index)),
		0, TRAILS.size() - 1)
	engine_index = clampi(int(cfg.get_value(SAVE_SECTION, "engine", engine_index)),
		0, ENGINES.size() - 1)


## Persist the current selection to `user://loadout.cfg`.
func save_loadout() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "hull", hull_index)
	cfg.set_value(SAVE_SECTION, "trail", trail_index)
	cfg.set_value(SAVE_SECTION, "engine", engine_index)
	cfg.save(SAVE_PATH)
