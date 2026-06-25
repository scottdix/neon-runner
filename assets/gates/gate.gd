class_name Gate
extends Node2D
## A single gate (#11): a math operation on the swarm "volume of fire"
## (GameState.projectile_count). Polarity (#56): ADD/MULTIPLY are POSITIVE (grow
## the fleet, magenta/green); SUBTRACT/DIVIDE are NEGATIVE (decimate it + drain the
## Glow Battery once #55 lands, red). Steering aims the whole stream (D1), so the
## ship's x at the crossing line decides which gate of a Split Choice you took.
##
## Logic (apply / get_display_text / trigger) works on a bare `.new()` instance for
## headless tests; visuals build in _ready. Rendered TEXTURED/additive so the neon
## frame blooms (the glow gotcha — draw_*/polylines never glow); the op number is a
## crisp world-space Label (readability over bloom for the digits).

enum Operation { ADD, SUBTRACT, MULTIPLY, DIVIDE }

## Gate FAMILY taxonomy (#86). Each family owns a distinct ring-frame SILHOUETTE + HDR hue
## (see Palette.GATE_FAMILY_*), all outside the enemy danger band. SPRAY_AUG/LANCE_AUG cover the
## math gates (Add/Mul → SPRAY_AUG, Sub/Div → LANCE_AUG, derived in _family_for_op); GEOM + UTILITY
## are UNIVERSAL (never ghosted); DEVIL is the reserved high-risk Overclock family (orange + barbed).
## SPRAY_AUG == 0 so a bare `.new()` / math gate's default `family` reads as SPRAY_AUG before configure.
enum Family { SPRAY_AUG, LANCE_AUG, GEOM, UTILITY, DEVIL }


## Map an authored op string (LevelDef schedule, #13) to an Operation. Keeps LevelDef
## free of any dependency on this enum — the data stays plain strings. Unknown → ADD.
static func op_from_string(s: String) -> int:
	match s:
		"add": return Operation.ADD
		"sub", "subtract": return Operation.SUBTRACT
		"mul", "multiply": return Operation.MULTIPLY
		"div", "divide": return Operation.DIVIDE
	return Operation.ADD

const BOX := Vector2(440.0, 150.0)          # visible panel size

# HDR colours live in Palette: trigger() flashes FLASH_WHITE; the resting ring hue comes from the
# FAMILY (Palette.GATE_FAMILY_*) via _family_color(), keyed off `family` in _ready().

var operation: int = Operation.MULTIPLY
var value: float = 2.0
var span_min: float = 0.0                   # horizontal trigger span (canvas x)
var span_max: float = 540.0
var has_been_triggered: bool = false

## Non-arithmetic gate effect (the dispatch seam). When `effect_id` is non-empty this gate is NOT a
## math gate: trigger() emits Events.gate_effect (GameState routes it through its handler table) and
## skips ALL economy math — no apply(), no gate_passed, no battery drain. `effect_params` is the
## authored payload handed to the effect handler. Empty `effect_id` (the default) keeps the today's
## pure-math path, so existing gates + headless tests are unaffected.
var effect_id: String = ""
var effect_params: Dictionary = {}

## Gate FAMILY (a `Family` enum value, default SPRAY_AUG == 0). Tags an effect gate with its category
## so visuals/telegraphs can colour it without re-deriving from effect_id. Set via configure_effect for
## effect gates; for MATH gates _ready derives it from the op (_family_for_op) so they stay coherent.
var family: int = Family.SPRAY_AUG

## STANCE-BASED POOL FILTERING (#88). When the GateSpawner builds a run around a stance allegiance, an
## off-allegiance gate that falls OUTSIDE the bias cap is flagged here (a STICKY pool-filter mark, set
## once at build time). The spawner's per-frame ghosting ORs this in, so a pool-filtered gate stays
## dimmed for the WHOLE run regardless of the live stance — unlike the per-frame wrong-stance dim, which
## relights the moment the live stance matches. Appearance only: a flagged gate still trigger()s if the
## ship steers through it (filtering decides look, not which side fires). Default off — bare gates/tests
## are unaffected.
var pool_filtered: bool = false

## Gate-hijack (#53). When `hijacked`, an Entropy enemy is parked on this gate and the
## splice is DENIED until that occupant is destroyed (`hijack_cleared`). GateSpawner
## assigns `hijack_id`; Targets parks/kills the occupant and reports back to the spawner,
## which flips `hijack_cleared`. A bare `.new()` gate is never hijacked (defaults off),
## so existing headless tests are unaffected.
var hijacked: bool = false
var hijack_cleared: bool = false
var hijack_id: int = -1

