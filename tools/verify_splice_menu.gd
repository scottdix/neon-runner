extends SceneTree
## Headless verification for P4 — DEBUG MENU UI.
##   - The debug_menu overlay instances headless and builds every row on open().
##   - Each TOGGLE row's tap writes the matching Debug field; each STEPPER's −/+ writes (and clamps)
##     the matching Debug field; UNBOUNDED knobs (density/cap) push past their soft 256/neutral, and
##     FIREPOWER LOSS reaches 0.
##   - The 3 PLACEHOLDER rows write their Debug field but produce NO gameplay effect (we assert the
##     Debug value changed and that no spawn/gameplay seam was touched — there is none to touch).
##
## Drives the real controls: each row is an anonymous Control holding a Label (its name) plus the
## pill/stepper panels whose hit_overlay Buttons we press via emit_signal("pressed"). Bare autoload
## names won't compile under -s, so Debug is reached via root.get_node_or_null. Writes a verdict file
## the runner polls for. Run:
##   tools/run-headless.sh res://tools/verify_splice_menu.gd /tmp/verify_splice_menu_result.txt

const RESULT_PATH := "/tmp/verify_splice_menu_result.txt"


func _initialize() -> void:
	# Defer all asserts one frame: a Node add_child()ed in _initialize has _ready DEFERRED under -s.
	_run()


