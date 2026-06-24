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
## PerkDef/DraftOffer preloaded by PATH (not class_name) for the headless `-s` loop — the global
## class cache isn't built without --import. These back the #78 meta draft + drafted perk carries.
const PERK := preload("res://resources/perk_def.gd")
const DRAFT_OFFER := preload("res://resources/draft_offer.gd")

## Draft shelf size + reroll economics (#78). Rerolls cost an ESCALATING amount of the persistent
## token wallet (Brotato-style): the Nth reroll of a stock costs REROLL_BASE_COST * (N+1).
const DRAFT_SHELF_SIZE := 3
const REROLL_BASE_COST := 5

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

## --- #78 meta economy --------------------------------------------------------
## Persistent EARNED-ONLY token wallet. GameState banks a run's haul here on a terminal
## (deposit_tokens); rerolls spend from it (spend_tokens). Persisted in splice.cfg; an old save
## without the key loads as 0.
var tokens: int = 0

## Drafted HORIZONTAL perk carries (Array of PerkDef). Folded into active_modifiers() AFTER the
## spliced weapon. Persisted as a resource_path list; an old save without the key loads empty.
var perks: Array[PerkDef] = []

## --- #78 draft shelf ---------------------------------------------------------
## The current draft offers (Array of DraftOffer). Built by stock(); a pick() carries its perk,
## reroll() re-rolls the unlocked slots for an escalating token cost, lock(i) freezes a slot.
var shelf: Array = []
## How many times the current stock has been rerolled (drives the escalating reroll cost).
var reroll_count: int = 0
## Per-slot lock flags, parallel to `shelf` (a locked slot survives a reroll).
var locked: Array[bool] = []

## Draft RNG (#78) — the shelf draws RANDOMLY from the full perk pool, so a reroll genuinely
## re-rolls (not the old positional pool[i] that re-drew the IDENTICAL slot) AND every authored perk
## can surface (the old pool[i % size] for i in {0,1,2} could only ever show pool[0..2], stranding
## half a 6-perk pool). Seeded in _ready; the headless verify can set `_draft_rng.seed` for
## deterministic offers. Off-tree (a bare unit test) it's unseeded — fine, the draw is still random.
var _draft_rng := RandomNumberGenerator.new()


## Seed the default inventory, then restore the persisted slot selection.
func _ready() -> void:
	_draft_rng.randomize()
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
		# #78 token-economy keys, NEUTRAL at 1.0. Fleet.apply_splice reads only the first 4 keys,
		# so these are inert to firing — the verify_combat/verify_splice invariant (a fresh run
		# fires EXACTLY as before) holds because the first 4 keys are UNCHANGED with nothing
		# spliced or drafted. These feed the TokenLayer (magnet) + Targets (_token_value bounty).
		"token_magnet_mult": 1.0,
		"token_bounty_mult": 1.0,
	}
	# Splice fold (UNCHANGED): only when both weapon slots are filled.
	if can_splice():
		var a: SpliceMod = inventory[slot_a]
		var b: SpliceMod = inventory[slot_b]
		# Slot B is the "scaled" stat: slot A's magnitude amplifies it (fused = a.mag × b.mag).
		_fold_mod(fx, b.op, b.stat, a.magnitude * b.magnitude)
		# Slot A also lands its own raw effect on its own stat.
		_fold_mod(fx, a.op, a.stat, a.magnitude)
	# Drafted perk fold (#78): each carried perk folds AFTER the splice (horizontal carries —
	# they add new options, not stat-creep). A perk folds into the token keys (or the weapon
	# keys for RATE/SPEED/SHOTS perks), leaving the NEUTRAL baseline intact when `perks` is empty.
	for p in perks:
		if p != null:
			p.fold(fx)
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


# --- #78 token wallet --------------------------------------------------------

## Bank `n` earned tokens into the persistent wallet (GameState calls this on a run terminal).
## No-op on a non-positive amount. Persists + announces draft_changed (the shelf affordability /
## wallet display refreshes off it).
func deposit_tokens(n: int) -> void:
	if n <= 0:
		return
	tokens += n
	save_splice()
	Events.draft_changed.emit()


## Spend `n` tokens from the wallet (rerolls). Returns true and deducts when affordable, else
## false and leaves the wallet untouched. Persists + announces on a successful spend.
func spend_tokens(n: int) -> bool:
	if n <= 0:
		return true
	if tokens < n:
		return false
	tokens -= n
	save_splice()
	Events.draft_changed.emit()
	return true


# --- #78 drafted perk carries ------------------------------------------------

