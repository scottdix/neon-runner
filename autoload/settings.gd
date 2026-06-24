extends Node
## Settings — persisted player options (autoload singleton: `Settings`).
##
## Session-12 "Platform feel" foundation (DESIGN_SPEC). Two premium-feel toggles for
## v0.2.0; more land with the Settings screen (#45):
##   • haptics_enabled — master switch for the Taptic/vibrator feedback (Haptics reads it).
##   • amoled_mode     — pitch-black clear + low-power bloom path for OLED screens.
##
## State is mutated only through the setters so every change persists + announces on the
## Events bus (systems react via Events, never by polling this node — CLAUDE.md decoupling).
## Persisted to a tiny ConfigFile; load is best-effort so a missing/old file just uses
## the defaults. Loading here (a const path, no _ready dependency on other autoloads)
## is safe before the rest of the tree exists.

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "display"
const PROGRESS := "progress"

## Master haptics switch (defaults ON — it's a paid-feel feature).
var haptics_enabled: bool = true
## Sound-effects master switch (defaults ON). AudioManager reads it before playing any SFX.
var sfx_enabled: bool = true
## Background-music master switch (defaults ON). AudioManager reads it before starting a track.
var music_enabled: bool = true
## OLED pitch-black + low-power bloom mode (defaults OFF — opt-in).
var amoled_mode: bool = false
## On-screen perf overlay (#35) visibility (defaults OFF — a debug surface). Toggled from the
## Settings screen so it works on a phone (no keyboard F3); the PerfOverlay reads this + reacts to
## perf_overlay_changed. Persisted alongside the other display toggles.
var perf_overlay_enabled: bool = false
## High score shown on Title (BEST) + flagged on Results (NEW BEST). Persisted here
## since this autoload already owns the save file.
var best_score: int = 0
## Difficulty mode (#80): 0=EASY, 1=MEDIUM, 2=HARD. Default MEDIUM. A PLAIN int — NO dependency
## on the Difficulty autoload (which loads AFTER this one and reads this field, not the reverse).
## The Difficulty autoload maps it to a DifficultyProfile; persisted here under PROGRESS.
var difficulty: int = 1

## Combat-redesign POC stance driver (#86/#87), LOCKED IN before a run starts (designer's call):
##   LEGACY         — today's gate-polarity stance (baseline / control).
##   KINETIC_CLUTCH — stance follows ship motion (moving=SPRAY, braked=LANCE).
##   GEOM_OVERDRIVE — default SPRAY; a triple-tap burns kill-fed geom_charge for a LANCE overdrive.
## Default LEGACY so an un-touched install plays the shipped combat. Persisted under PROGRESS; the
## run's StanceController reads it at game_started. Selected on the Settings screen (device-friendly).
enum PocMode { LEGACY, KINETIC_CLUTCH, GEOM_OVERDRIVE }
var poc_mode: int = PocMode.LEGACY


func _ready() -> void:
	load_settings()


func set_amoled_mode(enabled: bool) -> void:
	if enabled == amoled_mode:
		return
	amoled_mode = enabled
	save_settings()
	Events.amoled_mode_changed.emit(amoled_mode)


## Toggle the on-screen perf overlay (#35). No-op on no change, persist, and announce on the bus
## so the live PerfOverlay shows/hides immediately. The Settings screen is the device-friendly path.
func set_perf_overlay_enabled(enabled: bool) -> void:
	if enabled == perf_overlay_enabled:
		return
	perf_overlay_enabled = enabled
	save_settings()
	Events.perf_overlay_changed.emit(perf_overlay_enabled)


func set_haptics_enabled(enabled: bool) -> void:
	if enabled == haptics_enabled:
		return
	haptics_enabled = enabled
	save_settings()


func set_sfx_enabled(enabled: bool) -> void:
	if enabled == sfx_enabled:
		return
	sfx_enabled = enabled
	save_settings()


func set_music_enabled(enabled: bool) -> void:
	if enabled == music_enabled:
		return
	music_enabled = enabled
	save_settings()


## Set the difficulty mode (#80): clamp to 0..2, no-op on no change, persist, and announce on
## the Events bus. The Difficulty autoload re-reads its active profile on difficulty_changed; any
## open settings UI refreshes. Settings is the SINGLE owner of the persisted int.
func set_difficulty(mode: int) -> void:
	var m: int = clampi(mode, 0, 2)
	if m == difficulty:
		return
	difficulty = m
	save_settings()
	Events.difficulty_changed.emit(difficulty)


## Set the POC stance-driver mode (#86/#87): clamp to 0..2, no-op on no change, persist, announce on
## the Events bus. The run's StanceController re-reads the active mode (it caches at game_started, so
## the change takes effect on the NEXT run — intentional, the mode is locked in pre-run); any open
## Settings selector relights. Settings is the SINGLE owner of the persisted int.
func set_poc_mode(mode: int) -> void:
	var m: int = clampi(mode, 0, 2)
	if m == poc_mode:
		return
	poc_mode = m
	save_settings()
	Events.poc_mode_changed.emit(poc_mode)


## Record a finished run's score; persists + returns true if it beat the previous best
## (Results shows the NEW BEST badge on a true). No-op-returns-false for a tie/lower.
func record_score(s: int) -> bool:
	if s <= best_score:
		return false
	best_score = s
	save_settings()
	return true


## Best-effort load; absent keys keep their code defaults so an old/missing file is fine.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	haptics_enabled = bool(cfg.get_value(SECTION, "haptics_enabled", haptics_enabled))
	sfx_enabled = bool(cfg.get_value(SECTION, "sfx_enabled", sfx_enabled))
	music_enabled = bool(cfg.get_value(SECTION, "music_enabled", music_enabled))
	amoled_mode = bool(cfg.get_value(SECTION, "amoled_mode", amoled_mode))
	perf_overlay_enabled = bool(cfg.get_value(SECTION, "perf_overlay_enabled", perf_overlay_enabled))
	best_score = int(cfg.get_value(PROGRESS, "best_score", best_score))
	difficulty = clampi(int(cfg.get_value(PROGRESS, "difficulty", difficulty)), 0, 2)
	poc_mode = clampi(int(cfg.get_value(PROGRESS, "poc_mode", poc_mode)), 0, 2)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "haptics_enabled", haptics_enabled)
	cfg.set_value(SECTION, "sfx_enabled", sfx_enabled)
	cfg.set_value(SECTION, "music_enabled", music_enabled)
	cfg.set_value(SECTION, "amoled_mode", amoled_mode)
	cfg.set_value(SECTION, "perf_overlay_enabled", perf_overlay_enabled)
	cfg.set_value(PROGRESS, "best_score", best_score)
	cfg.set_value(PROGRESS, "difficulty", difficulty)
	cfg.set_value(PROGRESS, "poc_mode", poc_mode)
	cfg.save(CONFIG_PATH)
