extends CanvasLayer
## DEBUG MENU overlay (P4) — the HORDE designer-tuning surface, opened from the PAUSE overlay's
## DEBUG button. Sits ABOVE pause (layer 110 > pause's 100) on its own CanvasLayer, runs with
## PROCESS_MODE_ALWAYS so its controls respond while the tree is paused under the run.
##
## Every control reads its CURRENT Debug value when the menu opens (rebuilt on each open) and writes
## back through the matching Debug setter on change — the menu owns NO state of its own, Debug is the
## single source of truth (persisted to user://debug.cfg). The three Bullet-Passthrough rows are
## MARKED PLACEHOLDER: they write their Debug field so the dialled value survives, but no gameplay
## reads it yet (forward-looking, intentional).
##
## Rows reuse UI.toggle_row (promoted from settings.gd) for the booleans and UI.stepper_row for the
## numeric knobs. CLOSE returns to the pause overlay (the run stays paused underneath).
##
## Debug is read via root.get_node_or_null("Debug") so a bare-instance headless verify (no autoload
## context) builds the overlay without a hard `Debug.` dependency.

const UI := preload("res://assets/ui/ui_kit.gd")

const ROW_X := 70.0          # left inset of every row on the design width
const ROW_W := UI.DESIGN.x - 140.0
const ROW_GAP := 120.0       # vertical pitch between rows
const FIRST_Y := 260.0       # top of the first row (below the title)

var _dbg: Node = null
# Running Y cursor for row layout. MUST be an instance member, NOT a local captured by the add-row
# closure: a GDScript lambda captures locals BY VALUE, so `y += ROW_GAP` inside a closure never
# advances and every row lands on the same line (the original render bug). _add_row mutates this member.
var _next_y: float = 0.0


func _ready() -> void:
	layer = 110                                 # above the pause overlay (layer 100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dbg = get_node_or_null("/root/Debug")


## Show the menu, rebuilding every row from the LIVE Debug values so it always reflects current
## state (and survives a re-open after edits). Idempotent.
func open() -> void:
	_rebuild()
	visible = true


func close() -> void:
	visible = false


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	add_child(UI.screen_title("DEBUG", 150.0))

	# Each row is positioned manually so the menu reads top-to-bottom in fixed slots. The Debug node
	# may be absent under a bare-instance verify → fall back to the autoload's neutral defaults.
	var d := _dbg
	_next_y = FIRST_Y

	# --- Spawn toggles -------------------------------------------------------
	_add_row(UI.toggle_row("TOKENS", _tokens(d),
		func(on: bool) -> void:
			if d != null: d.set_tokens_enabled(on), ROW_W))
	_add_row(UI.toggle_row("ENEMIES", _enemies(d),
		func(on: bool) -> void:
			if d != null: d.set_enemies_enabled(on), ROW_W))
	_add_row(UI.toggle_row("GATES", _gates(d),
		func(on: bool) -> void:
			if d != null: d.set_gates_enabled(on), ROW_W))

	# --- Tuning steppers -----------------------------------------------------
	# Density: UNBOUNDED upward (max = INF). ×mult display.
	_add_row(UI.stepper_row("ENEMY DENSITY", _density(d), 0.25, 0.0, INF,
		_fmt_mult,
		func(v: float) -> void:
			if d != null: d.set_enemy_density_mult(v), ROW_W))
	# Speed: bounded mult.
	_add_row(UI.stepper_row("ENEMY SPEED", _speed(d), 0.25, 0.25, 5.0,
		_fmt_mult,
		func(v: float) -> void:
			if d != null: d.set_enemy_speed_mult(v), ROW_W))
	# Strength: bounded mult.
	_add_row(UI.stepper_row("ENEMY STRENGTH", _strength(d), 0.25, 0.25, 5.0,
		_fmt_mult,
		func(v: float) -> void:
			if d != null: d.set_enemy_strength_mult(v), ROW_W))
	# Firepower loss: allows 0 (no breach drain) up through a hard punish.
	_add_row(UI.stepper_row("FIREPOWER LOSS", _firepower(d), 0.25, 0.0, 5.0,
		_fmt_mult,
		func(v: float) -> void:
			if d != null: d.set_firepower_loss_mult(v), ROW_W))
	# Enemy cap: UNBOUNDED upward (max = INF) so the designer can push past 256 to the perf wall.
	_add_row(UI.stepper_row("ENEMY CAP", float(_cap(d)), 64.0, 0.0, INF,
		_fmt_int,
		func(v: float) -> void:
			if d != null: d.set_enemy_cap(int(round(v))), ROW_W))

	# --- Placeholders (write Debug, NO gameplay) -----------------------------
	_add_row(_placeholder_header())
	_add_row(UI.toggle_row("PASSTHROUGH (PH)", _pt_on(d),
		func(on: bool) -> void:
			if d != null: d.set_bullet_passthrough(on), ROW_W))
	_add_row(UI.stepper_row("PT LIFESPAN (PH)", _pt_life(d), 0.5, 0.0, 10.0,
		_fmt_secs,
		func(v: float) -> void:
			if d != null: d.set_bullet_passthrough_lifespan(v), ROW_W))
	_add_row(UI.stepper_row("ENEMY PT STR (PH)", _pt_estr(d), 0.25, 0.0, 5.0,
		_fmt_mult,
		func(v: float) -> void:
			if d != null: d.set_enemy_bullet_passthrough_strength(v), ROW_W))

	# --- Close ---------------------------------------------------------------
	var close_btn := UI.outline_button("CLOSE", Palette.ACCENT_CYAN_HUD, Vector2(660.0, 120.0), 28)
	UI.center_x(close_btn, 1760.0)
	add_child(close_btn)
	UI.hit_overlay(close_btn).pressed.connect(close)


