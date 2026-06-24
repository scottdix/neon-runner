extends Node
## AudioManager — procedural SFX + music bed + fake-adaptive intensity layer
## (autoload singleton: `AudioManager`). Issues #24 (bus/player scaffolding),
## #25 (event→sfx wiring), #61 (battery-driven DSP + intensity stem).
##
## WHY PROCEDURAL: the repo ships ZERO audio assets (audio/sfx, audio/music are
## empty). Rather than commit binaries, every sound is SYNTHESISED in code into an
## AudioStreamWAV at startup — same philosophy as Palette/UiKit "build the resource
## in code, keep the decision pure". This keeps the repo asset-free and makes the
## whole synth path UNIT-TESTABLE with no GPU/audio hardware.
##
## ARCHITECTURE (mirrors Haptics/GameState):
##   - All sound DESIGN lives in PURE methods (_synth, _build_sfx_table,
##     _sfx_for_gate, _next_player_index, _combo_pitch) callable on a bare
##     Script.new() with NO audio server, NO child players, NO _ready. The verify
##     script asserts on exactly these.
##   - _ready does the only hardware/tree-touching work: create the Music/SFX buses,
##     spawn the AudioStreamPlayer pool, and wire() the bus handlers.
##   - Every playback method (play_sfx/play_music/set_intensity) GUARDS on its node
##     being non-null, so a headless `.new()` instance no-ops instead of crashing.
##   - wire() is public + idempotent (is_connected-guarded) so a verify run can
##     connect handlers explicitly even though autoload _ready is deferred under `-s`.
##
## BUSES (#24/#61): "Master" → "Music" + "SFX". The Music bus carries an
## AudioEffectLowPassFilter (open by default); #61 lowers its cutoff as the Glow
## Battery drains, muffling the bed under pressure — a subtle adaptive-DSP hook.
##
## INTENSITY (#61 "fake adaptive"): a single extra "stem" AudioStreamPlayer on the
## Music bus is crossfaded up as the projectile swarm grows — more swarm, more layer.

# --- Synthesis constants (PURE; no hardware) ---------------------------------
const MIX_RATE := 22050                       # mono 22.05kHz — plenty for chiptune blips, small WAVs
const SFX_POOL_SIZE := 8                       # round-robined SFX players so concurrent hits don't stomp

# Default low-pass cutoff for the Music bus (Hz). "Open" = bed unmuffled. #61 lowers
# this toward MUSIC_LP_MIN as the battery empties, then restores it as it refills.
const MUSIC_LP_OPEN := 20000.0
const MUSIC_LP_MIN := 900.0

# Music fade: target-volume lerp speed (per second) used in _process.
const MUSIC_FADE_SPEED := 3.0
# Silent floor in dB — what a faded-out / disabled music player sits at.
const SILENCE_DB := -60.0
# Stem (intensity) ceiling in dB at full intensity; -inf-ish floor at zero.
const STEM_MAX_DB := -6.0

# --- Beat clock (#61 music-reactive grid) ------------------------------------
# The "game" bed is GAME_BED_NOTES bass notes arpeggiated over GAME_BED_DUR seconds
# (see _build_music_beds → _bed). The beat clock ticks ONE beat per note, so every emitted
# beat lands exactly on a bass-note onset of the actual playing bed — the grid pulses to the
# real bass envelope by construction, no FFT/spectrum read needed (and it stays deterministic
# + headless-testable). BEATS_PER_BAR == GAME_BED_NOTES so beat 0 of each loop is the bar
# downbeat (the bass root), emphasised over the off-beats.
const GAME_BED_DUR := 2.0
const GAME_BED_NOTES := 3
const BEATS_PER_BAR := GAME_BED_NOTES
const BEAT_DOWN_STRENGTH := 1.0       # bar downbeat (bass root) — the strong pulse
const BEAT_OFF_STRENGTH := 0.55       # off-beats — a gentler breath

# --- Runtime nodes (built in _ready; null on a bare .new()) ------------------
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx: int = 0
var _music_player: AudioStreamPlayer = null
var _stem_player: AudioStreamPlayer = null

