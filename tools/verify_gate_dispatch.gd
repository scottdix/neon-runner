extends SceneTree
## Headless verification for the gate-effect DISPATCH SEAM (#84 ph4-6, game_state.gd):
##   - Events.gate_effect routes a non-arithmetic effect_id through GameState._gate_effects
##     (the Callable table) so every state mutation stays inside the single owner (GameState),
##     and an UNKNOWN id fails soft (push_warning + no-op, no state change).
##   - geom_cache  : grants Geom charge through the single owner (add_geom).
##   - efficiency  : the PHASE-SCOPED sustain-vs-burst tradeoff — sets geom_drain_mult (< 1
##                   stretches the LANCE charge burn) + burst_damage_mult, and the lowered drain
##                   mult reduces the per-tick burn the StanceController computes
##                   (GEOM_DRAIN_PER_SEC × mult × delta, replicated here, no GPU / no Player).
##   - tungsten    : the GLOBAL armor-cracking buff — raises Fleet.hit_weight() in LANCE only,
##                   SPRAY is unaffected (the wide light wall).
##   - phase split : Events.phase_changed resets the PHASE-scoped buffs (geom_drain_mult /
##                   burst_damage_mult) to 1.0 but the GLOBAL tungsten lance_hit_weight_mult
##                   SURVIVES — proving the global-vs-phase buff split.
##
## GPU-free: drives the dispatch via the Events bus + reads GameState/Fleet pure logic, writing a
## verdict file the runner polls for (CLAUDE.md gotchas). Autoloads via root.get_node; scripts via
## runtime load() (no class_name cache under -s). Run:
##   tools/run-headless.sh res://tools/verify_gate_dispatch.gd /tmp/verify_gate_dispatch_result.txt

const RESULT_PATH := "/tmp/verify_gate_dispatch_result.txt"