var _panel: Sprite2D
var _label: Label
## Wrong-stance GHOSTING (#86): true while this gate's family mismatches GameState.stance, so the
## spawner can dim it without changing which gate trigger()s. Pure appearance; the setter restores the
## family hue when cleared. The trigger FLASH_WHITE must win on the trigger frame — see set_ghosted.
var _ghosted: bool = false


## Define this gate's op/value and its horizontal slot. `center_x` is where the
## panel draws; [span_min, span_max) is the steer band that counts as "through it".
func configure(op: int, val: float, smin: float, smax: float, center_x: float) -> void:
	operation = op
	value = val
	span_min = smin
	span_max = smax
	position.x = center_x


## Define this gate as a NON-arithmetic EFFECT gate (the dispatch seam): set `effect_id` (non-empty)
## so trigger() routes to GameState.gate_effect instead of the math path, stash the authored `params`
## payload, and tag the `family`. Mirrors configure() but for the effect fields; the spawner sets the
## horizontal slot (span_min/max + position.x) separately, exactly as it does for a math gate.
func configure_effect(eid: String, params: Dictionary, fam: int) -> void:
	effect_id = eid
	effect_params = params
	family = fam


func is_positive() -> bool:
	return operation == Operation.ADD or operation == Operation.MULTIPLY


## The STANCE this gate sets when crossed (#79): ADD/MULTIPLY open the stream into a wide
## SPRAY, SUBTRACT/DIVIDE converge it into a heavy LANCE. A parallel read off `operation`
## (mirrors is_positive()). NOTE: this does NOT touch trigger()/apply() economy math —
## GameState still derives the live stance from `gate_type` in gate_passed; sets_stance()
## exists for the spawner telegraph + gate visuals so they can preview the upcoming mode.
func sets_stance() -> int:
	return GameState.Stance.SPRAY if is_positive() else GameState.Stance.LANCE


func contains_x(x: float) -> bool:
	return x >= span_min and x < span_max


## New swarm volume after this gate (clamping to >= 0 is GameState's job).
func apply(count: int) -> int:
	match operation:
		Operation.ADD:
			return count + int(value)
		Operation.SUBTRACT:
			return count - int(value)
		Operation.MULTIPLY:
			return int(round(count * value))
		Operation.DIVIDE:
			return count if value == 0.0 else int(count / value)
	return count


func get_display_text() -> String:
	match operation:
		Operation.ADD:
			return "+%d" % int(value)
		Operation.SUBTRACT:
			return "-%d" % int(value)
		Operation.MULTIPLY:
			return "×%d" % int(value)
		Operation.DIVIDE:
			return "÷%d" % int(value)
	return "?"


## Fire this gate once: mark it, announce on the bus (GameState applies the economy
## effect; HUD/audio/#55 battery also react), and return the new volume. The emitted
## count is floored at 0 here so the signal payload is honest (review debt: was
## pre-clamp). Re-triggering is a no-op.
func trigger(count: int) -> int:
	if has_been_triggered:
		return count
	has_been_triggered = true
	# Gate-hijack (#53): a live occupant at the line DENIES the splice — no economy
	# effect, just a "blocked" announcement (HUD/audio/haptic) and a red flash.
	if hijacked and not hijack_cleared:
		Events.gate_hijack_blocked.emit(_op_string(), global_position)
		if _panel != null:
			_panel.modulate = Palette.GATE_NEGATIVE
		return count
	# Non-arithmetic effect gate (the dispatch seam): route to GameState's handler table and do
	# NO economy math (count is returned unchanged). The hijack-block above still guards both paths.
	if effect_id != "":
		Events.gate_effect.emit(effect_id, effect_params, global_position)
		if _panel != null:
			_panel.modulate = Palette.FLASH_WHITE
		return count
	var new_count := maxi(0, apply(count))
	Events.gate_passed.emit(_op_string(), value, new_count)
	if _panel != null:
		_panel.modulate = Palette.FLASH_WHITE
	return new_count


func _op_string() -> String:
	match operation:
		Operation.ADD: return "add"
		Operation.SUBTRACT: return "subtract"
		Operation.MULTIPLY: return "multiply"
		Operation.DIVIDE: return "divide"
	return "?"


