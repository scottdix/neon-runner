extends CanvasLayer
## Perf Overlay (#35) — the on-screen instrumentation seam for the perf pass. A toggleable
## CanvasLayer label panel that polls the engine's Performance monitors each frame (FPS, draw
## calls, active physics objects, visible RENDER objects, static memory) and prints them as a
## compact HUD readout. This is ALSO the seam #39 (profile-and-fix) reads from — the actual
## 60fps-on-device acceptance is DEVICE-ONLY (the Intel UHD 630 here can't render bloom or read
## real FPS), so this layer only owns the LOGIC: which monitors, how they're formatted.
##
## DESIGN / GOTCHA notes:
##   - The overlay sits on its OWN high CanvasLayer (above the HUD/pause) so it never gets shaken
##     or hidden by gameplay; it is a debug surface, not part of the playfield.
##   - DEVICE PATH (#bug): the overlay mirrors Settings.perf_overlay_enabled — a Settings-screen
##     toggle a phone can actually press (a keyboard F3 is unreachable on device). It applies that
##     setting on _ready and reacts to Events.perf_overlay_changed so flipping the switch shows/
##     hides it live. The keyboard action/F3 stays as a desktop convenience BONUS.
##   - Starts HIDDEN unless the setting is on — it must NOT cost anything (no per-frame polling/
##     label rebuild) while off.
##   - HEADLESS determinism: every metric→string decision lives in PURE static formatters
##     (_fmt_fps / _fmt_mem / _fmt_int / format_panel) that take plain numbers, so the verify
##     script asserts the readout text with NO renderer and NO live Performance singleton. _ready
##     (which builds the Label) is DEFERRED under `-s` and never fires — the pure path doesn't need it.
##
## Bus: none. This layer only READS engine Performance monitors; it never mutates run state or
## emits, so it can't regress gameplay logic (the core guard for the whole perf cluster).
##
## METRIC NOTE — PHYS (PHYSICS_2D_ACTIVE_OBJECTS) is expected to read ~0 BY DESIGN on this game: it
## uses NO physics bodies for gameplay (collision is the batched MultiMesh consume_volumes path, not
## Area2D/Body2D), so a near-constant zero there is correct, not a broken monitor. The load-bearing
## counts for #39 are the live enemy/bullet ARRAY sizes that drive consume_volumes cost (and the
## RENDER object/primitive counts shown) — read those, not PHYS, when profiling on device.

# Debug toggle: prefer a mapped input action, fall back to a keycode so it works with no remap.
const TOGGLE_ACTION := "perf_overlay"
const TOGGLE_KEYCODE := KEY_F3

# Panel layout (#35): pinned BOTTOM-RIGHT, right-aligned, small mono readout. PANEL_MARGIN insets
# it from the corner (x = right edge, y = bottom edge — the bottom margin clears the home indicator
# / gesture bar on modern iPhones). PANEL_HEIGHT just reserves a tall-enough box for the 6 lines; the
# text is bottom-aligned inside it, so the readout's bottom-right corner sits at the inset corner.
const PANEL_MARGIN := Vector2(24.0, 140.0)
const PANEL_HEIGHT := 400.0
const FONT_SIZE := 22

# Pure monitor descriptors: {label, monitor, kind}. `kind` selects the formatter so the verify
# script can round-trip each line without the live Performance singleton. The Performance.* enum
# values are resolved lazily in _sample() (engine-side); the PURE path takes raw numbers instead.
const METRICS := [
	{"label": "FPS", "monitor": "TIME_FPS", "kind": "fps"},
	{"label": "DRAW", "monitor": "RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "kind": "int"},
	{"label": "PHYS", "monitor": "PHYSICS_2D_ACTIVE_OBJECTS", "kind": "int"},
	{"label": "OBJ", "monitor": "RENDER_TOTAL_OBJECTS_IN_FRAME", "kind": "int"},
	{"label": "PRIM", "monitor": "RENDER_TOTAL_PRIMITIVES_IN_FRAME", "kind": "int"},
	{"label": "MEM", "monitor": "MEMORY_STATIC", "kind": "mem"},
]

var _label: Label
var _shown: bool = false


func _ready() -> void:
	# Build the readout label on a high layer; start hidden + non-processing so an OFF overlay is
	# free. NOTE: under headless `-s`, _ready is DEFERRED and never fires — the PURE formatters
	# (used by the verify) don't depend on the Label, so that's fine.
	layer = 110   # above HUD(50)/milestone(60)/pause(100)
	_label = Label.new()
	_label.name = "PerfLabel"
	# Anchor a full-width box along the bottom edge, then right- + bottom-align the text so the
	# readout hugs the bottom-right corner (inset by PANEL_MARGIN) regardless of how wide the metric
	# values get. Anchors are relative to the root viewport (CanvasLayer gives no rect of its own).
	_label.anchor_left = 0.0
	_label.anchor_top = 1.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = PANEL_MARGIN.x
	_label.offset_top = -PANEL_HEIGHT
	_label.offset_right = -PANEL_MARGIN.x
	_label.offset_bottom = -PANEL_MARGIN.y
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if Fonts.arcade != null:
		_label.add_theme_font_override("font", Fonts.arcade)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Palette.HUD_CYAN)
	add_child(_label)
	visible = false
	set_process(false)
	# Mirror the persisted Settings toggle (the device path) + react to it live. The keyboard F3
	# toggle below stays as a desktop bonus. Guard for the headless verify, which never runs _ready.
	if Events != null and not Events.perf_overlay_changed.is_connected(set_shown):
		Events.perf_overlay_changed.connect(set_shown)
	if Settings != null:
		set_shown(Settings.perf_overlay_enabled)


