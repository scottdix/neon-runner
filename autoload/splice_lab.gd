extends Node
## SpliceLab (autoload `SpliceLab`) — the Splice Lab data model (#68, docs/design/SCREENS.md).
##
## Holds the power-up modifier inventory + two equip slots, fuses the two equipped mods into
## a single spliced output, and persists the slot selection. The Splice Lab screen
## (`assets/ui/splice.gd`) is purely data-driven off this singleton; it never holds a direct
## ref to the lab and re-renders when `Events.splice_changed` fires (Events-bus decoupling,
## CLAUDE.md). The starter inventory is seeded in code via `SpliceMod.make()`.
##
## SpliceMod is preloaded by PATH (not its `class_name`) so this parses in the headless `-s`
## loop where the global class cache isn't built without `--import`.

const MOD := preload("res://resources/splice_mod.gd")

## The label shown in the INPUT node — the un-modded base gun the splice builds on.
const BASE_INPUT := "BASE GUN"

const SAVE_PATH := "user://splice.cfg"
const SAVE_SECTION := "splice"

## Owned modifiers (Array of SpliceMod). Seeded in `_ready()`.
var inventory: Array = []
## Index into `inventory` equipped in slot A, or -1 when empty.
var slot_a: int = -1
## Index into `inventory` equipped in slot B, or -1 when empty.
var slot_b: int = -1
## The last fused output, as a Dictionary {name, detail}. Empty until `splice()` runs.
var active_output: Dictionary = {}


## Seed the default inventory, then restore the persisted slot selection.
func _ready() -> void:
	_seed_inventory()
	load_splice()


## Populate the starter inventory (matches docs/design/SCREENS.md). Idempotent — clears first
## so a re-seed (e.g. a test calling it explicitly) doesn't duplicate cards.
func _seed_inventory() -> void:
	inventory = [
		MOD.make("SPREAD FIRE", "x2", "SPEED", 2.0, "cyan"),
		MOD.make("SHIELD GATE", "+5", "SHOTS", 5.0, "mint"),
		MOD.make("GRID BURST", "x2", "RATE", 2.0, "gold"),
	]


## Equip the inventory item at `i` into slot A.
func equip_a(i: int) -> void:
	slot_a = i
	save_splice()
	Events.splice_changed.emit()


## Equip the inventory item at `i` into slot B.
func equip_b(i: int) -> void:
	slot_b = i
	save_splice()
	Events.splice_changed.emit()


## Equip the inventory item at `i` into the first empty slot (A, then B). If both are full,
## the newest selection replaces slot B. This is the tap-a-card path the screen uses.
func equip_next(i: int) -> void:
	if slot_a == -1:
		slot_a = i
	elif slot_b == -1:
		slot_b = i
	else:
		slot_b = i
	save_splice()
	Events.splice_changed.emit()


## Empty both slots (and clear the active output).
func clear_slots() -> void:
	slot_a = -1
	slot_b = -1
	active_output = {}
	save_splice()
	Events.splice_changed.emit()


## True when both slots hold a valid inventory index — the precondition for `splice()`.
func can_splice() -> bool:
	return _is_valid(slot_a) and _is_valid(slot_b)


## Fuse the two equipped mods into a spliced output. Returns (and stores in `active_output`)
## a Dictionary {name, detail}:
##   • name   — "<ACCENT> SPREAD", coloured by slot A's accent (e.g. "GOLD SPREAD").
##   • detail — the two mods' effects joined, e.g. "10 SHOTS · x2 RATE" — slot A's
##              magnitude×slot B's magnitude applied to slot B's stat, then slot B's op/stat.
## No-op returning the empty Dictionary when the slots aren't both filled. Emits
## `Events.splice_changed` so listeners refresh.
func splice() -> Dictionary:
	if not can_splice():
		return active_output
	active_output = preview_output()
	Events.splice_changed.emit()
	return active_output


## Compute the fused output Dictionary {name, detail} WITHOUT mutating `active_output` or
## emitting — for the screen's live OUTPUT-box preview, which runs inside a rebuild that is
## itself driven by `splice_changed` (emitting here would recurse). Returns an empty
## Dictionary when the slots aren't both filled.
func preview_output() -> Dictionary:
	if not can_splice():
		return {}
	var a: SpliceMod = inventory[slot_a]
	var b: SpliceMod = inventory[slot_b]
	# Fused magnitude: slot A scales slot B's effect. Shown as an integer count.
	var fused: int = int(a.magnitude * b.magnitude)
	var name_str: String = "%s SPREAD" % _accent_word(a.accent)
	var detail: String = "%d %s · %s %s" % [fused, b.stat, a.op, a.stat]
	return {"name": name_str, "detail": detail}


