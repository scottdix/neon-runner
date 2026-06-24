extends Resource
class_name DifficultyProfile
## DifficultyProfile — the per-mode tuning DATA block for Easy/Medium/Hard (#80).
##
## One profile per difficulty mode (0=EASY, 1=MEDIUM, 2=HARD). It holds the multipliers /
## fractions the spine reads through the `Difficulty` autoload; the autoload caches the
## active profile (keyed by Settings.difficulty) and exposes its fields via typed readers so
## consumers never hold a profile reference.
##
## Profiles can be authored as `.tres`, but Difficulty seeds its {EASY,MEDIUM,HARD} set in
## code via the static `make()` factory (no `.tres` required — mirrors SpliceMod). Consumers
## preload this script by PATH (not the `class_name`) so it parses in the headless `-s` loop
## where the global class cache isn't built; the `class_name` stays so `.tres` can type it.
##
## THE keystone knob is `armor_chip_fraction` — it scales the #79 Rhombus per-hit FLOOR's
## SUB-THRESHOLD grind: a fraction > 0 (EASY/MEDIUM) lets a sustained SPRAY still chip a
## Rhombus down (taught-not-enforced), while HARD's 0.0 makes sub-threshold fire do TRUE 0
## damage — full immunity until the player focuses into a LANCE (Lance becomes mandatory).

## Display name shown on the mode selector ("EASY" / "MEDIUM" / "HARD").
@export var mode_name: String = "MEDIUM"
## Sub-threshold armor CHIP fraction (the #79 floor knob, mode-scaled). EASY 0.45 (forgiving
## grind), MEDIUM 0.15 (= the legacy const), HARD 0.0 (TRUE immunity — Lance mandatory).
@export var armor_chip_fraction: float = 0.15
## Negative-gate battery drain multiplier. EASY 0.7 (gentler), MEDIUM 1.0, HARD 1.35 (harsher).
@export var drain_mult: float = 1.0
## Enemy spawn-density multiplier (secondary _pick_kind/wave bias). EASY 0.8, MED 1.0, HARD 1.25.
@export var spawn_density_mult: float = 1.0
## Additive bias to the Rhombus archetype roll weight (more armor on harder). EASY/MED 0.0, HARD +0.10.
@export var rhombus_weight_bias: float = 0.0
## Negative-gate severity scale (DORMANT — no gate consumer this batch; parked field only).
@export var gate_negative_severity: float = 1.0
## Phase-director intensity scale (DORMANT — no phase consumer yet; parked field only).
@export var phase_intensity: float = 1.0
## UI tint role — one of {"mint","cyan","gold"} (EASY/MED/HARD). See accent_color().
@export var accent: String = "cyan"


## Factory: new a profile with every field set, so Difficulty can seed its mode set in code
## without authoring `.tres` files (mirrors SpliceMod.make()).
static func make(p_mode_name: String, p_chip: float, p_drain: float, p_density: float,
		p_rhombus_bias: float, p_gate_sev: float, p_phase: float, p_accent: String) -> DifficultyProfile:
	var p := DifficultyProfile.new()
	p.mode_name = p_mode_name
	p.armor_chip_fraction = p_chip
	p.drain_mult = p_drain
	p.spawn_density_mult = p_density
	p.rhombus_weight_bias = p_rhombus_bias
	p.gate_negative_severity = p_gate_sev
	p.phase_intensity = p_phase
	p.accent = p_accent
	return p


## Map this profile's `accent` role to the matching Palette HUD token (colour stays out of
## the screen — Palette is the source). Unknown roles fall back to cyan.
func accent_color() -> Color:
	match accent:
		"mint":
			return Palette.MENU_MINT_HUD
		"gold":
			return Palette.MENU_GOLD_HUD
		_:
			return Palette.ACCENT_CYAN_HUD