## Add a drafted perk to the carried set. Persists + announces (active_modifiers folds it).
## BOUNDED: a perk that comes from an authored .tres (has a resource_path) is deduped by that path,
## so drafting the same authored perk N times does NOT stack it into a permanent power ladder (e.g.
## rate_overcharge ×1.2 five times -> ×2.49 forever) — the #1 design-note failure mode (GATE_ECONOMY
## lane 3: meta is HORIZONTAL, not vertical stat-creep). The carry stays a SET of distinct authored
## perks. (Bare code-built perks with no path — the unit-test fixtures — are always added so the
## verify's fold assertions are unaffected.)
func add_perk(p: PerkDef) -> void:
	if p == null:
		return
	if p.resource_path != "" and _has_perk_path(p.resource_path):
		return                       # already carried — dedup, don't snowball
	perks.append(p)
	save_splice()
	Events.draft_changed.emit()


## True when a perk with `path` is already in the carried set (the dedup guard).
func _has_perk_path(path: String) -> bool:
	for p in perks:
		if p != null and p.resource_path == path:
			return true
	return false


## Drop all carried perks (e.g. a new meta loadout). Persists + announces.
func clear_perks() -> void:
	perks.clear()
	save_splice()
	Events.draft_changed.emit()


# --- #78 token-economy modifier helpers --------------------------------------

## The drafted token-magnet (pickup-radius) multiplier — magnetism widens the FLAT pickup radius
## (a headless-verifiable wider catch, not an attractive pull). Reads the folded active_modifiers.
func magnet_radius_mult() -> float:
	return float(active_modifiers().get("token_magnet_mult", 1.0))


## The drafted token-bounty multiplier — scales the token VALUE a kill drops (Targets reads it).
func bounty_mult() -> float:
	return float(active_modifiers().get("token_bounty_mult", 1.0))


# --- #78 draft shelf API -----------------------------------------------------

## Build a fresh draft shelf of DRAFT_SHELF_SIZE offers, resetting the reroll counter + locks.
## Slot perks are drawn from the perk pool (the data author seeds data/perks/*.tres; the
## scaffold falls back to a tiny code pool so the shelf is never empty). Announces draft_changed.
func stock() -> void:
	reroll_count = 0
	locked.clear()
	shelf.clear()
	var pool := _perk_pool()
	# Deal DISTINCT perks across the visible slots (no duplicate within one stock when the pool is
	# large enough) by shuffling a working copy and dealing off the top. RANDOM, not the old
	# positional pool[i] — so every authored perk can appear and a reroll truly re-rolls.
	var deal: Array = _shuffled(pool)
	for i in DRAFT_SHELF_SIZE:
		locked.append(false)
		shelf.append(DRAFT_OFFER.make(_deal_one(deal, pool, i)))
	Events.draft_changed.emit()


## Pick the offer at slot `i`: carry its perk and re-stock for the next pick. FREE (no token cost) —
## the pick is the reward; rerolls are the cost. LOCKED slots SURVIVE the pick (Brotato — a frozen
## offer the player paid attention to isn't silently discarded the instant they pick another slot);
## only the picked + unlocked slots re-roll. No-op on a bad index / empty slot.
func pick(i: int) -> void:
	if i < 0 or i >= shelf.size():
		return
	var offer: DraftOffer = shelf[i]
	if offer != null and offer.perk != null:
		add_perk(offer.perk)        # persists + emits draft_changed
	# Re-stock for the next pick, PRESERVING any locked slots (re-roll only the picked + unlocked
	# ones). The picked slot is treated as unlocked even if it was locked — its perk is now carried.
	if i < locked.size():
		locked[i] = false
	_restock_unlocked()              # emits draft_changed


## Re-stock the shelf KEEPING locked offers and re-rolling the unlocked slots, resetting the reroll
## price cycle (a new stock). Used by pick() so a locked offer survives across picks (not just
## rerolls). Announces draft_changed.
func _restock_unlocked() -> void:
	reroll_count = 0
	if shelf.is_empty():
		stock()
		return
	var pool := _perk_pool()
	var deal: Array = _shuffled(pool)
	for i in shelf.size():
		if i < locked.size() and locked[i]:
			continue                 # frozen slot survives the re-stock
		shelf[i] = DRAFT_OFFER.make(_deal_one(deal, pool, i))
	Events.draft_changed.emit()


## Skip the draft entirely (take nothing) — clears the shelf. Announces draft_changed.
func skip() -> void:
	shelf.clear()
	locked.clear()
	reroll_count = 0
	Events.draft_changed.emit()


## Reroll the UNLOCKED slots for the current escalating cost (REROLL_BASE_COST * (reroll_count+1)).
## Returns true on success (cost spent, slots re-rolled), false when unaffordable. Locked slots
## (lock(i)) keep their offer across the reroll. Announces draft_changed via spend/stock paths.
func reroll() -> bool:
	if shelf.is_empty():
		return false
	var cost: int = reroll_cost()
	if not spend_tokens(cost):       # emits draft_changed on success
		return false
	reroll_count += 1
	var pool := _perk_pool()
	# Re-roll the UNLOCKED slots with a fresh shuffled deal, preferring perks not already on a LOCKED
	# slot (so a reroll shows genuinely new options where the pool allows). Locked slots are untouched.
	var deal: Array = _shuffled(pool)
	for i in shelf.size():
		if i < locked.size() and locked[i]:
			continue                 # frozen slot survives the reroll
		shelf[i] = DRAFT_OFFER.make(_deal_one(deal, pool, i))
	Events.draft_changed.emit()
	return true


