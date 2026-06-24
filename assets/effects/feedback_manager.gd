extends Node2D
## FeedbackManager (#23) — screen shake + full-screen colour flash, driven ENTIRELY by the Events
## bus. Run instantiates ONE of these and add_child()s it; it self-wires to the bus in _ready and
## thereafter turns impactful beats (kills, breaches, denied splices, gate fires, collapse) into a
## camera trauma-shake and/or a colour flash. It NEVER references another system — it only listens.
##
## DESIGN / GOTCHA notes:
##   - CAMERA TRAUMA MODEL (the good one): a single _trauma float (0..1) is added to per impact and
##     decays continuously. The visible shake is trauma SQUARED times a deterministic pseudo-noise of
##     time, so small hits barely wobble while a collapse slams. The Camera2D is ANCHOR_MODE_FIXED_TOP_LEFT
##     at position ZERO → an identity view (world unchanged) until we push camera.offset. The HUD and grid
##     live on CanvasLayers, so they are immune to the camera — only world entities shake. Correct.
##   - FLASH: a CanvasLayer (layer ~90, above the world, the HUD sits higher still) holds one full-rect
##     mouse-ignoring ColorRect. flash() records colour + duration + resets elapsed; _process fades the
##     rect's modulate alpha 1→0 over the duration. The colour is a flat literal/Palette HUD token, NOT
##     HDR — a flash is a CanvasLayer overlay, not a bloom source, so it must stay <= 1.0 to read as a
##     clean tint and not blow out.
##   - HEADLESS determinism: every magnitude/where decision lives in a PURE method
##     (_shake_offset / _flash_alpha) callable on a bare .new() with NO Camera/CanvasLayer/tree. add_trauma
##     is pure float state; flash() just records fields. The ONLY GPU/tree-touching steps are in _process
##     (camera.offset / rect.modulate) and _ready (build) — all guarded so a pool-less / _ready-less .new()
##     instance no-ops instead of crashing. The verify script asserts the PURE methods + runs every bus
##     handler on a bare .new() without error.
##
## Bus inputs (READ-ONLY — this manager only listens, never re-emits run state):
##   trigger_screen_shake(intensity, duration) → add_trauma(intensity)  (duration is advisory; trauma decays)
##   trigger_screen_flash(color, duration)      → flash(color, duration)
##   enemy_destroyed(at, points)                → tiny kick per kill
##   enemy_breached(at, damage)                 → medium kick + a red breach flash
##   gate_hijack_blocked(gate_type, at)         → hard kick + a red denied flash
##   grid_collapsed                             → full slam + a white collapse flash
##   gate_passed(type, value, count)            → small kick (positive) / a bit more + faint red (negative)

# --- Trauma / shake tuning ---------------------------------------------------
## Trauma bleeds off this fast (units of trauma per second). ~1.2/s ⇒ a full 1.0 slam settles in
## under a second; a 0.10 kill kick is gone in ~0.08s — a punch, not a lingering wobble.
const TRAUMA_DECAY := 1.2
## Peak camera displacement at trauma 1 (shake == 1). Portrait 1080×1920, so ~34px reads as a solid
## slam without throwing world entities off-screen. _shake_offset stays within ±this on each axis.
const MAX_OFFSET := Vector2(34.0, 34.0)
## Pseudo-noise frequencies (rad/s-ish, t is _process accumulated time). Distinct + irrational-ish so
## x/y don't beat into a clean diagonal; a phase offset on y further decorrelates the two axes.
const SHAKE_FREQ_X := 47.0
const SHAKE_FREQ_Y := 61.0
const SHAKE_PHASE_Y := 1.7

# --- Per-event trauma magnitudes (named so the feel is one edit, see task contract) ---
const TRAUMA_KILL := 0.10     # enemy_destroyed — a tiny kick per kill
const TRAUMA_BREACH := 0.35   # enemy_breached — a noticeable jolt (you took damage)
const TRAUMA_HIJACK := 0.5    # gate_hijack_blocked — hard denied slam
const TRAUMA_COLLAPSE := 1.0  # grid_collapsed — maximum slam
const TRAUMA_GATE_POS := 0.12 # gate_passed positive (add/multiply) — a satisfying little pop
const TRAUMA_GATE_NEG := 0.22 # gate_passed negative (subtract/divide) — a heavier "you lost volume" jolt

# --- Flash tuning ------------------------------------------------------------
## CanvasLayer for the flash overlay: above the world, BELOW the HUD/menu layers so a flash never
## hides the readout. Run's run-scene z-order is world(0) < flash(40) < HUD(50) < milestone(60) < pause(100).
const FLASH_LAYER := 40
## Flash colours (flat LDR — a CanvasLayer overlay tint, NOT a bloom source, so kept <= 1.0). Red for
## loss/denied beats; white for the collapse. The alpha here is the PEAK opacity the flash fades from.
const FLASH_RED := Color(1.0, 0.18, 0.18, 0.55)        # breach / hijack-denied tint (LOSS family)
const FLASH_RED_FAINT := Color(1.0, 0.22, 0.22, 0.28)  # faint negative-gate tint (lighter than a breach)
const FLASH_WHITE := Color(1.0, 1.0, 1.0, 0.7)         # grid-collapse white wash