## Toggle on a debug action / keycode. Kept in _unhandled_input so it never eats gameplay input
## (the run handles steer/fire elsewhere); a perf debug toggle must not interfere with play.
func _unhandled_input(event: InputEvent) -> void:
	if _is_toggle(event):
		set_shown(not _shown)


## Is this event the overlay toggle? Prefers the mapped action when it exists, else the keycode.
## PURE-ish (only touches InputMap/the event), separated so intent is testable in isolation.
func _is_toggle(event: InputEvent) -> bool:
	if InputMap.has_action(TOGGLE_ACTION) and event.is_action_pressed(TOGGLE_ACTION):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).keycode == TOGGLE_KEYCODE
	return false


## Show/hide the overlay. Gates _process so an OFF overlay polls nothing (cheap-guard: the perf
## tool must never cost the run anything while disabled).
func set_shown(on: bool) -> void:
	_shown = on
	visible = on
	set_process(on)
	if not on and _label != null:
		_label.text = ""


func is_shown() -> bool:
	return _shown


func _process(_delta: float) -> void:
	if not _shown or _label == null:
		return
	_label.text = format_panel(_sample())


# --- Live sampling (engine-side; NOT exercised headless) ----------------------

## Read the live Performance monitors into a {label: raw_number} dict. The Performance.* enum
## constants are resolved here (engine singleton); the verify never calls this — it feeds
## format_panel a hand-built sample instead, so no live monitor is needed for the LOGIC test.
func _sample() -> Dictionary:
	var out := {}
	for m in METRICS:
		out[m["label"]] = Performance.get_monitor(_monitor_id(m["monitor"]))
	return out


## Map a monitor NAME to its Performance.* enum id. Centralised so the descriptor table can stay
## string-keyed (readable + testable) while the engine read uses the real enum.
func _monitor_id(name: String) -> int:
	match name:
		"TIME_FPS": return Performance.TIME_FPS
		"RENDER_TOTAL_DRAW_CALLS_IN_FRAME": return Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		"PHYSICS_2D_ACTIVE_OBJECTS": return Performance.PHYSICS_2D_ACTIVE_OBJECTS
		"RENDER_TOTAL_OBJECTS_IN_FRAME": return Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
		"RENDER_TOTAL_PRIMITIVES_IN_FRAME": return Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
		"MEMORY_STATIC": return Performance.MEMORY_STATIC
		_: return Performance.TIME_FPS


# --- PURE formatting (headless-safe; the verify asserts on these) -------------

## Build the full multi-line panel string from a {label: raw_number} sample, using the per-metric
## `kind` formatter from METRICS. PURE — no engine read, no Label; the verify hands it a known
## sample and asserts the exact text. A label missing from the sample renders as "—" so a partial
## sample can't crash the panel.
static func format_panel(sample: Dictionary) -> String:
	var lines: Array[String] = []
	for m in METRICS:
		var key: String = m["label"]
		var cell: String = "—"
		if sample.has(key):
			cell = _fmt_cell(m["kind"], sample[key])
		lines.append("%-4s %s" % [key, cell])
	return "\n".join(lines)


## Route a raw monitor value to its kind's formatter.
static func _fmt_cell(kind: String, value: float) -> String:
	match kind:
		"fps": return _fmt_fps(value)
		"mem": return _fmt_mem(value)
		"int", _: return _fmt_int(value)


## FPS → an integer string (frames are whole; we round to the nearest).
static func _fmt_fps(value: float) -> String:
	return str(int(roundf(value)))


## A counter → a thousands-grouped integer ("12345" → "12,345") so big draw-call / object counts
## read at a glance. Reuses no UI helper to stay a pure leaf the verify can call standalone.
static func _fmt_int(value: float) -> String:
	var n: int = int(roundf(value))
	var neg: bool = n < 0
	var digits: String = str(absi(n))
	var grouped: String = ""
	var c: int = 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		c += 1
		if c % 3 == 0 and i > 0:
			grouped = "," + grouped
	return ("-" + grouped) if neg else grouped


## Bytes → a compact "12.3 MB" / "456 KB" string (static memory reads in bytes). Picks the largest
## unit under which the value is >= 1 so the readout stays short.
static func _fmt_mem(bytes: float) -> String:
	var b: float = maxf(bytes, 0.0)
	if b >= 1048576.0:
		return "%.1f MB" % (b / 1048576.0)
	if b >= 1024.0:
		return "%.0f KB" % (b / 1024.0)
	return "%d B" % int(b)
