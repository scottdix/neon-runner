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
	# Give the layer an EXPLICIT full-design size, not just anchors: a plain Control parent
	# doesn't re-sort anchored children the way a Container does, so on device the layer could
	# come up sized (0,0). Its children (cards + SPLICE button) are positioned in DESIGN space,
	# so the layer must span the full design rect for their hit-test rects to resolve.
	_dynamic.set_anchors_preset(PRESET_FULL_RECT)
	_dynamic.size = UI.DESIGN
	# IGNORE (transparent passthrough): the full-rect layer must NOT be the pick target —
	# it sits on top of the back chevron, and PASS/STOP here would swallow every tap before
	# it reached the chrome below. IGNORE still hit-tests the layer's CHILDREN (the cards +
	# SPLICE button), so the interactive controls inside keep receiving taps.
	_dynamic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dynamic)
	Events.splice_changed.connect(_rebuild)
	# #78 draft shop: the shelf / wallet / drafted-perk state mutate through SpliceLab and announce
	# on draft_changed (Events-bus decoupling — the screen never refs the lab). Re-render on it too.
	Events.draft_changed.connect(_rebuild)
	# Stock a fresh shelf on entry so the draft is always populated when the screen opens (a pick
	# re-stocks; SKIP clears it). Only when empty so re-entering doesn't wipe a locked/rerolled shelf.
	if SpliceLab.shelf.is_empty():
		SpliceLab.stock()
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
	inv.position = Vector2(90.0, 1150.0)
	_dynamic.add_child(inv)
	for i in SpliceLab.inventory.size():
		_dynamic.add_child(_inventory_card(i, Vector2(90.0 + i * 270.0, 1200.0)))

	# SPLICE button — commits the fusion when both slots are filled.
	var splice := UI.glow_button("SPLICE", gold, Vector2(540.0, 120.0), 46)
	splice.position = Vector2(60.0, 1740.0)
	splice.mouse_filter = Control.MOUSE_FILTER_STOP   # solid pick target inside the IGNORE passthrough layer
	if not SpliceLab.can_splice():
		splice.modulate = UI.fade(UI.TEXT_BRIGHT, 0.45)
	_dynamic.add_child(splice)
	UI.hit_overlay(splice).pressed.connect(_on_splice_pressed)

	# #78 DRAFT SHOP — the between-run RNG perk shelf, rendered into the same dynamic layer.
	_build_draft_section()


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
	var card := UI.panel(Vector2(250.0, 150.0), UI.fade(accent, 0.5), 0.05, 2.0, 12)
	card.position = pos
	card.mouse_filter = Control.MOUSE_FILTER_STOP   # solid pick target inside the IGNORE passthrough layer
	var icon := UI.orb(16.0, accent)
	icon.position = Vector2(24.0, 22.0)
	card.add_child(icon)
	var op := UI.text("%s %s" % [mod.op, mod.stat], Fonts.mono, 20, UI.fade(accent, 0.95))
	op.position = Vector2(72.0, 26.0)
	card.add_child(op)
	var cl := UI.text(mod.mod_name.replace(" ", "\n"), Fonts.arcade, 20, accent)
	cl.position = Vector2(24.0, 78.0)
	card.add_child(cl)
	UI.hit_overlay(card).pressed.connect(_on_card_pressed.bind(i))
	return card


## Inventory card tap: equip into the next empty slot.
func _on_card_pressed(i: int) -> void:
	SpliceLab.equip_next(i)


# --- #78 DRAFT SHOP ----------------------------------------------------------

## Y origin of the draft band (header + offer row + reroll/skip controls).
const DRAFT_TOP := 1390.0
## One draft offer card's size — three sit in a row across the design width.
const DRAFT_CARD := Vector2(300.0, 230.0)


## Render the between-run RNG perk draft: a wallet readout, the DRAFT_SHELF_SIZE offer cards
## (tap = PICK, the LOCK pip freezes a slot across rerolls — Brotato), and a REROLL (escalating
## token cost) + SKIP control row. All state lives in SpliceLab; this redraws on draft_changed.
func _build_draft_section() -> void:
	var gold := Palette.MENU_GOLD_HUD
	var dim := Palette.TEXT_DIM_HUD

	# Section header + the persistent wallet (earned tokens available to spend on rerolls).
	var hdr := UI.text("DRAFT", Fonts.arcade, 26, dim)
	hdr.position = Vector2(90.0, DRAFT_TOP)
	_dynamic.add_child(hdr)
	var wallet := UI.text("◈ %s" % UI.commafy(int(SpliceLab.tokens)), Fonts.mono, 28, gold,
		HORIZONTAL_ALIGNMENT_RIGHT)
	wallet.size.x = 360.0
	wallet.position = Vector2(UI.DESIGN.x - 450.0, DRAFT_TOP - 4.0)
	_dynamic.add_child(wallet)

	var row_y := DRAFT_TOP + 44.0
	if SpliceLab.shelf.is_empty():
		# SKIPped (or never stocked) — invite a re-stock so the shelf is never a dead end.
		var none := UI.text("NO OFFERS — STOCK A SHELF", Fonts.mono, 26, UI.fade(dim, 0.9))
		none.position = Vector2(90.0, row_y + 40.0)
		_dynamic.add_child(none)
		var stock := UI.outline_button("STOCK", Palette.ACCENT_CYAN_HUD, Vector2(260.0, 96.0), 30)
		stock.position = Vector2(90.0, row_y + 110.0)
		stock.mouse_filter = Control.MOUSE_FILTER_STOP
		_dynamic.add_child(stock)
		UI.hit_overlay(stock).pressed.connect(SpliceLab.stock)
		return

	# Centre the offer row: N cards with even gaps across the design width.
	var n: int = SpliceLab.shelf.size()
	var gap := 24.0
	var total := n * DRAFT_CARD.x + (n - 1) * gap
	var x0 := (UI.DESIGN.x - total) * 0.5
	for i in n:
		_dynamic.add_child(_draft_card(i, Vector2(x0 + i * (DRAFT_CARD.x + gap), row_y)))

	# REROLL (escalating cost, disabled when unaffordable) + SKIP control row.
	var ctl_y := row_y + DRAFT_CARD.y + 18.0
	var cost: int = SpliceLab.reroll_cost()
	var afford: bool = int(SpliceLab.tokens) >= cost
	var reroll := UI.glow_button("REROLL  ◈%d" % cost, gold, Vector2(420.0, 100.0), 32)
	reroll.position = Vector2(90.0, ctl_y)
	reroll.mouse_filter = Control.MOUSE_FILTER_STOP
	if not afford:
		reroll.modulate = UI.fade(UI.TEXT_BRIGHT, 0.45)
	_dynamic.add_child(reroll)
	if afford:
		UI.hit_overlay(reroll).pressed.connect(_on_reroll_pressed)

	var skip := UI.outline_button("SKIP", dim, Vector2(300.0, 100.0), 30)
	skip.position = Vector2(UI.DESIGN.x - 390.0, ctl_y)
	skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_dynamic.add_child(skip)
	UI.hit_overlay(skip).pressed.connect(_on_skip_pressed)