# --- Flash durations (s) -----------------------------------------------------
const FLASH_DUR_BREACH := 0.18
const FLASH_DUR_HIJACK := 0.18
const FLASH_DUR_COLLAPSE := 0.4
const FLASH_DUR_GATE_NEG := 0.16

# --- State (pure floats; safe on a bare .new(), no tree/GPU) ------------------
var _trauma: float = 0.0
var _shake_t: float = 0.0          # accumulated time feeding the pseudo-noise (advances in _process)

var _flash_color: Color = Color(0, 0, 0, 0)
var _flash_duration: float = 0.0
var _flash_elapsed: float = 0.0    # >= _flash_duration ⇒ flash done (alpha 0)

# --- Tree/GPU handles (null until _ready; every use of them is guarded) -------
var _camera: Camera2D = null
var _flash_rect: ColorRect = null


func _ready() -> void:
	# Build the camera + flash overlay, then self-wire to the bus. Under headless `-s`, _ready is
	# DEFERRED and may never fire before a tool's _initialize — that's why the PURE methods need no
	# handles and _process guards every handle access. A verify script connects the bus explicitly
	# via wire().
	_build_camera()
	_build_flash_overlay()
	wire()


# --- Self-wiring (idempotent; mirrors GameState.wire_events / Haptics.wire) ----

## Connect every consumed bus signal to its handler. Idempotent (each connect guarded with
## is_connected) so _ready AND a verify script may both call it without a double-connect error.
func wire() -> void:
	if not Events.trigger_screen_shake.is_connected(_on_trigger_screen_shake):
		Events.trigger_screen_shake.connect(_on_trigger_screen_shake)
	if not Events.trigger_screen_flash.is_connected(_on_trigger_screen_flash):
		Events.trigger_screen_flash.connect(_on_trigger_screen_flash)
	if not Events.enemy_destroyed.is_connected(_on_enemy_destroyed):
		Events.enemy_destroyed.connect(_on_enemy_destroyed)
	if not Events.enemy_breached.is_connected(_on_enemy_breached):
		Events.enemy_breached.connect(_on_enemy_breached)
	if not Events.gate_hijack_blocked.is_connected(_on_gate_hijack_blocked):
		Events.gate_hijack_blocked.connect(_on_gate_hijack_blocked)
	if not Events.grid_collapsed.is_connected(_on_grid_collapsed):
		Events.grid_collapsed.connect(_on_grid_collapsed)
	if not Events.gate_passed.is_connected(_on_gate_passed):
		Events.gate_passed.connect(_on_gate_passed)


# --- Public API (pure state mutation; safe before _ready) --------------------

## Add `amount` of camera trauma, clamped into 0..1. Trauma is the shake's energy; _process squares
## it for the visible displacement and decays it. Pure float math — no tree/GPU, safe on a bare .new().
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Start a full-screen flash of `color`, fading to transparent over `duration` s. Records the fields
## only; _process does the (guarded) GPU apply. A non-positive duration is ignored (no divide-by-zero
## in _flash_alpha, no stuck-on overlay). Pure field set — safe on a bare .new().
func flash(color: Color, duration: float) -> void:
	if duration <= 0.0:
		return
	_flash_color = color
	_flash_duration = duration
	_flash_elapsed = 0.0


# --- Per-frame apply (the ONLY tree/GPU-touching step; fully guarded) ---------

func _process(delta: float) -> void:
	# --- Shake: advance noise time, decay trauma, push the (guarded) camera offset ---
	_shake_t += delta
	if _trauma > 0.0:
		_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	if _camera != null:
		# At trauma 0 _shake_offset returns ~ZERO, so the camera snaps back to the identity view.
		_camera.offset = _shake_offset(_trauma, _shake_t)

	# --- Flash: advance elapsed, fade the (guarded) overlay alpha ---
	if _flash_duration > 0.0:
		_flash_elapsed += delta
		if _flash_rect != null:
			var a := _flash_alpha(_flash_elapsed, _flash_duration)
			var c := _flash_color
			_flash_rect.modulate = Color(c.r, c.g, c.b, c.a * a)
		# Once fully faded, drop the duration so we stop touching the rect every frame.
		if _flash_elapsed >= _flash_duration:
			_flash_duration = 0.0


# --- PURE decision logic (headless-safe; the verify script asserts on these) --

