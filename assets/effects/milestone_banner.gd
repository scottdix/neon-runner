extends CanvasLayer
## Milestone celebration banner (#28) — punctuates the swarm getting BIG.
##
## When the swarm volume (projectile_count) first crosses 100 / 500 / 1000 in a run, this:
##   - emits Events.milestone_reached(m) ONCE per threshold (the contract: audio fanfare, a heavy
##     haptic, and extra particles all fire elsewhere off that signal — this layer owns none of it);
##   - flashes a big centred screen-space banner ("x100 SWARM") that scales up + fades out; and
##   - drops a brief slow-mo (Engine.time_scale ~0.6 for ~0.35s, restored on a timer) for punch.
##
## DESIGN / GOTCHA notes:
##   - CROSS-DETECTION is PURE: _crossed(prev, now) returns every milestone m with prev < m <= now,
##     in order, so a single huge gate spike that vaults past several at once celebrates each in
##     turn. The handler additionally filters anything already in _fired so each threshold fires
##     exactly ONCE per run (declines/re-rises never re-fire it). game_started clears _fired and
##     re-arms (_last_count = 0) so a fresh run can hit the same milestones again.
##   - HEADLESS determinism: ALL the decision logic (_crossed) is a PURE method callable on a bare
##     Script.new() with NO tree/GPU/Engine dependency. _celebrate ALWAYS emits milestone_reached
##     (state-free, safe to assert), but the banner + Engine.time_scale slow-mo are guarded behind
##     _is_live — set true only in _ready — so a verify .new() (no _ready) NEVER mutates global
##     time_scale or touches a missing Label. Mirrors GameState.wire_events / Haptics.wire.
##   - The banner Label is kept LDR/HUD-crisp (out of the bloom), same discipline as the HUD text.

# --- Thresholds (the swarm-volume celebrations) ------------------------------
const MILESTONES: Array[int] = [100, 500, 1000]

# Banner animation timing.
const BANNER_HOLD := 0.18       # seconds at full punch before it starts fading
const BANNER_FADE := 0.95       # seconds to scale-up + fade fully out
const BANNER_SCALE_FROM := 0.6  # pops in from small…
const BANNER_SCALE_TO := 1.35   # …and overshoots large as it dissolves

# Slow-mo punch.
const SLOWMO_SCALE := 0.6
const SLOWMO_DURATION := 0.35   # WALL-CLOCK seconds (timer ignores time_scale) before restore

# --- Run state (PURE-safe; no tree/GPU) --------------------------------------
var _last_count: int = 0
var _fired: Dictionary = {}     # milestone(int) -> true, so each celebrates once per run

# --- Live-only wiring (set in _ready; a bare .new() leaves it false) ----------
var _is_live: bool = false
var _label: Label = null
var _anim_t: float = 0.0        # 0..(BANNER_HOLD+BANNER_FADE); > total ⇒ idle/hidden
var _slowmo_timer: Timer = null


func _ready() -> void:
	# GPU/tree wiring lives here ONLY — _ready is deferred under headless `-s`, so none of this
	# runs in a verify, which is why every consumer below is guarded by _is_live.
	layer = 60                                  # above the HUD (50), below pause (100)
	_label = _build_label()
	add_child(_label)
	_slowmo_timer = Timer.new()
	_slowmo_timer.one_shot = true
	_slowmo_timer.timeout.connect(_on_slowmo_timeout)
	add_child(_slowmo_timer)
	_anim_t = BANNER_HOLD + BANNER_FADE + 1.0   # start parked/hidden
	set_process(true)
	_is_live = true
	wire()


## Public, idempotent bus wiring (mirrors Haptics.wire / GameState.wire_events). A verify script
## calls this explicitly because autoload/_ready ordering means the connections aren't live yet.
func wire() -> void:
	if not Events.projectile_count_changed.is_connected(_on_projectile_count_changed):
		Events.projectile_count_changed.connect(_on_projectile_count_changed)
	if not Events.game_started.is_connected(_on_game_started):
		Events.game_started.connect(_on_game_started)


# --- Bus handlers (thin: PURE cross-detect, then celebrate) ------------------

## Swarm volume changed. Celebrate every NEW milestone crossed since the last count (a single jump
## can cross several), skipping any already fired this run, then advance _last_count. PURE-safe:
## _crossed touches no tree/Engine; _celebrate's only global mutation (time_scale/banner) is guarded.
func _on_projectile_count_changed(count: int) -> void:
	for m in _crossed(_last_count, count):
		if _fired.has(m):
			continue
		_fired[m] = true
		_celebrate(m)
	_last_count = count


## A new run started — clear the fired set and re-arm at 0 so the same milestones can fire again.
func _on_game_started() -> void:
	_fired.clear()
	_last_count = 0


