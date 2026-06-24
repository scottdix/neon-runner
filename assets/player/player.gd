class_name Player
extends Node2D
## The player ship — analog slide-steer (D1, GAME_SCOPE, LOCKED).
##
## Continuous touch-drag maps to ship-x, smoothed + clamped to the steerable
## width. NOT discrete lanes. Steering aims both the ship and the bullet stream
## (the Fleet reads `position.x`). Always-on fire means steering is the ONLY
## player input; there is no fire button.
##
## Input: touch/screen-drag (mobile) or mouse (desktop, via emulate_touch) sets
## the target x; keyboard left/right also nudge it for desktop testing (#10).
## The steering MATH is in `step()` so it can be driven headless with no GPU.

## Half-width kept clear of each screen edge so the ship never clips off-screen.
@export var edge_margin: float = 80.0
## Higher = snappier follow. Frame-rate-independent (see `step`).
@export var steer_responsiveness: float = 12.0
## Keyboard nudge speed (px/sec) for desktop testing.
@export var key_steer_speed: float = 1400.0

var _design_width: float = 1080.0
var _target_x: float = 540.0
var _min_x: float = 80.0
var _max_x: float = 1000.0

# --- Combat-redesign POC input (#86/#87) -------------------------------------
## Horizontal ship velocity (px/s), measured in step() from the per-frame position delta. The
## KINETIC_CLUTCH POC (#87) reads it via velocity_x(): moving => SPRAY, braked/still => LANCE. The
## ship is position/lerp-driven (no native velocity), so we derive it; pure so headless tests assert it.
var _velocity_x: float = 0.0
## Walled Gauntlet (#86) lane clamp: an EXTRA steer-bound override that, while active, traps the ship
## in one lane. Defaults to the full steerable width (no clamp); the gauntlet narrows it via
## Events.lane_clamp_changed and restores the full width to release. set_target_x intersects it.
var _lane_min: float = -1.0e9
var _lane_max: float = 1.0e9
## Triple-tap detector (#87) for GEOM_OVERDRIVE's LANCE activation (replaces swipe-up, which would
## fight drag-steer). Timestamps (ms) of recent taps; 3 within TRIPLE_TAP_WINDOW_MS fires the toggle.
const TRIPLE_TAP_WINDOW_MS := 450
const TRIPLE_TAP_COUNT := 3
var _tap_times: Array[int] = []

## The ship's MultiMesh instance, kept so the loadout hull colour can be re-applied live.
var _ship_mesh: MultiMeshInstance2D

# --- Cosmetics: trail (#18) + engine (#67) -----------------------------------
# Both are delivered through the SAME textured-additive-HDR MultiMesh path the ship
# and the orb fleet use — the ONLY path Godot's 2D bloom catches. Issue #18 literally
# says "Line2D", but a Line2D (like any draw_* polyline) NEVER blooms (confirmed on
# device twice — memory glow-immediate-draw-no-bloom), so the neon trail is instead a
# MultiMesh ribbon of soft-orb quads. The trail rides a short ring-buffer of recent ship
# positions; the engine is a tiny additive plume at the tail. All the per-instance
# layout MATH is in pure methods (_push_trail_point / _trail_layout / _engine_params) so
# headless tests drive it with no GPU; the MultiMesh nodes only consume that math.

## Trail option indices (mirror Loadout.TRAILS = ["SLEEK","HELIX","RIBBON"]).
const TRAIL_SLEEK := 0
const TRAIL_HELIX := 1
const TRAIL_RIBBON := 2
## Engine option indices (mirror Loadout.ENGINES = ["STD","PULSAR","WARP"]).
const ENGINE_STD := 0
const ENGINE_PULSAR := 1
const ENGINE_WARP := 2

## How many recent ship samples the trail remembers (oldest = faintest tail).
const TRAIL_BUFFER := 18
## Soft-orb quad footprint for one trail dot (re-textured from the orb mask idea).
const TRAIL_QUAD := 30.0
const TRAIL_TEX_SIZE := 32
## How far behind the ship's MESH centre the trail/engine begin (local +y, "behind").
const TRAIL_BEHIND := 30.0
## HELIX lateral swing (px) of the two strands; RIBBON broadens this band instead.
const HELIX_SWING := 26.0
const RIBBON_SWING := 14.0
## HELIX winds this many radians across the whole tail.
const HELIX_WINDS := 6.0

