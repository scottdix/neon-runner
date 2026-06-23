extends SceneTree
## Headless verification for SLICE D — Fleet tier evolution (#57) + Splice consumption (#68):
##   - Tier table          : _tier_for_volume() steps up across each TIER_VOLUME boundary
##                           (0 below the first cutoff, +1 at/above each subsequent cutoff).
##   - Tier-down shatter    : driving set_volume() UP then DOWN across a tier boundary queues
##                           a shatter (shatter_count() > 0); a flat/up change queues none.
##   - Splice neutrality    : SpliceLab.active_modifiers() is NEUTRAL ({1.0,1.0,1.0,0}) with
##                           empty slots — the verify_combat invariant (no-splice == today).
##   - Splice consumption    : after equip_a/equip_b/splice with a RATE mod, active_modifiers()
##                           is non-neutral and Fleet._effective_fire_rate() reflects rate_mult>1.
##
## All logic exercised here is PURE (no GPU): a bare Fleet.new() + SpliceLab pulled from /root.
## Run:
##   tools/run-headless.sh res://tools/verify_fleet_tiers.gd /tmp/verify_fleet_tiers_result.txt

const RESULT_PATH := "/tmp/verify_fleet_tiers_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	if FleetS == null:
		lines.append("RESULT=FAIL (fleet.gd missing)"); _write(lines); return

	var lab: Node = root.get_node_or_null("SpliceLab")
	if lab == null:
		lines.append("RESULT=FAIL (SpliceLab autoload missing)"); _write(lines); return

	# === 1) TIER TABLE — boundaries step the tier up ==========================
	var fleet: Node2D = FleetS.new()
	var cutoffs: Array = fleet.get("TIER_VOLUME")
	lines.append("tier: cutoffs=%s" % str(cutoffs))
	# Below the first cutoff -> T0.
	var t_below: int = fleet.call("_tier_for_volume", int(cutoffs[0]) - 1)
	if t_below != 0:
		lines.append("tier FAIL: volume below first cutoff is not T0 (got %d)" % t_below); ok = false
	# At/above each cutoff, the tier must be >= its 1-based index and strictly increase.
	var prev_t: int = -1
	var monotonic := true
	for idx in cutoffs.size():
		var t_at: int = fleet.call("_tier_for_volume", int(cutoffs[idx]))
		if t_at != idx + 1:
			lines.append("tier FAIL: at cutoff[%d]=%d expected tier %d, got %d" % [
				idx, int(cutoffs[idx]), idx + 1, t_at]); ok = false
		if t_at <= prev_t:
			monotonic = false
		prev_t = t_at
	if not monotonic:
		lines.append("tier FAIL: _tier_for_volume not monotonic across boundaries"); ok = false
	if ok:
		lines.append("tier OK: _tier_for_volume steps up across every TIER_VOLUME boundary")

	# === 2) TIER-DOWN SHATTER ================================================
	# Seed high (top tier), then decimate below a boundary -> shatter queued.
	var f2: Node2D = FleetS.new()
	var top_v: int = int(cutoffs[cutoffs.size() - 1]) + 50
	f2.call("set_volume", top_v)                        # baseline high tier, no prior -> may shatter from T?
	# Reset any shatter from the climb by stepping it out, then assert a CLEAN baseline.
	for i in 30:
		f2.call("step", 1.0 / 60.0)
	var clean: int = f2.call("shatter_count")
	if clean != 0:
		lines.append("shatter note: residual shards after settle=%d" % clean)
	# Upward change must NOT shatter.
	f2.call("set_volume", top_v + 20)
	var up_shards: int = f2.call("shatter_count")
	# Downward change ACROSS a boundary must shatter.
	var low_v: int = maxi(0, int(cutoffs[0]) - 5)       # well below T1 -> big tier drop
	var tier_hi: int = f2.call("_tier_for_volume", top_v + 20)
	var tier_lo: int = f2.call("_tier_for_volume", low_v)
	f2.call("set_volume", low_v)
	var down_shards: int = f2.call("shatter_count")
	lines.append("shatter: tier %d->%d  up_shards=%d down_shards=%d (want up=0, down>0)" % [
		tier_hi, tier_lo, up_shards, down_shards])
	if up_shards != 0:
		lines.append("shatter FAIL: an upward volume change queued a shatter"); ok = false
	if tier_lo >= tier_hi:
		lines.append("shatter FAIL: test setup did not cross a tier boundary downward"); ok = false
	elif down_shards <= 0:
		lines.append("shatter FAIL: tier-down did not queue a shatter"); ok = false
	else:
		lines.append("shatter OK: a downward tier crossing queues a one-shot shatter")

	# === 3) SPLICE NEUTRALITY (empty slots) =================================
	# Seed inventory explicitly (headless _ready is deferred) and clear slots.
	lab.call("_seed_inventory")
	lab.call("clear_slots")
	var neutral: Dictionary = lab.call("active_modifiers")
	lines.append("splice neutral: %s" % str(neutral))
	if not _is_neutral(neutral):
		lines.append("splice FAIL: empty-slot active_modifiers() is not neutral"); ok = false
	else:
		lines.append("splice OK: empty slots -> neutral modifiers (no-splice == today)")

	# A fleet built against neutral splice must keep today's fire-rate exactly.
	var f3: Node2D = FleetS.new()
	f3.call("apply_splice")                             # neutral -> mults stay 1.0
	var base_rate: float = f3.call("_effective_fire_rate", 40)
	var raw_rate: float = clampf(26.0 + 40.0 * 0.8, 26.0, 160.0)
	lines.append("splice neutral rate: eff=%.3f raw=%.3f (want equal)" % [base_rate, raw_rate])
	if absf(base_rate - raw_rate) > 0.001:
		lines.append("splice FAIL: neutral splice changed the fire-rate"); ok = false

	# === 4) SPLICE CONSUMPTION (RATE mod -> rate_mult > 1) ===================
	# Find a RATE / "x" mod in the seeded inventory (GRID BURST = x2 RATE), equip it in BOTH
	# slots so the fused stat lands on RATE multiplicatively, then splice.
	var inv: Array = lab.get("inventory")
	var rate_idx := -1
	for i in inv.size():
		var m = inv[i]
		if String(m.stat) == "RATE":
			rate_idx = i
			break
	if rate_idx == -1:
		lines.append("splice FAIL: no RATE mod in seeded inventory"); ok = false
	else:
		lab.call("equip_a", rate_idx)
		lab.call("equip_b", rate_idx)
		lab.call("splice")
		var fx: Dictionary = lab.call("active_modifiers")
		lines.append("splice equipped: %s" % str(fx))
		if _is_neutral(fx):
			lines.append("splice FAIL: equipping a RATE mod left modifiers neutral"); ok = false
		if float(fx.get("rate_mult", 1.0)) <= 1.0:
			lines.append("splice FAIL: RATE splice did not raise rate_mult above 1"); ok = false
		# A fresh fleet reading this splice must fire faster than the neutral baseline.
		var f4: Node2D = FleetS.new()
		f4.call("apply_splice")
		var fast_rate: float = f4.call("_effective_fire_rate", 40)
		lines.append("splice rate: neutral=%.3f spliced=%.3f (want spliced > neutral)" % [
			base_rate, fast_rate])
		if fast_rate <= base_rate:
			lines.append("splice FAIL: _effective_fire_rate did not reflect rate_mult>1"); ok = false
		else:
			lines.append("splice OK: RATE splice raises rate_mult and _effective_fire_rate")
	# Tidy up so we don't persist a spliced loadout into a real run from the test.
	lab.call("clear_slots")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## True when a modifier dict is the NEUTRAL default (mults 1.0, bonus 0).
func _is_neutral(fx: Dictionary) -> bool:
	return absf(float(fx.get("rate_mult", 0.0)) - 1.0) < 0.001 \
		and absf(float(fx.get("spread_mult", 0.0)) - 1.0) < 0.001 \
		and absf(float(fx.get("speed_mult", 0.0)) - 1.0) < 0.001 \
		and int(fx.get("start_projectiles_bonus", -1)) == 0


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