func _run() -> void:
	var lines: Array[String] = []
	var ok := true

	var dbg: Node = root.get_node_or_null("Debug")
	if dbg == null:
		lines.append("RESULT=FAIL (Debug autoload missing)")
		_write(lines)
		return

	# Clean slate: wipe any persisted debug.cfg, reload defaults.
	var cfg_path: String = String(dbg.CONFIG_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	dbg.load_debug()

	var menu_script: GDScript = load("res://assets/ui/debug_menu.gd")
	var menu: CanvasLayer = menu_script.new()
	root.add_child(menu)
	await process_frame              # let _ready fire (grabs the Debug node)
	menu.open()
	await process_frame              # let the rebuilt rows' _ready fire

	# --- helpers --------------------------------------------------------------
	# Find the anonymous row Control whose first Label child's text starts with `prefix`.
	var find_row := func(prefix: String) -> Control:
		for child in menu.get_children():
			if not (child is Control):
				continue
			var lbl := _first_label(child)
			if lbl != null and lbl.text.begins_with(prefix):
				return child
		return null

	# Collect the hit_overlay Buttons under a row, in tree order (toggle: 1; stepper: minus, plus).
	var buttons := func(row: Control) -> Array:
		var out: Array = []
		_collect_buttons(row, out)
		return out

	# 1) TOGGLES: tapping flips the matching Debug field.
	var toggles := {
		"TOKENS": "tokens_on",
		"ENEMIES": "enemies_on",
		"GATES": "gates_on",
	}
	for label in toggles:
		var row: Control = find_row.call(label)
		var btns: Array = buttons.call(row)
		var before: bool = bool(dbg.call(toggles[label]))
		if row == null or btns.size() < 1:
			lines.append("toggle %s -> MISSING row/button" % label)
			ok = false
			continue
		btns[0].emit_signal("pressed")
		var after: bool = bool(dbg.call(toggles[label]))
		var pass_t: bool = (after == (not before))
		lines.append("toggle %s %s->%s -> %s" % [label, str(before), str(after), "OK" if pass_t else "BAD"])
		ok = ok and pass_t

	# 2) STEPPERS: + raises, − lowers, writing the matching Debug field.
	#    [label, getter, expect_change_after_one_plus]
	var steppers := {
		"ENEMY DENSITY": "density_mult",
		"ENEMY SPEED": "speed_mult",
		"ENEMY STRENGTH": "strength_mult",
		"FIREPOWER LOSS": "firepower_loss",
	}
	for label in steppers:
		var row: Control = find_row.call(label)
		var btns: Array = buttons.call(row)
		if row == null or btns.size() < 2:
			lines.append("stepper %s -> MISSING row/buttons (%d)" % [label, btns.size()])
			ok = false
			continue
		var getter: String = steppers[label]
		var v0: float = float(dbg.call(getter))
		btns[1].emit_signal("pressed")   # plus
		var v1: float = float(dbg.call(getter))
		btns[0].emit_signal("pressed")   # minus -> back toward v0
		var v2: float = float(dbg.call(getter))
		var pass_s: bool = (v1 > v0) and is_equal_approx(v2, v0)
		lines.append("stepper %s %.2f->%.2f->%.2f -> %s" % [label, v0, v1, v2, "OK" if pass_s else "BAD"])
		ok = ok and pass_s

	# 2b) ENEMY CAP stepper writes the int cap and is UNBOUNDED upward (push past 256).
	var cap_row: Control = find_row.call("ENEMY CAP")
	var cap_btns: Array = buttons.call(cap_row)
	if cap_row != null and cap_btns.size() >= 2:
		var c0: int = int(dbg.cap())
		cap_btns[1].emit_signal("pressed")
		var c1: int = int(dbg.cap())
		var cap_ok: bool = (c1 > c0) and (c1 > 256)
		lines.append("ENEMY CAP %d->%d (unbounded past 256) -> %s" % [c0, c1, "OK" if cap_ok else "BAD"])
		ok = ok and cap_ok
	else:
		lines.append("ENEMY CAP -> MISSING")
		ok = false

	# 2c) FIREPOWER LOSS can reach 0 (steps of 0.25 from 1.0 -> 4 minus presses).
	var fp_row: Control = find_row.call("FIREPOWER LOSS")
	var fp_btns: Array = buttons.call(fp_row)
	if fp_row != null and fp_btns.size() >= 2:
		for i in 20:
			fp_btns[0].emit_signal("pressed")  # minus, clamps at 0
		var fp: float = float(dbg.firepower_loss())
		var fp_ok: bool = is_equal_approx(fp, 0.0)
		lines.append("FIREPOWER LOSS floor=%.2f (expect 0) -> %s" % [fp, "OK" if fp_ok else "BAD"])
		ok = ok and fp_ok
	else:
		lines.append("FIREPOWER LOSS floor -> MISSING")
		ok = false

	# 3) PLACEHOLDERS: write Debug values but NO gameplay effect. There is no spawn/gameplay seam that
	#    reads these (by design), so we assert (a) the Debug field changes and (b) the live spawn
	#    multipliers used by gameplay (density/speed/strength) are UNTOUCHED by the placeholder writes.
	var dens_before: float = float(dbg.density_mult())
	var speed_before: float = float(dbg.speed_mult())
	var strn_before: float = float(dbg.strength_mult())

	var ph_on_row: Control = find_row.call("PASSTHROUGH (PH)")
	var ph_on_btns: Array = buttons.call(ph_on_row)
	var ph_pass := true
	if ph_on_row != null and ph_on_btns.size() >= 1:
		var pt_before: bool = bool(dbg.bullet_passthrough)
		ph_on_btns[0].emit_signal("pressed")
		ph_pass = ph_pass and (bool(dbg.bullet_passthrough) == (not pt_before))
	else:
		ph_pass = false

	var ph_life_row: Control = find_row.call("PT LIFESPAN (PH)")
	var ph_life_btns: Array = buttons.call(ph_life_row)
	if ph_life_row != null and ph_life_btns.size() >= 2:
		var life0: float = float(dbg.bullet_passthrough_lifespan)
		ph_life_btns[1].emit_signal("pressed")
		ph_pass = ph_pass and (float(dbg.bullet_passthrough_lifespan) > life0)
	else:
		ph_pass = false

	var ph_estr_row: Control = find_row.call("ENEMY PT STR (PH)")
	var ph_estr_btns: Array = buttons.call(ph_estr_row)
	if ph_estr_row != null and ph_estr_btns.size() >= 2:
		var estr0: float = float(dbg.enemy_bullet_passthrough_strength)
		ph_estr_btns[1].emit_signal("pressed")
		ph_pass = ph_pass and (float(dbg.enemy_bullet_passthrough_strength) > estr0)
	else:
		ph_pass = false

	# No-gameplay: the placeholder writes left the live spawn mults exactly where they were.
	var no_effect: bool = is_equal_approx(float(dbg.density_mult()), dens_before) \
		and is_equal_approx(float(dbg.speed_mult()), speed_before) \
		and is_equal_approx(float(dbg.strength_mult()), strn_before)
	lines.append("placeholders write Debug=%s, no gameplay seam touched=%s -> %s"
		% [str(ph_pass), str(no_effect), "OK" if (ph_pass and no_effect) else "BAD"])
	ok = ok and ph_pass and no_effect

	# Cleanup: free the overlay + wipe our test config.
	menu.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


## First Label descendant (depth-first) of `n`, or null.
func _first_label(n: Node) -> Label:
	for c in n.get_children():
		if c is Label:
			return c
		var deep := _first_label(c)
		if deep != null:
			return deep
	return null


## Append every Button descendant of `n` to `out`, in tree order.
func _collect_buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_collect_buttons(c, out)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.flush()
		f.close()
	quit()
