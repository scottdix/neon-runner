extends Control
## 06 · SPLICE LAB (#68, docs/design/SCREENS.md) — the namesake screen, reached from Title.
## A node graph fuses an INPUT (base gun) + two MOD slots into a SPLICED OUTPUT, with an
## inventory drawer of mod cards below. The graph + inventory are DATA-DRIVEN off the
## SpliceLab autoload: INPUT shows `SpliceLab.BASE_INPUT`, the two slots reflect
## `slot_a`/`slot_b`, the inventory row renders a card per `SpliceLab.inventory` item, and the
## OUTPUT box previews `SpliceLab.splice()` when both slots are filled. Tapping a card equips
## it (`equip_next`) and re-renders; the SPLICE button commits the fusion. The screen never
## holds a ref to the lab — it rebuilds the dynamic layer on `Events.splice_changed`. Back
## returns to Title. Colours come from each mod's `accent_color()` / Palette (never hardcoded).

const UI := preload("res://assets/ui/ui_kit.gd")

## Container for the data-driven nodes (slots, inventory, output) — cleared + redrawn on each
## change so the static chrome (backdrop / title / back / cables) stays put.
var _dynamic: Control


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	add_child(UI.backdrop(Settings.amoled_mode))
	_build_static()
	_dynamic = Control.new()
	_dynamic.set_anchors_preset(PRESET_FULL_RECT)
	_dynamic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dynamic)
	Events.splice_changed.connect(_rebuild)
	_rebuild()


## The fixed chrome: back chevron, title, the connecting cables, and the INPUT node. Built once.
func _build_static() -> void:
	var cyan := Palette.ACCENT_CYAN_HUD
	var gold := Palette.MENU_GOLD_HUD
	var cx := UI.DESIGN.x * 0.5
	add_child(UI.back_button(SceneManager.goto_title))
	add_child(UI.screen_title("SPLICE LAB"))

	# INPUT -> (MOD A + MOD B) -> OUTPUT, joined by cables.
	_cable(cx, 400.0, 120.0, cyan)
	add_child(_node_box("INPUT", SpliceLab.BASE_INPUT, cyan,
		Rect2(cx - 250.0, 300.0, 500.0, 110.0), 36))
	_cable(cx, 740.0, 110.0, gold)


## Clear + redraw the data-driven layer (slots, inventory, output, splice button) from the
## current SpliceLab state. Called on `Events.splice_changed` and at first build.
func _rebuild() -> void:
	if _dynamic == null:
		return
	for c in _dynamic.get_children():
		c.queue_free()

	var cx := UI.DESIGN.x * 0.5
	var gold := Palette.MENU_GOLD_HUD

	# The two MOD slots reflect slot_a / slot_b.
	_dynamic.add_child(_slot_box("MOD A", SpliceLab.slot_a,
		Rect2(90.0, 540.0, 420.0, 190.0)))
	_dynamic.add_child(_slot_box("MOD B", SpliceLab.slot_b,
		Rect2(UI.DESIGN.x - 510.0, 540.0, 420.0, 190.0)))

	# OUTPUT — the spliced preview when both slots are filled, else a muted placeholder.
	_dynamic.add_child(_output_box(Rect2(cx - 330.0, 860.0, 660.0, 240.0)))

	# INVENTORY drawer — one tappable card per SpliceLab.inventory mod.
	var inv := UI.text("INVENTORY", Fonts.arcade, 24, Palette.TEXT_DIM_HUD)
	inv.position = Vector2(90.0, 1200.0)
	_dynamic.add_child(inv)
	for i in SpliceLab.inventory.size():
		_dynamic.add_child(_inventory_card(i, Vector2(90.0 + i * 270.0, 1260.0)))

	# SPLICE button — commits the fusion when both slots are filled.
	var splice := UI.glow_button("SPLICE", gold, Vector2(UI.DESIGN.x - 120.0, 140.0), 50)
	splice.position = Vector2(60.0, 1660.0)
	if not SpliceLab.can_splice():
		splice.modulate = UI.fade(UI.TEXT_BRIGHT, 0.45)
	_dynamic.add_child(splice)
	UI.hit_overlay(splice).pressed.connect(_on_splice_pressed)


## SPLICE tap: fuse when ready (which emits splice_changed → _rebuild refreshes OUTPUT).
func _on_splice_pressed() -> void:
	if SpliceLab.can_splice():
		SpliceLab.splice()


## A vertical cable segment centred at `x`, from `y` down `length` px.
func _cable(x: float, y: float, length: float, color: Color) -> void:
	var c := ColorRect.new()
	c.color = UI.fade(color, 0.7)
	c.size = Vector2(4.0, length)
	c.position = Vector2(x - 2.0, y)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


