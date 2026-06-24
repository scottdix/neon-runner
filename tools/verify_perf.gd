extends SceneTree
## Headless verification for the PERF cluster — #35 overlay, #38 viewport cull, #37 particle
## budget, #36 sprite atlas. All four keep their logic in PURE methods (static formatters / band
## tests / caps / region maps) so we assert them on bare .new()s and statics with NO renderer and
## NO live Performance singleton — which is the whole point of the perf seam: the LOGIC is testable
## here, the on-device 60fps/glow acceptance (#39) is device-only and stays OPEN.
##
## Run:
##   tools/run-headless.sh res://tools/verify_perf.gd /tmp/verify_perf_result.txt

const RESULT_PATH := "/tmp/verify_perf_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# === #38 viewport cull — in_band boundaries + band slop =====================
	var CullS: GDScript = load("res://assets/levels/viewport_cull.gd")
	if CullS == null:
		lines.append("RESULT=FAIL (viewport_cull.gd missing)"); _write(lines); return
	var top := 0.0
	var bottom := 1920.0
	var m: float = float(CullS.DEFAULT_MARGIN)
	# Inside the visible band → keep.
	var keep_mid: bool = CullS.in_band(Vector2(540, 960), top, bottom, m)
	# Just above the top by less than the margin → still kept (slop).
	var keep_top_slop: bool = CullS.in_band(Vector2(540, top - (m - 1.0)), top, bottom, m)
	# Above the top by MORE than the margin → culled.
	var cull_above: bool = CullS.in_band(Vector2(540, top - (m + 1.0)), top, bottom, m)
	# Below the bottom by more than the margin → culled (the common scroll-past case).
	var cull_below: bool = CullS.in_band(Vector2(540, bottom + (m + 1.0)), top, bottom, m)
	# Exactly on the band edge (bottom + margin) → kept (inclusive).
	var keep_edge: bool = CullS.in_band(Vector2(540, bottom + m), top, bottom, m)
	lines.append("cull in_band: mid=%s topslop=%s above=%s below=%s edge=%s (want T,T,F,F,T)" % [
		keep_mid, keep_top_slop, cull_above, cull_below, keep_edge])
	if not (keep_mid and keep_top_slop and not cull_above and not cull_below and keep_edge):
		lines.append("cull FAIL: in_band boundary/slop wrong"); ok = false
	# band_for exposes the exact thresholds.
	var bf: Vector2 = CullS.band_for(top, bottom, m)
	if not (is_equal_approx(bf.x, top - m) and is_equal_approx(bf.y, bottom + m)):
		lines.append("cull FAIL: band_for thresholds wrong (%s)" % bf); ok = false
	# _apply on a bare instance: a Node2D out of band gets process disabled + counted as culled;
	# in-band gets it enabled. Non-Node2D is left alone. Tolerates the headless sweep.
	var cull: Node = CullS.new()
	cull.call("set_band", top, bottom)
	var n_in := Node2D.new()
	n_in.global_position = Vector2(540, 960)
	var n_out := Node2D.new()
	n_out.global_position = Vector2(540, bottom + m + 500.0)
	var n_plain := Node.new()   # not a Node2D → untouched
	var culled_in: bool = bool(cull.call("_apply", n_in))
	var culled_out: bool = bool(cull.call("_apply", n_out))
	var culled_plain: bool = bool(cull.call("_apply", n_plain))
	lines.append("cull _apply: in_culled=%s out_culled=%s plain_culled=%s in_proc=%s out_proc=%s (want F,T,F,T,F)" % [
		culled_in, culled_out, culled_plain, n_in.is_processing(), n_out.is_processing()])
	if culled_in or not culled_out or culled_plain or not n_in.is_processing() or n_out.is_processing():
		lines.append("cull FAIL: _apply policy did not gate processing by band"); ok = false
	n_in.free(); n_out.free(); n_plain.free()
	# _step tolerates an empty/headless target list (no crash, zero culled).
	if int(cull.call("_step")) != 0:
		lines.append("cull FAIL: _step on empty target list should cull nothing"); ok = false

	# #38 HONEST-SCOPE: sweeping a REAL Targets/Fleet layer culls ZERO of the batched scrollers and
	# changes NO gameplay state. The heavy entities (enemies/bullets) are MultiMesh data arrays, not
	# child nodes — the only Node2D child is the layer's `_mmi` MultiMeshInstance2D (skipped by _apply),
	# so the sweep is a provable no-op on gameplay. This catches the old "verify on an EMPTY list"
	# blind spot the review flagged.
	var TargetsS: GDScript = load("res://assets/obstacles/targets.gd")
	var FleetS: GDScript = load("res://assets/projectiles/fleet.gd")
	if TargetsS == null or FleetS == null:
		lines.append("RESULT=FAIL (targets/fleet scripts missing for cull-scope test)"); _write(lines); return
	var fleet_layer: Node2D = FleetS.new()
	fleet_layer.position = Vector2(540.0, 1680.0)
	(fleet_layer.get("_rng") as RandomNumberGenerator).seed = 0x5C0FF
	fleet_layer.call("set_volume", 120)
	var targets_layer: Node2D = TargetsS.new()
	targets_layer.call("set_fleet", fleet_layer)
	# A live OFF-BAND enemy (well below the band) + an IN-BAND one — neither is a child node, so the
	# cull can't touch them; both must survive the sweep with identical state.
	var enemies: Array = targets_layer.get("_enemies")
	enemies.append({"pos": Vector2(540, 960), "hp": 100.0, "max_hp": 100.0, "size": 64.0, "speed": 0.0, "flash": 0.0})
	enemies.append({"pos": Vector2(540, bottom + m + 5000.0), "hp": 100.0, "max_hp": 100.0, "size": 64.0, "speed": 0.0, "flash": 0.0})
	var cull2: Node = CullS.new()
	cull2.call("set_band", top, bottom)
	cull2.call("add_target", targets_layer)
	cull2.call("add_target", fleet_layer)
	var enemies_before: int = (targets_layer.get("_enemies") as Array).size()
	var kills_before: int = int(targets_layer.get("kills"))
	# Build a bullet stream so the Fleet has a live _mmi child + bullets, then sweep.
	for i in 20:
		fleet_layer.call("step", 1.0 / 60.0)
	var bullets_before: int = int(fleet_layer.call("live_count"))
	var culled_real: int = int(cull2.call("_step"))
	var enemies_after: int = (targets_layer.get("_enemies") as Array).size()
	var kills_after: int = int(targets_layer.get("kills"))
	var bullets_after: int = int(fleet_layer.call("live_count"))
	lines.append("cull-scope: culled_children=%d enemies %d->%d kills %d->%d bullets %d->%d (want 0 culled, all unchanged)" % [
		culled_real, enemies_before, enemies_after, kills_before, kills_after, bullets_before, bullets_after])
	if culled_real != 0 or enemies_after != enemies_before or kills_after != kills_before or bullets_after != bullets_before:
		lines.append("cull-scope FAIL: sweeping a real layer culled a scroller or changed gameplay state"); ok = false
	else:
		lines.append("cull-scope OK: sweeping real Targets/Fleet layers culls nothing + changes no gameplay state")
	# _apply must SKIP a MultiMeshInstance2D and a GPUParticles2D even when off-band (batched render
	# sink / GPU-driven one-shot — gating them is wrong/pointless, minor finding). Confirm directly.
	var mmi := MultiMeshInstance2D.new()
	mmi.global_position = Vector2(540, bottom + m + 9000.0)   # far off-band
	var gpu := GPUParticles2D.new()
	gpu.global_position = Vector2(540, bottom + m + 9000.0)   # far off-band
	# _apply returns false (NOT culled) for both even though they're far off-band — the skip. (We
	# don't assert is_processing(): an off-tree node always reports false there, so it can't tell the
	# skip apart; the return value is the contract _apply guarantees.)
	var mmi_culled: bool = bool(cull2.call("_apply", mmi))
	var gpu_culled: bool = bool(cull2.call("_apply", gpu))
	# A plain off-band Node2D control DOES cull — proving the skip above is specific to mmi/gpu.
	var ctrl := Node2D.new()
	ctrl.global_position = Vector2(540, bottom + m + 9000.0)
	var ctrl_culled: bool = bool(cull2.call("_apply", ctrl))
	lines.append("cull-skip: mmi_culled=%s gpu_culled=%s control_culled=%s (want F,F,T)" % [
		mmi_culled, gpu_culled, ctrl_culled])
	if mmi_culled or gpu_culled or not ctrl_culled:
		lines.append("cull-skip FAIL: _apply did not skip MultiMesh/GPUParticles (or skipped a plain Node2D)"); ok = false
	else:
		lines.append("cull-skip OK: _apply skips MultiMeshInstance2D + GPUParticles2D, still culls a plain off-band Node2D")
	ctrl.free()
	mmi.free(); gpu.free()
	cull2.free()
	targets_layer.free()
	fleet_layer.free()

	# === #37 particle budget — selection + caps =================================
	var BudgetS: GDScript = load("res://assets/effects/particle_budget.gd")
	if BudgetS == null:
		lines.append("RESULT=FAIL (particle_budget.gd missing)"); _write(lines); return
	# Selection: >50 → gpu, <20 → cpu, the 20..50 band → gpu (default batched).
	var k_big: String = BudgetS.select_kind(80)
	var k_small: String = BudgetS.select_kind(8)
	var k_mid: String = BudgetS.select_kind(35)
	var k_edge_lo: String = BudgetS.select_kind(20)   # NOT < 20 → gpu
	var k_edge_hi: String = BudgetS.select_kind(50)   # NOT > 50 → gpu
	lines.append("budget select: 80=%s 8=%s 35=%s 20=%s 50=%s (want gpu,cpu,gpu,gpu,gpu)" % [
		k_big, k_small, k_mid, k_edge_lo, k_edge_hi])
	if not (k_big == BudgetS.KIND_GPU and k_small == BudgetS.KIND_CPU and k_mid == BudgetS.KIND_GPU \
			and k_edge_lo == BudgetS.KIND_GPU and k_edge_hi == BudgetS.KIND_GPU):
		lines.append("budget FAIL: select_kind thresholds wrong"); ok = false
	# Caps: grant fills to the cap, never negative; would_exceed_cap matches.
	var g_fill: int = BudgetS.grant(950, 100)         # → 50 (fills to 1000)
	var g_none: int = BudgetS.grant(1000, 40)         # → 0 (no headroom)
	var g_over: int = BudgetS.grant(1200, 40)         # → 0 (already over → never negative)
	var g_room: int = BudgetS.grant(100, 200)         # → 200 (room to spare)
	lines.append("budget grant: 950+100=%d 1000+40=%d 1200+40=%d 100+200=%d (want 50,0,0,200)" % [
		g_fill, g_none, g_over, g_room])
	if not (g_fill == 50 and g_none == 0 and g_over == 0 and g_room == 200):
		lines.append("budget FAIL: grant cap math wrong"); ok = false
	if not (BudgetS.would_exceed_cap(950, 100) and not BudgetS.would_exceed_cap(100, 200)):
		lines.append("budget FAIL: would_exceed_cap wrong"); ok = false
	# Texture + blend gates.
	if not (BudgetS.texture_ok(24) and BudgetS.texture_ok(64) and not BudgetS.texture_ok(128) and not BudgetS.texture_ok(0)):
		lines.append("budget FAIL: texture_ok <=64px gate wrong"); ok = false
	if not (BudgetS.blend_ok(CanvasItemMaterial.BLEND_MODE_ADD) and not BudgetS.blend_ok(CanvasItemMaterial.BLEND_MODE_MIX)):
		lines.append("budget FAIL: blend_ok must require additive"); ok = false
	# plan() composes select + grant.
	var plan: Dictionary = BudgetS.plan(120, 950)     # kind gpu, granted 50, capped true
	lines.append("budget plan(120,950): kind=%s granted=%s capped=%s (want gpu,50,true)" % [
		plan["kind"], plan["granted"], plan["capped"]])
	if not (plan["kind"] == BudgetS.KIND_GPU and int(plan["granted"]) == 50 and bool(plan["capped"])):
		lines.append("budget FAIL: plan() composition wrong"); ok = false

	# === #36 sprite atlas — region lookup round-trip + non-overlap ==============
	var AtlasS: GDScript = load("res://assets/effects/sprite_atlas.gd")
	if AtlasS == null:
		lines.append("RESULT=FAIL (sprite_atlas.gd missing)"); _write(lines); return
	var regions: Dictionary = AtlasS.build_regions()
	# Every named sprite has a region, and region_for round-trips the map.
	var roundtrip_ok := true
	for name in AtlasS.SPRITES:
		var r: Rect2 = AtlasS.region_for(name)
		if not regions.has(name) or regions[name] != r or r.size == Vector2.ZERO:
			roundtrip_ok = false
	# Unknown name → zero-size miss sentinel.
	var miss: Rect2 = AtlasS.region_for("nope")
	lines.append("atlas: count=%d roundtrip=%s miss_zero=%s has_token=%s" % [
		AtlasS.SPRITES.size(), roundtrip_ok, miss.size == Vector2.ZERO, AtlasS.has_sprite("token_chip")])
	if not (roundtrip_ok and miss.size == Vector2.ZERO and AtlasS.has_sprite("token_chip") and not AtlasS.has_sprite("nope")):
		lines.append("atlas FAIL: region lookup / miss sentinel wrong"); ok = false
	# No two regions overlap (deterministic grid packing).
	var keys: Array = regions.keys()
	var overlap := false
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var ra: Rect2 = regions[keys[i]]
			var rb: Rect2 = regions[keys[j]]
			if ra.intersects(rb):
				overlap = true
	# Every region fits inside the page.
	var page: Vector2i = AtlasS.page_size()
	var inside := true
	for name in AtlasS.SPRITES:
		var r2: Rect2 = AtlasS.region_for(name)
		if r2.position.x < 0 or r2.position.y < 0 or r2.end.x > float(page.x) or r2.end.y > float(page.y):
			inside = false
	lines.append("atlas: page=%s overlap=%s inside_page=%s (want no-overlap, all-inside)" % [page, overlap, inside])
	if overlap or not inside:
		lines.append("atlas FAIL: regions overlap or escape the page"); ok = false

	# === #35 perf overlay — pure metric formatting ==============================
	var OverlayS: GDScript = load("res://assets/ui/perf_overlay.gd")
	if OverlayS == null:
		lines.append("RESULT=FAIL (perf_overlay.gd missing)"); _write(lines); return
	# fps rounds to int; int groups thousands; mem picks the unit.
	var f_fps: String = OverlayS._fmt_fps(59.6)        # → "60"
	var f_int: String = OverlayS._fmt_int(12345.0)     # → "12,345"
	var f_int_small: String = OverlayS._fmt_int(42.0)  # → "42"
	var f_mem_mb: String = OverlayS._fmt_mem(157286400.0)  # 150 MB → "150.0 MB"
	var f_mem_kb: String = OverlayS._fmt_mem(2048.0)       # → "2 KB"
	var f_mem_b: String = OverlayS._fmt_mem(512.0)         # → "512 B"
	lines.append("overlay fmt: fps=%s int=%s small=%s mem_mb=%s mem_kb=%s mem_b=%s" % [
		f_fps, f_int, f_int_small, f_mem_mb, f_mem_kb, f_mem_b])
	if f_fps != "60" or f_int != "12,345" or f_int_small != "42" or f_mem_mb != "150.0 MB" or f_mem_kb != "2 KB" or f_mem_b != "512 B":
		lines.append("overlay FAIL: metric formatting wrong"); ok = false
	# format_panel builds one line per metric, with a "—" for a missing sample key.
	var sample := {"FPS": 60.0, "DRAW": 4200.0, "PHYS": 8.0, "OBJ": 350.0, "PRIM": 99999.0, "MEM": 157286400.0}
	var panel: String = OverlayS.format_panel(sample)
	var panel_lines: int = panel.split("\n").size()
	var has_fps_line: bool = panel.contains("FPS  60")
	var has_draw_grouped: bool = panel.contains("4,200")
	var partial: String = OverlayS.format_panel({"FPS": 60.0})   # other keys → "—"
	lines.append("overlay panel: lines=%d (want %d) has_fps=%s has_grouped_draw=%s partial_dash=%s" % [
		panel_lines, OverlayS.METRICS.size(), has_fps_line, has_draw_grouped, partial.contains("—")])
	if panel_lines != OverlayS.METRICS.size() or not has_fps_line or not has_draw_grouped or not partial.contains("—"):
		lines.append("overlay FAIL: format_panel layout/missing-key handling wrong"); ok = false
	# _monitor_id maps the names to real Performance enums (engine-side, but pure int return — safe).
	if OverlayS.new()._monitor_id("RENDER_TOTAL_DRAW_CALLS_IN_FRAME") != Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME:
		lines.append("overlay FAIL: _monitor_id mapping wrong"); ok = false

	# === #35 perf overlay — DEVICE TOGGLE: Settings persistence + overlay honors it ====
	# The keyboard F3 toggle is unreachable on a phone, so the overlay must be driven by a persisted
	# Settings flag (set from the Settings screen). Assert: default OFF, the setter emits-once on the
	# bus + persists through a ConfigFile round-trip, and set_shown() drives visibility/_process.
	var settings: Node = root.get_node_or_null("Settings")
	var events: Node = root.get_node_or_null("Events")
	if settings == null or events == null:
		lines.append("overlay FAIL: Settings/Events autoloads missing for the device-toggle test"); ok = false
	else:
		var def_perf: bool = bool(settings.get("perf_overlay_enabled"))
		var seen := [0, false]
		var on_perf := func(en: bool) -> void: seen[0] += 1; seen[1] = en
		events.connect("perf_overlay_changed", on_perf)
		settings.call("set_perf_overlay_enabled", true)
		settings.call("set_perf_overlay_enabled", true)     # idempotent — must NOT re-emit
		# Round-trip: a fresh ConfigFile load reflects the saved value under the display section.
		var fresh := ConfigFile.new()
		var rc: int = fresh.load(settings.CONFIG_PATH)
		var saved_perf: bool = bool(fresh.get_value("display", "perf_overlay_enabled", false)) if rc == OK else false
		events.disconnect("perf_overlay_changed", on_perf)
		lines.append("overlay toggle: default=%s after-on=%s emits=%d saved=%s (want F,T,1,T)" % [
			def_perf, settings.get("perf_overlay_enabled"), seen[0], saved_perf])
		if def_perf:
			lines.append("overlay FAIL: perf_overlay_enabled should default OFF"); ok = false
		if not bool(settings.get("perf_overlay_enabled")) or seen[0] != 1 or not bool(seen[1]) or not saved_perf:
			lines.append("overlay FAIL: setter didn't emit-once + persist perf_overlay_enabled"); ok = false
		else:
			lines.append("overlay OK: perf_overlay_enabled defaults OFF, emit-once + ConfigFile round-trip")
		settings.call("set_perf_overlay_enabled", false)    # restore clean state

		# The overlay HONORS the flag: set_shown() drives visible + _process gating (the pure path the
		# Events.perf_overlay_changed connection calls). A bare instance never runs _ready, so build the
		# Label manually first so set_shown's _label clear is exercised.
		var ov: CanvasLayer = OverlayS.new()
		ov.set("_label", Label.new())
		ov.call("set_shown", true)
		var shown_on: bool = bool(ov.call("is_shown")) and ov.visible
		ov.call("set_shown", false)
		var shown_off: bool = (not bool(ov.call("is_shown"))) and (not ov.visible)
		lines.append("overlay honor: set_shown(true)->on=%s set_shown(false)->off=%s (want T,T)" % [shown_on, shown_off])
		if not (shown_on and shown_off):
			lines.append("overlay FAIL: set_shown did not drive visibility (overlay can't honor the setting)"); ok = false
		else:
			lines.append("overlay OK: set_shown drives visibility -> overlay honors Settings.perf_overlay_enabled")
		ov.free()

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
