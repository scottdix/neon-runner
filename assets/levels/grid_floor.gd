class_name GridFloor
extends Node2D
## The reactive vector grid floor (#NEW, DESIGN_SPEC "Reactive vector grid"). A faint
## blue grid that scrolls toward the ship and warps under action — the primary ground
## signature (supersedes the first-pass perspective rings; those can stay as a secondary
## accent later).
##
## It is ONE full-screen ColorRect driven by shaders/reactive_grid.gdshader, parented to
## its own CanvasLayer at layer -1 so it renders BEHIND every world entity regardless of
## tree order. Wiring is Events-only: scroll follows `distance_changed` on the SHARED
## TrackView projection (so the grid moves at the same rate as gates/finish),
## `trigger_grid_ripple` pokes a transient radial warp, and `gate_passed` tints the grid.
## Glow + warp are device-unproven here (Intel UHD 630 can't compile glow pipelines) —
## confirm on iPhone (#47/#54).
##
## #16 (multi-ripple): a FIXED 8-slot ripple POOL lets several kills/breaches ring at
## once instead of clobbering one shared ripple; when all slots are busy the OLDEST is
## evicted. #17 (implosion + color-shift): divide/breach ripples PULL inward, and the
## whole grid lerps toward the last gate's hue, decaying back to blue.
##
## ALL pool bookkeeping (allocate / evict / age / decay) lives in PURE methods that run
## with NO live ShaderMaterial, so verify_grid.gd can drive them headless on a bare
## .new() instance. Every set_shader_parameter is guarded behind `if _mat != null`; the
## GPU push (_flush_*) is the only part that touches the material.

const TRACK := preload("res://assets/levels/track.gd")
const GRID_SHADER := preload("res://shaders/reactive_grid.gdshader")

const CELL_PX := 96.0               # must match the shader's default feel
## A poked ripple expands at this px/sec and fades over RIPPLE_LIFE seconds.
const RIPPLE_SPEED := 900.0
const RIPPLE_LIFE := 0.55
const RIPPLE_START_STRENGTH := 26.0 # px of displacement at the ring's birth

## Number of simultaneous ripples (#16). MUST equal the shader's `MAX_RIPPLES` literal —
## we push exactly this many entries into each ripple_* uniform array every frame.
const MAX_RIPPLES := 8

## Color-shift (#17): the last gate's tint fades out over this many seconds.
const SHIFT_DECAY := 0.6

## Beat pulse (#61 music-reactive): a music_beat arms a global brightness/warp "breath" at the
## beat's strength, decaying to 0 over this many seconds — snappy so each beat reads as a
## distinct throb rather than a smear.
const BEAT_PULSE_DECAY := 0.26

var _mat: ShaderMaterial
var _design := Vector2(1080, 1920)
## The full-screen grid quad. Held so the size_changed handler can re-fit it to the ACTUAL
## visible viewport (#70 — a fixed 1080x1920 rect leaves a dead band on a tall 19.5:9 phone).
var _rect: ColorRect

## The ripple pool. Each slot is a Dictionary {active:bool, age:float, center:Vector2,
## implode:bool}. Fixed length MAX_RIPPLES, allocated once in _init so the PURE methods
## (and the verifier) never depend on _ready / a material having run.
var _ripples: Array[Dictionary] = []

## Color-shift state, decayed in _process. _shift_color is the target hue (HDR), _shift
## is the current 0..1 strength.
var _shift_color := Color(0.30, 0.30, 3.8, 1.0)
var _shift: float = 0.0

## Beat-pulse strength (0..1), armed by Events.music_beat and decayed in advance() (#61).
var _beat_pulse: float = 0.0


func _init() -> void:
	# Build the pool eagerly so allocate/evict/age work on a bare .new() (headless tests
	# never reach _ready). Slots start inactive (strength 0 → invisible in the shader).
	_ripples.clear()
	for i in MAX_RIPPLES:
		_ripples.append({"active": false, "age": 0.0, "center": Vector2.ZERO, "implode": false})


func _ready() -> void:
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))

	_mat = ShaderMaterial.new()
	_mat.shader = GRID_SHADER
	_mat.set_shader_parameter("resolution", _design)
	_mat.set_shader_parameter("cell_size", CELL_PX)
	_mat.set_shader_parameter("grid_color", Palette.GRID_BLUE)
	_shift_color = Palette.GRID_BLUE        # idle tint matches the grid (no visible shift)
	_flush_ripples()                        # zero every slot so nothing rings at birth
	_flush_shift()

	# FULL_RECT anchors pin the quad to the whole viewport so it always covers the actual
	# device, not the 1080x1920 design rect (#70). _fit_to_viewport() then syncs the shader's
	# `resolution` to the real covered size so cells stay cell_size px (no stretch on tall
	# screens — just more rows below the old 1920 line).
	var rect := ColorRect.new()
	rect.name = "GridRect"
	rect.material = _mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat steer touches
	_rect = rect

	var layer := CanvasLayer.new()
	layer.name = "GridLayer"
	layer.layer = -1                                  # behind all world entities
	layer.add_child(rect)
	add_child(layer)

	# Fit now, and re-fit whenever the viewport size changes (rotation, resolution, the
	# editor) so the band can never reappear.
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()

	Events.distance_changed.connect(_on_distance_changed)
	Events.trigger_grid_ripple.connect(_on_grid_ripple)
	Events.gate_passed.connect(_on_gate_passed)
	Events.music_beat.connect(_on_music_beat)


