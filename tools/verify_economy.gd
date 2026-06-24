extends SceneTree
## Headless verification for the #78 Splice Lab economy — token drops + RNG perk draft.
##
## GPU-free: drives the pure logic on bare instances / the autoloads and writes a verdict file
## the runner polls for (CLAUDE.md gotchas). Scripts are loaded by PATH (no class_name cache
## under -s). Run:
##   tools/run-headless.sh res://tools/verify_economy.gd /tmp/verify_economy_result.txt
##
## Asserts:
##   1. PerkDef.fold routes RATE|SPEED|SHOTS|MAGNET|BOUNTY into the right active_modifiers key,
##      and SpliceLab.active_modifiers stays NEUTRAL with nothing spliced/drafted, folds a perk
##      numerically once drafted (and the first-4 weapon keys are UNTOUCHED by a token perk).
##   2. TokenLayer: a dropped token DRIFTS down (pure step y+), is ABSORBED only WITHIN the
##      magnet radius (a token just outside is NOT collected), and a MAGNET perk WIDENS the
##      radius so a token that was outside is now inside.
##   3. collect_token increments GameState.run_tokens and a terminal BANKS it to SpliceLab.tokens.
##   4. Draft shelf: stock fills DRAFT_SHELF_SIZE, pick carries a perk + re-stocks, reroll spends
##      an ESCALATING cost and re-rolls only UNLOCKED slots, lock freezes a slot, skip clears.

const RESULT_PATH := "/tmp/verify_economy_result.txt"

