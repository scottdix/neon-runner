class_name LaneArena
extends Node2D
## The HORDE arena divider (#90, H1) — a PERMANENT, STATIC, FULL-HEIGHT neon wall down the
## centre of the playfield at CENTER_X. It is the FIRING BOUNDARY of HORDE mode: the ship
## free-steers the full width, but the fleet only DAMAGES enemies on the same side of the
## divider as the fleet muzzle (Targets enforces the far-side filter). The far half still
## renders/descends/breaches — it just takes no hits that frame, so the player must commit
## the fleet to a side.
##
## CLONED from WalledGauntlet's VALIDATED geometry (CENTER_X, the additive-HDR bar MultiMesh,
## _make_bar_texture, lane_bounds_for) but with the TRANSIENT machinery DROPPED: no scroll
## projection, no PENDING/TRAPPING/DONE state machine, no _start_m, no per-distance crossing
## _step. The bar is drawn ONCE at full screen height and never moves. Pure helper
## (lane_bounds_for, side_of) so the headless verify drives it with no GPU.
##
## Gated entirely behind Settings.poc_mode == HORDE: run.gd only instances this in HORDE, and
## skips the transient _gauntlet. LEGACY/KINETIC/GEOM never see it.

## Divider geometry (cloned from WalledGauntlet, unchanged). Half-width of the glowing bar +
## the lane gap that keeps a committed lane clear of it.
const BARRIER_HALF := 10.0             # #90 P0: thinned 44->10 — a crisp 'vectory' neon line, not a wall
const LANE_GAP := 80.0                 # a committed lane stays this far off the divider centre
const CENTER_X := 540.0                # lane split (half of 1080)
const TEX := 32                        # soft-bar texture resolution

var _design := Vector2(1080, 1920)
var _mmi: MultiMeshInstance2D


func _ready() -> void:
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_build_multimesh()
	_render()


# --- Pure geometry (verify asserts these; no GPU) ----------------------------

## Steerable [min_x, max_x] for a side of the divider (0 LEFT / 1 RIGHT): the half of the
## playfield on that side, held LANE_GAP + BARRIER_HALF clear of the centre. Pure — CLONED
## from WalledGauntlet.lane_bounds_for so the geometry is identical to the validated trap.
## NOTE: in HORDE the SHIP is NOT clamped to a lane (it steers the full width); this is kept
## so the far-side firing maths + any future lane logic share one source of truth.
func lane_bounds_for(lane: int) -> Vector2:
	var inner: float = CENTER_X - (BARRIER_HALF + LANE_GAP)
	var outer: float = CENTER_X + (BARRIER_HALF + LANE_GAP)
	if lane == 0:
		return Vector2(0.0, inner)            # LEFT lane
	return Vector2(outer, _design.x)          # RIGHT lane


## Which side of the divider a world x is on: 0 == LEFT (x < CENTER_X), 1 == RIGHT.
## The single source of truth the far-side firing filter keys off (Targets.side_of mirrors it).
static func side_of(x: float) -> int:
	return 0 if x < CENTER_X else 1


# --- Rendering (additive-HDR full-height bar — the bloom path) ----------------

func _build_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(BARRIER_HALF * 2.0, 1.0)   # unit-height; scaled to the full screen each frame
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance2D.new()
	_mmi.name = "ArenaBar"
	_mmi.multimesh = mm
	_mmi.texture = _make_bar_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mmi.material = mat
	add_child(_mmi)


## Draw the divider ONCE: a full screen-height bar at CENTER_X. Static — no scroll, no state.
## Re-called only on ready (and re-callable if the design size ever changes).
func _render() -> void:
	if _mmi == null:
		return
	var mm := _mmi.multimesh
	mm.visible_instance_count = 1
	var height: float = _design.y
	var mid_y: float = _design.y * 0.5
	# Scale the unit-height quad to the FULL screen span; place it on the lane centre. The node
	# sits at origin, so the instance carries the absolute placement.
	var xf := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, height), Vector2(CENTER_X, mid_y))
	mm.set_instance_transform_2d(0, xf)
	mm.set_instance_color(0, Palette.DIVIDER_CYAN)     # #90 P0: cool cyan — contrasts the pink/green enemies


## Soft-edged vertical bar mask: bright down the centre column, falling off to the left/right
## edges so the divider blooms as a neon wall. Shape is alpha; colour is the HDR instance tint.
## CLONED from WalledGauntlet._make_bar_texture (unchanged).
func _make_bar_texture() -> ImageTexture:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var c := (TEX - 1) * 0.5
	for y in TEX:
		for x in TEX:
			var dx: float = absf(x - c) / c           # 0 at centre column, 1 at the edges
			var a: float = clampf(1.0 - dx, 0.0, 1.0)
			# #90 P0: SHARPEN the falloff (a*a -> a^4) so the bright core is a tight crisp column with a
			# fast edge falloff — a 'vectory' neon line, not a soft fat wall. Shape is alpha; HDR tint glows.
			var aa: float = a * a
			img.set_pixel(x, y, Color(1, 1, 1, aa * aa))
	return ImageTexture.create_from_image(img)