# Music fade state (lerped in _process toward the target).
var _music_target_db: float = SILENCE_DB
var _music_current_db: float = SILENCE_DB
# Stem (intensity) fade state.
var _stem_target_db: float = SILENCE_DB
var _stem_current_db: float = SILENCE_DB

# Beat clock state (#61). Only ticks while the driving game bed is the active music
# (set in play_music); _process advances the phase and emits Events.music_beat per onset.
var _beat_enabled: bool = false
var _beat_phase: float = 0.0          # seconds into the current beat (wraps at the period)
var _beat_index: int = 0              # beats since the bed started (index % BEATS_PER_BAR → bar pos)

# The synthesised sound table + named music beds (built once; pure builders below).
var _sfx: Dictionary = {}                      # name -> AudioStreamWAV
var _music_beds: Dictionary = {}               # track -> AudioStreamWAV (looped)


func _ready() -> void:
	# Hardware/tree wiring ONLY (deferred under headless `-s`; the pure table is also
	# (re)built here so the live singleton has it without waiting on a test).
	_sfx = _build_sfx_table()
	_music_beds = _build_music_beds()
	_ensure_buses()
	_build_players()
	wire()


func _process(delta: float) -> void:
	# Smooth music + stem volume toward their targets (the fade). Guarded: no players → nothing.
	if _music_player != null and not is_equal_approx(_music_current_db, _music_target_db):
		_music_current_db = move_toward(_music_current_db, _music_target_db, MUSIC_FADE_SPEED * 60.0 * delta)
		_music_player.volume_db = _music_current_db
	if _stem_player != null and not is_equal_approx(_stem_current_db, _stem_target_db):
		_stem_current_db = move_toward(_stem_current_db, _stem_target_db, MUSIC_FADE_SPEED * 60.0 * delta)
		_stem_player.volume_db = _stem_current_db
	# Beat clock (#61): while the game bed plays, advance the phase and fire a music_beat on each
	# bass-note onset crossed this frame. GridFloor catches it as a pulse. PURE advance below.
	if _beat_enabled:
		var step: Dictionary = _advance_beat_phase(_beat_phase, delta, _beat_period())
		_beat_phase = float(step["phase"])
		for _i in int(step["fired"]):
			Events.music_beat.emit(_beat_strength(_beat_index))
			_beat_index += 1


# --- Bus / player construction (hardware; guarded, idempotent) ---------------

## Idempotently create the "Music" and "SFX" buses routed to "Master", and hang an
## AudioEffectLowPassFilter (open) on Music for #61. Checks by NAME first so a second
## call (or an editor that already added them) never double-adds. AudioServer is a
## global singleton (present even headless), but we guard defensively regardless.
func _ensure_buses() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, "Music")
		AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_index("SFX") < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, "SFX")
		AudioServer.set_bus_send(i, "Master")
	# Low-pass on Music (the #61 DSP hook) — add only if absent.
	var mbus := AudioServer.get_bus_index("Music")
	if mbus >= 0 and not _bus_has_lowpass(mbus):
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = MUSIC_LP_OPEN
		AudioServer.add_bus_effect(mbus, lp)


## True if the bus already carries an AudioEffectLowPassFilter (avoid double-adding).
func _bus_has_lowpass(bus_idx: int) -> bool:
	for e in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, e) is AudioEffectLowPassFilter:
			return true
	return false


## Build the SFX player pool + the music + stem players, parented to this node, each
## routed to its bus. Guarded so a re-call doesn't double-build.
func _build_players() -> void:
	if _sfx_players.is_empty():
		for i in SFX_POOL_SIZE:
			var p := AudioStreamPlayer.new()
			p.bus = "SFX"
			add_child(p)
			_sfx_players.append(p)
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.bus = "Music"
		_music_player.volume_db = SILENCE_DB
		add_child(_music_player)
	if _stem_player == null:
		_stem_player = AudioStreamPlayer.new()
		_stem_player.bus = "Music"
		_stem_player.volume_db = SILENCE_DB
		add_child(_stem_player)


# --- Self-wiring (#25 event→sfx + #61) — idempotent, mirrors Haptics.wire ----

