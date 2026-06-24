extends Node
## Haptics — tactile feedback tiers (autoload singleton: `Haptics`).
##
## Session-12 "Platform feel" (DESIGN_SPEC). Three durations mapped to gameplay
## events via the Events bus, gated by Settings.haptics_enabled. iOS routes
## `Input.vibrate_handheld` to the Taptic engine, Android to the vibrator API; on
## desktop/headless it is a harmless no-op, so this is safe to wire everywhere.
##
## Durations are the DESIGN_SPEC starting tiers — tune on device:
##   light  ~15 ms — a minor hit (an enemy breaching the ship line).
##   medium ~35 ms — a gate SPLICE (passing any gate).
##   heavy  ~80 ms — death / hard collision (battery emptied → grid collapse).
##
## Wiring is in a public, idempotent wire() called from _ready, mirroring
## GameState.wire_events: under the headless `-s` loop autoload _ready is deferred past
## _initialize, so a test that wants the connections live calls wire() itself.

const LIGHT_MS := 15
const MEDIUM_MS := 35
const HEAVY_MS := 80


func _ready() -> void:
	wire()


func wire() -> void:
	if not Events.gate_passed.is_connected(_on_gate_passed):
		Events.gate_passed.connect(_on_gate_passed)
	if not Events.gate_hijack_blocked.is_connected(_on_gate_hijack_blocked):
		Events.gate_hijack_blocked.connect(_on_gate_hijack_blocked)
	if not Events.enemy_breached.is_connected(_on_enemy_breached):
		Events.enemy_breached.connect(_on_enemy_breached)
	if not Events.grid_collapsed.is_connected(_on_grid_collapsed):
		Events.grid_collapsed.connect(_on_grid_collapsed)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)
	if not Events.milestone_reached.is_connected(_on_milestone_reached):
		Events.milestone_reached.connect(_on_milestone_reached)


func light() -> void:
	_pulse(LIGHT_MS)


func medium() -> void:
	_pulse(MEDIUM_MS)


func heavy() -> void:
	_pulse(HEAVY_MS)


func _pulse(ms: int) -> void:
	if not Settings.haptics_enabled:
		return
	Input.vibrate_handheld(ms)


# --- Event mapping -----------------------------------------------------------

func _on_gate_passed(_gate_type: String, _value: float, _new_count: int) -> void:
	medium()                                # the splice


func _on_gate_hijack_blocked(_gate_type: String, _at: Vector2) -> void:
	heavy()                                 # splice denied — the occupant lived


func _on_enemy_breached(_at: Vector2, _damage: float) -> void:
	light()                                 # a minor hit got through


func _on_grid_collapsed() -> void:
	heavy()                                 # death / loss terminal


func _on_player_died() -> void:
	heavy()


func _on_milestone_reached(_count: int) -> void:
	heavy()                                 # a swarm milestone — a celebratory thump (#28)
