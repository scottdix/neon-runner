extends SceneTree
## Headless verification for P2 — DEBUG AUTOLOAD.
##   - Debug autoload is registered (after Settings, before GameState).
##   - Defaults are NEUTRAL: all mults 1.0, toggles ON, cap 256, placeholders off/neutral.
##   - Each setter ROUND-TRIPS (set then read back), PERSISTS across a fresh load_debug(), and
##     emits Events.debug_changed.
##
## Uses the live Debug + Events autoloads via root.get_node_or_null (bare names won't compile under
## -s). Writes a verdict file the runner polls for (CLAUDE.md gotchas). Run:
##   tools/run-headless.sh res://tools/verify_splice_debug.gd /tmp/verify_splice_debug_result.txt

const RESULT_PATH := "/tmp/verify_splice_debug_result.txt"

var _signal_count: int = 0


func _on_debug_changed() -> void:
	_signal_count += 1


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var dbg: Node = root.get_node_or_null("Debug")
	var ev: Node = root.get_node_or_null("Events")
	if dbg == null or ev == null:
		lines.append("RESULT=FAIL (Debug=%s Events=%s autoload missing)" % [str(dbg), str(ev)])
		_write(lines)
		return

	# Start from a clean slate: wipe any persisted debug.cfg, reload defaults.
	var cfg_path: String = String(dbg.CONFIG_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	dbg.load_debug()

	ev.debug_changed.connect(_on_debug_changed)

	# 1) Defaults are NEUTRAL.
	var defaults_ok := true
	defaults_ok = defaults_ok and bool(dbg.tokens_on()) == true
	defaults_ok = defaults_ok and bool(dbg.enemies_on()) == true
	defaults_ok = defaults_ok and bool(dbg.gates_on()) == true
	defaults_ok = defaults_ok and is_equal_approx(float(dbg.density_mult()), 1.0)
	defaults_ok = defaults_ok and is_equal_approx(float(dbg.speed_mult()), 1.0)
	defaults_ok = defaults_ok and is_equal_approx(float(dbg.strength_mult()), 1.0)
	defaults_ok = defaults_ok and is_equal_approx(float(dbg.firepower_loss()), 1.0)
	defaults_ok = defaults_ok and int(dbg.cap()) == 256
	defaults_ok = defaults_ok and bool(dbg.bullet_passthrough) == false
	defaults_ok = defaults_ok and is_equal_approx(float(dbg.bullet_passthrough_lifespan), 1.0)
	defaults_ok = defaults_ok and is_equal_approx(float(dbg.enemy_bullet_passthrough_strength), 0.0)
	lines.append("defaults neutral -> %s" % ("OK" if defaults_ok else "BAD"))
	ok = ok and defaults_ok

	# 2) Every setter round-trips on the live node + emits debug_changed.
	_signal_count = 0
	dbg.set_tokens_enabled(false)
	dbg.set_enemies_enabled(false)
	dbg.set_gates_enabled(false)
	dbg.set_enemy_density_mult(2.5)
	dbg.set_enemy_speed_mult(0.5)
	dbg.set_enemy_strength_mult(3.0)
	dbg.set_firepower_loss_mult(0.25)
	dbg.set_enemy_cap(512)
	dbg.set_bullet_passthrough(true)
	dbg.set_bullet_passthrough_lifespan(2.0)
	dbg.set_enemy_bullet_passthrough_strength(0.75)

	var roundtrip_ok := true
	roundtrip_ok = roundtrip_ok and bool(dbg.tokens_on()) == false
	roundtrip_ok = roundtrip_ok and bool(dbg.enemies_on()) == false
	roundtrip_ok = roundtrip_ok and bool(dbg.gates_on()) == false
	roundtrip_ok = roundtrip_ok and is_equal_approx(float(dbg.density_mult()), 2.5)
	roundtrip_ok = roundtrip_ok and is_equal_approx(float(dbg.speed_mult()), 0.5)
	roundtrip_ok = roundtrip_ok and is_equal_approx(float(dbg.strength_mult()), 3.0)
	roundtrip_ok = roundtrip_ok and is_equal_approx(float(dbg.firepower_loss()), 0.25)
	roundtrip_ok = roundtrip_ok and int(dbg.cap()) == 512
	roundtrip_ok = roundtrip_ok and bool(dbg.bullet_passthrough) == true
	roundtrip_ok = roundtrip_ok and is_equal_approx(float(dbg.bullet_passthrough_lifespan), 2.0)
	roundtrip_ok = roundtrip_ok and is_equal_approx(float(dbg.enemy_bullet_passthrough_strength), 0.75)
	lines.append("setters round-trip -> %s" % ("OK" if roundtrip_ok else "BAD"))
	ok = ok and roundtrip_ok

	# 3) debug_changed fired once per changing setter (11 distinct changes).
	var emit_ok: bool = (_signal_count == 11)
	lines.append("debug_changed emits=%d (expect 11) -> %s" % [_signal_count, "OK" if emit_ok else "BAD"])
	ok = ok and emit_ok

	# 3b) A no-op setter does NOT emit (no change).
	_signal_count = 0
	dbg.set_enemy_density_mult(2.5)  # already 2.5
	dbg.set_tokens_enabled(false)    # already false
	var noop_ok: bool = (_signal_count == 0)
	lines.append("no-op setters silent emits=%d (expect 0) -> %s" % [_signal_count, "OK" if noop_ok else "BAD"])
	ok = ok and noop_ok

	# 4) PERSIST across a fresh load: blow away the in-memory values, reload from disk.
	dbg.tokens_enabled = true
	dbg.enemies_enabled = true
	dbg.gates_enabled = true
	dbg.enemy_density_mult = 1.0
	dbg.enemy_speed_mult = 1.0
	dbg.enemy_strength_mult = 1.0
	dbg.firepower_loss_mult = 1.0
	dbg.enemy_cap = 256
	dbg.bullet_passthrough = false
	dbg.bullet_passthrough_lifespan = 1.0
	dbg.enemy_bullet_passthrough_strength = 0.0
	dbg.load_debug()

	var persist_ok := true
	persist_ok = persist_ok and bool(dbg.tokens_on()) == false
	persist_ok = persist_ok and bool(dbg.enemies_on()) == false
	persist_ok = persist_ok and bool(dbg.gates_on()) == false
	persist_ok = persist_ok and is_equal_approx(float(dbg.density_mult()), 2.5)
	persist_ok = persist_ok and is_equal_approx(float(dbg.speed_mult()), 0.5)
	persist_ok = persist_ok and is_equal_approx(float(dbg.strength_mult()), 3.0)
	persist_ok = persist_ok and is_equal_approx(float(dbg.firepower_loss()), 0.25)
	persist_ok = persist_ok and int(dbg.cap()) == 512
	persist_ok = persist_ok and bool(dbg.bullet_passthrough) == true
	persist_ok = persist_ok and is_equal_approx(float(dbg.bullet_passthrough_lifespan), 2.0)
	persist_ok = persist_ok and is_equal_approx(float(dbg.enemy_bullet_passthrough_strength), 0.75)
	lines.append("values persist across fresh load_debug -> %s" % ("OK" if persist_ok else "BAD"))
	ok = ok and persist_ok

	# Cleanup: remove our test config so we don't leave the box dirty.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.flush()
		f.close()
	quit()