## StanceController._step_geom's burn rate (assert it stays in sync — the formula is replicated below).
const GEOM_DRAIN_PER_SEC := 40.0


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	if FleetS == null:
		lines.append("RESULT=FAIL (fleet script missing)"); _write(lines); return

	var gs: Node = root.get_node_or_null("GameState")
	var ev: Node = root.get_node_or_null("Events")
	if gs == null or ev == null:
		lines.append("RESULT=FAIL (GameState/Events autoloads missing)"); _write(lines); return
	# Under -s the autoload _ready is deferred past _initialize, so the dispatch table isn't built
	# yet — wire_events is public + idempotent for exactly this (populates _gate_effects + connects).
	gs.call("wire_events")
	gs.call("start_run")

	# --- 1) geom_cache: dispatch raises geom_charge via the single owner (add_geom) --------------
	var geom_before: float = float(gs.get("geom_charge"))
	ev.call("emit_signal", "gate_effect", "geom_cache", {"amount": 40.0}, Vector2.ZERO)
	var geom_after: float = float(gs.get("geom_charge"))
	lines.append("geom_cache: geom_charge %.1f -> %.1f (want +40 via add_geom)" % [geom_before, geom_after])
	if absf(geom_after - (geom_before + 40.0)) > 0.0001:
		lines.append("geom_cache FAIL: gate_effect did not grant Geom charge through add_geom"); ok = false
	else:
		lines.append("geom_cache OK: dispatch granted +40 Geom through the single owner")

	# --- 2) UNKNOWN effect id is a safe no-op (no crash, no state change) -------------------------
	var geom_pre: float = float(gs.get("geom_charge"))
	var drain_pre: float = float(gs.get("geom_drain_mult"))
	var burst_pre: float = float(gs.get("burst_damage_mult"))
	var lance_pre: float = float(gs.get("lance_hit_weight_mult"))
	ev.call("emit_signal", "gate_effect", "no_such_effect", {"amount": 999.0}, Vector2.ZERO)
	var unchanged: bool = absf(float(gs.get("geom_charge")) - geom_pre) < 0.0001 \
		and absf(float(gs.get("geom_drain_mult")) - drain_pre) < 0.0001 \
		and absf(float(gs.get("burst_damage_mult")) - burst_pre) < 0.0001 \
		and absf(float(gs.get("lance_hit_weight_mult")) - lance_pre) < 0.0001
	lines.append("unknown-id: state unchanged after an unregistered effect_id = %s" % unchanged)
	if not unchanged:
		lines.append("unknown FAIL: an unknown effect_id mutated run state (must no-op)"); ok = false
	else:
		lines.append("unknown OK: unregistered effect_id is a safe no-op (push_warning + no state change)")

	# --- 3) efficiency: sets the PHASE-scoped mults; the lowered drain mult shrinks the LANCE burn --
	ev.call("emit_signal", "gate_effect", "efficiency", {"drain_mult": 0.6, "burst_mult": 0.75}, Vector2.ZERO)
	var drain_mult: float = float(gs.get("geom_drain_mult"))
	var burst_mult: float = float(gs.get("burst_damage_mult"))
	lines.append("efficiency: geom_drain_mult=%.2f burst_damage_mult=%.2f (want 0.60 / 0.75)" % [drain_mult, burst_mult])
	if absf(drain_mult - 0.6) > 0.0001 or absf(burst_mult - 0.75) > 0.0001:
		lines.append("efficiency FAIL: _fx_efficiency did not set the phase-scoped mults"); ok = false
	else:
		lines.append("efficiency OK: dispatch set geom_drain_mult=0.60 + burst_damage_mult=0.75")

	# Replicate StanceController._step_geom's per-tick burn (GEOM_DRAIN_PER_SEC × mult × delta): the
	# < 1 drain mult must reduce the charge spent vs the neutral (×1.0) rate over the same delta.
	var delta := 0.1
	var burn_efficient: float = GEOM_DRAIN_PER_SEC * drain_mult * delta
	var burn_neutral: float = GEOM_DRAIN_PER_SEC * 1.0 * delta
	lines.append("burn/tick: efficient=%.2f neutral=%.2f (want efficient < neutral — sustain longer)" % [burn_efficient, burn_neutral])
	if not (burn_efficient < burn_neutral - 0.0001):
		lines.append("burn FAIL: geom_drain_mult < 1 did not reduce the per-tick LANCE burn"); ok = false
	else:
		lines.append("burn OK: a sub-1 drain mult shrinks the per-tick charge burn (longer LANCE)")

	# --- 4) tungsten: raises Fleet.hit_weight() in LANCE only; SPRAY is unaffected ----------------
	# Capture the pre-tungsten weights from a real Fleet so the wiring (GameState mults → hit_weight)
	# is exercised, not faked. SPRAY (_stance 0) is the light wall; LANCE (_stance 1) is the heavy burst.
	# NB efficiency above set burst_damage_mult=0.75, which folds into the LANCE weight too — so reset
	# the phase buffs to neutral here to isolate the tungsten effect (a fresh phase would do this).
	gs.call("_reset_phase_buffs")
	var fl_sp: Node2D = FleetS.new()
	fl_sp.call("set_stance", 0)                     # 0 == GameState.Stance.SPRAY
	var fl_ln: Node2D = FleetS.new()
	fl_ln.call("set_stance", 1)                     # 1 == GameState.Stance.LANCE
	var spray_before: float = float(fl_sp.call("hit_weight"))
	var lance_before: float = float(fl_ln.call("hit_weight"))
	ev.call("emit_signal", "gate_effect", "tungsten", {"mult": 1.5}, Vector2.ZERO)
	var lance_mult: float = float(gs.get("lance_hit_weight_mult"))
	var spray_after: float = float(fl_sp.call("hit_weight"))
	var lance_after: float = float(fl_ln.call("hit_weight"))
	lines.append("tungsten: lance_hit_weight_mult=%.2f | SPRAY %.2f->%.2f (want same) | LANCE %.2f->%.2f (want ×1.5)" % [
		lance_mult, spray_before, spray_after, lance_before, lance_after])
	if absf(lance_mult - 1.5) > 0.0001:
		lines.append("tungsten FAIL: _fx_tungsten did not raise lance_hit_weight_mult"); ok = false
	elif absf(spray_after - spray_before) > 0.0001:
		lines.append("tungsten FAIL: tungsten changed the SPRAY hit weight (must be LANCE-only)"); ok = false
	elif absf(lance_after - lance_before * 1.5) > 0.0001:
		lines.append("tungsten FAIL: tungsten did not scale the LANCE hit weight ×1.5"); ok = false
	else:
		lines.append("tungsten OK: LANCE weight ×1.5, SPRAY unaffected (the global cracking lever)")

	# --- 5) phase split: phase_changed resets the PHASE buffs but the GLOBAL tungsten SURVIVES -----
	# Re-arm a phase-scoped buff so the reset has something to clear, alongside the live global tungsten.
	ev.call("emit_signal", "gate_effect", "efficiency", {"drain_mult": 0.6, "burst_mult": 0.75}, Vector2.ZERO)
	var drain_armed: float = float(gs.get("geom_drain_mult"))
	var lance_armed: float = float(gs.get("lance_hit_weight_mult"))
	# A new phase begins — the "phase clear" for phase-scoped buffs (args are discarded by the handler).
	ev.call("emit_signal", "phase_changed", 1, "PHASE 2", {})
	var drain_post: float = float(gs.get("geom_drain_mult"))
	var burst_post: float = float(gs.get("burst_damage_mult"))
	var lance_post: float = float(gs.get("lance_hit_weight_mult"))
	lines.append("phase split: armed drain=%.2f tungsten=%.2f | post-boundary drain=%.2f burst=%.2f tungsten=%.2f" % [
		drain_armed, lance_armed, drain_post, burst_post, lance_post])
	if absf(drain_post - 1.0) > 0.0001 or absf(burst_post - 1.0) > 0.0001:
		lines.append("phase FAIL: phase_changed did not reset the phase-scoped buffs to 1.0"); ok = false
	elif absf(lance_post - 1.5) > 0.0001:
		lines.append("phase FAIL: the GLOBAL tungsten mult did not survive the phase boundary"); ok = false
	else:
		lines.append("phase OK: phase-scoped buffs reset to 1.0, GLOBAL tungsten (×1.5) survives — split proven")

	fl_sp.free()
	fl_ln.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
