extends Node2D
## Score popup layer (#27) — the floating "+N" (and "+N x2" when combo'd) numbers that rise off a
## kill point and fade. Run instantiates ONE of these and add_child()s it LAST onto the world root,
## so the popups live in WORLD space: they sit exactly at the kill point and ride the camera shake
## with everything else (a CanvasLayer HUD would float free of the world and miss the impact).
##
## DESIGN / GOTCHA notes:
##   - These are deliberately LDR HUD-colour Labels (Press Start 2P via UI.text), kept crisp and OUT
##     of the bloom — a glowing score number reads mushy; the punch comes from the rise + fade + a
##     points-scaled size, not a halo. (Same discipline as the in-run HUD; see Palette `_HUD` tokens.)
##   - HEADLESS determinism: every which-text / which-colour / how-big / which-slot decision lives in
##     a PURE method (_format / _color_for / _scale_for / _next_index) callable on a bare .new() with
##     NO pool, NO tree, NO GPU. The Label pool is built in _ready only (DEFERRED under `-s`, so it
##     never fires in the verify run); _spawn is GUARDED so a pool-less instance no-ops, never crashes.
##
## Bus inputs (READ-ONLY — this layer only listens, never re-emits run state):
##   enemy_destroyed(at, points)  → the primary case: a "+N" (combo'd "+N x2") popup at the kill point,
##                                  coloured combo-orange when GameState.combo_multiplier>1 else white,
##                                  sized up for a fatter-points kill.
##   player_steered(x, _)         → track ship x so any gate-gain popup (secondary) can land on the
##                                  ship line; set_crossing_y(y) (mirrors effect_layer) feeds the line y.

# --- Popup kinds (the PURE vocabulary _color_for speaks in) -------------------
const KIND_COMBO := "combo"     # combo'd enemy kill — orange
const KIND_NORMAL := "normal"   # plain enemy kill — white
const KIND_GAIN := "gain"       # positive gate gain — green HUD tint

# Pool size: round-robined so a burst of back-to-back kills doesn't stomp live popups mid-rise.
const POOL_SIZE := 16
const LIFETIME := 0.9           # seconds a popup rises + fades before it's hidden
const RISE_SPEED := 220.0       # px/s upward drift
const FONT_SIZE := 40

# Points→scale clamp: a chip kill stays ~1.0, a fat kill swells toward ~1.8 so value reads at a glance.
const SCALE_MIN := 1.0
const SCALE_MAX := 1.8
const SCALE_PER_POINT := 1.0 / 250.0   # points needed to grow one full unit of scale

# Where a gate-gain popup visually happens: the ship line y. Run overrides via set_crossing_y(); the
# default keeps the layer sane standalone. Ship x is tracked off player_steered.
var _crossing_y: float = 1680.0
var _ship_x: float = 540.0

# One pooled popup's live state. Parallel arrays keyed by pool index (no per-popup object churn).
var _pool: Array[Label] = []
var _elapsed: Array[float] = []      # seconds since this slot was (re)spawned; >= LIFETIME → idle
var _base_scale: Array[float] = []   # the points-scaled size locked in at spawn
var _next: int = 0