## The token cost of the NEXT reroll (escalates with reroll_count).
func reroll_cost() -> int:
	return REROLL_BASE_COST * (reroll_count + 1)


## Freeze/unfreeze slot `i` across rerolls (toggles). Announces draft_changed.
func lock(i: int) -> void:
	if i < 0 or i >= locked.size():
		return
	locked[i] = not locked[i]
	if i < shelf.size() and shelf[i] != null:
		(shelf[i] as DraftOffer).locked = locked[i]
	Events.draft_changed.emit()


## The perk pool the shelf draws from: the authored data/perks/*.tres if present, else a small
## code fallback so the draft is always populated in the headless loop / before data lands.
func _perk_pool() -> Array:
	var pool: Array = []
	var dir := DirAccess.open("res://data/perks")
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and (fn.ends_with(".tres") or fn.ends_with(".res")):
				var r: Resource = load("res://data/perks/" + fn)
				if r != null:
					pool.append(r)
			fn = dir.get_next()
		dir.list_dir_end()
	if pool.is_empty():
		# Scaffold fallback (the economy author replaces this with the 6 authored perks).
		pool = [
			PERK.make("MAGNETISM", "Wider token pickup radius.", "cyan",
				{"stat": "MAGNET", "op": "*", "magnitude": 1.5}),
			PERK.make("TOKEN BOUNTY", "Kills drop more tokens.", "gold",
				{"stat": "BOUNTY", "op": "*", "magnitude": 1.5}),
			PERK.make("RATE OVERCHARGE", "Faster fire.", "magenta",
				{"stat": "RATE", "op": "*", "magnitude": 1.2}),
		]
	return pool


## A shuffled working copy of the perk pool (the draft RNG, so a seeded verify is deterministic).
## stock()/reroll() deal off the FRONT of this so distinct slots get distinct perks while the deck
## lasts. A non-empty pool always yields a non-empty deal.
func _shuffled(pool: Array) -> Array:
	var deck: Array = pool.duplicate()
	# Fisher–Yates with the draft RNG (Array.shuffle uses the global RNG; this keeps it seedable).
	for k in range(deck.size() - 1, 0, -1):
		var j: int = _draft_rng.randi() % (k + 1)
		var tmp = deck[k]
		deck[k] = deck[j]
		deck[j] = tmp
	return deck


## Deal ONE perk for a slot: pop the next off the shuffled deck (distinct while it lasts); once the
## deck is exhausted (pool smaller than the shelf), fall back to a fresh random pick from the full
## pool so the slot is never empty. RANDOM throughout — a reroll genuinely re-rolls and every authored
## perk is reachable. `_i` is kept for signature stability with the old positional draw (unused now).
func _deal_one(deck: Array, pool: Array, _i: int) -> PerkDef:
	if not deck.is_empty():
		return deck.pop_front()
	if pool.is_empty():
		return null
	return pool[_draft_rng.randi() % pool.size()]


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
	# #78: token wallet + drafted perks. Both tolerate an OLD save without the keys (wallet -> 0,
	# perks -> empty) so existing splice.cfg files load clean. Perks persist as a resource_path
	# list; a path that no longer loads is skipped.
	tokens = int(cfg.get_value(SAVE_SECTION, "tokens", 0))
	perks.clear()
	var paths: Array = cfg.get_value(SAVE_SECTION, "perks", [])
	var seen: Dictionary = {}
	for p in paths:
		var sp: String = String(p)
		if seen.has(sp):
			continue                 # dedup an old save that may have stacked duplicates
		var r: Resource = load(sp)
		if r is PerkDef:
			seen[sp] = true
			perks.append(r)


## Persist slot_a/slot_b to the ConfigFile.
func save_splice() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "slot_a", slot_a)
	cfg.set_value(SAVE_SECTION, "slot_b", slot_b)
	cfg.set_value(SAVE_SECTION, "tokens", tokens)   # #78 persistent wallet
	# #78 drafted perks as a resource_path list (only perks that have a path persist).
	var paths: Array = []
	for p in perks:
		if p != null and p.resource_path != "":
			paths.append(p.resource_path)
	cfg.set_value(SAVE_SECTION, "perks", paths)
	cfg.save(SAVE_PATH)


## True when `i` is a real index into `inventory`.
func _is_valid(i: int) -> bool:
	return i >= 0 and i < inventory.size()


## The accent role uppercased for the fused output name (e.g. "gold" -> "GOLD").
func _accent_word(accent: String) -> String:
	return accent.to_upper()
