class_name StanceController
extends Node
## Drives the stream STANCE for the combat-redesign POCs (#86/#87). Stance has ONE owner —
## GameState.set_stance (game_state.gd) — and this node is an alternative DRIVER of it, selected by
## Settings.poc_mode (locked in before the run starts, the designer's call):
##
##   • LEGACY         — idle. Gates drive stance the old way (GameState._on_gate_passed); this node
##                      touches nothing.
##   • KINETIC_CLUTCH — stance follows the ship's horizontal motion: moving => SPRAY (wide), braked /
##                      stationary for STILL_SECS => LANCE (tight column). Reads Player.velocity_x().
##   • GEOM_OVERDRIVE — default SPRAY; a TRIPLE-TAP (Player → Events.overdrive_toggle_requested) burns
##                      the kill-fed GameState.geom_charge to enter a LANCE "smart-bomb" overdrive,
##                      draining heavily; auto-reverts to SPRAY when the charge empties.
##
## Run injects the Player (set_player) and adds this as a sibling; the mode is cached at game_started
## so it's stable for the whole run. The mapping MATH is in pure helpers (kinetic_stance) so the
## headless verify can assert it with no GPU / no tree. Decoupled: stance/geom mutate through
## GameState, input arrives via the Events bus — this node holds only the Player ref (for velocity).

## KINETIC: |velocity_x| above this (px/s) counts as "moving" => SPRAY.
const MOVE_EPS := 30.0
## KINETIC: time (s) the ship must stay sub-MOVE_EPS before it commits to LANCE (a brief brake, not
## an instant flip on every micro-pause). Device-tuned (like GEOM_DRAIN_PER_SEC) — dropped below the
## POC 2 spec's 0.2 s so the brake-to-LANCE flip feels snappier on touch; keep in (0.10, 0.15].
const STILL_SECS := 0.13
## GEOM: overdrive LANCE burn rate (charge/s). At MAX_GEOM 100 a full gauge sustains ~2.5 s of LANCE.
const GEOM_DRAIN_PER_SEC := 40.0

var _player: Node2D = null
var _mode: int = 0                        # cached Settings.PocMode for the run (set at game_started)
var _still_secs: float = 0.0              # KINETIC: how long the ship has been near-stationary


func _ready() -> void:
	_mode = int(Settings.poc_mode)
	# The mode is locked in pre-run, but re-cache on a fresh run so a Settings change between runs
	# (without a scene rebuild) still takes effect on the NEXT run.
	Events.game_started.connect(func() -> void: _on_run_started())
	# GEOM_OVERDRIVE activation gesture (triple-tap). Inert in the other modes (guarded in the handler).
	Events.overdrive_toggle_requested.connect(_on_overdrive_toggle_requested)


## Run injects the Player so KINETIC can read its derived velocity. Kept a plain ref (not the bus)
## because velocity is a high-frequency per-frame poll, not an event.
func set_player(player: Node2D) -> void:
	_player = player


func _on_run_started() -> void:
	_mode = int(Settings.poc_mode)
	_still_secs = 0.0


func _process(delta: float) -> void:
	if not GameState.run_active:
		return
	# if/elif (not match): the POC modes are autoload-enum rvalues, not compile-time constants, so a
	# match PATTERN on them won't parse — the same reason fleet.gd compares GameState.Stance via `==`.
	if _mode == Settings.PocMode.KINETIC_CLUTCH:
		_step_kinetic(delta)
	elif _mode == Settings.PocMode.GEOM_OVERDRIVE:
		_step_geom(delta)
	# else LEGACY: gates own the stance; nothing to drive here.


# --- KINETIC_CLUTCH (POC 2) --------------------------------------------------

## Movement-driven stance. Accumulate "still" time while the ship is sub-MOVE_EPS; commit to the
## mapped stance each frame. Pure mapping lives in kinetic_stance() so the verify drives it directly.
func _step_kinetic(delta: float) -> void:
	if _player == null:
		return
	var vx: float = float(_player.call("velocity_x")) if _player.has_method("velocity_x") else 0.0
	if absf(vx) > MOVE_EPS:
		_still_secs = 0.0
	else:
		_still_secs += delta
	GameState.set_stance(kinetic_stance(vx, _still_secs))


## PURE: map a horizontal velocity + how long the ship has been still to a stance. Moving => SPRAY;
## still for at least STILL_SECS => LANCE. (Below the still threshold it holds SPRAY — a momentary
## slow-down mid-sweep shouldn't snap to LANCE; only a deliberate brake commits.)
func kinetic_stance(vx: float, still_secs: float) -> int:
	if absf(vx) > MOVE_EPS:
		return GameState.Stance.SPRAY
	if still_secs >= STILL_SECS:
		return GameState.Stance.LANCE
	return GameState.Stance.SPRAY


# --- GEOM_OVERDRIVE (POC 4) --------------------------------------------------

## While in overdrive, burn charge each tick; auto-revert to SPRAY the instant it empties. Default
## state (no overdrive) is plain SPRAY.
func _step_geom(delta: float) -> void:
	if GameState.overdrive_active:
		# #84 ph6: an Efficiency gate scales the burn (geom_drain_mult < 1 = sustain longer). The base
		# rate stays the const; the phase-scoped mult (1.0 = today, reset each boundary) folds in here.
		GameState.drain_geom(GEOM_DRAIN_PER_SEC * GameState.geom_drain_mult * delta)
		if GameState.geom_charge <= 0.0:
			_exit_overdrive()
	else:
		GameState.set_stance(GameState.Stance.SPRAY)


## Triple-tap toggle (#87). Only meaningful in GEOM_OVERDRIVE. Enter overdrive only with charge in the
## tank; a second triple-tap exits early back to SPRAY. Auto-revert at empty is handled in _step_geom.
func _on_overdrive_toggle_requested() -> void:
	if _mode != Settings.PocMode.GEOM_OVERDRIVE or not GameState.run_active:
		return
	if GameState.overdrive_active:
		_exit_overdrive()
	elif GameState.geom_charge > 0.0:
		GameState.set_stance(GameState.Stance.LANCE)
		GameState.set_overdrive_active(true)


func _exit_overdrive() -> void:
	GameState.set_overdrive_active(false)
	GameState.set_stance(GameState.Stance.SPRAY)