func wire() -> void:
	if not Events.gate_passed.is_connected(_on_gate_passed):
		Events.gate_passed.connect(_on_gate_passed)
	if not Events.enemy_destroyed.is_connected(_on_enemy_destroyed):
		Events.enemy_destroyed.connect(_on_enemy_destroyed)
	if not Events.combo_updated.is_connected(_on_combo_updated):
		Events.combo_updated.connect(_on_combo_updated)
	if not Events.gate_hijack_blocked.is_connected(_on_gate_hijack_blocked):
		Events.gate_hijack_blocked.connect(_on_gate_hijack_blocked)
	if not Events.grid_collapsed.is_connected(_on_grid_collapsed):
		Events.grid_collapsed.connect(_on_grid_collapsed)
	if not Events.milestone_reached.is_connected(_on_milestone_reached):
		Events.milestone_reached.connect(_on_milestone_reached)
	if not Events.game_started.is_connected(_on_game_started):
		Events.game_started.connect(_on_game_started)
	if not Events.run_completed.is_connected(_on_run_completed):
		Events.run_completed.connect(_on_run_completed)
	if not Events.projectile_count_changed.is_connected(_on_projectile_count_changed):
		Events.projectile_count_changed.connect(_on_projectile_count_changed)
	if not Events.glow_battery_changed.is_connected(_on_glow_battery_changed):
		Events.glow_battery_changed.connect(_on_glow_battery_changed)


# --- Public API (guarded: no nodes → no-op, never crash) ---------------------