func _process(delta: float) -> void:
	# PURE step first (ages ripples, frees the dead, decays the color-shift), then push the
	# resulting numbers to the GPU. Splitting it this way lets the verifier call advance()
	# with no material and read the pool back.
	advance(delta)
	_flush_ripples()
	_flush_shift()
	_flush_beat()


# === Viewport coverage (#70 — kill the bottom band) ==========================

## Resize the grid quad to the ACTUAL visible viewport and push that size to the shader's
## `resolution` so the grid fills any aspect (e.g. a 1080x2340 19.5:9 phone) instead of the
## fixed 1080x1920 design rect. FULL_RECT already pins the rect; we still set size/resolution
## explicitly so the shader's px math matches what's on screen and re-fits on size_changed.
func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var size := coverage_size(vp.get_visible_rect().size)
	if _rect != null:
		_rect.position = Vector2.ZERO
		_rect.size = size
	if _mat != null:
		_mat.set_shader_parameter("resolution", size)

## PURE: the px coverage size for a given viewport size. Never smaller than the design rect
## on either axis, so a viewport TALLER than 1920 (the band case) is fully covered while cell
## density stays cell_size px (the shader tiles more rows — no stretch). Headless-testable:
## the verifier feeds it a 2340-tall size and asserts full coverage.
func coverage_size(viewport_size: Vector2) -> Vector2:
	return Vector2(maxf(viewport_size.x, _design.x), maxf(viewport_size.y, _design.y))


# === PURE pool API (headless-safe; no material, no GPU) ======================
# All of the following run on a bare GridFloor.new() — they only mutate _ripples / _shift.

## Allocate a ripple at `center`. Reuses a free slot; if every slot is busy, EVICTS the
## OLDEST (max age) and reuses it (#16 — a burst of kills never silently drops the newest).
## `implode` (#17) flags the slot so the shader pulls inward instead of pushing outward.
## Returns the slot index used (handy for tests).
func allocate_ripple(center: Vector2, implode: bool) -> int:
	var idx := _free_slot()
	if idx < 0:
		idx = _oldest_slot()              # all busy → evict the oldest
	var slot: Dictionary = _ripples[idx]
	slot["active"] = true
	slot["age"] = 0.0
	slot["center"] = center
	slot["implode"] = implode
	return idx


## Age every active ripple by `delta`, freeing any that outlive RIPPLE_LIFE, and decay the
## color-shift toward 0 over SHIFT_DECAY. The whole frame's pure update, GPU-free.
func advance(delta: float) -> void:
	for slot in _ripples:
		if not bool(slot["active"]):
			continue
		slot["age"] = float(slot["age"]) + delta
		if float(slot["age"]) >= RIPPLE_LIFE:
			slot["active"] = false
			slot["age"] = 0.0
	if _shift > 0.0:
		_shift = maxf(0.0, _shift - delta / SHIFT_DECAY)
	if _beat_pulse > 0.0:
		_beat_pulse = maxf(0.0, _beat_pulse - delta / BEAT_PULSE_DECAY)


## Set the recent-action color-shift to full strength toward `color` (#17). Decays in
## advance(). Kept pure so a test can poke it and watch it fade.
func set_color_shift(color: Color) -> void:
	_shift_color = color
	_shift = 1.0


## How many ripple slots are currently live (0..MAX_RIPPLES). Exposed for the verifier's
## eviction assertion.
func active_ripple_count() -> int:
	var n := 0
	for slot in _ripples:
		if bool(slot["active"]):
			n += 1
	return n


## Read-only access to the slot pool (the verifier inspects age / implode / center).
func ripple_slots() -> Array[Dictionary]:
	return _ripples


## Current color-shift strength (0..1). Exposed so the verifier can watch the decay.
func shift_amount() -> float:
	return _shift


## Arm the global beat "breath" to `strength` (0..1), decayed in advance() (#61). max() so a
## weaker off-beat never cuts a stronger downbeat short. PURE — only mutates _beat_pulse.
func pulse_beat(strength: float) -> void:
	_beat_pulse = maxf(_beat_pulse, clampf(strength, 0.0, 1.0))


## Current beat-pulse strength (0..1). Exposed so the verifier can watch the decay.
func beat_pulse_amount() -> float:
	return _beat_pulse


