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

## Master haptics switch (defaults ON — it's a paid-feel feature).
var haptics_enabled: bool = true
## OLED pitch-black + low-power bloom mode (defaults OFF — opt-in).
var amoled_mode: bool = false


func _ready() -> void:
	load_settings()


func set_amoled_mode(enabled: bool) -> void:
	if enabled == amoled_mode:
		return
	amoled_mode = enabled
	save_settings()
	Events.amoled_mode_changed.emit(amoled_mode)


func set_haptics_enabled(enabled: bool) -> void:
	if enabled == haptics_enabled:
		return
	haptics_enabled = enabled
	save_settings()


## Best-effort load; absent keys keep their code defaults so an old/missing file is fine.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	haptics_enabled = bool(cfg.get_value(SECTION, "haptics_enabled", haptics_enabled))
	amoled_mode = bool(cfg.get_value(SECTION, "amoled_mode", amoled_mode))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "haptics_enabled", haptics_enabled)
	cfg.set_value(SECTION, "amoled_mode", amoled_mode)
	cfg.save(CONFIG_PATH)
