extends Node
## Viewport Cull (#38) — an off-screen-processing GATE: it disables per-frame processing for
## Node2D children of the layers it's given when they scroll OUTSIDE the visible vertical band (above
## the top / below the bottom by a margin), and re-enables them on re-entry. Purely additive — it only
## flips set_process()/set_physics_process() on nodes the run already owns; a culled node is never
## deleted or moved, so the gameplay RESULT is provably unchanged.
##
## SCOPE / HONEST LIMITS (read this — the old header over-claimed):
##   - This sweep only sees the layers' direct Node2D CHILDREN. But the run's heavy scrollers — the
##     swarm bullets and the field enemies — are NOT child nodes: Fleet renders all bullets through a
##     SINGLE MultiMeshInstance2D and Targets keeps its enemies as an Array[Dictionary] drawn by one
##     MultiMesh (each layer adds exactly ONE `_mmi` child at the layer origin, always on-screen). So
##     for the MultiMesh entity path this cull does NO work — there are no per-entity child nodes to
##     gate. That is BY DESIGN for v1: the cull is a correctness-safe INSTRUMENTATION SEAM, not the
##     batched-array optimiser. Culling the data arrays themselves (skipping off-band entities inside
##     Targets/Fleet step) is a deeper rescope deferred to the on-device perf pass (#39).
##   - Because the heavy entities are NOT in this cull's reach, and collision/score run from each
##     LAYER's own step() (not gated here), the cull CANNOT skip a still-on-screen enemy's collision
##     or score — zero gameplay effect, verified (verify_perf sweeps a real layer and asserts no
##     state change). The remaining cullable children are short-lived one-shot effect emitters, which
##     this sweep deliberately SKIPS (see _apply) — GPU particle sim is GPU-driven, so gating their
##     script process is pointless churn and a latent trap, not a win.
##
## DESIGN / GOTCHA notes:
##   - The band check is a PURE function in_band(pos, top, bottom, margin) → bool so the verify can
##     assert the boundaries with NO scene tree. The cull/restore policy (_apply, _band) is built on
##     top of it and is likewise side-effect-isolated to set_process toggles.
##   - "No visual glitches": we ONLY gate processing, never `visible` — a culled node keeps drawing
##     its last position (it's off-screen anyway), so there's no pop when it re-enters. We also leave
##     a generous margin so an object that re-enters mid-frame isn't a frame late waking up.
##   - HEADLESS: in_band / band_for are static-pure; _step (the live sweep) tolerates a null/empty
##     target list and any node missing a band-position method, so a bare .new() never errors.
##   - This holds refs to the layers it sweeps via add_target(); it never reads their state, only
##     walks their children's positions — staying decoupled (no cross-system API beyond a
##     global_position read).

# How far past the visible band an object must be before it's culled (and within which it wakes).
# Generous so a fast scroller doesn't wake a frame late, and so a margin-straddling object doesn't
# thrash process on/off frame-to-frame.
const DEFAULT_MARGIN := 240.0

# The live visible band, in WORLD y. Run sets this from the viewport each sweep (or once, if the
# camera is fixed — the run's camera is FIXED_TOP_LEFT identity, so the band is the viewport rect).
var band_top: float = 0.0
var band_bottom: float = 1920.0
var margin: float = DEFAULT_MARGIN

# Layers whose direct children get swept. Holds the Node refs the run injects (Targets/Fleet/Effects).
var _targets: Array[Node] = []


## PURE band test: is `pos` inside the [top - margin, bottom + margin] vertical band? Only y matters
## (the run scrolls vertically and the playfield is full-width). Static so the verify calls it with
## hand-built numbers and asserts both edges + the margin slop. Returns true = KEEP processing.
static func in_band(pos: Vector2, top: float, bottom: float, p_margin: float) -> bool:
	return pos.y >= (top - p_margin) and pos.y <= (bottom + p_margin)


## PURE: the effective band [lo, hi] for a given top/bottom/margin — exposes the exact cull
## thresholds so the verify can assert the slop is applied symmetrically.
static func band_for(top: float, bottom: float, p_margin: float) -> Vector2:
	return Vector2(top - p_margin, bottom + p_margin)


# --- Run-facing wiring (injection; no cross-system reads) ---------------------

## Run injects a layer (Targets / Fleet / Effects) whose direct children scroll and should be culled
## when off-screen. Idempotent — re-adding the same layer is a no-op. Pure state set.
func add_target(layer: Node) -> void:
	if layer != null and not _targets.has(layer):
		_targets.append(layer)


## Run sets the visible band each sweep (or once, for a fixed camera). top/bottom in WORLD y.
func set_band(top: float, bottom: float) -> void:
	band_top = top
	band_bottom = bottom


# --- Live sweep (side-effects isolated to set_process toggles) -----------------

## Sweep every tracked layer's direct children: a child OUTSIDE the band gets its process +
## physics_process disabled; one INSIDE gets them re-enabled. Tolerant: null layers, children with
## no global_position, and an empty target list are all safe no-ops — so a bare .new() (headless)
## never errors. Returns the number of children currently CULLED (for the verify / overlay).
func _step() -> int:
	var culled := 0
	for layer in _targets:
		if layer == null or not is_instance_valid(layer):
			continue
		for child in layer.get_children():
			if _apply(child):
				culled += 1
	return culled


## Apply the band policy to ONE node: keep-processing if in band, cull if out. Returns true when the
## node ended up CULLED. A node without a global_position (not a Node2D) is left alone (returns false)
## so non-spatial children (timers, audio) are never touched. ALSO skipped:
##   • GPUParticles2D — its simulation is GPU-driven (not gated by the node's set_process), so culling
##     it is pointless churn and a latent trap if _process logic is ever added (minor: the pooled
##     one-shot effect emitters are short-lived and never the perf problem this cull targets).
##   • MultiMeshInstance2D — the run's batched-render sink sits at the layer origin (always in-band),
##     and gating it would stop the whole swarm/enemy draw; it's not a per-entity scroller anyway.
func _apply(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not (node is Node2D):
		return false
	if node is GPUParticles2D or node is MultiMeshInstance2D:
		return false
	var keep: bool = in_band((node as Node2D).global_position, band_top, band_bottom, margin)
	node.set_process(keep)
	node.set_physics_process(keep)
	return not keep