## A labelled graph node: small caption over a big value, inside an accented panel.
func _node_box(caption: String, value: String, accent: Color, rect: Rect2,
		value_size: int) -> Control:
	var p := UI.panel(rect.size, accent, 0.12, 2.0, 12)
	p.position = rect.position
	var cap := UI.text(caption, Fonts.arcade, 20, UI.fade(accent, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	cap.size.x = rect.size.x
	cap.position = Vector2(0.0, 18.0)
	p.add_child(cap)
	var val := UI.text(value, Fonts.display, value_size, UI.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	val.size.x = rect.size.x
	val.position = Vector2(0.0, 56.0)
	p.add_child(val)
	return p


## A MOD slot reflecting an inventory index: when filled, shows the equipped mod's op (big),
## its stat, and is accented in the mod's colour; when empty (-1) it is a dashed-feel muted
## panel reading "EMPTY".
func _slot_box(slot: String, idx: int, rect: Rect2) -> Control:
	if idx < 0 or idx >= SpliceLab.inventory.size():
		var accent := Palette.TEXT_DIM_HUD
		var p := UI.panel(rect.size, UI.fade(accent, 0.5), 0.03, 2.0, 12)
		p.position = rect.position
		var sl := UI.text(slot, Fonts.arcade, 20, UI.fade(accent, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
		sl.size.x = rect.size.x
		sl.position = Vector2(0.0, 18.0)
		p.add_child(sl)
		var em := UI.text("EMPTY", Fonts.arcade, 30, UI.fade(accent, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
		em.size.x = rect.size.x
		em.position = Vector2(0.0, 80.0)
		p.add_child(em)
		return p

	var mod = SpliceLab.inventory[idx]
	var accent: Color = mod.accent_color()
	var p := UI.panel(rect.size, accent, 0.10, 2.0, 12)
	p.position = rect.position
	var sl := UI.text(slot, Fonts.arcade, 20, UI.fade(accent, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	sl.size.x = rect.size.x
	sl.position = Vector2(0.0, 18.0)
	p.add_child(sl)
	var o := UI.text(mod.op, Fonts.arcade, 52, UI.TEXT_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	o.size.x = rect.size.x
	o.position = Vector2(0.0, 64.0)
	p.add_child(o)
	var st := UI.text(mod.stat, Fonts.mono, 28, UI.fade(accent, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	st.size.x = rect.size.x
	st.position = Vector2(0.0, 140.0)
	p.add_child(st)
	return p


## The SPLICED OUTPUT box: a gold-glow preview of `SpliceLab.splice()` when both slots are
## filled, else a muted placeholder prompting the player to fill the slots.
func _output_box(rect: Rect2) -> Control:
	var cx := rect.position.x
	if not SpliceLab.can_splice():
		var muted := Palette.TEXT_DIM_HUD
		var box := _node_box("SPLICED OUTPUT", "—", UI.fade(muted, 0.6), rect, 60)
		var hint := UI.text("EQUIP TWO MODS", Fonts.mono, 30, UI.fade(muted, 0.9),
			HORIZONTAL_ALIGNMENT_CENTER)
		hint.size.x = rect.size.x
		hint.position = Vector2(cx, rect.position.y + 160.0)
		_dynamic.add_child(hint)
		return box

	# Compute the preview WITHOUT committing/emitting (we are inside a splice_changed rebuild).
	var preview: Dictionary = SpliceLab.preview_output()
	var gold := Palette.MENU_GOLD_HUD
	var box := _node_box("SPLICED OUTPUT", preview.get("name", ""), gold, rect, 60)
	var sub := UI.text(preview.get("detail", ""), Fonts.mono, 30, Palette.TEXT_MUTED_HUD,
		HORIZONTAL_ALIGNMENT_CENTER)
	sub.size.x = rect.size.x
	sub.position = Vector2(cx, rect.position.y + 160.0)
	_dynamic.add_child(sub)
	return box


## An inventory card for `SpliceLab.inventory[i]`: name + accent orb, accented in the mod's
## colour. Tapping equips it into the next empty slot (which re-renders via splice_changed).
func _inventory_card(i: int, pos: Vector2) -> Control:
	var mod = SpliceLab.inventory[i]
	var accent: Color = mod.accent_color()
	var card := UI.panel(Vector2(250.0, 280.0), UI.fade(accent, 0.5), 0.05, 2.0, 12)
	card.position = pos
	var icon := UI.orb(20.0, accent)
	icon.position = Vector2(28.0, 28.0)
	card.add_child(icon)
	var cl := UI.text(mod.mod_name.replace(" ", "\n"), Fonts.arcade, 22, accent)
	cl.position = Vector2(28.0, 160.0)
	card.add_child(cl)
	var op := UI.text("%s %s" % [mod.op, mod.stat], Fonts.mono, 22, UI.fade(accent, 0.95))
	op.position = Vector2(28.0, 100.0)
	card.add_child(op)
	UI.hit_overlay(card).pressed.connect(_on_card_pressed.bind(i))
	return card


## Inventory card tap: equip into the next empty slot.
func _on_card_pressed(i: int) -> void:
	SpliceLab.equip_next(i)
