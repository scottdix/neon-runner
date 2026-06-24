extends Resource
class_name DraftOffer
## DraftOffer — one slot on the meta draft shelf (#78 draft).
##
## Spine-scaffold stub: wraps a PerkDef with a per-slot `locked` flag (Brotato-style — a locked
## slot survives a reroll). Loaded by PATH in SpliceLab (no class_name cache under the headless
## `-s` loop); the `class_name` stays so `.tres` instances can type it. The economy author
## fleshes out any richer offer state (cost, rarity) on top of this shape.

## The perk this slot offers.
@export var perk: PerkDef
## True = this slot is frozen across rerolls (the player locked it).
@export var locked: bool = false


## Factory: wrap a PerkDef in a fresh (unlocked) offer.
static func make(p_perk: PerkDef) -> DraftOffer:
	var o := DraftOffer.new()
	o.perk = p_perk
	o.locked = false
	return o
