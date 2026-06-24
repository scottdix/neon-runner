extends SceneTree
## Headless verification for AudioManager (#24 buses/players, #25 event→sfx, #61 adaptive).
##
## AudioManager keeps every SOUND-DESIGN + routing decision in PURE methods (synth, table
## builders, gate→sfx map, round-robin index, combo pitch) so we assert them with NO audio
## hardware and NO _ready (deferred under `-s`, never fires here). The player pool + buses are
## only built in _ready, so every playback path (play_sfx/play_music/set_intensity) is a
## GUARDED no-op on a bare .new() — the bus handlers must run clean. We assert:
##   - _synth returns a non-empty 16-bit mono WAV whose data.size() == frames*2 (exact bytes).
##   - _build_sfx_table() (PURE, not via _ready) holds all expected keys, each a non-empty WAV.
##   - _sfx_for_gate maps all four ops (add/multiply/subtract/divide) to the right key.
##   - _next_player_index advances + WRAPS over SFX_POOL_SIZE.
##   - _combo_pitch is monotonic non-decreasing in combo AND clamped to [1, 2].
##   - the music bed("game") has loop_mode == LOOP_FORWARD.
##   - the _on_* bus handlers + play_sfx/play_music/set_intensity run on a bare .new() w/o crash.
## Run:
##   tools/run-headless.sh res://tools/verify_audio.gd /tmp/verify_audio_result.txt

const RESULT_PATH := "/tmp/verify_audio_result.txt"