const NEUTRAL := {
	"rate_mult": 1.0, "spread_mult": 1.0, "speed_mult": 1.0, "start_projectiles_bonus": 0,
	"token_magnet_mult": 1.0, "token_bounty_mult": 1.0,
}


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var PerkS: GDScript = load("res://resources/perk_def.gd")
	var TokenS: GDScript = load("res://assets/economy/token_layer.gd")
	if PerkS == null or TokenS == null:
		lines.append("RESULT=FAIL (perk_def or token_layer script missing)"); _write(lines); return
	var lab: Node = root.get_node_or_null("SpliceLab")
	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if lab == null or gs == null or ev == null:
		lines.append("RESULT=FAIL (SpliceLab/GameState/Events autoloads missing)"); _write(lines); return

	# Clean meta state for determinism.
	lab.call("_seed_inventory")
	lab.call("clear_slots")
	lab.call("clear_perks")
	lab.set("tokens", 0)

	# --- 1) PerkDef.fold + active_modifiers neutrality/fold ---------------------
	# fold a MAGNET perk into a fresh neutral dict -> token_magnet_mult moves, weapon keys don't.
	var magnet: Resource = PerkS.call("make", "MAGNETISM", "", "cyan",
		{"stat": "MAGNET", "op": "*", "magnitude": 1.5})
	var fx := NEUTRAL.duplicate(true)
	magnet.call("fold", fx)
	if absf(float(fx["token_magnet_mult"]) - 1.5) > 0.0001:
		lines.append("fold FAIL: MAGNET perk did not land on token_magnet_mult (got %s)" % fx["token_magnet_mult"]); ok = false
	elif float(fx["rate_mult"]) != 1.0 or float(fx["speed_mult"]) != 1.0 or int(fx["start_projectiles_bonus"]) != 0:
		lines.append("fold FAIL: MAGNET perk leaked into the weapon keys"); ok = false
	else:
		lines.append("fold OK: MAGNET perk -> token_magnet_mult ×1.5, weapon keys untouched")

	# A BOUNTY perk routes to token_bounty_mult; a SHOTS perk adds the flat bonus.
	var bounty: Resource = PerkS.call("make", "BOUNTY", "", "gold",
		{"stat": "BOUNTY", "op": "*", "magnitude": 2.0})
	var shots: Resource = PerkS.call("make", "SWARM", "", "cyan",
		{"stat": "SHOTS", "op": "+", "magnitude": 4.0})
	var fx2 := NEUTRAL.duplicate(true)
	bounty.call("fold", fx2)
	shots.call("fold", fx2)
	if absf(float(fx2["token_bounty_mult"]) - 2.0) > 0.0001 or int(fx2["start_projectiles_bonus"]) != 4:
		lines.append("fold FAIL: BOUNTY/SHOTS perks mis-routed (bounty=%s shots=%s)" % [fx2["token_bounty_mult"], fx2["start_projectiles_bonus"]]); ok = false
	else:
		lines.append("fold OK: BOUNTY ×2.0 + SHOTS +4 routed correctly")

	# active_modifiers NEUTRAL with nothing spliced/drafted (the verify_combat invariant — the
	# first 4 keys must be exactly today's neutral so Fleet.apply_splice is a no-op).
	var base_fx: Dictionary = lab.call("active_modifiers")
	if not _is_neutral(base_fx):
		lines.append("baseline FAIL: nothing spliced/drafted is NOT the neutral baseline -> %s" % base_fx); ok = false
	else:
		lines.append("baseline OK: nothing spliced/drafted -> neutral {rate/spread/speed 1.0, shots 0, magnet/bounty 1.0}")

	# Draft a magnet perk -> active_modifiers folds it (token_magnet_mult moves off 1.0), weapon
	# keys STILL neutral (a token perk must not change firing).
	lab.call("add_perk", magnet)
	var drafted_fx: Dictionary = lab.call("active_modifiers")
	if absf(float(drafted_fx["token_magnet_mult"]) - 1.5) > 0.0001:
		lines.append("draft-fold FAIL: drafted MAGNET perk did not fold into active_modifiers (%s)" % drafted_fx["token_magnet_mult"]); ok = false
	elif float(drafted_fx["rate_mult"]) != 1.0 or float(drafted_fx["speed_mult"]) != 1.0 or int(drafted_fx["start_projectiles_bonus"]) != 0:
		lines.append("draft-fold FAIL: a drafted token perk changed the firing keys"); ok = false
	else:
		lines.append("draft-fold OK: drafted MAGNET -> magnet_radius_mult=%.2f, firing keys unchanged" % float(lab.call("magnet_radius_mult")))
	lab.call("clear_perks")

	# --- 2) TokenLayer drift + radius-gated absorb -------------------------------
	# A bare layer (off-tree) reads magnet_mult via the SpliceLab autoload at /root — which is
	# present here. Clear perks first so the radius is the BASE (×1.0).
	var layer: Node2D = TokenS.new()
	root.add_child(layer)
	layer.call("wire_events")
	layer.call("set_ship_line", 1680.0)
	# Steer the ship to a known x.
	ev.call("emit_signal", "player_steered", 540.0, 0.5)
	var base_r: float = layer.call("magnet_radius")
	lines.append("token radius: base=%.1f (BASE_PICKUP_RADIUS × magnet_mult 1.0)" % base_r)

	# Drop a token slightly BELOW the ship line but OUTSIDE the radius (so a couple of drift steps
	# bring it INTO range — proving drift y+ and the radius gate). Place it base_r+40 above the
	# ship line so it must drift down to be caught.
	var drop_y := 1680.0 - (base_r + 40.0)
	ev.call("emit_signal", "token_dropped", Vector2(540.0, drop_y), 3)
	var start_tokens := int(gs.get("run_tokens"))
	# One small step: token moves down a little, still outside the radius -> NOT collected.
	layer.call("step", 0.05)
	if layer.call("live_count") != 1 or int(gs.get("run_tokens")) != start_tokens:
		lines.append("absorb FAIL: token absorbed OUTSIDE the magnet radius (auto-collect leak)"); ok = false
	else:
		lines.append("absorb OK: token outside radius is NOT collected (no auto-collect)")
	# Now step enough seconds for the token to drift into the radius -> collected exactly once.
	var collected := [0]
	var on_collect := func(_at: Vector2, _v: int, _w: int) -> void: collected[0] += 1
	ev.connect("token_collected", on_collect)
	for s in 30:
		layer.call("step", 0.05)
	ev.disconnect("token_collected", on_collect)
	if layer.call("live_count") != 0 or collected[0] != 1:
		lines.append("drift FAIL: token did not drift into radius + collect once (live=%d emits=%d)" % [layer.call("live_count"), collected[0]]); ok = false
	elif int(gs.get("run_tokens")) != start_tokens + 3:
		lines.append("collect FAIL: collect_token did not add the value to run_tokens (%d != %d)" % [int(gs.get("run_tokens")), start_tokens + 3]); ok = false
	else:
		lines.append("drift+collect OK: token drifted into radius, collected once, run_tokens += 3")

	# Magnetism WIDENS the radius: draft the magnet perk and confirm the live radius grows, and a
	# token at the SAME just-outside distance is now caught on the FIRST step (was not before).
	lab.call("add_perk", magnet)
	var wide_r: float = layer.call("magnet_radius")
	if wide_r <= base_r + 0.5:
		lines.append("magnet FAIL: a drafted MAGNET perk did not widen the pickup radius (%.1f <= %.1f)" % [wide_r, base_r]); ok = false
	else:
		lines.append("magnet OK: drafted MAGNET widened radius %.1f -> %.1f" % [base_r, wide_r])
	# Drop a token at the OLD edge (base_r + 10 above the ship line) — inside the WIDE radius, so
	# the very first step absorbs it (it would have been outside the base radius).
	var edge_y := 1680.0 - (base_r + 10.0)
	var before := int(gs.get("run_tokens"))
	ev.call("emit_signal", "token_dropped", Vector2(540.0, edge_y), 2)
	layer.call("step", 0.016)
	if int(gs.get("run_tokens")) != before + 2 or layer.call("live_count") != 0:
		lines.append("magnet-catch FAIL: widened radius did not catch the near-edge token"); ok = false
	else:
		lines.append("magnet-catch OK: near-edge token caught by the widened radius on first step")
	layer.free()
	lab.call("clear_perks")

	# --- 3) terminal banks the run haul to the persistent wallet -----------------
	lab.set("tokens", 0)
	gs.call("start_run")                 # resets run_tokens to 0
	gs.call("collect_token", 7)
	gs.call("collect_token", 5)
	if int(gs.get("run_tokens")) != 12:
		lines.append("wallet FAIL: run_tokens not 12 after two collects (%d)" % int(gs.get("run_tokens"))); ok = false
	# Fail the run (a terminal) -> the 12-token haul banks to SpliceLab.tokens.
	gs.call("fail_run")
	if int(lab.get("tokens")) != 12:
		lines.append("bank FAIL: a terminal did not deposit run_tokens into the wallet (%d)" % int(lab.get("tokens"))); ok = false
	else:
		lines.append("bank OK: terminal banked run_tokens (12) into the persistent wallet")

	# --- 4) draft shelf: stock / pick / reroll(escalating) / lock / skip ---------
	lab.call("clear_perks")
	lab.set("tokens", 100)
	lab.call("stock")
	var shelf: Array = lab.get("shelf")
	# DRAFT_SHELF_SIZE is a const (not a member var, so get() won't read it); the stocked shelf
	# size IS that const, so capture it from the freshly-stocked shelf.
	var shelf_size: int = shelf.size()
	if shelf_size < 1 or int(lab.get("reroll_count")) != 0:
		lines.append("stock FAIL: stock() did not fill DRAFT_SHELF_SIZE offers / reset reroll_count"); ok = false
	else:
		lines.append("stock OK: shelf has %d offers, reroll_count reset" % shelf.size())

	# reroll cost escalates: first = REROLL_BASE_COST*1, second = *2 ...
	var c1: int = int(lab.call("reroll_cost"))
	var w0: int = int(lab.get("tokens"))
	var r1: bool = bool(lab.call("reroll"))
	var c2: int = int(lab.call("reroll_cost"))
	var w1: int = int(lab.get("tokens"))
	if not r1 or w1 != w0 - c1 or c2 <= c1:
		lines.append("reroll FAIL: cost not spent or not escalating (c1=%d c2=%d w0=%d w1=%d)" % [c1, c2, w0, w1]); ok = false
	else:
		lines.append("reroll OK: spent %d, cost escalated %d -> %d" % [c1, c1, c2])

	# lock(0) freezes slot 0 across a reroll: capture its perk, reroll, slot 0 unchanged.
	lab.call("lock", 0)
	var locked0 = (lab.get("shelf")[0]).perk
	lab.call("reroll")
	var after0 = (lab.get("shelf")[0]).perk
	var locks: Array = lab.get("locked")
	if not bool(locks[0]) or after0 != locked0:
		lines.append("lock FAIL: a locked slot did not survive the reroll"); ok = false
	else:
		lines.append("lock OK: locked slot 0 kept its perk across a reroll")

	# pick(1) carries the offered perk into perks[] and re-stocks a fresh shelf.
	var n_perks_before: int = (lab.get("perks") as Array).size()
	lab.call("pick", 1)
	var n_perks_after: int = (lab.get("perks") as Array).size()
	if n_perks_after != n_perks_before + 1 or (lab.get("shelf") as Array).size() != shelf_size:
		lines.append("pick FAIL: pick did not carry a perk + re-stock (perks %d->%d)" % [n_perks_before, n_perks_after]); ok = false
	else:
		lines.append("pick OK: pick carried a perk + re-stocked a fresh shelf")

	# skip clears the shelf (take nothing).
	lab.call("skip")
	if not (lab.get("shelf") as Array).is_empty():
		lines.append("skip FAIL: skip() did not clear the shelf"); ok = false
	else:
		lines.append("skip OK: skip cleared the shelf")

	# --- 4b) RNG draft: a reroll genuinely RE-ROLLS (not the old positional no-op) + the WHOLE
	#         authored pool is reachable (the old pool[i % size] stranded perks 3..5). ------------
	# Seed the draft RNG so the draw is deterministic; give plenty of tokens so rerolls always afford.
	if lab.get("_draft_rng") != null:
		(lab.get("_draft_rng") as RandomNumberGenerator).seed = 0xD7A57
	lab.set("tokens", 1_000_000)
	# Reroll many times and confirm the shelf actually CHANGES at least once (the no-op bug would
	# leave every reroll showing the identical positional perks forever).
	lab.call("stock")
	var changed_once := false
	var prev_names := _shelf_names(lab.get("shelf"))
	for r in 40:
		if not bool(lab.call("reroll")):
			break
		var now_names := _shelf_names(lab.get("shelf"))
		if now_names != prev_names:
			changed_once = true
		prev_names = now_names
	lines.append("reroll-rng: shelf changed across rerolls=%s (want true — reroll is not a no-op)" % changed_once)
	if not changed_once:
		lines.append("reroll-rng FAIL: rerolls never changed the shelf (positional no-op bug)"); ok = false
	else:
		lines.append("reroll-rng OK: a reroll genuinely re-rolls the unlocked slots")

	# Reachability: across many fresh stocks, EVERY authored perk in the pool must surface at least
	# once (the old positional draw could only ever show the first DRAFT_SHELF_SIZE of the pool).
	var pool: Array = lab.call("_perk_pool")
	var pool_names: Dictionary = {}
	for p in pool:
		if p != null:
			pool_names[String(p.perk_name)] = true
	var seen_names: Dictionary = {}
	for s in 400:
		lab.call("stock")
		for nm in _shelf_names(lab.get("shelf")):
			seen_names[nm] = true
	var all_reachable := true
	var missing: Array = []
	for nm in pool_names.keys():
		if not seen_names.has(nm):
			all_reachable = false
			missing.append(nm)
	lines.append("reach: pool=%d seen=%d missing=%s (want every authored perk reachable)" % [
		pool_names.size(), seen_names.size(), str(missing)])
	if not all_reachable:
		lines.append("reach FAIL: authored perks are unreachable on the shelf (half-pool dead content)"); ok = false
	else:
		lines.append("reach OK: every authored perk can surface on the shelf")

	# Distinct-within-a-stock: when the pool is >= shelf size, the visible slots don't duplicate.
	if pool.size() >= shelf_size:
		var dup_seen := false
		for s in 200:
			lab.call("stock")
			var names := _shelf_names(lab.get("shelf"))
			var uniq: Dictionary = {}
			for nm in names:
				uniq[nm] = true
			if uniq.size() != names.size():
				dup_seen = true
		lines.append("distinct: duplicate within a stock seen=%s (want false)" % dup_seen)
		if dup_seen:
			lines.append("distinct FAIL: a single stock dealt the same perk to two slots"); ok = false
		else:
			lines.append("distinct OK: a stock deals distinct perks across slots")

	# Bounded carry: drafting the SAME authored (path-bearing) perk twice must NOT stack it.
	lab.call("clear_perks")
	if not pool.is_empty():
		var p0: Resource = pool[0]
		lab.call("add_perk", p0)
		lab.call("add_perk", p0)            # same authored perk again — should dedup
		var n_after_dup: int = (lab.get("perks") as Array).size()
		lines.append("bounded: same perk added twice -> carried=%d (want 1, deduped)" % n_after_dup)
		if n_after_dup != 1:
			lines.append("bounded FAIL: the same authored perk stacked (unbounded power ladder)"); ok = false
		else:
			lines.append("bounded OK: drafting the same authored perk twice does not stack")
	lab.call("clear_perks")
	lab.set("tokens", 0)
	lab.call("skip")

	# Restore clean meta state.
	lab.call("clear_perks")
	lab.set("tokens", 0)
	lab.call("skip")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## The perk names currently on the shelf (in slot order) — for the reroll-change / reachability asserts.
func _shelf_names(shelf: Array) -> Array:
	var out: Array = []
	for offer in shelf:
		if offer != null and offer.perk != null:
			out.append(String(offer.perk.perk_name))
		else:
			out.append("")
	return out


func _is_neutral(fx: Dictionary) -> bool:
	return absf(float(fx.get("rate_mult", 1.0)) - 1.0) < 0.0001 \
		and absf(float(fx.get("spread_mult", 1.0)) - 1.0) < 0.0001 \
		and absf(float(fx.get("speed_mult", 1.0)) - 1.0) < 0.0001 \
		and int(fx.get("start_projectiles_bonus", 0)) == 0 \
		and absf(float(fx.get("token_magnet_mult", 1.0)) - 1.0) < 0.0001 \
		and absf(float(fx.get("token_bounty_mult", 1.0)) - 1.0) < 0.0001


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
