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

# HDR polarity colours now live in Palette (×=magenta, +=acid green, negative=red);
# referenced at runtime in _polarity_color() / trigger().

var operation: int = Operation.MULTIPLY
var value: float = 2.0
var span_min: float = 0.0                   # horizontal trigger span (canvas x)
var span_max: float = 540.0
var has_been_triggered: bool = false

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


## Define this gate's op/value and its horizontal slot. `center_x` is where the
## panel draws; [span_min, span_max) is the steer band that counts as "through it".
func configure(op: int, val: float, smin: float, smax: float, center_x: float) -> void:
	operation = op
	value = val
	span_min = smin
	span_max = smax
	position.x = center_x


func is_positive() -> bool:
	return operation == Operation.ADD or operation == Operation.MULTIPLY


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


func _polarity_color() -> Color:
	match operation:
		Operation.MULTIPLY: return Palette.GATE_MULTIPLY
		Operation.ADD: return Palette.GATE_ADD
	return Palette.GATE_NEGATIVE


# --- Visuals -----------------------------------------------------------------

func _ready() -> void:
	_panel = Sprite2D.new()
	_panel.name = "Panel"
	_panel.texture = _make_frame_texture()
	_panel.scale = BOX / Vector2(_panel.texture.get_size())
	_panel.modulate = _polarity_color()
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


## A glowing rectangular frame: bright border band fading inward, transparent core,
## so additive blending reads as a neon-bordered panel. Tolerant of being scaled.
func _make_frame_texture() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var border := 0.16                      # border band as a fraction of the size
	for y in n:
		for x in n:
			var fx: float = float(x) / (n - 1)
			var fy: float = float(y) / (n - 1)
			# distance to the nearest edge, normalised 0 (edge) .. 0.5 (center)
			var edge: float = minf(minf(fx, 1.0 - fx), minf(fy, 1.0 - fy))
			var a: float = clampf((border - edge) / border, 0.0, 1.0)
			a = a * a                       # tighten the band toward the rim
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