## Index of a free slot, or -1 if all are busy.
func _free_slot() -> int:
	for i in MAX_RIPPLES:
		if not bool(_ripples[i]["active"]):
			return i
	return -1


## Index of the OLDEST active slot (max age) — the eviction victim when the pool is full.
func _oldest_slot() -> int:
	var best := 0
	var best_age := -1.0
	for i in MAX_RIPPLES:
		var a := float(_ripples[i]["age"])
		if bool(_ripples[i]["active"]) and a > best_age:
			best_age = a
			best = i
	return best


# === GPU push (material-only; the just-aged pool → uniform arrays) ============

## Pack the pool into the shader's ripple_* arrays. Each slot's radius = age*SPEED, its
## strength fades over its life (0 when inactive), and implode flags the inward pull. Sized
## exactly MAX_RIPPLES to match the shader. No-op without a material (headless).
func _flush_ripples() -> void:
	if _mat == null:
		return
	var centers := PackedVector2Array()
	var radii := PackedFloat32Array()
	var strengths := PackedFloat32Array()
	var implodes := PackedFloat32Array()
	centers.resize(MAX_RIPPLES)
	radii.resize(MAX_RIPPLES)
	strengths.resize(MAX_RIPPLES)
	implodes.resize(MAX_RIPPLES)
	for i in MAX_RIPPLES:
		var slot: Dictionary = _ripples[i]
		if bool(slot["active"]):
			var k: float = float(slot["age"]) / RIPPLE_LIFE      # 0..1 over the life
			centers[i] = slot["center"]
			radii[i] = float(slot["age"]) * RIPPLE_SPEED
			strengths[i] = RIPPLE_START_STRENGTH * (1.0 - k)
			implodes[i] = 1.0 if bool(slot["implode"]) else 0.0
		else:
			centers[i] = Vector2.ZERO
			radii[i] = 0.0
			strengths[i] = 0.0                                   # 0 == inactive in shader
			implodes[i] = 0.0
	_mat.set_shader_parameter("ripple_center", centers)
	_mat.set_shader_parameter("ripple_radius", radii)
	_mat.set_shader_parameter("ripple_strength", strengths)
	_mat.set_shader_parameter("ripple_implode", implodes)


## Push the current color-shift hue + strength to the shader. No-op without a material.
func _flush_shift() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("shift_color", _shift_color)
	_mat.set_shader_parameter("shift_amount", _shift)


## Push the current beat-pulse strength to the shader (#61). No-op without a material.
func _flush_beat() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("beat_pulse", _beat_pulse)


# === Events wiring ===========================================================

## Scroll the grid in CELLS, derived from metres travelled on the shared projection so
## it tracks gates/finish exactly (PIXELS_PER_METER px per metre / CELL_PX px per cell).
## NEGATED so forward travel reads as the grid flowing TOP -> BOTTOM (the world coming toward
## the player at the bottom). The shader does `gy = p.y / cell_size + scroll`; a POSITIVE
## scroll slides lines UP on screen (backward), so we feed it the negative of distance to get
## the correct downward forward-motion flow on device. Warp/ripple/beat-pulse are untouched.
func _on_distance_changed(distance: float, _progress: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("scroll", -distance * TRACK.PIXELS_PER_METER / CELL_PX)


## A kill (is_implosion=false → outward ring) or a breach/divide (is_implosion=true →
## inward pull, #17) pokes a fresh ripple into the pool. Allocation is pure; the GPU sees
## it on the next _process flush.
func _on_grid_ripple(at: Vector2, is_implosion: bool) -> void:
	allocate_ripple(at, is_implosion)


## Tint the grid toward the gate's hue when one is crossed (#17 color-shift). Maps the
## gate_type string (see gate.gd._op_string) to a Palette HDR colour; decays in advance().
func _on_gate_passed(gate_type: String, _value: float, _new_count: int) -> void:
	set_color_shift(_shift_color_for(gate_type))


## A music beat landed (#61): arm the global brightness/warp breath at the beat's strength.
## The pulse is pure state; the GPU sees it on the next _process flush (_flush_beat).
func _on_music_beat(strength: float) -> void:
	pulse_beat(strength)


## Gate-op → tint. Positive ops glow their own hue; subtract/divide use the "negative" red.
func _shift_color_for(gate_type: String) -> Color:
	match gate_type:
		"multiply":
			return Palette.GATE_MULTIPLY
		"add":
			return Palette.GATE_ADD
		"subtract", "divide":
			return Palette.GATE_NEGATIVE
	return Palette.GRID_BLUE


## AMOLED / low-power: dim the grid and calm its warp so the screen is quieter and the
## bloom path cheaper (DESIGN_SPEC "Platform feel"). Standard mode is the brighter grid.
func set_low_power(low: bool) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("intensity", 0.18 if low else 0.35)
	# Standard warp matches the calmed resting baseline (#71); low-power calms it further.
	_mat.set_shader_parameter("warp_amp", 2.0 if low else 4.0)
