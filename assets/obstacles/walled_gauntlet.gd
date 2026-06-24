class_name WalledGauntlet
extends Node2D
## The Walled Gauntlet (#86) — a center divider that scrolls down the lane and HARD-CLAMPS the ship
## into one half for ~7 seconds, forcing a lane commitment. One side is a weak Glitch swarm + a
## utility gate; the other is an armored Rhombus guarding a high-value loot gate. A POC obstacle for
## the combat-redesign playtest: a single gauntlet fires once per run at an authored distance.
##
## PACING (the 7-s trap): the level scrolls at LevelDef.scroll_speed_mps (8 m/s) projected at
## TrackView.PIXELS_PER_METER (66). A barrier 56 m long (8 × 7) is on the ship line for exactly 7 s.
## The barrier occupies track positions [start_m, start_m + LEN_M]; its FRONT edge (the smaller
## track_m) reaches the ship line first. The ship is trapped while distance ∈ [start_m, start_m+LEN_M].
##
## DECOUPLING: occupants spawn via Targets.spawn_add and the lane gates via GateSpawner.spawn_split
## (both injected by run.gd); the lane clamp + release go out on Events.lane_clamp_changed (Player
## binds it). Ship x arrives via Events.player_steered. The crossing/commit MATH is pure (_step,
## lane_bounds_for) so the headless verify drives it with no GPU.

const TRACK := preload("res://assets/levels/track.gd")

## Trap length in metres == scroll_speed (8) × 7 s. On-screen height = LEN_M × PIXELS_PER_METER.
const LEN_M := 56.0
## Divider geometry. Half-width of the glowing bar + the lane gap that keeps the ship clear of it.
const BARRIER_HALF := 44.0
const LANE_GAP := 80.0                 # ship stays this far off the divider centre
const CENTER_X := 540.0                # lane split (half of 1080)
const TEX := 32                        # soft-bar texture resolution

## Gauntlet lifecycle.
enum { PENDING, TRAPPING, DONE }
var _state: int = PENDING

var _targets: Node2D = null            # injected: Targets.spawn_add for lane occupants
var _gates: Node2D = null              # injected: GateSpawner.spawn_split for the lane gates
var _ship_line_y: float = 1680.0
var _ship_x: float = CENTER_X
var _design := Vector2(1080, 1920)
var _start_m: float = 80.0             # track metre where the gauntlet's FRONT edge hits the line
var _committed_lane: int = -1          # -1 none, 0 LEFT, 1 RIGHT (debug/verify)
var _mmi: MultiMeshInstance2D


func _ready() -> void:
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_build_multimesh()
	Events.player_steered.connect(func(x: float, _n: float) -> void: _ship_x = x)


func _process(_delta: float) -> void:
	if GameState.run_active:
		_step(GameState.distance, _ship_x)
	_render()


# --- Injection (run.gd wires these before adding us) -------------------------

func set_targets(targets: Node2D) -> void:
	_targets = targets


func set_gates(gates: Node2D) -> void:
	_gates = gates


func set_ship_line(y: float) -> void:
	_ship_line_y = y


## Where (track metre) the gauntlet's FRONT edge reaches the ship line. run.gd authors this; the
## occupants + lane gates are placed relative to it when the trap engages.
func set_start_m(m: float) -> void:
	_start_m = m


# --- Pure-ish step (crossing + commit + release) -----------------------------

## Advance the gauntlet against the run's distance + ship x. PENDING → TRAPPING the frame the front
## edge reaches the ship line (latch the committed lane, clamp the ship, spawn occupants + gates);
## TRAPPING → DONE once the back edge passes the line (release the ship to the full width). The lane
## clamp/release go out on Events.lane_clamp_changed; Player honours them.
func _step(distance: float, ship_x: float) -> void:
	match _state:
		PENDING:
			if distance >= _start_m:
				_state = TRAPPING
				_committed_lane = 0 if ship_x < CENTER_X else 1
				var b: Vector2 = lane_bounds_for(_committed_lane)
				Events.lane_clamp_changed.emit(b.x, b.y)
				_populate_lanes()
		TRAPPING:
			if distance > _start_m + LEN_M:
				_state = DONE
				_committed_lane = -1
				# Release: full design width — Player intersects with its own edge band, so this
				# restores the normal steerable range.
				Events.lane_clamp_changed.emit(0.0, _design.x)
		DONE:
			pass


