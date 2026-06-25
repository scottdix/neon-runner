extends Node
## Debug — HORDE designer-tuning knobs (autoload singleton: `Debug`).
##
## A self-contained tuning surface for the locked HORDE core game, opened from the PAUSE overlay's
## DEBUG button. Every field is a designer dial: spawn toggles, density/speed/strength/firepower-loss
## multipliers, a soft enemy spawn cap (UNBOUNDED so the wall can be found past 256), gate toggle,
## plus a small block of forward-looking PLACEHOLDERS (bullet pass-through) wired now so the menu can
## expose them before the gameplay lands.
##
## OWNERSHIP / DECOUPLING (CLAUDE.md): state mutates ONLY through the setters, each of which no-ops on
## no change, persists to its OWN ConfigFile (user://debug.cfg — independent of Settings' file), and
## announces a single coarse Events.debug_changed. Systems react via that signal / pull the live field
## (they never poll a getter in a hot loop blindly — they cache off debug_changed). The null-safe
## accessor methods (tokens_on(), density_mult(), …) exist so a bare-instance headless verify (which has
## no autoload context) and defensive callers can read a sane value without a hard `Debug.` dependency —
## production readers use root.get_node_or_null("Debug") and fall back to neutral defaults when absent
## (like Targets already does for Difficulty), keeping the parked verifies green.
##
## Registered AFTER Settings and BEFORE GameState in project.godot.

const CONFIG_PATH := "user://debug.cfg"
const SECTION := "debug"

# --- Spawn toggles -----------------------------------------------------------
## Master token-drop toggle (default ON). TokenLayer / kill path reads tokens_on() before dropping.
var tokens_enabled: bool = true
## Master enemy-spawn toggle (default ON). Targets reads enemies_on() before spawning fodder/bosses.
var enemies_enabled: bool = true
## Gate-spawn toggle (default ON). The gate spawner reads gates_on() before building a formation.
var gates_enabled: bool = true

# --- Tuning multipliers (all NEUTRAL at 1.0) ---------------------------------
## Enemy spawn-density multiplier. >1 packs more fodder; <1 thins it.
var enemy_density_mult: float = 1.0
## Enemy movement-speed multiplier (lane-march pace toward the ship line).
var enemy_speed_mult: float = 1.0
## Enemy strength multiplier (hp / firepower-to-kill).
var enemy_strength_mult: float = 1.0
## Firepower-loss multiplier on a breach. >1 punishes breaches harder; <1 softens them.
var firepower_loss_mult: float = 1.0

# --- Soft spawn cap ----------------------------------------------------------
## SOFT enemy spawn cap (default 256). UNBOUNDED on purpose so the designer can push past 256 to
## find the perf wall; the MultiMesh HARD buffer (1024) is the real ceiling. Never clamped here.
var enemy_cap: int = 256

# --- Placeholders (forward-looking, persisted so the menu state survives) -----
## Placeholder: PLAYER bullets pass through enemies instead of stopping on first hit.
var bullet_passthrough: bool = false
## Placeholder: how long (s) a passed-through player bullet lives.
var bullet_passthrough_lifespan: float = 1.0
## Placeholder: ENEMY-bullet pass-through strength (0 = off).
var enemy_bullet_passthrough_strength: float = 0.0


func _ready() -> void:
	load_debug()


# --- Setters (no-op on no change → persist → announce) -----------------------

func set_tokens_enabled(enabled: bool) -> void:
	if enabled == tokens_enabled:
		return
	tokens_enabled = enabled
	_commit()


func set_enemies_enabled(enabled: bool) -> void:
	if enabled == enemies_enabled:
		return
	enemies_enabled = enabled
	_commit()


func set_gates_enabled(enabled: bool) -> void:
	if enabled == gates_enabled:
		return
	gates_enabled = enabled
	_commit()


func set_enemy_density_mult(m: float) -> void:
	if is_equal_approx(m, enemy_density_mult):
		return
	enemy_density_mult = m
	_commit()


func set_enemy_speed_mult(m: float) -> void:
	if is_equal_approx(m, enemy_speed_mult):
		return
	enemy_speed_mult = m
	_commit()


func set_enemy_strength_mult(m: float) -> void:
	if is_equal_approx(m, enemy_strength_mult):
		return
	enemy_strength_mult = m
	_commit()