## One draft offer slot: the perk's name/effect, accented in its colour, with a LOCK pip that
## freezes the slot across rerolls. Tapping the card body PICKS the perk (free — the reward);
## tapping the LOCK pip toggles the freeze (Brotato). A locked slot reads with a bright border.
func _draft_card(i: int, pos: Vector2) -> Control:
	var offer = SpliceLab.shelf[i]
	if offer == null or offer.perk == null:
		var empty := UI.panel(DRAFT_CARD, UI.fade(Palette.TEXT_DIM_HUD, 0.4), 0.03, 2.0, 12)
		empty.position = pos
		return empty
	var perk = offer.perk
	var accent: Color = perk.accent_color()
	var is_locked: bool = i < SpliceLab.locked.size() and SpliceLab.locked[i]
	var card := UI.panel(DRAFT_CARD, accent, 0.12 if is_locked else 0.06, 3.0 if is_locked else 2.0, 12)
	card.position = pos
	card.mouse_filter = Control.MOUSE_FILTER_STOP   # whole card is the PICK target

	var orb := UI.orb(16.0, accent)
	orb.position = Vector2(24.0, 22.0)
	card.add_child(orb)
	var nm := UI.text(perk.perk_name.replace(" ", "\n"), Fonts.arcade, 24, accent)
	nm.position = Vector2(24.0, 64.0)
	card.add_child(nm)
	var fx := UI.text(_effect_label(perk), Fonts.mono, 22, UI.fade(accent, 0.95))
	fx.position = Vector2(24.0, DRAFT_CARD.y - 56.0)
	fx.size.x = DRAFT_CARD.x - 48.0
	card.add_child(fx)
	# PICK on the card body.
	UI.hit_overlay(card).pressed.connect(_on_pick_pressed.bind(i))

	# LOCK pip (top-right) — toggles the freeze. A small solid button OVER the card-body hit
	# overlay so it intercepts its own taps before the PICK overlay sees them.
	var lock := UI.panel(Vector2(64.0, 64.0),
		gold_if_locked(is_locked, accent), 0.22 if is_locked else 0.06, 2.0, 10)
	lock.position = Vector2(DRAFT_CARD.x - 80.0, 16.0)
	lock.mouse_filter = Control.MOUSE_FILTER_STOP
	var lk := UI.text("L" if is_locked else "l", Fonts.arcade, 28,
		UI.TEXT_BRIGHT if is_locked else UI.fade(accent, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	lk.set_anchors_preset(Control.PRESET_FULL_RECT)
	lk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.add_child(lk)
	card.add_child(lock)
	UI.hit_overlay(lock).pressed.connect(_on_lock_pressed.bind(i))
	return card


## The locked pip's accent: gold when frozen, the perk accent otherwise.
func gold_if_locked(is_locked: bool, accent: Color) -> Color:
	return Palette.MENU_GOLD_HUD if is_locked else accent


## A compact human label for a perk's fold effect, e.g. "×1.5 MAGNET" / "+4 SHOTS".
func _effect_label(perk) -> String:
	var e: Dictionary = perk.effect
	var op := String(e.get("op", "*"))
	var sym := "×" if (op.begins_with("*") or op.begins_with("x") or op.begins_with("X")) else "+"
	var mag := float(e.get("magnitude", 1.0))
	var mag_str := ("%d" % int(mag)) if (sym == "+" or mag == floor(mag)) else ("%.2f" % mag)
	return "%s%s %s" % [sym, mag_str, String(e.get("stat", ""))]


## PICK the offer at `i`: carry its perk (free) and re-stock (SpliceLab emits draft_changed).
func _on_pick_pressed(i: int) -> void:
	SpliceLab.pick(i)


## Toggle the LOCK on slot `i` (freezes it across rerolls).
func _on_lock_pressed(i: int) -> void:
	SpliceLab.lock(i)


## REROLL the unlocked slots for the escalating token cost.
func _on_reroll_pressed() -> void:
	SpliceLab.reroll()


## SKIP the draft (take nothing, clear the shelf).
func _on_skip_pressed() -> void:
	SpliceLab.skip()