## Play a named SFX on the next round-robin pool player. Honours Settings.sfx_enabled
## (master switch). No-ops if the pool is empty (headless `.new()`), the name is
## unknown, or the chosen player is null. `pitch` retunes (combo escalation); `volume_db`
## trims level.
func play_sfx(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not Settings.sfx_enabled:
		return
	if _sfx_players.is_empty():
		return
	var stream: AudioStreamWAV = _sfx.get(name, null)
	if stream == null:
		return
	var idx := _next_player_index()
	if idx < 0 or idx >= _sfx_players.size():
		return
	var p := _sfx_players[idx]
	if p == null:
		return
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


## Start (or crossfade to) a looping music bed. Honours Settings.music_enabled. The fade
## itself is the _process lerp toward _music_target_db; `fade` is accepted for call-site
## clarity (longer fades read as "ease in"). No-ops with no music player (headless).
func play_music(track: String, fade: float = 0.6) -> void:
	if _music_player == null:
		return
	if not Settings.music_enabled:
		# Master off — keep it silent but remember intent is "stopped".
		_music_target_db = SILENCE_DB
		_beat_enabled = false
		return
	var bed: AudioStreamWAV = _music_beds.get(track, null)
	if bed == null:
		return
	# Beat clock (#61): only the driving "game" bed pulses the grid. Reset the phase to the
	# downbeat when entering game music (but not on a redundant same-track call, so the pulse
	# never stutters). Other beds (menu) disable it.
	var want_beats := track == "game"
	if want_beats and not _beat_enabled:
		_beat_phase = 0.0
		_beat_index = 0
	_beat_enabled = want_beats
	# Swap the bed only if it changed, so a redundant call doesn't restart the loop.
	if _music_player.stream != bed:
		_music_player.stream = bed
		_music_player.volume_db = SILENCE_DB
		_music_current_db = SILENCE_DB
		_music_player.play()
	_music_target_db = 0.0
	# `fade` modulates how fast we ease in: a 0 fade snaps, a long fade is gentler.
	if fade <= 0.0:
		_music_current_db = 0.0
		_music_player.volume_db = 0.0


## Fade the music bed back to silence (and stop the stem). Guarded.
func stop_music() -> void:
	_music_target_db = SILENCE_DB
	_stem_target_db = SILENCE_DB
	_beat_enabled = false


## #61 fake-adaptive layer: crossfade the intensity STEM in/out. `level` is 0..1; the stem
## sits at SILENCE_DB at 0 and STEM_MAX_DB at 1 (lerped). Starts the stem bed lazily on first
## non-zero call. Guarded: no stem player → no-op.
func set_intensity(level: float) -> void:
	if _stem_player == null:
		return
	level = clampf(level, 0.0, 1.0)
	if not Settings.music_enabled:
		_stem_target_db = SILENCE_DB
		return
	# Lazily attach + start the stem bed the first time intensity is wanted.
	var bed: AudioStreamWAV = _music_beds.get("stem", null)
	if bed != null and _stem_player.stream != bed:
		_stem_player.stream = bed
		_stem_player.volume_db = SILENCE_DB
		_stem_current_db = SILENCE_DB
		_stem_player.play()
	_stem_target_db = lerpf(SILENCE_DB, STEM_MAX_DB, level)


## #61 DSP: drive the Music bus low-pass from the Glow Battery. Full battery → fully open
## (MUSIC_LP_OPEN); empty → muffled (MUSIC_LP_MIN). Subtle. Guarded: no Music bus → no-op.
func set_music_lowpass_from_battery(value: float, max_value: float) -> void:
	var mbus := AudioServer.get_bus_index("Music")
	if mbus < 0:
		return
	var frac := 0.0 if max_value <= 0.0 else clampf(value / max_value, 0.0, 1.0)
	var cutoff := lerpf(MUSIC_LP_MIN, MUSIC_LP_OPEN, frac)
	for e in AudioServer.get_bus_effect_count(mbus):
		var fx := AudioServer.get_bus_effect(mbus, e)
		if fx is AudioEffectLowPassFilter:
			(fx as AudioEffectLowPassFilter).cutoff_hz = cutoff
			return


# --- PURE helpers (headless-safe; the verify script asserts on these) --------

## Map a gate economy op to its SFX key. Positive ops get their own gain stings; both
## negative ops (subtract/divide) share the loss buzz. Vocabulary matches gate.gd /
## effect_layer ("add"/"subtract"/"multiply"/"divide").
func _sfx_for_gate(gate_type: String) -> String:
	match gate_type:
		"multiply":
			return "gate_multiply"
		"add":
			return "gate_add"
		_:
			# subtract / divide (and any unknown) → the negative buzz.
			return "gate_negative"


## Round-robin the SFX pool: return the current index and advance (wrapping at
## SFX_POOL_SIZE) so back-to-back plays land on different players. PURE — no node
## access; mirrors EffectLayer._next_emitter_index.
func _next_player_index() -> int:
	if SFX_POOL_SIZE <= 0:
		return -1
	var idx := _next_sfx
	_next_sfx = (_next_sfx + 1) % SFX_POOL_SIZE
	return idx


## Escalating combo pitch: rises with the combo count, clamped so a long combo doesn't
## go chipmunk-shrill. Monotonic non-decreasing in `combo`. PURE.
func _combo_pitch(combo: int) -> float:
	var steps := maxi(combo - 1, 0)            # combo 1 = base pitch
	return clampf(1.0 + 0.06 * float(steps), 1.0, 2.0)


## Gentle 0..1 map of swarm projectile count → intensity (#61). Soft so the layer eases
## in across a wide count range rather than snapping. PURE.
func _intensity_for_count(count: int) -> float:
	return clampf(float(maxi(count, 0)) / 600.0, 0.0, 1.0)


## Seconds per beat — one beat per bass note of the game bed, so beats land on the bed's note
## onsets exactly. PURE. > 0 as long as GAME_BED_NOTES > 0.
func _beat_period() -> float:
	return GAME_BED_DUR / float(maxi(GAME_BED_NOTES, 1))


## Strength (0..1) of the beat at absolute `index`: the bar DOWNBEAT (the bass root, index
## divisible by BEATS_PER_BAR) is strongest; the off-beats are gentler. PURE.
func _beat_strength(index: int) -> float:
	return BEAT_DOWN_STRENGTH if index % BEATS_PER_BAR == 0 else BEAT_OFF_STRENGTH


## Advance the beat phase by `delta`, returning {phase, fired}: `phase` is the remaining
## sub-beat time (always < period), `fired` is how many beat onsets were crossed this frame
## (handles a long delta after a stall). PURE — no signals/nodes; _process emits per `fired`.
func _advance_beat_phase(phase: float, delta: float, period: float) -> Dictionary:
	var p := phase + maxf(delta, 0.0)
	var fired := 0
	while period > 0.0 and p >= period:
		p -= period
		fired += 1
	return {"phase": p, "fired": fired}


# --- PURE synthesis (the testable core) --------------------------------------

## Synthesise a single mono 16-bit AudioStreamWAV. PURE — no AudioServer, no tree, no
## RNG (a fixed-seed LCG drives the "noise" wave so output is deterministic and the
## verify can byte-count it). `opts` keys (all optional):
##   wave:  "sine" (default) / "square" / "saw" / "noise"
##   end_freq: float — if > 0, linearly sweep pitch freq → end_freq over the duration
##   attack/decay/sustain/release: ADSR fractions of the duration (sum may be < 1)
##   sustain_level: float 0..1 — the held amplitude during sustain
##   volume: float 0..1 — overall amplitude scale
func _synth(freq: float, dur: float, opts: Dictionary = {}) -> AudioStreamWAV:
	var wave: String = opts.get("wave", "sine")
	var end_freq: float = opts.get("end_freq", 0.0)
	var attack: float = opts.get("attack", 0.01)
	var decay: float = opts.get("decay", 0.1)
	var sustain: float = opts.get("sustain", 0.6)
	var release: float = opts.get("release", 0.29)
	var sustain_level: float = opts.get("sustain_level", 0.7)
	var volume: float = opts.get("volume", 0.8)

	var frames := int(maxf(dur, 0.001) * float(MIX_RATE))
	if frames < 1:
		frames = 1
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)                    # 16-bit mono = 2 bytes/frame

	var phase := 0.0
	var lcg := 1103515245                        # fixed-seed LCG state (deterministic "noise")
	for i in frames:
		var t := float(i) / float(frames)        # 0..1 through the sound
		# --- pitch (optional linear sweep) ---
		var f := freq if end_freq <= 0.0 else lerpf(freq, end_freq, t)
		phase += f / float(MIX_RATE)
		var ph := fposmod(phase, 1.0)
		# --- waveform ---
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if ph < 0.5 else -1.0
			"saw":
				s = 2.0 * ph - 1.0
			"noise":
				lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
				s = (float(lcg) / 1073741823.5) - 1.0
			_:  # sine
				s = sin(ph * TAU)
		# --- ADSR envelope ---
		var env := _adsr(t, attack, decay, sustain, release, sustain_level)
		var sample := clampf(s * env * volume, -1.0, 1.0)
		var v := int(round(sample * 32767.0))
		v = clampi(v, -32768, 32767)
		# little-endian int16
		var u := v if v >= 0 else v + 65536
		bytes[i * 2] = u & 0xff
		bytes[i * 2 + 1] = (u >> 8) & 0xff

	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = bytes
	return w