## Deterministic camera displacement for a given trauma + time. `shake = trauma*trauma` so small hits
## barely move and big hits slam (the trauma-model standard). Each axis is a sin pseudo-noise of `t`
## (distinct frequencies + a y phase offset so x/y don't lock into a diagonal), scaled by shake and
## MAX_OFFSET. Returns ~Vector2.ZERO at trauma 0 and ALWAYS stays within ±MAX_OFFSET (|sin| <= 1,
## shake in 0..1). NO tree/GPU — the verify script asserts the zero + bounds.
func _shake_offset(trauma: float, t: float) -> Vector2:
	var shake := trauma * trauma
	var ox := sin(t * SHAKE_FREQ_X) * MAX_OFFSET.x * shake
	var oy := sin(t * SHAKE_FREQ_Y + SHAKE_PHASE_Y) * MAX_OFFSET.y * shake
	return Vector2(ox, oy)


## Flash opacity factor for `elapsed` into a `duration`-long flash: 1.0 at elapsed 0, linearly down to
## 0.0 at/after duration, clamped into 0..1 (never negative, never > 1). Monotonically non-increasing.
## A non-positive duration returns 0 (caller never starts one; the guard here is belt-and-braces). NO
## tree/GPU — the verify script asserts the endpoints, clamp, and monotonicity.
func _flash_alpha(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - elapsed / duration, 0.0, 1.0)


# --- Bus handlers (thin: pick a magnitude/colour, call the pure public API) ----

## Explicit shake request — the value is the trauma to add (the most direct path; other beats below
## map their own named magnitudes). `duration` is advisory; trauma decay owns the falloff.
func _on_trigger_screen_shake(intensity: float, _duration: float) -> void:
	add_trauma(intensity)


## Explicit flash request — pass straight through.
func _on_trigger_screen_flash(color: Color, duration: float) -> void:
	flash(color, duration)


## #19/combat: an enemy died — a tiny per-kill kick so the swarm's work has weight without the screen
## ever feeling jittery during a heavy firefight (TRAUMA_KILL is intentionally small + clamps anyway).
func _on_enemy_destroyed(_at: Vector2, _points: int) -> void:
	add_trauma(TRAUMA_KILL)


## #55 loss loop: an enemy breached the ship line and drained the battery — a medium jolt + a red
## breach flash so a hit is felt and seen even if your eyes were elsewhere.
func _on_enemy_breached(_at: Vector2, _damage: float) -> void:
	add_trauma(TRAUMA_BREACH)
	flash(FLASH_RED, FLASH_DUR_BREACH)


## #53 hijack: a denied splice (enemy parked in the gate survived to the line) — a hard kick + a red
## denied flash, distinctly heavier than a breach so "you lost an upgrade" lands.
func _on_gate_hijack_blocked(_gate_type: String, _at: Vector2) -> void:
	add_trauma(TRAUMA_HIJACK)
	flash(FLASH_RED, FLASH_DUR_HIJACK)


## #55 terminal: the Glow Battery hit 0 and the grid collapsed — the maximum slam + a white wash so the
## loss reads as a hard, total beat.
func _on_grid_collapsed() -> void:
	add_trauma(TRAUMA_COLLAPSE)
	flash(FLASH_WHITE, FLASH_DUR_COLLAPSE)


## #11/#56: a gate fired. Positive ops (add/multiply) get a small celebratory kick; negative ops
## (subtract/divide) get a heavier jolt + a faint red wash so a loss of swarm volume is felt as well as
## seen. Positivity uses the same vocabulary as effect_layer (_is_positive_op).
func _on_gate_passed(gate_type: String, _value: float, _new_count: int) -> void:
	if _is_positive_op(gate_type):
		add_trauma(TRAUMA_GATE_POS)
	else:
		add_trauma(TRAUMA_GATE_NEG)
		flash(FLASH_RED_FAINT, FLASH_DUR_GATE_NEG)


# --- PURE helpers ------------------------------------------------------------

## Positive economy op? add / multiply grow the swarm (a celebratory kick); subtract / divide shrink it
## (a heavier jolt + faint red). Matches gate.gd / effect_layer's vocabulary
## ("add"/"subtract"/"multiply"/"divide"). PURE — the verify script may assert it.
func _is_positive_op(gate_type: String) -> bool:
	return gate_type == "add" or gate_type == "multiply"


# --- Tree/GPU construction (built in _ready only; never on a bare .new()) ------

## The shake camera. ANCHOR_MODE_FIXED_TOP_LEFT at position ZERO is an identity view — the world is
## unchanged until _process pushes camera.offset, and the HUD/grid CanvasLayers are immune to it. We
## make_current() so this is the active camera the moment the manager enters the run.
func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	cam.position = Vector2.ZERO
	add_child(cam)
	cam.make_current()
	_camera = cam


## The flash overlay: a CanvasLayer (above the world, below the HUD) holding one full-rect ColorRect.
## It ignores mouse so touches pass through to the world, and starts fully transparent (modulate a=0);
## flash() + _process drive its modulate alpha. Anchored full-rect so it covers the whole portrait frame
## at any device size.
func _build_flash_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = FLASH_LAYER
	add_child(layer)

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)              # white base; the per-flash colour rides modulate
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.modulate = Color(1, 1, 1, 0)           # start invisible
	layer.add_child(rect)
	_flash_rect = rect