## The current output's display name, or `BASE_INPUT` when nothing has been spliced.
func active_output_name() -> String:
	return active_output.get("name", BASE_INPUT)


## Structured, NUMERIC view of the equipped splice for a RUN to consume (#68). `active_output`
## carries a DISPLAY string ("10 SHOTS · x2 RATE") for the screen; this is the machine-readable
## twin the fleet reads at run start to scale its fire-rate / spread / projectile-speed and seed
## starting projectiles. Returns a Dictionary with these keys, always present:
##   • rate_mult                — fire-rate multiplier (1.0 = today's behaviour)
##   • spread_mult              — stream-spread multiplier (1.0 = unchanged)
##   • speed_mult               — projectile-speed multiplier (1.0 = unchanged)
##   • start_projectiles_bonus  — flat bullets added to the starting swarm (0 = none)
##
## NEUTRAL default ({1.0, 1.0, 1.0, 0}) whenever nothing is spliced or a slot is empty, so a
## fresh run with no Splice Lab interaction behaves EXACTLY as before (verify_combat invariant).
## Folding: each equipped mod contributes by its `stat`. Slot A's magnitude scales slot B (the
## same A-scales-B rule the display fusion uses), so the FUSED magnitude (a.mag × b.mag) is what
## actually lands on slot B's stat; slot A also applies its own magnitude to ITS stat. An "x"
## op is multiplicative (folds into the *_mult), a "+" op is additive (RATE/SPEED fold a
## fractional boost, SHOTS folds the flat count).
func active_modifiers() -> Dictionary:
	var fx := {
		"rate_mult": 1.0,
		"spread_mult": 1.0,
		"speed_mult": 1.0,
		"start_projectiles_bonus": 0,
	}
	if not can_splice():
		return fx
	var a: SpliceMod = inventory[slot_a]
	var b: SpliceMod = inventory[slot_b]
	# Slot B is the "scaled" stat: slot A's magnitude amplifies it (fused = a.mag × b.mag).
	_fold_mod(fx, b.op, b.stat, a.magnitude * b.magnitude)
	# Slot A also lands its own raw effect on its own stat.
	_fold_mod(fx, a.op, a.stat, a.magnitude)
	return fx


## Apply one mod's numeric effect into the accumulating `fx` dict. `op` "x*" is multiplicative
## (scales the matching *_mult), "+*" is additive. Stat routing:
##   RATE  -> rate_mult     SPEED -> speed_mult     SHOTS -> start_projectiles_bonus (+ spread)
## A larger SHOTS swarm also widens visually, so an additive SHOTS nudges spread_mult a touch;
## an "x" SHOTS scales the flat bonus off a baseline so a fresh swarm still gets a sane count.
func _fold_mod(fx: Dictionary, op: String, stat: String, mag: float) -> void:
	var is_mult: bool = op.begins_with("x") or op.begins_with("X") or op.begins_with("*")
	match stat:
		"RATE":
			if is_mult:
				fx["rate_mult"] = float(fx["rate_mult"]) * mag
			else:
				fx["rate_mult"] = float(fx["rate_mult"]) + mag * 0.1
		"SPEED":
			if is_mult:
				fx["speed_mult"] = float(fx["speed_mult"]) * mag
			else:
				fx["speed_mult"] = float(fx["speed_mult"]) + mag * 0.1
		"SHOTS":
			if is_mult:
				fx["start_projectiles_bonus"] = int(fx["start_projectiles_bonus"]) + int(mag)
			else:
				fx["start_projectiles_bonus"] = int(fx["start_projectiles_bonus"]) + int(mag)
			# A denser starting swarm also reads a little wider.
			fx["spread_mult"] = float(fx["spread_mult"]) + 0.02 * mag


## Restore slot_a/slot_b from the ConfigFile. Indices are validated against the seeded
## inventory and reset to -1 if stale (e.g. inventory shrank between builds).
func load_splice() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	slot_a = int(cfg.get_value(SAVE_SECTION, "slot_a", -1))
	slot_b = int(cfg.get_value(SAVE_SECTION, "slot_b", -1))
	if slot_a != -1 and not _is_valid(slot_a):
		slot_a = -1
	if slot_b != -1 and not _is_valid(slot_b):
		slot_b = -1


## Persist slot_a/slot_b to the ConfigFile.
func save_splice() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "slot_a", slot_a)
	cfg.set_value(SAVE_SECTION, "slot_b", slot_b)
	cfg.save(SAVE_PATH)


## True when `i` is a real index into `inventory`.
func _is_valid(i: int) -> bool:
	return i >= 0 and i < inventory.size()


## The accent role uppercased for the fused output name (e.g. "gold" -> "GOLD").
func _accent_word(accent: String) -> String:
	return accent.to_upper()