## Place a row at the running Y cursor and advance it. _next_y is an INSTANCE member (not a captured
## local) so the cursor genuinely advances row-to-row — the fix for the all-rows-on-one-line bug.
func _add_row(row: Control) -> void:
	row.position = Vector2(ROW_X, _next_y)
	add_child(row)
	_next_y += ROW_GAP


## A faint section divider above the placeholder block (so they read as not-yet-live).
func _placeholder_header() -> Control:
	var c := Control.new()
	c.size = Vector2(ROW_W, 80.0)
	var lab := UI.text("— PLACEHOLDERS (no gameplay) —", Fonts.ui, 32, Palette.TEXT_DIM_HUD)
	lab.position = Vector2(0.0, 30.0)
	c.add_child(lab)
	return c


# --- Value readers (null-safe: live Debug accessor, else the neutral default) -----------------

func _tokens(d: Node) -> bool:
	return bool(d.tokens_on()) if d != null else true


func _enemies(d: Node) -> bool:
	return bool(d.enemies_on()) if d != null else true


func _gates(d: Node) -> bool:
	return bool(d.gates_on()) if d != null else true


func _density(d: Node) -> float:
	return float(d.density_mult()) if d != null else 1.0


func _speed(d: Node) -> float:
	return float(d.speed_mult()) if d != null else 1.0


func _strength(d: Node) -> float:
	return float(d.strength_mult()) if d != null else 1.0


func _firepower(d: Node) -> float:
	return float(d.firepower_loss()) if d != null else 1.0


func _cap(d: Node) -> int:
	return int(d.cap()) if d != null else 256


func _pt_on(d: Node) -> bool:
	return bool(d.bullet_passthrough) if d != null else false


func _pt_life(d: Node) -> float:
	return float(d.bullet_passthrough_lifespan) if d != null else 1.0


func _pt_estr(d: Node) -> float:
	return float(d.enemy_bullet_passthrough_strength) if d != null else 0.0


# --- Display formatters -----------------------------------------------------------------------

func _fmt_mult(v: float) -> String:
	return "%.2f×" % v


func _fmt_secs(v: float) -> String:
	return "%.1fs" % v


func _fmt_int(v: float) -> String:
	return str(int(round(v)))
