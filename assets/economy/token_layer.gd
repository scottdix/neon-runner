extends Node2D
## TokenLayer (#78) — the in-run token economy's world layer. A world-space SIBLING of the
## ship (Run adds it after Targets). It owns the drifting collectable tokens a kill drops and
## the ship-touch pickup that banks them into the in-run wallet.
##
## Flow (fully Events-bus decoupled — it never holds a ref to Targets / the ship / GameState
## beyond the autoload globals):
##   • Targets._kill emits Events.token_dropped(at, value) -> we spawn a drifting token at `at`.
##   • Each token DRIFTS straight down (pure step: y increases at DRIFT_SPEED) — gravity-of-the-
##     conveyor, no homing. Magnetism is a WIDENED flat pickup radius (magnet_radius()), NOT an
##     attractive pull, so the pickup test stays a simple distance check (headless-verifiable).
##   • The live ship x is tracked off Events.player_steered (the muzzle/ship line y is fixed at
##     ship_pos.y, fed via set_ship_line). A token within magnet_rad() of the ship point is
##     ABSORBED -> GameState.collect_token(value) + Events.token_collected(at, value, wallet).
##   • A token that drifts past the bottom of the screen despawns uncollected (pooled back).
##
## Pooled: free tokens are kept in `_pool` and re-used so a long run with thousands of drops
## doesn't churn allocations (the projectile-swarm-as-followers discipline, CLAUDE.md). The
## tokens are plain Dictionaries (pos / value / alive) stepped each frame — GPU-free, so the
## drift + absorb logic runs headless. Rendering is a cheap _draw of additive orbs.

## Base pickup radius (design units). The drafted MAGNETISM perk multiplies this via
## SpliceLab.magnet_radius_mult() — a WIDER catch, not a pull. Generous so a near-miss drift
## still banks on a thumb-steered ship.
const BASE_PICKUP_RADIUS := 90.0

## Downward drift speed (design units / second). Slow enough to read as a floating pickup the
## ship can sweep into, fast enough that an uncollected token clears the screen.
const DRIFT_SPEED := 220.0

## Despawn once a token's y passes this far below the ship line (off the bottom of the play area).
const DESPAWN_BELOW := 260.0

## Visual: a small gold orb per token. Additive so overlaps read hot (the neon path — a textured/
## MultiMesh upgrade is a device-only polish; the _draw orb keeps the logic self-contained here).
const TOKEN_RADIUS := 12.0

## Live tokens — each {pos: Vector2, value: int, alive: bool}.
var _tokens: Array = []
## Free-list of recycled token Dictionaries (pooled to avoid per-drop allocation).
var _pool: Array = []

## The ship line y (the muzzle/breach line). Set by Run via set_ship_line; absorb tests the
## ship POINT (ship_x, ship_line_y). Defaults to a sane bottom-of-design value for bare tests.
var _ship_line_y: float = 1680.0
## Live ship x, mirrored off Events.player_steered (the same trick the Fleet/Effects use).
var _ship_x: float = 540.0


func _ready() -> void:
	z_index = 5   # over the grid + gates, under the HUD CanvasLayer
	wire_events()


## Connect to the bus. Public + idempotent so the headless `-s` verify can wire it explicitly
## (autoload/added-node _ready is deferred past _initialize — CLAUDE.md gotcha).
func wire_events() -> void:
	if not Events.token_dropped.is_connected(_on_token_dropped):
		Events.token_dropped.connect(_on_token_dropped)
	if not Events.player_steered.is_connected(_on_player_steered):
		Events.player_steered.connect(_on_player_steered)


## Run injects the ship-line y (the fixed muzzle/breach line) so absorb tests the real ship point.
func set_ship_line(y: float) -> void:
	_ship_line_y = y


## A kill dropped a token (#78). Spawn a drifting collectable at `at` carrying `value`.
func _on_token_dropped(at: Vector2, value: int) -> void:
	if value <= 0:
		return
	var t: Dictionary = _pool.pop_back() if not _pool.is_empty() else {}
	t["pos"] = at
	t["value"] = value
	t["alive"] = true
	_tokens.append(t)


## Mirror the live ship x (the muzzle rides under the ship; tokens are caught at the ship point).
func _on_player_steered(x: float, _x_normalized: float) -> void:
	_ship_x = x


## The live pickup radius: the base flat catch widened by the drafted token-magnet multiplier.
## Magnetism = a BIGGER radius (not an attractive pull), so this is the single knob the absorb
## test reads. Null-safe — a bare unit-test layer with no SpliceLab autoload gets the base radius.
func magnet_radius() -> float:
	return BASE_PICKUP_RADIUS * _magnet_mult()


## Null-safe drafted token-magnet multiplier. Reads SpliceLab.magnet_radius_mult() when the
## autoload tree is present; 1.0 for pure-logic unit tests that new() a bare TokenLayer.
func _magnet_mult() -> float:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var lab: Node = (loop as SceneTree).root.get_node_or_null("SpliceLab")
		if lab != null and lab.has_method("magnet_radius_mult"):
			return float(lab.call("magnet_radius_mult"))
	return 1.0


func _process(delta: float) -> void:
	step(delta)
	queue_redraw()


## Pure per-frame update (GPU-free, headless-verifiable): drift every token down, absorb any
## within the live magnet radius of the ship point (-> collect + emit), despawn those that fall
## off the bottom uncollected. Tokens are absorbed ONLY inside the radius — none auto-collect.
func step(delta: float) -> void:
	if _tokens.is_empty():
		return
	var radius: float = magnet_radius()
	var r2: float = radius * radius
	var ship := Vector2(_ship_x, _ship_line_y)
	var i: int = _tokens.size() - 1
	while i >= 0:
		var t: Dictionary = _tokens[i]
		var pos: Vector2 = t["pos"]
		pos.y += DRIFT_SPEED * delta
		t["pos"] = pos
		if pos.distance_squared_to(ship) <= r2:
			_absorb(t)
			_recycle(i)
		elif pos.y > _ship_line_y + DESPAWN_BELOW:
			# Fell past the ship line uncollected — despawn (pooled, NOT collected).
			t["alive"] = false
			_recycle(i)
		i -= 1


## Bank a touched token: add to the in-run wallet (GameState owns run-state) and announce the
## pickup with the new running total for the chime/vfx. Null-safe for the bare-instance test.
func _absorb(t: Dictionary) -> void:
	var value: int = int(t["value"])
	var at: Vector2 = t["pos"]
	var wallet: int = value
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var gs: Node = (loop as SceneTree).root.get_node_or_null("GameState")
		if gs != null and gs.has_method("collect_token"):
			gs.call("collect_token", value)
			wallet = int(gs.get("run_tokens"))
	Events.token_collected.emit(at, value, wallet)


## Move the token at `idx` back to the free-list (swap-remove keeps the loop O(1)).
func _recycle(idx: int) -> void:
	var t: Dictionary = _tokens[idx]
	_tokens.remove_at(idx)
	_pool.append(t)


## Live (uncollected) token count — for the verify + any HUD debug.
func live_count() -> int:
	return _tokens.size()


## Additive gold orbs (the neon pickup read). draw_* never glows under the 2D bloom (memory note),
## but the additive blend makes overlaps read hot; the device polish is a textured/MultiMesh swap.
func _draw() -> void:
	for t in _tokens:
		var p: Vector2 = t["pos"]
		draw_circle(p, TOKEN_RADIUS, Color(1.0, 0.88, 0.30, 0.85))
		draw_circle(p, TOKEN_RADIUS * 0.5, Color(1.4, 1.3, 0.8, 1.0))