## The FAMILY this gate's op belongs to (#86): Add/Mul open the stream → SPRAY_AUG; Sub/Div focus it
## → LANCE_AUG. Keeps the math gates inside the family taxonomy so a +/× reads green and a −/÷ reads
## cyan, matching the stance they set. Effect gates set `family` directly via configure_effect.
func _family_for_op() -> int:
	return Family.SPRAY_AUG if is_positive() else Family.LANCE_AUG


## HDR ring-frame hue for `fam` (#86) — the additive/textured colour the bloom catches. All five sit
## outside the enemy RED→MAGENTA→VIOLET band (green / cyan / amber / teal / orange). Unknown → SPRAY.
static func _family_color(fam: int) -> Color:
	match fam:
		Family.SPRAY_AUG: return Palette.GATE_FAMILY_SPRAY
		Family.LANCE_AUG: return Palette.GATE_FAMILY_LANCE
		Family.GEOM: return Palette.GATE_FAMILY_GEOM
		Family.UTILITY: return Palette.GATE_FAMILY_UTILITY
		Family.DEVIL: return Palette.GATE_FAMILY_DEVIL
	return Palette.GATE_FAMILY_SPRAY


## Wrong-stance GHOSTING (#86) — a pure setter the spawner calls each frame. When `on`, DESATURATE +
## DIM the panel + label so a gate the current stance can't use recedes (appearance only — steering
## still decides which gate trigger()s). When off, restore the family hue / crisp digits. Idempotent.
## IMPORTANT: once the gate has fired, this is a NO-OP so the trigger() FLASH_WHITE always wins — even
## if the spawner ghosts after the same frame's trigger (a mismatched gate the ship steered through).
func set_ghosted(on: bool) -> void:
	if has_been_triggered:
		return
	if on == _ghosted and _panel != null:
		return
	_ghosted = on
	if _panel == null:
		return                                   # visuals not built yet (headless / pre-_ready)
	if on:
		# Pull the family hue toward a dim grey: lerp to grey desaturates, the 0.45 scale dims it
		# below the bloom threshold so a ghosted ring barely glows.
		var c: Color = _family_color(family)
		var lum: float = (c.r + c.g + c.b) / 3.0
		_panel.modulate = Color(lum, lum, lum, 1.0).lerp(c, 0.35) * 0.45
		_label.modulate = Palette.HUD_WHITE * 0.4
	else:
		_panel.modulate = _family_color(family)
		_label.modulate = Palette.HUD_WHITE


# --- Visuals -----------------------------------------------------------------

func _ready() -> void:
	# Math gates derive their family from the op so the +/×/−/÷ keep a coherent look; effect gates
	# already carry an explicit family from configure_effect. (Done here, not in configure(), so a bare
	# `.new()` headless gate never needs the enum and tests stay logic-only.)
	if effect_id == "":
		family = _family_for_op()
	_panel = Sprite2D.new()
	_panel.name = "Panel"
	_panel.texture = _family_texture(family)
	_panel.scale = BOX / Vector2(_panel.texture.get_size())
	_panel.modulate = _family_color(family)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_panel.material = mat
	add_child(_panel)

	_label = Label.new()
	_label.name = "Op"
	_label.text = get_display_text()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size = BOX
	_label.position = -BOX * 0.5            # center the label box on the gate
	_label.add_theme_font_size_override("font_size", 84)
	Fonts.apply(_label, Fonts.arcade)       # Press Start 2P arcade numerals
	_label.modulate = Palette.HUD_WHITE     # crisp white digits (out of bloom)
	add_child(_label)


## STATIC per-family ring-frame texture cache (#86). The five family silhouettes are pixel-identical
## across every gate of that family, so we generate each ImageTexture ONCE here and share it — never
## per-gate (a gate every few metres × a 96² Image.set_pixel loop would churn). Keyed by Family enum.
static var _family_textures: Dictionary = {}


## The shared ring-frame texture for `fam`, building + caching it on first use (#86). White RGB so the
## per-gate `_panel.modulate` tints it to the family hue; the silhouette + transparent core live in the
## alpha. Every family gets a distinct OUTER SHAPE; the core stays alpha~0 so additive bloom can't blur
## it — that hard negative-space core is the glow-safe design (a transparent pixel emits nothing).
static func _family_texture(fam: int) -> ImageTexture:
	if _family_textures.has(fam):
		return _family_textures[fam]
	var tex := _make_frame_texture(fam)
	_family_textures[fam] = tex
	return tex


