extends SceneTree
## Headless verification for the Events autoload (#3).
##
## Buffering-proof: Godot block-buffers stdout to a file and then hangs at
## shutdown on this mac-mini, so print()ed markers never reach the log. Instead
## we write the verdict to an ABSOLUTE path via FileAccess (flushed on close,
## BEFORE quit), and poll for that file.
##
## Run:  godot --headless -s res://tools/verify_events.gd --path <project>
## Poll: wait for /tmp/verify_events_result.txt to exist, then read it.

const RESULT_PATH := "/tmp/verify_events_result.txt"

func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	# 1) Does the script parse + instantiate? (independent of autoload registration)
	var scr: Variant = load("res://autoload/events.gd")
	if scr == null or not (scr is GDScript):
		lines.append("script_load=FAIL (events.gd did not load as GDScript)")
		ok = false
	else:
		lines.append("script_load=OK")
		var inst: Object = scr.new()
		var expected := [
			"gate_passed", "gate_spawned",
			"game_started", "game_over",
			"score_changed", "multiplier_changed", "combo_updated",
			"spawn_particles", "trigger_screen_shake", "trigger_grid_ripple",
		]
		var missing: Array[String] = []
		for s in expected:
			if not inst.has_signal(s):
				missing.append(s)
		if missing.is_empty():
			lines.append("signals=OK (all %d declared)" % expected.size())
		else:
			lines.append("signals=FAIL missing=[%s]" % ", ".join(missing))
			ok = false
		if inst is RefCounted:
			pass # auto-freed
		else:
			(inst as Node).free()

	# 2) Is it registered as the 'Events' autoload at /root? (info; may be absent in -s mode)
	var node := root.get_node_or_null("Events")
	lines.append("autoload_node=%s" % ("present" if node != null else "absent(in -s mode)"))

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))

	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("\n".join(lines))  # best-effort; may be buffered
	quit(0 if ok else 1)