func _initialize() -> void:
	var lines: Array[String] = []
	var ok := true

	var ev: Node = root.get_node_or_null("Events")
	var st: Node = root.get_node_or_null("Settings")
	if ev == null or st == null:
		lines.append("RESULT=FAIL (autoloads missing: Events/Settings)"); _write(lines); return

	var AudioS: GDScript = load("res://autoload/audio_manager.gd")
	if AudioS == null:
		lines.append("RESULT=FAIL (audio_manager.gd missing)"); _write(lines); return

	var am: Node = AudioS.new()   # bare .new(): no _ready, no players, no buses

	# === 1) _synth produces an exact-size 16-bit mono WAV =====================
	var dur := 0.1
	var w: AudioStreamWAV = am.call("_synth", 440.0, dur, {})
	var expected_frames := int(maxf(dur, 0.001) * float(AudioS.MIX_RATE))
	lines.append("synth: is_wav=%s data=%d expected=%d fmt16=%s mono=%s" % [
		w is AudioStreamWAV, w.data.size(), expected_frames * 2,
		w.format == AudioStreamWAV.FORMAT_16_BITS, not w.stereo])
	if not (w is AudioStreamWAV) or w.data.size() <= 0 or w.data.size() != expected_frames * 2:
		lines.append("synth FAIL: WAV size mismatch (want frames*2 for 16-bit mono)"); ok = false
	if w.format != AudioStreamWAV.FORMAT_16_BITS or w.stereo:
		lines.append("synth FAIL: not 16-bit mono"); ok = false

	# A pitch-sweep + noise variant must also produce non-empty deterministic data.
	var w_sweep: AudioStreamWAV = am.call("_synth", 700.0, 0.08, {"wave": "saw", "end_freq": 120.0})
	var w_noise: AudioStreamWAV = am.call("_synth", 0.0, 0.05, {"wave": "noise"})
	if w_sweep.data.size() <= 0 or w_noise.data.size() <= 0:
		lines.append("synth FAIL: sweep/noise produced empty data"); ok = false

	# === 2) _build_sfx_table holds all keys, each a non-empty WAV =============
	var table: Dictionary = am.call("_build_sfx_table")
	var want_keys := ["gate_add", "gate_multiply", "gate_negative", "explosion", "combo",
		"ui_select", "milestone", "hijack_denied", "collapse"]
	var missing: Array[String] = []
	for k in want_keys:
		var s = table.get(k, null)
		if not (s is AudioStreamWAV) or (s as AudioStreamWAV).data.size() <= 0:
			missing.append(k)
	lines.append("sfx table: keys=%d want=%d missing=%s" % [table.size(), want_keys.size(), str(missing)])
	if not missing.is_empty():
		lines.append("sfx table FAIL: keys missing or empty"); ok = false

	# === 3) _sfx_for_gate maps all four ops ==================================
	var m_add := String(am.call("_sfx_for_gate", "add"))
	var m_mul := String(am.call("_sfx_for_gate", "multiply"))
	var m_sub := String(am.call("_sfx_for_gate", "subtract"))
	var m_div := String(am.call("_sfx_for_gate", "divide"))
	lines.append("gate map: add=%s multiply=%s subtract=%s divide=%s" % [m_add, m_mul, m_sub, m_div])
	if m_add != "gate_add" or m_mul != "gate_multiply" or m_sub != "gate_negative" or m_div != "gate_negative":
		lines.append("gate map FAIL: op→sfx mapping wrong"); ok = false

	# === 4) _next_player_index advances + wraps ==============================
	var seen: Array[int] = []
	for i in AudioS.SFX_POOL_SIZE:
		seen.append(int(am.call("_next_player_index")))
	var wrap: int = int(am.call("_next_player_index"))   # one past pool → wraps to 0
	var monotonic := true
	for i in AudioS.SFX_POOL_SIZE:
		if seen[i] != i:
			monotonic = false
	lines.append("index: first=%d last=%d wrap=%d (want 0, %d, 0)" % [
		seen[0], seen[AudioS.SFX_POOL_SIZE - 1], wrap, AudioS.SFX_POOL_SIZE - 1])
	if not monotonic or seen[0] != 0 or seen[AudioS.SFX_POOL_SIZE - 1] != AudioS.SFX_POOL_SIZE - 1 or wrap != 0:
		lines.append("index FAIL: player index did not advance/wrap across the pool"); ok = false

	# === 5) _combo_pitch monotonic non-decreasing + clamped ==================
	var prev := 0.0
	var mono_pitch := true
	var clamped := true
	for c in range(1, 60):
		var p := float(am.call("_combo_pitch", c))
		if p < prev:
			mono_pitch = false
		if p < 1.0 or p > 2.0:
			clamped = false
		prev = p
	lines.append("combo pitch: p(1)=%.3f p(2)=%.3f p(59)=%.3f mono=%s clamped=%s" % [
		float(am.call("_combo_pitch", 1)), float(am.call("_combo_pitch", 2)),
		float(am.call("_combo_pitch", 59)), mono_pitch, clamped])
	if not mono_pitch or not clamped:
		lines.append("combo pitch FAIL: not monotonic non-decreasing or out of [1,2]"); ok = false
	# combo 1 should be the base pitch (no escalation yet).
	if not is_equal_approx(float(am.call("_combo_pitch", 1)), 1.0):
		lines.append("combo pitch FAIL: combo 1 not base pitch 1.0"); ok = false

	# === 6) music bed loops forward ==========================================
	var beds: Dictionary = am.call("_build_music_beds")
	var game_bed = beds.get("game", null)
	var stem_bed = beds.get("stem", null)
	lines.append("music bed: game_is_wav=%s loop=%s stem_is_wav=%s" % [
		game_bed is AudioStreamWAV,
		(game_bed as AudioStreamWAV).loop_mode if game_bed is AudioStreamWAV else -1,
		stem_bed is AudioStreamWAV])
	if not (game_bed is AudioStreamWAV) or (game_bed as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD:
		lines.append("music bed FAIL: game bed not LOOP_FORWARD"); ok = false
	if not (stem_bed is AudioStreamWAV) or (stem_bed as AudioStreamWAV).data.size() <= 0:
		lines.append("music bed FAIL: stem bed missing/empty"); ok = false

	# === 7) handlers + playback run clean on a bare .new() (guarded no-ops) ===
	# No players/buses exist (no _ready), so every playback path must early-return cleanly.
	am.call("play_sfx", "explosion")
	am.call("play_sfx", "does_not_exist")          # unknown key → no-op
	am.call("play_music", "game")
	am.call("play_music", "no_such_track")
	am.call("set_intensity", 0.5)
	am.call("set_intensity", 1.5)                  # out-of-range → clamped, no-op
	am.call("stop_music")
	am.call("set_music_lowpass_from_battery", 30.0, 100.0)
	am.call("_on_gate_passed", "multiply", 2.0, 20)
	am.call("_on_gate_passed", "subtract", 5.0, 12)
	am.call("_on_enemy_destroyed", Vector2(300, 400), 50)
	am.call("_on_combo_updated", 5)
	am.call("_on_combo_updated", 1)                # not > 1 → no combo sting
	am.call("_on_gate_hijack_blocked", "add", Vector2(540, 960))
	am.call("_on_grid_collapsed")
	am.call("_on_milestone_reached", 500)
	am.call("_on_game_started")
	am.call("_on_run_completed", 12345, 600.0)
	am.call("_on_projectile_count_changed", 250)
	am.call("_on_glow_battery_changed", 40.0, 100.0)
	lines.append("handlers: all _on_* + play_sfx/play_music/set_intensity ran without error (no audio nodes)")

	lines.append("RESULT=%s" % ("PASS" if ok else "FAIL"))
	_write(lines)


func _write(lines: Array[String]) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