func set_firepower_loss_mult(m: float) -> void:
	if is_equal_approx(m, firepower_loss_mult):
		return
	firepower_loss_mult = m
	_commit()


## UNBOUNDED on purpose (see field doc) — only guard against a negative.
func set_enemy_cap(cap: int) -> void:
	var c: int = maxi(cap, 0)
	if c == enemy_cap:
		return
	enemy_cap = c
	_commit()


func set_bullet_passthrough(enabled: bool) -> void:
	if enabled == bullet_passthrough:
		return
	bullet_passthrough = enabled
	_commit()


func set_bullet_passthrough_lifespan(s: float) -> void:
	if is_equal_approx(s, bullet_passthrough_lifespan):
		return
	bullet_passthrough_lifespan = s
	_commit()


func set_enemy_bullet_passthrough_strength(s: float) -> void:
	if is_equal_approx(s, enemy_bullet_passthrough_strength):
		return
	enemy_bullet_passthrough_strength = s
	_commit()


# --- Null-safe accessors (sane neutral reads for bare-instance verifies) ------

func tokens_on() -> bool:
	return tokens_enabled


func enemies_on() -> bool:
	return enemies_enabled


func gates_on() -> bool:
	return gates_enabled


func density_mult() -> float:
	return enemy_density_mult


func speed_mult() -> float:
	return enemy_speed_mult


func strength_mult() -> float:
	return enemy_strength_mult


func firepower_loss() -> float:
	return firepower_loss_mult


func cap() -> int:
	return enemy_cap


# --- Persistence -------------------------------------------------------------

## Persist + announce. Single seam so every setter stays a one-liner and the contract (save THEN
## emit) is in one place.
func _commit() -> void:
	save_debug()
	# Bare `Events` global is the established autoload-to-autoload pattern (see Settings.set_*); it's
	# the -s MAIN verify script (a SceneTree extension) that can't see bare autoload names, not this
	# production autoload. The connecting verify reads the SAME live Events node via root.get_node.
	Events.debug_changed.emit()


## Best-effort load; absent keys keep their code defaults so a missing/old file is fine.
func load_debug() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	tokens_enabled = bool(cfg.get_value(SECTION, "tokens_enabled", tokens_enabled))
	enemies_enabled = bool(cfg.get_value(SECTION, "enemies_enabled", enemies_enabled))
	gates_enabled = bool(cfg.get_value(SECTION, "gates_enabled", gates_enabled))
	enemy_density_mult = float(cfg.get_value(SECTION, "enemy_density_mult", enemy_density_mult))
	enemy_speed_mult = float(cfg.get_value(SECTION, "enemy_speed_mult", enemy_speed_mult))
	enemy_strength_mult = float(cfg.get_value(SECTION, "enemy_strength_mult", enemy_strength_mult))
	firepower_loss_mult = float(cfg.get_value(SECTION, "firepower_loss_mult", firepower_loss_mult))
	enemy_cap = maxi(int(cfg.get_value(SECTION, "enemy_cap", enemy_cap)), 0)
	bullet_passthrough = bool(cfg.get_value(SECTION, "bullet_passthrough", bullet_passthrough))
	bullet_passthrough_lifespan = float(cfg.get_value(SECTION, "bullet_passthrough_lifespan", bullet_passthrough_lifespan))
	enemy_bullet_passthrough_strength = float(cfg.get_value(SECTION, "enemy_bullet_passthrough_strength", enemy_bullet_passthrough_strength))


func save_debug() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "tokens_enabled", tokens_enabled)
	cfg.set_value(SECTION, "enemies_enabled", enemies_enabled)
	cfg.set_value(SECTION, "gates_enabled", gates_enabled)
	cfg.set_value(SECTION, "enemy_density_mult", enemy_density_mult)
	cfg.set_value(SECTION, "enemy_speed_mult", enemy_speed_mult)
	cfg.set_value(SECTION, "enemy_strength_mult", enemy_strength_mult)
	cfg.set_value(SECTION, "firepower_loss_mult", firepower_loss_mult)
	cfg.set_value(SECTION, "enemy_cap", enemy_cap)
	cfg.set_value(SECTION, "bullet_passthrough", bullet_passthrough)
	cfg.set_value(SECTION, "bullet_passthrough_lifespan", bullet_passthrough_lifespan)
	cfg.set_value(SECTION, "enemy_bullet_passthrough_strength", enemy_bullet_passthrough_strength)
	cfg.save(CONFIG_PATH)