# --- PURE decision logic (headless-safe; the verify asserts on this) ----------

## Every milestone strictly above `prev` and at-or-below `now`, in ascending order. Empty when the
## count held or fell (now <= prev). Handles a multi-cross jump (e.g. 480→1200 ⇒ [500, 1000]). NO
## tree / Engine / GPU — pure arithmetic over MILESTONES, so the verify can assert it on a .new().
func _crossed(prev: int, now: int) -> Array[int]:
	var hit: Array[int] = []
	for m in MILESTONES:
		if prev < m and m <= now:
			hit.append(m)
	return hit


# --- Celebration (contract emit is PURE; banner/slow-mo guarded by _is_live) --

## ALWAYS emit milestone_reached(m) — the contract that audio fanfare / heavy haptic / extra
## particles hang off of. Then, ONLY when live, flash the banner and drop the brief slow-mo. The
## _is_live guard means a bare .new() in a verify emits the signal but never mutates Engine.time_scale
## nor reaches into the (un-built) Label.
func _celebrate(m: int) -> void:
	Events.milestone_reached.emit(m)
	if not _is_live:
		return
	_show_banner(m)
	_begin_slowmo()
	_celebrate_particles()


## "Extra particles/effects" (#28): fire a screen-wide spread of explosion bursts off the existing
## spawn_particles bus signal — EffectLayer already pools + fires its GPU bursts in response, so the
## milestone reads as a playfield-wide pop with no new emitter here. Canvas == world (identity camera),
## so these design-space points land where intended. Live-only (called from the guarded branch).
func _celebrate_particles() -> void:
	var points := [
		Vector2(270.0, 760.0), Vector2(540.0, 620.0), Vector2(810.0, 760.0),
		Vector2(400.0, 920.0), Vector2(680.0, 920.0)]
	for p in points:
		Events.spawn_particles.emit(p, "explosion")


## Snap the banner to its milestone text, reset the animation clock, and let _process run the
## scale-up + fade. Live-only (guarded by its caller).
func _show_banner(m: int) -> void:
	if _label == null:
		return
	_label.text = "x%d SWARM" % m
	_label.modulate = Color(Palette.HUD_WHITE.r, Palette.HUD_WHITE.g, Palette.HUD_WHITE.b, 1.0)
	_anim_t = 0.0


## Engage slow-mo and arm the wall-clock restore timer. Timer.timeout ignores time_scale, so the
## slow-mo always lasts SLOWMO_DURATION real seconds regardless of the scale it sets.
func _begin_slowmo() -> void:
	if _slowmo_timer == null:
		return
	Engine.time_scale = SLOWMO_SCALE
	_slowmo_timer.start(SLOWMO_DURATION)


func _on_slowmo_timeout() -> void:
	Engine.time_scale = 1.0


# --- Banner animation (live-only; _process is disabled until _ready) ----------

## Drive the banner pop: hold at full punch, then scale-up toward BANNER_SCALE_TO while fading alpha
## to 0 over BANNER_FADE. Parks (hidden) once past the total duration. `delta` here is UNSCALED so
## the banner reads at a steady speed even while the slow-mo is active.
func _process(delta: float) -> void:
	if _label == null:
		return
	var total := BANNER_HOLD + BANNER_FADE
	if _anim_t > total:
		if _label.modulate.a != 0.0:
			_label.modulate.a = 0.0
		return
	_anim_t += delta / maxf(Engine.time_scale, 0.0001)   # un-scale so slow-mo doesn't slow the banner
	if _anim_t <= BANNER_HOLD:
		_apply_banner(BANNER_SCALE_FROM, 1.0)
	else:
		var f: float = clampf((_anim_t - BANNER_HOLD) / BANNER_FADE, 0.0, 1.0)
		_apply_banner(lerpf(BANNER_SCALE_FROM, BANNER_SCALE_TO, f), 1.0 - f)


## Apply a scale (about the screen centre) + alpha to the banner Label. Live-only helper.
func _apply_banner(s: float, a: float) -> void:
	if _label == null:
		return
	_label.scale = Vector2(s, s)
	_label.pivot_offset = _label.size * 0.5
	_label.modulate.a = a


# --- Banner Label construction (GPU/tree; built in _ready only) ---------------

## The centred celebration Label — big, crisp HUD-white (kept out of the bloom, same as the HUD).
## Full-rect + centred so the pivot-scaled pop reads from the screen centre on any device size.
func _build_label() -> Label:
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 120)
	lbl.add_theme_color_override("font_color", Palette.HUD_WHITE)
	lbl.modulate = Color(1, 1, 1, 0.0)          # start invisible until a milestone fires
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl
