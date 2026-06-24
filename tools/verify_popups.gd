extends SceneTree
## Headless verification for #27 — SCORE POPUP LAYER (floating "+N" / "+N x2" rise-and-fade numbers).
##
## ScorePopupLayer keeps every which-text / which-colour / how-big / which-slot decision in PURE
## methods so we can assert them with NO pool, NO tree, NO GPU (the Label pool is built only in
## _ready, which is DEFERRED under `-s` and never fires here — so _spawn is a guarded no-op and the
## bus handlers run clean on a bare .new()). We assert:
##   - _format: mult <= 1.0 → "+100"; mult > 1.0 → "+100 x2" (integer-part xN tag).
##   - _next_index() advances and WRAPS at POOL_SIZE.
##   - _color_for is DISTINCT for combo vs normal vs gain (so the three tell apart at a glance).
##   - _scale_for clamps to [SCALE_MIN, SCALE_MAX] and GROWS with points.
##   - enemy_destroyed / player_steered handlers run without error on a pool-less .new() (no crash).
## Run:
##   tools/run-headless.sh res://tools/verify_popups.gd /tmp/verify_popups_result.txt

const RESULT_PATH := "/tmp/verify_popups_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	var pal: Node = root.get_node_or_null("Palette")
	var gs: Node = root.get_node_or_null("GameState")
	if ev == null or pal == null or gs == null:
		lines.append("RESULT=FAIL (autoloads missing: Events/Palette/GameState)"); _write(lines); return

	var PopupS: GDScript = load("res://assets/ui/score_popup_layer.gd")
	if PopupS == null:
		lines.append("RESULT=FAIL (score_popup_layer.gd missing)"); _write(lines); return

	var sp: Node2D = PopupS.new()   # bare .new(): no _ready, no pool, no tree

	# === 1) _format — combo suffix ===========================================
	var f_plain: String = sp.call("_format", 100, 1.0)
	var f_combo: String = sp.call("_format", 100, 2.0)
	var f_combo3: String = sp.call("_format", 250, 3.7)   # integer part → x3, not x3.7
	lines.append("format: mult1.0='%s' mult2.0='%s' mult3.7='%s' (want '+100','+100 x2','+250 x3')" % [
		f_plain, f_combo, f_combo3])
	if f_plain != "+100":
		lines.append("format FAIL: no-combo did not render '+100'"); ok = false
	if f_combo != "+100 x2":
		lines.append("format FAIL: combo did not render '+100 x2'"); ok = false
	if f_combo3 != "+250 x3":
		lines.append("format FAIL: combo did not use the multiplier integer part"); ok = false

	# === 2) _next_index advances + wraps =====================================
	var seen: Array[int] = []
	for i in PopupS.POOL_SIZE:
		seen.append(int(sp.call("_next_index")))
	var wrap: int = int(sp.call("_next_index"))   # one past the pool → wraps to seen[0]
	var monotonic := true
	for i in PopupS.POOL_SIZE:
		if seen[i] != i:
			monotonic = false
	lines.append("index: first=%d last=%d wrap=%d (want 0, %d, 0)" % [
		seen[0], seen[PopupS.POOL_SIZE - 1], wrap, PopupS.POOL_SIZE - 1])
	if not monotonic or seen[0] != 0 or seen[PopupS.POOL_SIZE - 1] != PopupS.POOL_SIZE - 1 or wrap != 0:
		lines.append("index FAIL: slot index did not advance/wrap across the pool"); ok = false

	# === 3) _color_for — distinct per kind ===================================
	var c_combo: Color = sp.call("_color_for", PopupS.KIND_COMBO)
	var c_normal: Color = sp.call("_color_for", PopupS.KIND_NORMAL)
	var c_gain: Color = sp.call("_color_for", PopupS.KIND_GAIN)
	lines.append("color: combo==COMBO_ORANGE_HUD=%s normal==HUD_WHITE=%s gain==MENU_MINT_HUD=%s" % [
		c_combo == Palette.COMBO_ORANGE_HUD, c_normal == Palette.HUD_WHITE, c_gain == Palette.MENU_MINT_HUD])
	if c_combo != Palette.COMBO_ORANGE_HUD:
		lines.append("color FAIL: combo kill not COMBO_ORANGE_HUD"); ok = false
	if c_normal != Palette.HUD_WHITE:
		lines.append("color FAIL: normal kill not HUD_WHITE"); ok = false
	if c_combo == c_normal or c_combo == c_gain or c_normal == c_gain:
		lines.append("color FAIL: combo/normal/gain are not three distinct colours"); ok = false

	# === 4) _scale_for — clamps + grows with points ==========================
	var s_chip: float = sp.call("_scale_for", 10)      # small kill → at/near floor
	var s_fat: float = sp.call("_scale_for", 200)      # fat kill → bigger
	var s_huge: float = sp.call("_scale_for", 100000)  # absurd → clamped to ceiling
	lines.append("scale: chip=%.3f fat=%.3f huge=%.3f (want floor<=chip<fat<=ceil, huge==ceil)" % [
		s_chip, s_fat, s_huge])
	if s_chip < PopupS.SCALE_MIN - 0.001 or s_huge > PopupS.SCALE_MAX + 0.001:
		lines.append("scale FAIL: scale escaped [SCALE_MIN, SCALE_MAX]"); ok = false
	if not (s_fat > s_chip):
		lines.append("scale FAIL: scale did not grow with points"); ok = false
	if absf(s_huge - PopupS.SCALE_MAX) > 0.001:
		lines.append("scale FAIL: huge points did not clamp to SCALE_MAX"); ok = false

	# === 5) handlers run clean (pool-less → guarded no-op on the spawn path) ==
	# set_crossing_y + the steer track feed any gate-gain position; the handlers must resolve a popup
	# and reach the guarded _spawn without erroring (no pool → nothing shown, no crash).
	sp.call("set_crossing_y", 1680.0)
	sp.call("_on_player_steered", 720.0, 0.66)             # move ship x
	sp.call("_on_enemy_destroyed", Vector2(300, 400), 50)  # reads GameState.combo_multiplier
	sp.call("_on_enemy_destroyed", Vector2(640, 900), 300)
	sp.call("_on_gate_gain", 120)
	lines.append("handlers: enemy_destroyed/player_steered/gate_gain ran without error (no pool, no GPU)")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
