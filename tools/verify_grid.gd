extends SceneTree
## Headless verification for SLICE B — the reactive grid's multi-ripple pool (#16) and
## implosion + color-shift (#17). Drives ONLY GridFloor's PURE pool API on a bare .new()
## instance (no ShaderMaterial, no GPU): allocate_ripple / advance / set_color_shift and
## the read-back helpers (active_ripple_count / ripple_slots / shift_amount). The GPU push
## (_flush_*) is guarded behind `if _mat != null`, so none of it runs here. Run:
##   tools/run-headless.sh res://tools/verify_grid.gd /tmp/verify_grid_result.txt

const RESULT_PATH := "/tmp/verify_grid_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var GridS: GDScript = load("res://assets/levels/grid_floor.gd")
	if GridS == null:
		lines.append("RESULT=FAIL (grid_floor.gd missing)"); _write(lines); return

	var g = GridS.new()                       # bare instance — no _ready, no material
	var cap: int = g.MAX_RIPPLES
	lines.append("setup: MAX_RIPPLES=%d, initial active=%d (want active=0)" % [cap, g.active_ripple_count()])
	if cap != 8 or g.active_ripple_count() != 0:
		lines.append("setup FAIL: pool should start empty with 8 slots"); ok = false

	# === 1) MULTI-RIPPLE CAP + OLDEST EVICTION (#16) =========================
	# Poke 9 ripples, each slightly OLDER than the next by advancing a hair between pokes,
	# so slot ages are strictly ordered and the eviction victim is unambiguous.
	# The FIRST ripple (oldest) carries a unique center we can prove gets evicted.
	var evict_marker := Vector2(111.0, 222.0)
	g.allocate_ripple(evict_marker, false)    # ripple #1 — should become the oldest
	for i in range(8):                        # 8 more → total 9 allocations, 1 over cap
		g.advance(0.001)                      # age the existing ones a touch (keeps order)
		g.allocate_ripple(Vector2(float(i) * 10.0, 0.0), false)

	lines.append("cap: after 9 allocations active=%d (want <=8, exactly 8)" % g.active_ripple_count())
	if g.active_ripple_count() > 8:
		lines.append("cap FAIL: pool exceeded MAX_RIPPLES"); ok = false
	if g.active_ripple_count() != 8:
		lines.append("cap FAIL: pool should be full (8) after 9 pokes"); ok = false

	# The oldest (the evict_marker ripple) must have been overwritten — no live slot keeps
	# that center any more.
	var marker_alive := false
	for slot in g.ripple_slots():
		if bool(slot["active"]) and Vector2(slot["center"]).is_equal_approx(evict_marker):
			marker_alive = true
	lines.append("evict: oldest marker still alive=%s (want false — it was evicted)" % str(marker_alive))
	if marker_alive:
		lines.append("evict FAIL: the oldest ripple was not the eviction victim"); ok = false

	# === 2) IMPLOSION FLAG STORED (#17) ======================================
	var g2 = GridS.new()
	var imp_idx: int = g2.allocate_ripple(Vector2(540.0, 960.0), true)   # implosion ripple
	var out_idx: int = g2.allocate_ripple(Vector2(100.0, 100.0), false)  # outward ripple
	var imp_stored := bool(g2.ripple_slots()[imp_idx]["implode"])
	var out_stored := bool(g2.ripple_slots()[out_idx]["implode"])
	lines.append("implode: stored flags implode=%s outward=%s (want true,false)" % [str(imp_stored), str(out_stored)])
	if not imp_stored or out_stored:
		lines.append("implode FAIL: implosion flag not stored per-slot"); ok = false

	# === 3) RIPPLE AGE-OUT / FREE (#16) ======================================
	# A single ripple must free itself once advanced past RIPPLE_LIFE.
	var g3 = GridS.new()
	g3.allocate_ripple(Vector2.ZERO, false)
	lines.append("ageout: active before=%d (want 1)" % g3.active_ripple_count())
	if g3.active_ripple_count() != 1:
		lines.append("ageout FAIL: ripple did not allocate"); ok = false
	g3.advance(g3.RIPPLE_LIFE + 0.01)         # push it past its life
	lines.append("ageout: active after life=%d (want 0 — freed)" % g3.active_ripple_count())
	if g3.active_ripple_count() != 0:
		lines.append("ageout FAIL: dead ripple was not freed"); ok = false

	# === 4) COLOR-SHIFT DECAY → 0 (#17) ======================================
	var g4 = GridS.new()
	g4.set_color_shift(Color(3.6, 0.6, 3.0, 1.0))    # mimic Palette.GATE_MULTIPLY
	var s_full: float = g4.shift_amount()
	lines.append("shift: after set=%.3f (want 1.0)" % s_full)
	if not is_equal_approx(s_full, 1.0):
		lines.append("shift FAIL: color-shift did not arm to full"); ok = false
	# Advance roughly half the decay window — strength should drop but not hit 0.
	g4.advance(g4.SHIFT_DECAY * 0.5)
	var s_mid: float = g4.shift_amount()
	lines.append("shift: mid-decay=%.3f (want 0<x<1, decaying)" % s_mid)
	if not (s_mid > 0.0 and s_mid < s_full):
		lines.append("shift FAIL: color-shift not decaying"); ok = false
	# Advance past the rest of the window — strength must reach exactly 0 (clamped).
	g4.advance(g4.SHIFT_DECAY)
	var s_end: float = g4.shift_amount()
	lines.append("shift: fully decayed=%.3f (want 0.0)" % s_end)
	if s_end != 0.0:
		lines.append("shift FAIL: color-shift did not decay to 0"); ok = false

	# === 5) GATE-OP → TINT MAP (#17) =========================================
	# The pure op→colour helper must distinguish the three families and fall back to blue.
	var mul: Color = g4._shift_color_for("multiply")
	var add: Color = g4._shift_color_for("add")
	var subc: Color = g4._shift_color_for("subtract")
	var divc: Color = g4._shift_color_for("divide")
	lines.append("tint: mul!=add=%s  sub==div=%s  (want true,true)" % [
		str(mul != add), str(subc == divc)])
	if mul == add or subc != divc:
		lines.append("tint FAIL: gate ops did not map to distinct tints"); ok = false

	# === 6) VIEWPORT COVERAGE — NO BOTTOM BAND (#70) =========================
	# A bare instance's _design is the 1080x1920 default. coverage_size() must FILL a viewport
	# taller than 1920 (a 19.5:9 iPhone renders ~1080x2340), so the grid reaches the bottom
	# instead of leaving the dead band the device feedback showed.
	var g5 = GridS.new()
	var tall := Vector2(1080.0, 2340.0)               # emulated 19.5:9 portrait device
	var cover: Vector2 = g5.coverage_size(tall)
	lines.append("cover: tall %s -> grid %s (want height >= 2340, width >= 1080)" % [str(tall), str(cover)])
	if cover.y < tall.y or cover.x < tall.x:
		lines.append("cover FAIL: grid does not cover a taller-than-1920 viewport — band remains"); ok = false
	# The design rect is the FLOOR — a viewport SMALLER than design still covers the design.
	var small: Vector2 = g5.coverage_size(Vector2(900.0, 1600.0))
	lines.append("cover: small viewport -> grid %s (want >= 1080x1920 design floor)" % str(small))
	if small.x < 1080.0 or small.y < 1920.0:
		lines.append("cover FAIL: coverage dropped below the design rect"); ok = false

	# === 7) SHADER STILL COMPILES + RIPPLE UNIFORMS INTACT (#70/#71) =========
	# The restyle (depth falloff, calmer warp) must not break the shader or drop the ripple/
	# color-shift uniforms the reactivity (#16/#17) pushes every frame.
	var sh: Shader = load("res://shaders/reactive_grid.gdshader")
	if sh == null:
		lines.append("shader FAIL: reactive_grid.gdshader did not load"); ok = false
	else:
		var sm := ShaderMaterial.new()
		sm.shader = sh
		# Probe every uniform the GDScript flush writes — a typo/removal would make these no-op
		# silently on the material, so assert each round-trips a set value.
		var probes := {
			"ripple_center": PackedVector2Array([Vector2(1.0, 2.0)]),
			"ripple_radius": PackedFloat32Array([3.0]),
			"ripple_strength": PackedFloat32Array([4.0]),
			"ripple_implode": PackedFloat32Array([1.0]),
			"shift_color": Color(0.3, 0.3, 3.8, 1.0),
			"shift_amount": 0.5,
			"beat_pulse": 0.7,
			"resolution": Vector2(1080.0, 2340.0),
		}
		for key in probes:
			sm.set_shader_parameter(key, probes[key])
		var missing: Array[String] = []
		for key in probes:
			if sm.get_shader_parameter(key) == null:
				missing.append(key)
		lines.append("shader: ripple/shift/resolution uniforms present, missing=%s (want [])" % str(missing))
		if not missing.is_empty():
			lines.append("shader FAIL: reactive uniforms missing after restyle"); ok = false

	# === 8) BEAT PULSE (#61): arms, max()-holds, decays to 0 ==================
	# music_beat → pulse_beat arms a global brightness/warp breath; a weaker off-beat must not
	# cut a live stronger downbeat short, and it must decay cleanly to 0 (pure, no material).
	var g6 = GridS.new()
	lines.append("beat: initial pulse=%.2f (want 0)" % g6.beat_pulse_amount())
	if g6.beat_pulse_amount() != 0.0:
		lines.append("beat FAIL: pulse should start at 0"); ok = false
	g6.pulse_beat(1.0)
	if not is_equal_approx(g6.beat_pulse_amount(), 1.0):
		lines.append("beat FAIL: pulse_beat did not arm to full"); ok = false
	g6.pulse_beat(0.3)                                 # weaker off-beat must NOT clobber the 1.0
	lines.append("beat: after weak-over-strong=%.3f (want 1.0 — max-held)" % g6.beat_pulse_amount())
	if not is_equal_approx(g6.beat_pulse_amount(), 1.0):
		lines.append("beat FAIL: weak pulse clobbered a stronger live one"); ok = false
	g6.advance(g6.BEAT_PULSE_DECAY * 0.5)
	var b_mid: float = g6.beat_pulse_amount()
	g6.advance(g6.BEAT_PULSE_DECAY)                     # past the rest of the window → 0
	var b_end: float = g6.beat_pulse_amount()
	lines.append("beat: mid=%.3f end=%.3f (want 0<mid<1, end=0)" % [b_mid, b_end])
	if not (b_mid > 0.0 and b_mid < 1.0) or b_end != 0.0:
		lines.append("beat FAIL: beat pulse did not decay to 0"); ok = false

	# === 9) SCROLL DIRECTION (#bug): forward travel flows the grid TOP -> BOTTOM ==
	# The shader samples `gy = p.y/cell_size + scroll`; a POSITIVE scroll slides lines UP
	# (backward). To read as forward motion (world coming toward the bottom-of-screen ship)
	# the grid must flow DOWN, so GridFloor must feed a NEGATIVE scroll for POSITIVE distance.
	# Drive _on_distance_changed against a real material (the only material-touching path here)
	# and assert the pushed `scroll` uniform is negative + scales with distance.
	var g7 = GridS.new()
	var sm2 := ShaderMaterial.new()
	sm2.shader = load("res://shaders/reactive_grid.gdshader")
	g7._mat = sm2                                  # inject a material so the flush path runs
	g7._on_distance_changed(0.0, 0.0)
	var scroll0: float = float(sm2.get_shader_parameter("scroll"))
	g7._on_distance_changed(100.0, 0.5)
	var scroll_fwd: float = float(sm2.get_shader_parameter("scroll"))
	lines.append("scroll-dir: at d=0 scroll=%.3f, at d=100 scroll=%.3f (want negative -> downward flow)" % [scroll0, scroll_fwd])
	if not (is_equal_approx(scroll0, 0.0) and scroll_fwd < 0.0):
		lines.append("scroll-dir FAIL: forward travel must push a NEGATIVE scroll (grid flows TOP->BOTTOM)"); ok = false
	else:
		lines.append("scroll-dir OK: forward travel pushes negative scroll -> grid flows top->bottom toward the ship")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
