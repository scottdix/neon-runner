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

	# --- 2) TokenLayer drift + REAL magnet attraction + contact absorb -----------
	# A bare layer (off-tree) reads magnet_mult via the SpliceLab autoload at /root — which is
	# present here. Clear perks first so the radius is the BASE (×1.0).
	var layer: Node2D = TokenS.new()
	root.add_child(layer)
	layer.call("wire_events")
	layer.call("set_ship_line", 1680.0)
	# Steer the ship to a known x.
	ev.call("emit_signal", "player_steered", 540.0, 0.5)
	var base_r: float = layer.call("magnet_radius")
	var contact_r: float = float(layer.get("CONTACT_RADIUS"))
	lines.append("token radius: magnet=%.1f contact=%.1f (BASE_PICKUP_RADIUS × magnet_mult 1.0; contact < magnet)" % [base_r, contact_r])
	if not (contact_r < base_r):
		lines.append("radius FAIL: contact radius must be smaller than the magnet radius (no attraction gap)"); ok = false

	# 2a) ATTRACTION: a token placed JUST INSIDE the magnet radius (but well outside contact) must
	# move measurably CLOSER to the ship after one step (the magnet pull), and a token OUTSIDE the
	# radius must NOT be pulled toward the ship — its horizontal distance to the ship stays put and
	# it only falls. Use an OFF-AXIS x so a pure down-drift can't be mistaken for attraction.
	var ship_pt := Vector2(540.0, 1680.0)
	# Inside the magnet field: offset the token in x so the pull has a horizontal component to read.
	var inside_pos := Vector2(540.0 + (base_r - 20.0) * 0.7, 1680.0 - (base_r - 20.0) * 0.7)
	ev.call("emit_signal", "token_dropped", inside_pos, 1)
	var d_in_before: float = inside_pos.distance_to(ship_pt)
	layer.call("step", 0.016)
	# Read the live token's new pos (only one token live).
	var inside_after: Vector2 = (layer.get("_tokens")[0])["pos"]
	var d_in_after: float = inside_after.distance_to(ship_pt)
	lines.append("attract-in: dist %.1f -> %.1f (want closer — homing pull)" % [d_in_before, d_in_after])
	if not (d_in_after < d_in_before - 1.0):
		lines.append("attract FAIL: a token inside the magnet radius did not move toward the ship"); ok = false
	else:
		lines.append("attract OK: in-range token homes toward the ship")
	# Clear that token off (drift it past the bottom) so the next check starts clean.
	for s in 60:
		layer.call("step", 0.05)
	# Outside the magnet field: drop a token FAR off to the side, just below the ship line so it
	# won't fall into range. After a step its HORIZONTAL distance to the ship must be unchanged
	# (no sideways pull) — only y changes from drift.
	var out_pos := Vector2(540.0 + base_r + 300.0, 1680.0 + 5.0)
	ev.call("emit_signal", "token_dropped", out_pos, 1)
	var out_dx_before: float = absf(out_pos.x - ship_pt.x)
	layer.call("step", 0.016)
	var out_after: Vector2 = (layer.get("_tokens")[0])["pos"]
	var out_dx_after: float = absf(out_after.x - ship_pt.x)
	lines.append("attract-out: |dx| %.1f -> %.1f (want unchanged — no pull outside radius)" % [out_dx_before, out_dx_after])
	if not is_equal_approx(out_dx_before, out_dx_after):
		lines.append("attract FAIL: a token OUTSIDE the magnet radius was pulled sideways toward the ship"); ok = false
	else:
		lines.append("attract OK: out-of-range token is not pulled (down-drift only)")
	# Flush that token off the bottom.
	for s in 80:
		layer.call("step", 0.05)

	# 2b) NO AUTO-COLLECT outside contact: a token sitting INSIDE the magnet radius but OUTSIDE the
	# contact radius must NOT bank on the step it enters range — it absorbs only once it homes to
	# contact. Place it on-axis above the ship at a distance between contact and magnet radius.
	var mid_y := 1680.0 - (contact_r + (base_r - contact_r) * 0.5)
	ev.call("emit_signal", "token_dropped", Vector2(540.0, mid_y), 3)
	var start_tokens := int(gs.get("run_tokens"))
	layer.call("step", 0.001)   # tiny step: inside magnet radius, but can't reach contact yet
	if layer.call("live_count") != 1 or int(gs.get("run_tokens")) != start_tokens:
		lines.append("absorb FAIL: token banked before reaching contact (magnet radius != contact)"); ok = false
	else:
		lines.append("absorb OK: in-field token is attracted, not auto-banked before contact")
	# Now step on so the magnet homes it to contact -> collected exactly once.
	var collected := [0]
	var on_collect := func(_at: Vector2, _v: int, _w: int) -> void: collected[0] += 1
	ev.connect("token_collected", on_collect)
	for s in 30:
		layer.call("step", 0.05)
	ev.disconnect("token_collected", on_collect)
	if layer.call("live_count") != 0 or collected[0] != 1:
		lines.append("home FAIL: token did not home to contact + collect once (live=%d emits=%d)" % [layer.call("live_count"), collected[0]]); ok = false
	elif int(gs.get("run_tokens")) != start_tokens + 3:
		lines.append("collect FAIL: collect_token did not add the value to run_tokens (%d != %d)" % [int(gs.get("run_tokens")), start_tokens + 3]); ok = false
	else:
		lines.append("home+collect OK: token homed to contact, collected once, run_tokens += 3")

	# 2c) Magnetism WIDENS the range: draft the magnet perk and confirm the live radius grows, and a
	# token at a distance that was OUTSIDE the base field is now INSIDE the widened one (so it gets
	# pulled toward the ship where the base radius left it falling straight down).
	lab.call("add_perk", magnet)
	var wide_r: float = layer.call("magnet_radius")
	if wide_r <= base_r + 0.5:
		lines.append("magnet FAIL: a drafted MAGNET perk did not widen the pickup radius (%.1f <= %.1f)" % [wide_r, base_r]); ok = false
	else:
		lines.append("magnet OK: drafted MAGNET widened radius %.1f -> %.1f" % [base_r, wide_r])
	# Drop a token in the band that's OUTSIDE base_r but INSIDE wide_r, off-axis so the pull reads.
	var gap_r := (base_r + wide_r) * 0.5
	var gap_pos := Vector2(540.0 + gap_r * 0.7, 1680.0 - gap_r * 0.7)
	ev.call("emit_signal", "token_dropped", gap_pos, 2)
	var d_gap_before: float = gap_pos.distance_to(ship_pt)
	layer.call("step", 0.016)
	var gap_after: Vector2 = (layer.get("_tokens")[0])["pos"]
	var d_gap_after: float = gap_after.distance_to(ship_pt)
	lines.append("magnet-pull: at %.1f (>base %.1f, <wide %.1f) dist %.1f -> %.1f (want closer)" % [
		gap_r, base_r, wide_r, d_gap_before, d_gap_after])
	if not (d_gap_after < d_gap_before - 1.0):
		lines.append("magnet-pull FAIL: widened radius did not attract a token the base radius would have missed"); ok = false
	else:
		lines.append("magnet-pull OK: widened radius attracts a token outside the base field")
	# Let it home in + bank to keep state clean.
	var before := int(gs.get("run_tokens"))
	for s in 40:
		layer.call("step", 0.05)
	if int(gs.get("run_tokens")) != before + 2 or layer.call("live_count") != 0:
		lines.append("magnet-catch FAIL: widened-field token did not home in + bank"); ok = false
	else:
		lines.append("magnet-catch OK: widened-field token homed in and banked")
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

	# --- 5) Gate-effect SEAM regression: the dispatch refactor must NOT change math-gate
	#        behaviour, and an "fx"-typed gate built by the spawner must grant its EFFECT
	#        (geom charge) rather than touching the projectile economy. -------------------
	# The seam splits the old single gate_passed path in two: math gates still emit gate_passed
	# (GameState mutates projectile_count + drains battery on −/÷), while a non-arithmetic gate emits
	# gate_effect (routed through GameState's _gate_effects handler table — NO economy math). These
	# checks pin BOTH halves so the refactor can't silently regress either, driving the REAL signals
	# (gate_passed / gate_effect) and the REAL spawner build path, not hand-set state.
	lines.append("--- #seam gate-effect dispatch regression ---")
	gs.call("wire_events")                          # idempotent — builds the _gate_effects table

	var GateS: GDScript = load("res://assets/gates/gate.gd")
	var SpawnerS: GDScript = load("res://assets/gates/gate_spawner.gd")
	if GateS == null or SpawnerS == null:
		lines.append("seam FAIL: gate / gate_spawner script missing"); ok = false
		lines.append("RESULT=%s" % ("PASS" if ok else "FAIL")); _write(lines); return

	# 5a) A POSITIVE math gate via gate_passed STILL sets projectile_count to its post-op count and
	#     does NOT drain the battery (the +/× side of the Split Choice is unchanged by the seam).
	gs.call("start_run")                            # battery -> 100, projectile_count -> START_PROJECTILES
	var pos_bat0: float = float(gs.get("glow_battery"))
	# Emit the math signal directly (what Gate.trigger does for a math gate): new_count is the gate's
	# already-applied, floored-at-0 post-op count. GameState commits it via set_projectile_count.
	ev.call("emit_signal", "gate_passed", "multiply", 2.0, 240)
	lines.append("5a math+: projectile_count=%d (want 240) battery %.0f->%.0f (want unchanged)" % [
		int(gs.get("projectile_count")), pos_bat0, float(gs.get("glow_battery"))])
	if int(gs.get("projectile_count")) != 240:
		lines.append("5a FAIL: a positive gate_passed did not commit its new_count to projectile_count"); ok = false
	if absf(float(gs.get("glow_battery")) - pos_bat0) > 0.001:
		lines.append("5a FAIL: a POSITIVE gate drained the battery (only −/÷ should)"); ok = false
	if ok:
		lines.append("5a OK: positive gate_passed still sets projectile_count, no battery drain")

	# 5b) A NEGATIVE (divide) math gate via gate_passed STILL thins the swarm to its post-op count AND
	#     drains the Glow Battery by exactly DRAIN_PER_NEGATIVE_GATE × the active difficulty drain_mult
	#     (GameState._on_gate_passed's formula — read it the same way so this is mode-agnostic).
	# DRAIN_PER_NEGATIVE_GATE is a const on the GameState script (not a member var, so get() can't
	# read it) — load the script and read the const off it. Mirror GameState's own formula exactly.
	var GameStateS: GDScript = load("res://autoload/game_state.gd")
	var drain_const: float = float(GameStateS.DRAIN_PER_NEGATIVE_GATE)
	var drain_each: float = drain_const * float(root.get_node("Difficulty").call("drain_mult"))
	var neg_bat0: float = float(gs.get("glow_battery"))
	ev.call("emit_signal", "gate_passed", "divide", 2.0, 120)
	var neg_bat1: float = float(gs.get("glow_battery"))
	lines.append("5b math÷: projectile_count=%d (want 120) battery %.1f->%.1f drain=%.1f (want %.1f)" % [
		int(gs.get("projectile_count")), neg_bat0, neg_bat1, neg_bat0 - neg_bat1, drain_each])
	if int(gs.get("projectile_count")) != 120:
		lines.append("5b FAIL: a negative gate_passed did not commit its new_count to projectile_count"); ok = false
	if absf((neg_bat0 - neg_bat1) - drain_each) > 0.01:
		lines.append("5b FAIL: a negative gate did not drain exactly DRAIN_PER_NEGATIVE_GATE × drain_mult"); ok = false
	if ok:
		lines.append("5b OK: negative gate_passed thins the swarm AND drains the battery as before")

	# 5c) An "fx"-typed gate BUILT BY THE SPAWNER grants its effect (geom charge) and does NOT change
	#     the projectile economy. Drive the REAL build path: a formation whose chosen side is an
	#     ["fx", {effect:"geom_cache", params:{amount}}] spec, steered through + scrolled past the line
	#     so the spawner's update() fires gate.trigger() -> Events.gate_effect -> _fx_geom_cache.
	gs.call("start_run")                            # fresh run: geom_charge 0, run_active (add_geom no-ops otherwise)
	var fx_count0: int = int(gs.get("projectile_count"))
	var fx_bat0: float = float(gs.get("glow_battery"))
	var fx_geom0: float = float(gs.get("geom_charge"))
	var sp: Node2D = SpawnerS.new()
	sp.call("setup", 1680.0)
	# Left side = the fx gate (Geom Cache, +35 charge); right side = a harmless math gate we WON'T take.
	# GEOM family (2) tags it as the universal geom family. The left gate slots into [0, 540), so we
	# steer to x=280 (LEFT_CENTER) to take it.
	sp.call("build_formations", [
		{"m": 30.0,
		 "l": ["fx", {"effect": "geom_cache", "params": {"amount": 35.0}, "family": 2}],
		 "r": ["add", 5.0]},
	])
	# Scroll the @30m formation well past the ship line with the ship steered onto the fx (left) side,
	# so update() crosses it once and fires gate.trigger() on the fx gate (effect_id != "" -> gate_effect).
	sp.call("update", 200.0, 280.0)
	lines.append("5c fx-gate: geom %.0f->%.0f (want +35) count %d->%d (want unchanged) battery %.0f->%.0f triggers=%d" % [
		fx_geom0, float(gs.get("geom_charge")), fx_count0, int(gs.get("projectile_count")),
		fx_bat0, float(gs.get("glow_battery")), int(sp.get("triggers"))])
	if int(sp.get("triggers")) != 1:
		lines.append("5c FAIL: the spawner did not fire the crossed fx formation exactly once"); ok = false
	if absf(float(gs.get("geom_charge")) - (fx_geom0 + 35.0)) > 0.01:
		lines.append("5c FAIL: an fx geom_cache gate did not grant its geom charge via the dispatch seam"); ok = false
	if int(gs.get("projectile_count")) != fx_count0:
		lines.append("5c FAIL: an fx gate changed projectile_count (it must do NO economy math)"); ok = false
	if absf(float(gs.get("glow_battery")) - fx_bat0) > 0.001:
		lines.append("5c FAIL: an fx gate drained the battery (it must do NO economy math)"); ok = false
	if ok:
		lines.append("5c OK: a spawner-built fx gate grants its effect (geom) and leaves the economy untouched")
	sp.free()

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