## Ring buffer of recent ship world-positions; head = newest. A plain Array used as a
## bounded queue (append newest, pop oldest once full) — see `_push_trail_point`.
var _trail_pts: Array[Vector2] = []
## The trail ribbon MultiMesh (built in _ready, fed from `_trail_layout`).
var _trail_mesh: MultiMeshInstance2D
## The engine-plume MultiMesh (built in _ready, fed from `_engine_params`).
var _engine_mesh: MultiMeshInstance2D
## Free-running clock for time-varying engine modes (PULSAR pulse, WARP shimmer).
var _engine_clock: float = 0.0


func _ready() -> void:
	_design_width = float(ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1080))
	_min_x = edge_margin
	_max_x = _design_width - edge_margin
	# #86: start unclamped (full steerable width); the Walled Gauntlet narrows this to one lane.
	_lane_min = _min_x
	_lane_max = _max_x
	if position.x <= 0.0:
		position.x = _design_width * 0.5
	_target_x = position.x
	# Trail and engine sit BEHIND the ship mesh — added first so they draw under it.
	_build_trail_visual()
	_build_engine_visual()
	_build_ship_visual()
	# Recolour/retune live when the player changes hull/trail/engine in the Garage
	# (CLAUDE.md: bus, no refs).
	Events.loadout_changed.connect(_on_loadout_changed)
	# #86: the Walled Gauntlet clamps/releases the steerable range via the bus (no direct ref).
	Events.lane_clamp_changed.connect(_on_lane_clamp_changed)


# --- Ship visual -------------------------------------------------------------
# The ship is drawn via a textured MultiMesh instance with an additive material
# and an HDR instance color — the SAME path the orb fleet uses, which is the only
# one Godot's 2D bloom actually picks up. Immediate-mode draw_colored_polygon
# (the previous approach) never blooms regardless of how bright the color is
# (confirmed on device twice — see memory glow-immediate-draw-no-bloom).
#
# CANONICAL HULL SILHOUETTE (#72). The in-run ship and the Garage build-screen
# preview MUST be the same vessel ("what I fly == what I built"). They previously
# diverged: the run drew a fuzzy soft-triangle while the Garage drew a swept
# arrowhead with a cockpit chevron, so only the hull COLOUR carried over. The fix:
# both now render from ONE silhouette — the arrowhead below, baked into the ship
# texture and shared via `build_ship_preview()`, which the Garage calls. The point
# table mirrors ui_kit.ship_mark's hull (a 48-unit box, apex up, swept tail) so the
# textured run-ship reads as the same shape the menu draws.

const SHIP_TEX_SIZE := 64
const SHIP_QUAD := 168.0   # on-screen ship footprint — the design wants a prominent hero ship

## The canonical hull outline in a 48×48 design box (apex up the screen, swept-back
## tail), shared by the in-run ship texture and the Garage preview so they match. The
## cockpit chevron sits inside it. Kept here (player.gd owns the ship) as the single
## source of truth for the silhouette both screens render.
const HULL_BOX := 48.0
const HULL_PTS: Array[Vector2] = [
	Vector2(24, 3), Vector2(43, 41), Vector2(24, 31), Vector2(5, 41),
]
const COCKPIT_PTS: Array[Vector2] = [
	Vector2(24, 7), Vector2(30, 26), Vector2(24, 21), Vector2(18, 26),
]


func _build_ship_visual() -> void:
	var mmi := build_ship_preview(Loadout.hull_color_hdr())
	mmi.name = "ShipMesh"
	add_child(mmi)
	_ship_mesh = mmi