## Pure ADSR amplitude at normalised time `t` (0..1). Stages are fractions of the whole
## duration; whatever's left after A+D+S becomes release. Returns 0..1.
func _adsr(t: float, attack: float, decay: float, sustain: float, release: float, sustain_level: float) -> float:
	if t < attack and attack > 0.0:
		return t / attack
	if t < attack + decay and decay > 0.0:
		var d := (t - attack) / decay
		return lerpf(1.0, sustain_level, d)
	if t < attack + decay + sustain:
		return sustain_level
	# release tail
	var rstart := attack + decay + sustain
	var rlen := maxf(release, 1.0 - rstart)
	if rlen <= 0.0:
		return 0.0
	var r := clampf((t - rstart) / rlen, 0.0, 1.0)
	return lerpf(sustain_level, 0.0, r)


## Mix two AudioStreamWAVs of equal length into one (for chords). PURE; clamps on overflow.
## Falls back to `a` if lengths differ (defensive — callers build equal-length layers).
func _mix(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	var da := a.data
	var db := b.data
	if da.size() != db.size():
		return a
	var out := PackedByteArray()
	out.resize(da.size())
	var n := da.size() / 2
	for i in n:
		var sa := _read_s16(da, i)
		var sb := _read_s16(db, i)
		var v := clampi(int((sa + sb) * 0.6), -32768, 32767)
		var u := v if v >= 0 else v + 65536
		out[i * 2] = u & 0xff
		out[i * 2 + 1] = (u >> 8) & 0xff
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = out
	return w


## Read a little-endian int16 sample at frame index `i` from a byte buffer. PURE helper.
func _read_s16(buf: PackedByteArray, i: int) -> int:
	var u := buf[i * 2] | (buf[i * 2 + 1] << 8)
	return u if u < 32768 else u - 65536


# --- PURE table builders (callable on a bare .new(); the verify uses these) ---

## Build the full named-SFX table. PURE: synthesises every sting from _synth, returns a
## fresh Dictionary. _ready stashes the result in `_sfx`; the verify calls this directly
## (NOT via _ready) so it can assert keys + non-empty data with no audio server.
func _build_sfx_table() -> Dictionary:
	var t := {}
	# +N add: short rising blip (gain, modest).
	t["gate_add"] = _synth(520.0, 0.16, {
		"wave": "square", "end_freq": 760.0,
		"attack": 0.01, "decay": 0.2, "sustain": 0.2, "release": 0.59, "sustain_level": 0.5})
	# ×N multiply: bright rising arpeggio (the big gain — three stacked rising blips).
	t["gate_multiply"] = _arp([660.0, 880.0, 1320.0], 0.34, "square")
	# −/÷ negative: descending buzz (loss).
	t["gate_negative"] = _synth(440.0, 0.26, {
		"wave": "saw", "end_freq": 150.0,
		"attack": 0.01, "decay": 0.1, "sustain": 0.3, "release": 0.59, "sustain_level": 0.6})
	# Enemy kill: short noise burst, fast decay.
	t["explosion"] = _synth(0.0, 0.18, {
		"wave": "noise",
		"attack": 0.005, "decay": 0.25, "sustain": 0.0, "release": 0.745, "sustain_level": 0.0,
		"volume": 0.7})
	# Combo: a clean rising blip (pitch is escalated at the call site via _combo_pitch).
	t["combo"] = _synth(700.0, 0.14, {
		"wave": "sine", "end_freq": 980.0,
		"attack": 0.01, "decay": 0.15, "sustain": 0.2, "release": 0.64, "sustain_level": 0.5})
	# UI select: tiny crisp tick.
	t["ui_select"] = _synth(880.0, 0.07, {
		"wave": "square",
		"attack": 0.01, "decay": 0.3, "sustain": 0.0, "release": 0.69, "sustain_level": 0.0,
		"volume": 0.5})
	# Milestone: a triumphant chord (root + major third + fifth, held).
	t["milestone"] = _chord([523.25, 659.25, 783.99], 0.5)
	# Hijack denied: a harsh low square thunk.
	t["hijack_denied"] = _synth(180.0, 0.2, {
		"wave": "square", "end_freq": 110.0,
		"attack": 0.005, "decay": 0.1, "sustain": 0.3, "release": 0.595, "sustain_level": 0.8,
		"volume": 0.8})
	# Collapse: long downward sweep (the loss terminal).
	t["collapse"] = _synth(700.0, 0.7, {
		"wave": "saw", "end_freq": 80.0,
		"attack": 0.02, "decay": 0.2, "sustain": 0.4, "release": 0.38, "sustain_level": 0.7,
		"volume": 0.85})
	return t


## Build the looping music beds + the intensity stem. PURE. Each bed is a short WAV with
## LOOP_FORWARD so the player loops seamlessly. _ready stashes in `_music_beds`.
func _build_music_beds() -> Dictionary:
	var beds := {}
	# Game bed: GAME_BED_NOTES bass notes over GAME_BED_DUR — the beat clock ticks one beat per
	# note (see _beat_period), so a music_beat fires on each of these onsets. Keep the note count
	# == GAME_BED_NOTES so the two stay locked.
	beds["game"] = _loopify(_bed([220.0, 277.18, 329.63], GAME_BED_DUR, "saw"))  # A minor-ish driving bed
	beds["menu"] = _loopify(_bed([196.0, 246.94, 293.66], 3.0, "sine"))    # calmer G bed
	beds["stem"] = _loopify(_bed([440.0, 554.37, 659.25], 2.0, "square"))  # bright upper layer (#61)
	return beds


## Synthesise a short looping bed from a chord cycled across its duration. PURE: arpeggiates
## the notes evenly so the loop has motion, mixed into one mono WAV.
func _bed(notes: Array, dur: float, wave: String) -> AudioStreamWAV:
	var n := notes.size()
	if n == 0:
		return _synth(220.0, dur, {"wave": wave})
	var seg := dur / float(n)
	# Build each note segment, then concatenate the byte buffers into one bed.
	var out := PackedByteArray()
	for note in notes:
		var part := _synth(float(note), seg, {
			"wave": wave,
			"attack": 0.02, "decay": 0.1, "sustain": 0.7, "release": 0.18, "sustain_level": 0.7,
			"volume": 0.5})
		out.append_array(part.data)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = out
	return w


## Stamp loop metadata onto a WAV: LOOP_FORWARD across the whole buffer. PURE. Returns the
## same stream (mutated) for chaining.
func _loopify(w: AudioStreamWAV) -> AudioStreamWAV:
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / 2             # frame count (16-bit mono)
	return w


## A rising arpeggio: notes played in quick succession, concatenated. PURE.
func _arp(notes: Array, dur: float, wave: String) -> AudioStreamWAV:
	var n := notes.size()
	if n == 0:
		return _synth(660.0, dur, {"wave": wave})
	var seg := dur / float(n)
	var out := PackedByteArray()
	for note in notes:
		var part := _synth(float(note), seg, {
			"wave": wave,
			"attack": 0.01, "decay": 0.2, "sustain": 0.2, "release": 0.59, "sustain_level": 0.5})
		out.append_array(part.data)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = out
	return w


## A held chord: synth each note over the SAME duration and mix them. PURE.
func _chord(notes: Array, dur: float) -> AudioStreamWAV:
	if notes.is_empty():
		return _synth(523.25, dur, {})
	var acc := _synth(float(notes[0]), dur, {
		"wave": "sine",
		"attack": 0.02, "decay": 0.2, "sustain": 0.5, "release": 0.28, "sustain_level": 0.7,
		"volume": 0.6})
	for i in range(1, notes.size()):
		var layer := _synth(float(notes[i]), dur, {
			"wave": "sine",
			"attack": 0.02, "decay": 0.2, "sustain": 0.5, "release": 0.28, "sustain_level": 0.7,
			"volume": 0.6})
		acc = _mix(acc, layer)
	return acc


# --- Bus handlers (#25/#61) — thin: resolve PURE, then guarded playback -------

func _on_gate_passed(gate_type: String, _value: float, _new_count: int) -> void:
	play_sfx(_sfx_for_gate(gate_type))


func _on_enemy_destroyed(_at: Vector2, _points: int) -> void:
	# Tiny deterministic pitch wobble keyed off the round-robin index so a volley of kills
	# doesn't sound like a metronome. Index is read pre-advance for determinism.
	var wob := 0.92 + 0.02 * float(_next_sfx % SFX_POOL_SIZE)
	play_sfx("explosion", wob)


func _on_combo_updated(combo_count: int) -> void:
	if combo_count > 1:
		play_sfx("combo", _combo_pitch(combo_count))


func _on_gate_hijack_blocked(_gate_type: String, _at: Vector2) -> void:
	play_sfx("hijack_denied")


func _on_grid_collapsed() -> void:
	play_sfx("collapse")
	play_music("menu")                         # drop back to the calm bed on the loss terminal


func _on_milestone_reached(_count: int) -> void:
	play_sfx("milestone")


func _on_game_started() -> void:
	play_music("game")


func _on_run_completed(_final_score: int, _distance: float) -> void:
	play_music("menu")                         # win terminal → calm bed under the Results screen


func _on_projectile_count_changed(count: int) -> void:
	set_intensity(_intensity_for_count(count))  # #61 fake-adaptive: more swarm, more layer


func _on_glow_battery_changed(value: float, max_value: float) -> void:
	set_music_lowpass_from_battery(value, max_value)  # #61 DSP: drain muffles the bed