## Steerable [min_x, max_x] for a committed lane (0 LEFT / 1 RIGHT): the half of the playfield on
## that side of the divider, held LANE_GAP + BARRIER_HALF clear of the centre. Pure — verify asserts it.
func lane_bounds_for(lane: int) -> Vector2:
	var inner: float = CENTER_X - (BARRIER_HALF + LANE_GAP)
	var outer: float = CENTER_X + (BARRIER_HALF + LANE_GAP)
	if lane == 0:
		return Vector2(0.0, inner)            # LEFT lane (Player re-clamps to its edge margin)
	return Vector2(outer, _design.x)          # RIGHT lane


## Spawn the lane occupants + gates when the trap engages (#86, hardcoded for the POC): LEFT = a weak
## Glitch swarm + a utility (+) gate; RIGHT = an armored Rhombus guarding a high-value (×) loot gate.
func _populate_lanes() -> void:
	if _targets != null and _targets.has_method("spawn_add"):
		# Left lane: a few Glitches (weak swarm).
		for i in 4:
			_targets.call("spawn_add", {"kind": "glitch", "x": 280.0})
		# Right lane: one armored Rhombus (only a LANCE cracks it) guarding the loot.
		_targets.call("spawn_add", {"kind": "rhombus", "x": 800.0})
	if _gates != null and _gates.has_method("spawn_split"):
		# A Split Choice crossing mid-trap (~half the window in): LEFT utility +12 volume, RIGHT a
		# ×2 loot multiplier (the high-value pick the Rhombus guards). update() fires only the lane
		# the clamped ship is in.
		_gates.call("spawn_split", _start_m + LEN_M * 0.5, "add", 12.0, "mul", 2.0)


# --- Readability (verify / run.gd) -------------------------------------------

func is_trapping() -> bool:
	return _state == TRAPPING


func committed_lane() -> int:
	return _committed_lane


## On-screen barrier height (px) — should be exactly LEN_M × PIXELS_PER_METER (the 7-s span).
func barrier_height_px() -> float:
	return LEN_M * TRACK.PIXELS_PER_METER


# --- Rendering (additive-HDR bar — the bloom path) ---------------------------

func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(BARRIER_HALF * 2.0, 1.0)   # unit-height; scaled to the live span each frame
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance2D.new()
	_mmi.name = "GauntletBar"
	_mmi.multimesh = mm
	_mmi.texture = _make_bar_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mmi.material = mat
	add_child(_mmi)


func _render() -> void:
	if _mmi == null:
		return
	var mm := _mmi.multimesh
	# Only visible while the bar is anywhere on/approaching the screen (PENDING after start, or DONE,
	# hides it). Show during TRAPPING and for the lead-in once distance is within ~one screen.
	var dist: float = GameState.distance
	var front_y: float = TRACK.screen_y(_start_m, dist, _ship_line_y)
	var back_y: float = TRACK.screen_y(_start_m + LEN_M, dist, _ship_line_y)
	var on_screen: bool = _state != DONE and front_y > -100.0 and back_y < _design.y + 100.0
	if not on_screen:
		mm.visible_instance_count = 0
		return
	mm.visible_instance_count = 1
	var height: float = front_y - back_y               # == LEN_M × PPM
	var mid_y: float = (front_y + back_y) * 0.5
	# Scale the unit-height quad to the live span; place it on the lane centre. Node is at origin,
	# so the instance carries the absolute placement.
	var xf := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, height), Vector2(CENTER_X, mid_y))
	mm.set_instance_transform_2d(0, xf)
	mm.set_instance_color(0, Palette.GRID_BLUE)        # HDR blue — reads white-hot through the bloom


## Soft-edged vertical bar mask: bright down the centre column, falling off to the left/right edges so
## the divider blooms as a neon wall. Shape is alpha; colour is the HDR instance tint above.
func _make_bar_texture() -> ImageTexture:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var c := (TEX - 1) * 0.5
	for y in TEX:
		for x in TEX:
			var dx: float = absf(x - c) / c           # 0 at centre column, 1 at the edges
			var a: float = clampf(1.0 - dx, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