func _ready() -> void:
	# Build the Label pool + self-connect to the bus. Under headless `-s` this is DEFERRED and may
	# never fire before a tool's _initialize — fine: the PURE methods don't need the pool, and _spawn
	# is guarded so a pool-less instance no-ops. We wire via the idempotent wire() so a verify script
	# can connect handlers explicitly too (mirrors GameState.wire_events / Haptics.wire).
	const UI := preload("res://assets/ui/ui_kit.gd")
	for i in POOL_SIZE:
		var l: Label = UI.text("", Fonts.arcade, FONT_SIZE, Palette.HUD_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		l.visible = false
		add_child(l)
		_pool.append(l)
		_elapsed.append(LIFETIME)   # start idle
		_base_scale.append(1.0)
	wire()


# --- Self-wire (idempotent; _ready calls it, a verify script may too) ---------

## Connect the bus handlers. Guarded with is_connected so a double-call (e.g. _ready then a test)
## doesn't stack connections. Mirrors GameState.wire_events / Haptics.wire so the headless loop can
## wire deterministically without depending on the deferred _ready.
func wire() -> void:
	if not Events.enemy_destroyed.is_connected(_on_enemy_destroyed):
		Events.enemy_destroyed.connect(_on_enemy_destroyed)
	if not Events.player_steered.is_connected(_on_player_steered):
		Events.player_steered.connect(_on_player_steered)


# --- Run-facing setters ------------------------------------------------------

## Run calls this with ship_pos.y so a gate-gain popup lands on the ship line (gate_passed carries no
## position). Pure state set; safe before _ready. Mirrors effect_layer.set_crossing_y.
func set_crossing_y(y: float) -> void:
	_crossing_y = y


# --- Bus handlers (thin: resolve PURE, then spawn) ---------------------------

func _on_player_steered(x: float, _x_norm: float) -> void:
	_ship_x = x


## #27 primary case: an enemy died. Show "+N" (or "+N x2" when combo'd) at the kill point, coloured
## by whether the combo multiplier is live, sized up for fatter points. Reads GameState.combo_multiplier
## (the autoload) for both the text suffix and the colour bucket.
func _on_enemy_destroyed(at: Vector2, points: int) -> void:
	var mult: float = GameState.combo_multiplier
	var kind: String = KIND_COMBO if mult > 1.0 else KIND_NORMAL
	_spawn(at, _format(points, mult), _color_for(kind), _scale_for(points))


## Secondary: a positive gate gain reads as a green "+N" on the ship line. gate_passed has no
## position, so x = tracked ship x, y = the crossing line. (Kills are the primary path; this just
## reuses the same machinery so a gain still gets a number.) Run may connect this; not auto-wired.
func _on_gate_gain(points: int) -> void:
	_spawn(Vector2(_ship_x, _crossing_y), _format(points, 1.0), _color_for(KIND_GAIN), 1.0)


# --- PURE decision logic (headless-safe; the verify script asserts on these) --

## The popup text. "+100" when there's no live combo (mult <= 1.0); "+100 x2" when combo'd, using the
## multiplier's INTEGER part as the "xN" tag (combo_multiplier is a float like 2.0/2.5 — we show the
## whole-number step the player feels). NO tree/GPU — pure string.
func _format(points: int, mult: float) -> String:
	var base := "+%d" % points
	if mult > 1.0:
		return "%s x%d" % [base, int(mult)]
	return base


## Round-robin the pool: hand out the next slot index and advance (wrapping at POOL_SIZE) so back-to-
## back popups use fresh slots instead of restarting a live one. PURE — no tree. Returns -1 if the
## pool is empty (headless / no _ready), which _spawn treats as a no-op.
func _next_index() -> int:
	if POOL_SIZE <= 0:
		return -1
	var idx := _next
	_next = (_next + 1) % POOL_SIZE
	return idx


## Map a popup kind to an LDR HUD colour — kept crisp, out of the bloom. Combo kill reads combo-orange
## (matches the HUD combo readout), a plain kill reads white, a gate gain reads green (mint HUD tint,
## the +add family). DISTINCT per kind so combo vs normal vs gain tell apart at a glance.
func _color_for(kind: String) -> Color:
	match kind:
		KIND_COMBO:
			return Palette.COMBO_ORANGE_HUD
		KIND_GAIN:
			return Palette.MENU_MINT_HUD
		KIND_NORMAL, _:
			return Palette.HUD_WHITE


## Label scale for a kill's points: a chip kill stays ~SCALE_MIN, a fat kill swells toward SCALE_MAX so
## the number's heft reads instantly. Clamped both ends. PURE — no tree.
func _scale_for(points: int) -> float:
	return clampf(SCALE_MIN + float(points) * SCALE_PER_POINT, SCALE_MIN, SCALE_MAX)


# --- Per-frame rise + fade (guarded; no pool → no-op) ------------------------

## Advance every live popup: drift it upward, fade alpha over its life, hide it when expired. Guarded
## so a pool-less instance (headless / no _ready) does nothing. Only touches already-built Labels.
func _process(delta: float) -> void:
	if _pool.is_empty():
		return
	for i in _pool.size():
		if _elapsed[i] >= LIFETIME:
			continue
		_elapsed[i] += delta
		var l: Label = _pool[i]
		if l == null:
			continue
		if _elapsed[i] >= LIFETIME:
			l.visible = false
			continue
		l.position.y -= RISE_SPEED * delta
		# Fade out over the back half of life so it holds bright, then dissolves.
		var t: float = _elapsed[i] / LIFETIME
		var a: float = clampf(1.0 - t, 0.0, 1.0)
		var c: Color = l.modulate
		l.modulate = Color(c.r, c.g, c.b, a)


# --- Spawn (the ONLY tree-touching part; guarded) ----------------------------

## Light up the next pooled Label at `at` with `txt`/`color`/`scale` and reset its life so _process
## carries it up and fades it. Guarded: a -1 index (empty pool) or a null/missing slot no-ops, so a
## headless `.new()` instance survives this path untouched (no tree mutated).
func _spawn(at: Vector2, txt: String, color: Color, scale: float) -> void:
	var idx := _next_index()
	if idx < 0 or idx >= _pool.size():
		return
	var l: Label = _pool[idx]
	if l == null:
		return
	l.text = txt
	l.modulate = color
	l.scale = Vector2(scale, scale)
	# Centre the label on the spawn point (Press Start 2P labels grow from top-left otherwise).
	l.position = at - Vector2(l.size.x * scale * 0.5, l.size.y * scale * 0.5)
	l.visible = true
	_elapsed[idx] = 0.0
	_base_scale[idx] = scale
