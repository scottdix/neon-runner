extends Node
## Difficulty — the per-mode tuning lookup (autoload singleton: `Difficulty`, #80).
##
## Registered AFTER Settings (it reads Settings.difficulty) and BEFORE GameState (which reads
## drain_mult() through it). Holds one DifficultyProfile per mode {EASY,MEDIUM,HARD}, seeded
## in code via DifficultyProfile.make() (no `.tres` required — mirrors SpliceLab's SpliceMod
## seeding). Caches the active profile keyed by Settings.difficulty; re-reads it on
## Events.difficulty_changed.
##
## Public readers are the spine contract — consumers call e.g. Difficulty.armor_chip_fraction()
## and never touch a profile reference. The keystone reader is armor_chip_fraction(): it
## mode-scales the #79 Rhombus per-hit FLOOR's sub-threshold grind (EASY 0.45 chips, HARD 0.0 =
## true immunity / Lance mandatory).
##
## wire_events() is public + idempotent because under the headless `-s` loop autoload _ready is
## deferred past _initialize — the verify scripts call it explicitly (same pattern as GameState).

# Preloaded by PATH (not the `class_name`) so this autoload parses in the headless dev loop
# where the global class cache isn't built without --import.
const PROFILE := preload("res://resources/difficulty_profile.gd")

enum { EASY, MEDIUM, HARD }

## The three mode profiles, seeded once in _build_profiles(). Keyed by the mode int.
var _profiles: Dictionary = {}
## The active profile, cached from Settings.difficulty (re-read on difficulty_changed).
var _active: DifficultyProfile


func _ready() -> void:
	_build_profiles()
	wire_events()
	_refresh()


## Connect to the difficulty bus + cache the active profile. Public + idempotent so the
## headless verify can call it explicitly (autoload _ready is deferred under `-s`). Settings
## is registered before this autoload, so it's present by the time this runs.
func wire_events() -> void:
	if _profiles.is_empty():
		_build_profiles()
	if not Events.difficulty_changed.is_connected(_on_difficulty_changed):
		Events.difficulty_changed.connect(_on_difficulty_changed)
	_refresh()


func _on_difficulty_changed(_mode: int) -> void:
	_refresh()


## Re-read the active profile from Settings.difficulty (clamped to a valid mode).
func _refresh() -> void:
	var mode: int = clampi(int(Settings.difficulty), EASY, HARD)
	_active = _profiles.get(mode, _profiles.get(MEDIUM))


# --- Public readers (the spine contract) -------------------------------------

## The sub-threshold armor CHIP fraction for the active mode (#79 floor knob, #80-scaled).
## EASY 0.45 > MEDIUM 0.15 > HARD 0.0 (== true immunity). Targets reads this at its chip site.
func armor_chip_fraction() -> float:
	return _active.armor_chip_fraction if _active != null else 0.15


## Negative-gate battery drain multiplier for the active mode. GameState folds it into the
## DRAIN_PER_NEGATIVE_GATE on a −/÷ gate. EASY 0.7 < MEDIUM 1.0 < HARD 1.35.
func drain_mult() -> float:
	return _active.drain_mult if _active != null else 1.0


func spawn_density_mult() -> float:
	return _active.spawn_density_mult if _active != null else 1.0


func rhombus_weight_bias() -> float:
	return _active.rhombus_weight_bias if _active != null else 0.0


func gate_negative_severity() -> float:
	return _active.gate_negative_severity if _active != null else 1.0


func phase_intensity() -> float:
	return _active.phase_intensity if _active != null else 1.0


## Display name for a mode (for the UI selector / read-only indicator).
func mode_name(mode: int) -> String:
	var p: DifficultyProfile = profile_for(mode)
	return p.mode_name if p != null else "MEDIUM"


## The profile for an explicit mode (clamped). Lets UI preview a mode without switching to it.
func profile_for(mode: int) -> DifficultyProfile:
	var m: int = clampi(mode, EASY, HARD)
	return _profiles.get(m, _profiles.get(MEDIUM))


## Seed the {EASY,MEDIUM,HARD} profile set in code (no `.tres` authoring needed). MEDIUM mirrors
## today's constants (armor_chip 0.15 = the legacy ARMOR_CHIP_FRACTION, all mults 1.0) so the
## default mode is a no-op vs the pre-#80 balance — the verify_combat/verify_stance invariant.
func _build_profiles() -> void:
	_profiles = {
		#                           name      chip  drain density rhombus gate  phase  accent
		EASY:   PROFILE.make("EASY",   0.45, 0.70, 0.80, 0.00, 0.80, 0.85, "mint"),
		MEDIUM: PROFILE.make("MEDIUM", 0.15, 1.00, 1.00, 0.00, 1.00, 1.00, "cyan"),
		HARD:   PROFILE.make("HARD",   0.00, 1.35, 1.25, 0.10, 1.20, 1.20, "gold"),
	}