## Build one family's ring-frame: a BRIGHT NEON RING tracing the family's outer silhouette with a
## DARK/TRANSPARENT NEGATIVE-SPACE CORE. Per family the silhouette differs (wide ring / narrow-tall /
## hex / octagon / barbed); shared machinery is an SDF whose zero-level is that shape, with the ring
## as a band around |sdf| and alpha falling to 0 inward (the core never emits). White RGB, tint at draw.
static func _make_frame_texture(fam: int) -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var band := 0.10                        # ring half-thickness in normalised SDF units
	for y in n:
		for x in n:
			# Centred coords in [-1, 1]; p is the unit-square sample point.
			var p := Vector2(float(x) / (n - 1) * 2.0 - 1.0, float(y) / (n - 1) * 2.0 - 1.0)
			# Signed distance to the family silhouette boundary (<0 inside, 0 on the rim, >0 outside).
			var d: float = _family_sdf(fam, p)
			# Ring band: brightest on the rim (|d| small), fading to 0 by `band`. Squaring tightens it.
			var a: float = clampf((band - absf(d)) / band, 0.0, 1.0)
			a = a * a
			# Hard negative-space core: anything well inside the shape stays fully transparent so the
			# additive bloom leaves the centre crisp (no glow bleed across the dark core).
			if d < -band:
				a = 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Signed distance from unit-square point `p` (∈[-1,1]²) to family `fam`'s outer silhouette: negative
## inside, 0 on the rim, positive outside. Each family is a different primitive so the rims read as
## distinct shapes through the bloom (#86): SPRAY_AUG a WIDE ring, LANCE_AUG a NARROW-TALL ring, GEOM a
## HEXAGON, UTILITY an OCTAGON, DEVIL a BARBED ring (angular spikes — the reserved high-risk family).
static func _family_sdf(fam: int, p: Vector2) -> float:
	match fam:
		Family.SPRAY_AUG:
			# Wide rounded box (broad, short) — the open/spray silhouette.
			return _sdf_box(p, Vector2(0.92, 0.62), 0.18)
		Family.LANCE_AUG:
			# Narrow + tall rounded box — the focused/converged silhouette.
			return _sdf_box(p, Vector2(0.55, 0.92), 0.14)
		Family.GEOM:
			# Hexagon (6 sides) — the geometry family reads as a faceted gem.
			return _sdf_ngon(p, 6, 0.86, 0.0)
		Family.UTILITY:
			# Octagon (8 sides) — rounder than the hex; the neutral utility silhouette.
			return _sdf_ngon(p, 8, 0.86, 0.0)
		Family.DEVIL:
			# Barbed ring: an 8-point star (alternating long spikes / short notches) — angular + hostile,
			# reserved for the Overclock high-risk family. Orange-tinted at draw, never red/magenta.
			return _sdf_star(p, 8, 0.9, 0.5)
	return _sdf_box(p, Vector2(0.92, 0.62), 0.18)


## SDF of a rounded box: half-extents `b`, corner radius `r`. <0 inside.
static func _sdf_box(p: Vector2, b: Vector2, r: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - b + Vector2(r, r)
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	return outside + minf(maxf(q.x, q.y), 0.0) - r


## SDF of a regular `sides`-gon, circumradius `radius`, rotated by `rot` radians. <0 inside.
static func _sdf_ngon(p: Vector2, sides: int, radius: float, rot: float) -> float:
	var a: float = atan2(p.y, p.x) - rot
	var seg: float = TAU / float(sides)
	# Fold the angle into one wedge, then distance is along the wedge bisector.
	var ha: float = seg * 0.5
	var fold: float = absf(fposmod(a + ha, seg) - ha)
	var apothem: float = radius * cos(ha)
	return p.length() * cos(fold) - apothem


## SDF of an `points`-point star: outer radius `outer`, inner radius `outer*inner`. <0 inside. Gives the
## DEVIL family its barbed rim (spikes out, notches in) without per-vertex polygon work.
static func _sdf_star(p: Vector2, points: int, outer: float, inner: float) -> float:
	var a: float = atan2(p.y, p.x)
	var seg: float = TAU / float(points)
	var ha: float = seg * 0.5
	var fold: float = absf(fposmod(a + ha, seg) - ha) / ha   # 0 at a spike tip, 1 at a notch
	# Lerp the radius from outer (tip) to inner notch across the wedge — an angular barbed boundary.
	var rad: float = lerpf(outer, outer * inner, fold)
	return p.length() - rad
