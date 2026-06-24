extends Resource
class_name PerkDef
## PerkDef — a drafted HORIZONTAL meta perk carried into a run (#78 draft).
##
## Spine-scaffold stub: holds the shape the economy author fleshes out. A perk has a display
## name/description, an accent colour role, and a single `effect` that folds into SpliceLab's
## active_modifiers() at run start. Effects are HORIZONTAL (new options / sidegrades, never raw
## stat-creep). Loaded by PATH in SpliceLab (no class_name cache under the headless `-s` loop),
## but the `class_name` stays so `.tres` instances can type it.
##
## effect = {stat, op, magnitude}:
##   • stat  — one of RATE | SPEED | SHOTS | MAGNET | BOUNTY
##   • op    — "*" (multiplicative) | "+" (additive)
##   • magnitude — the numeric amount

## Display name, e.g. "MAGNETISM".
@export var perk_name: String = ""
## Short flavour / effect description for the draft card.
@export var description: String = ""
## Accent colour role — one of {"cyan","magenta","gold","mint"}. See accent_color().
@export var accent: String = "cyan"
## The single fold effect — {"stat": String, "op": String, "magnitude": float}.
@export var effect: Dictionary = {"stat": "RATE", "op": "*", "magnitude": 1.0}


## Factory: new a PerkDef with all fields set (lets the data layer seed perks in code).
static func make(p_name: String, p_desc: String, p_accent: String, p_effect: Dictionary) -> PerkDef:
	var p := PerkDef.new()
	p.perk_name = p_name
	p.description = p_desc
	p.accent = p_accent
	p.effect = p_effect
	return p


## Fold this perk's effect into an accumulating active_modifiers `mods` dict. Routes its `stat`
## to the matching key (RATE->rate_mult, SPEED->speed_mult, SHOTS->start_projectiles_bonus,
## MAGNET->token_magnet_mult, BOUNTY->token_bounty_mult); "*" scales, "+" adds. Unknown keys
## are created defensively so a malformed perk can't crash the fold.
func fold(mods: Dictionary) -> void:
	var stat: String = String(effect.get("stat", "RATE"))
	var op: String = String(effect.get("op", "*"))
	var mag: float = float(effect.get("magnitude", 1.0))
	var key := _key_for(stat)
	if key == "":
		return
	var is_mult: bool = op.begins_with("*") or op.begins_with("x") or op.begins_with("X")
	if key == "start_projectiles_bonus":
		mods[key] = int(mods.get(key, 0)) + int(mag)
		return
	var cur: float = float(mods.get(key, 1.0))
	mods[key] = cur * mag if is_mult else cur + mag


func _key_for(stat: String) -> String:
	match stat:
		"RATE": return "rate_mult"
		"SPEED": return "speed_mult"
		"SHOTS": return "start_projectiles_bonus"
		"MAGNET": return "token_magnet_mult"
		"BOUNTY": return "token_bounty_mult"
	return ""


## Map the accent role to the matching Palette HUD token (Palette is the colour source).
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