## Build ONE neon ship node (textured-additive-HDR MultiMesh) on the canonical
## silhouette, tinted by `hdr_color`. This is the SHARED render path (#72): the run
## calls it for the live ship and the Garage calls it for the build-screen preview, so
## the two are pixel-identical. Static + GPU-light (it allocates an ImageTexture) — it
## must NOT touch `self`, so the Garage can use it without a Player in the tree.
static func build_ship_preview(hdr_color: Color) -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = Vector2(SHIP_QUAD, SHIP_QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.set_instance_transform_2d(0, Transform2D())
	# Luminance-rich HDR hull colour; additive + soft mask makes the core read white-hot.
	mm.set_instance_color(0, hdr_color)
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.texture = _make_ship_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mmi.material = mat
	return mmi


## Re-tint an existing ship-preview node (from `build_ship_preview`) to a new HDR
## colour. Shared by the run's live recolour and the Garage's `loadout_changed`.
static func tint_ship_preview(mmi: MultiMeshInstance2D, hdr_color: Color) -> void:
	if mmi != null and mmi.multimesh != null:
		mmi.multimesh.set_instance_color(0, hdr_color)


## Re-apply the loadout cosmetics live when the Garage changes them. Hull recolour
## (the original contract) PLUS the trail tint and engine plume retune — every axis the
## Loadout exposes is now reflected in-run without a reference (Events bus only).
func _on_loadout_changed() -> void:
	# Re-tint via the SAME shared helper the Garage uses (#72), so run + preview agree.
	tint_ship_preview(_ship_mesh, Loadout.hull_color_hdr())
	# Trail strand count keys off the style, so resize its instance budget on a switch.
	if _trail_mesh != null and _trail_mesh.multimesh != null:
		_trail_mesh.multimesh.instance_count = _trail_capacity()
		_trail_mesh.multimesh.visible_instance_count = 0
	# Engine plume tint follows the hull glow; size/length come from _engine_params each
	# frame, so nothing else to rebuild here.
	if _engine_mesh != null and _engine_mesh.multimesh != null:
		_engine_mesh.multimesh.set_instance_color(0, Loadout.hull_color_hdr())


## Bake the canonical hull silhouette (HULL_PTS + COCKPIT_PTS, the SAME shape the Garage
## draws) into a soft alpha mask. Shape comes from alpha; the glow colour comes from the
## HDR instance colour. Static so `build_ship_preview` can call it without a Player.
## The 48-unit hull box is scaled to fill SHIP_TEX_SIZE with a small margin so the soft
## edge + faint halo have room.
static func _make_ship_texture() -> ImageTexture:
	var img := Image.create(SHIP_TEX_SIZE, SHIP_TEX_SIZE, false, Image.FORMAT_RGBA8)
	# Map the 48-unit design box onto the texture, leaving a margin for the soft halo.
	var margin := 6.0
	var scale: float = (SHIP_TEX_SIZE - 2.0 * margin) / HULL_BOX
	var hull: Array[Vector2] = _scaled_poly(HULL_PTS, scale, margin)
	var cockpit: Array[Vector2] = _scaled_poly(COCKPIT_PTS, scale, margin)
	for y in SHIP_TEX_SIZE:
		for x in SHIP_TEX_SIZE:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			# Signed distance to the hull (positive inside); the cockpit reads as a
			# brighter core, so take the brighter of the two contributions.
			var hd: float = _signed_dist_to_poly(p, hull)
			var cd: float = _signed_dist_to_poly(p, cockpit)
			var a_hull: float = clampf((hd + 1.5) / 3.0, 0.0, 1.0)   # soft edge + halo
			var a_cock: float = clampf((cd + 1.0) / 2.0, 0.0, 1.0)
			var a: float = maxf(a_hull * a_hull, a_cock)              # cockpit core hotter
			img.set_pixel(x, y, Color(1, 1, 1, a))
	# The silhouette is authored apex-up (small y), but a QuadMesh rendered through
	# MultiMeshInstance2D maps image rows bottom-to-top — so an apex baked at the top renders
	# pointing DOWN on screen (the radially-symmetric orb/trail textures never exposed this).
	# Flip vertically so the nose points UP the screen, toward the direction of fire/travel.
	img.flip_y()
	return ImageTexture.create_from_image(img)


## Scale a 48-box polygon into texture space (apex up = small y), offset by `margin`.
static func _scaled_poly(pts: Array[Vector2], scale: float, margin: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v in pts:
		out.append(v * scale + Vector2(margin, margin))
	return out


## Signed distance from point `p` to a closed polygon: +inside, -outside, magnitude in
## pixels. Used to soft-mask the hull/cockpit so the silhouette blooms cleanly. Pure
## math (the classic edge-projection winding test) — GPU-free, headless-safe.
static func _signed_dist_to_poly(p: Vector2, poly: Array[Vector2]) -> float:
	var n: int = poly.size()
	var d: float = INF
	var inside := false
	var j: int = n - 1
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		var e: Vector2 = b - a
		var w: Vector2 = p - a
		var t: float = clampf(w.dot(e) / maxf(e.length_squared(), 0.0001), 0.0, 1.0)
		d = minf(d, (w - e * t).length())
		# Ray-cast winding test for inside/outside.
		if (a.y > p.y) != (b.y > p.y):
			var x_cross: float = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if p.x < x_cross:
				inside = not inside
		j = i
	return d if inside else -d


# --- Trail + engine rendering (skipped under headless; math above is the truth) ---
# Both build a soft-orb-textured MultiMesh with an additive material + HDR colour, the
# only path the bloom catches. They consume _trail_layout() / _engine_params() so the
# headless-tested math and the on-screen pixels can never disagree.

func _build_trail_visual() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(TRAIL_QUAD, TRAIL_QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = TRAIL_BUFFER * 2          # max budget (HELIX uses both strands)
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.name = "TrailMesh"
	mmi.multimesh = mm
	mmi.texture = _make_trail_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mmi.material = mat
	add_child(mmi)
	_trail_mesh = mmi


func _render_trail() -> void:
	if _trail_mesh == null or _trail_mesh.multimesh == null:
		return
	var mm := _trail_mesh.multimesh
	var dots: Array = _trail_layout()
	var n: int = mini(dots.size(), mm.instance_count)
	mm.visible_instance_count = n
	# Trail tint = the hull glow, so trail and ship read as one neon vessel.
	var tint: Color = Loadout.hull_color_hdr()
	for i in n:
		var d: Dictionary = dots[i]
		var s: float = float(d["scale"])
		# Trail dots live in this node's local space; subtract our origin. Push the dot
		# BEHIND the ship mesh (local +y) so the trail streams out the tail.
		var local: Vector2 = (Vector2(d["pos"]) - position) + Vector2(0.0, TRAIL_BEHIND)
		mm.set_instance_transform_2d(i, Transform2D(Vector2(s, 0), Vector2(0, s), local))
		mm.set_instance_color(i, tint * float(d["alpha"]))


func _make_trail_texture() -> ImageTexture:
	# Soft radial alpha mask (same idea as the orb mask) — shape is alpha, colour is the
	# HDR instance tint above, so it blooms.
	var img := Image.create(TRAIL_TEX_SIZE, TRAIL_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (TRAIL_TEX_SIZE - 1) * 0.5
	for y in TRAIL_TEX_SIZE:
		for x in TRAIL_TEX_SIZE:
			var dd := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - dd, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _build_engine_visual() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(TRAIL_QUAD, TRAIL_QUAD)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.visible_instance_count = 1
	mm.set_instance_color(0, Loadout.hull_color_hdr())
	var mmi := MultiMeshInstance2D.new()
	mmi.name = "EngineMesh"
	mmi.multimesh = mm
	mmi.texture = _make_trail_texture()           # reuse the soft radial mask
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mmi.material = mat
	add_child(mmi)
	_engine_mesh = mmi


func _render_engine() -> void:
	if _engine_mesh == null or _engine_mesh.multimesh == null:
		return
	var p: Dictionary = _engine_params(Loadout.engine_index, _engine_clock)
	var mm := _engine_mesh.multimesh
	# A single stretched quad at the tail, scaled length (local +y) × width (local +x).
	var sx: float = float(p["width"])
	var sy: float = float(p["length"])
	# Anchor so the plume's near edge sits at the tail and it streaks backward (+y).
	var local := Vector2(0.0, TRAIL_BEHIND + sy * TRAIL_QUAD * 0.5)
	mm.set_instance_transform_2d(0, Transform2D(Vector2(sx, 0), Vector2(0, sy), local))
	mm.set_instance_color(0, Loadout.hull_color_hdr() * float(p["alpha"]))


func _unhandled_input(event: InputEvent) -> void:
	# Touch drag / press, and (via emulate_touch_from_mouse) desktop mouse.
	if event is InputEventScreenDrag:
		set_target_x(event.position.x)
	elif event is InputEventScreenTouch and event.pressed:
		set_target_x(event.position.x)
		# #87 GEOM_OVERDRIVE: a TRIPLE-TAP toggles the LANCE overdrive. The tap still steers (sets
		# target_x to the tap x — expected; you tap where you are), so steering is unaffected.
		if register_tap(Time.get_ticks_msec()):
			Events.overdrive_toggle_requested.emit()


func _process(delta: float) -> void:
	# Keyboard steer for desktop testing — additive to whatever touch set.
	var key_axis := Input.get_axis("ui_left", "ui_right")
	if key_axis != 0.0:
		set_target_x(_target_x + key_axis * key_steer_speed * delta)
	step(delta)
	_engine_clock += delta
	_render_trail()
	_render_engine()


## Advance the steer one frame. Pure + GPU-free so headless tests can call it
## directly. Lerp is exponential-smoothed so it's identical at any frame rate.
## Also samples the post-move position into the trail ring-buffer (pure), so the
## trail follows even when driven headless.
func step(delta: float) -> void:
	var prev_x: float = position.x
	var t: float = 1.0 - pow(0.0001, delta * (steer_responsiveness / 12.0))
	position.x = lerpf(position.x, clampf(_target_x, _min_x, _max_x), t)
	# #87 KINETIC_CLUTCH: derive horizontal velocity from the frame's position delta (the ship has no
	# native velocity — it's lerp-driven). guard delta so a 0-dt frame can't divide-by-zero.
	_velocity_x = (position.x - prev_x) / maxf(delta, 1.0e-5)
	var span: float = maxf(1.0, _max_x - _min_x)
	var x_norm: float = clampf((position.x - _min_x) / span, 0.0, 1.0)
	_push_trail_point(position)
	Events.player_steered.emit(position.x, x_norm)


# --- Trail cosmetics (#18) — PURE math, no GPU --------------------------------

## Push the newest ship position onto the trail ring-buffer (head). Once the buffer is
## full it drops the OLDEST sample, so it behaves as a fixed-length recent-path queue.
## Pure + GPU-free: headless tests call this and assert the buffer fills then caps.
func _push_trail_point(p: Vector2) -> void:
	_trail_pts.push_front(p)
	while _trail_pts.size() > TRAIL_BUFFER:
		_trail_pts.pop_back()


## How many MultiMesh instances the current trail style needs. HELIX renders TWO strands
## (offset on a sine), so it doubles the instance budget; SLEEK/RIBBON are one strand.
func _trail_capacity() -> int:
	if Loadout.trail_index == TRAIL_HELIX:
		return TRAIL_BUFFER * 2
	return TRAIL_BUFFER


## Lay the ring-buffer out into render dots: a list of {pos, scale, alpha}. The newest
## sample (head) is brightest/biggest; older samples fade and shrink monotonically toward
## the tail. The pattern varies by Loadout.trail_index:
##   SLEEK  = one tight strand centred on the path.
##   HELIX  = two strands swung left/right on a sine wave (a lateral offset SLEEK lacks).
##   RIBBON = one strand swung in a wider, slower band with bigger dots (fewer, fatter).
## Pure + GPU-free; this is the single source of truth the renderer consumes AND the
## headless test asserts on (count, monotonic fade, per-style offset).
func _trail_layout() -> Array:
	var out: Array = []
	var n: int = _trail_pts.size()
	if n == 0:
		return out
	var style: int = Loadout.trail_index
	for i in n:
		# age 0 at the head (newest), -> 1 at the oldest tail sample.
		var age: float = float(i) / float(maxi(1, TRAIL_BUFFER - 1))
		var fade: float = clampf(1.0 - age, 0.0, 1.0)
		var base: Vector2 = _trail_pts[i]
		match style:
			TRAIL_HELIX:
				# Two counter-phase strands winding down the tail; lateral swing decays
				# with fade so the braid tucks into the ship.
				var ph: float = age * HELIX_WINDS
				var off: float = sin(ph) * HELIX_SWING * fade
				out.append({
					"pos": base + Vector2(off, 0.0),
					"scale": 0.5 + fade * 0.7,
					"alpha": fade * fade,
				})
				out.append({
					"pos": base + Vector2(-off, 0.0),
					"scale": 0.5 + fade * 0.7,
					"alpha": fade * fade,
				})
			TRAIL_RIBBON:
				# A wider, slower band of fatter dots (a fatter trail, fewer winds).
				var roff: float = sin(age * 2.0) * RIBBON_SWING * fade
				out.append({
					"pos": base + Vector2(roff, 0.0),
					"scale": 1.2 + fade * 1.1,
					"alpha": fade * fade * 0.9,
				})
			_:
				# SLEEK: one tight strand dead-centre on the recorded path.
				out.append({
					"pos": base,
					"scale": 0.7 + fade * 0.8,
					"alpha": fade * fade,
				})
	return out


# --- Engine cosmetics (#67) — PURE math, no GPU -------------------------------

## Engine plume parameters for the current engine + clock: {length, width, alpha}, in
## local units measured BEHIND the ship tail. Pure + GPU-free so headless tests assert it.
##   STD    = a modest steady plume (constant).
##   PULSAR = the plume size oscillates over `time` (a visible pulse).
##   WARP   = an elongated streak (long, thin) with a faint time shimmer.
## `time` is passed explicitly (not read from _engine_clock) so the test is deterministic.
func _engine_params(engine_index: int, time: float) -> Dictionary:
	match engine_index:
		ENGINE_PULSAR:
			# Oscillate length+width together so the plume visibly pulses.
			var pulse: float = 0.5 + 0.5 * sin(time * 9.0)
			return {
				"length": 1.0 + pulse * 1.0,
				"width": 0.8 + pulse * 0.5,
				"alpha": 0.7 + pulse * 0.3,
			}
		ENGINE_WARP:
			# Long thin streak; small shimmer keeps it alive without pulsing in size much.
			var shimmer: float = 0.92 + 0.08 * sin(time * 16.0)
			return {
				"length": 3.4 * shimmer,
				"width": 0.55,
				"alpha": 0.85,
			}
		_:
			# STD: a steady, modest plume — no time dependence.
			return {
				"length": 1.3,
				"width": 1.0,
				"alpha": 0.8,
			}


## Request a new steer target; clamped to the steerable width AND the active lane clamp (#86). The
## lane clamp is normally the full width (a no-op); the Walled Gauntlet narrows it to trap the ship.
func set_target_x(x: float) -> void:
	var lo: float = maxf(_min_x, _lane_min)
	var hi: float = minf(_max_x, _lane_max)
	if lo > hi:                     # degenerate clamp (shouldn't happen) — fall back to the edge band
		lo = _min_x
		hi = _max_x
	_target_x = clampf(x, lo, hi)


func get_target_x() -> float:
	return _target_x


## #87 KINETIC_CLUTCH: the ship's current horizontal speed (px/s), derived in step(). Read by the
## StanceController to drive stance: moving => SPRAY, near-stationary => LANCE.
func velocity_x() -> float:
	return _velocity_x


## #87: register a tap at timestamp `t_ms`; returns true when this tap completes a TRIPLE_TAP_COUNT
## burst within TRIPLE_TAP_WINDOW_MS (then resets so the next triple starts fresh). PURE (the stamp
## is passed in, not read from the clock) so a headless test drives it deterministically.
func register_tap(t_ms: int) -> bool:
	_tap_times.append(t_ms)
	# Drop taps older than the window so only a fast burst counts.
	while not _tap_times.is_empty() and t_ms - _tap_times[0] > TRIPLE_TAP_WINDOW_MS:
		_tap_times.pop_front()
	if _tap_times.size() >= TRIPLE_TAP_COUNT:
		_tap_times.clear()
		return true
	return false


## #86: the Walled Gauntlet set the active lane clamp (or restored the full steerable width to
## release). Re-clamp the live target immediately so the ship snaps into the committed lane.
func _on_lane_clamp_changed(min_x: float, max_x: float) -> void:
	_lane_min = min_x
	_lane_max = max_x
	set_target_x(_target_x)
