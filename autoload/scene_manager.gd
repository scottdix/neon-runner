extends Node
## SceneManager — the screen-flow driver + app-level state machine (autoload `SceneManager`,
## #60/#8). Owns the BOOT → TITLE → RUN → RESULTS flow and the TITLE branches
## (GARAGE/SPLICE/SETTINGS); see docs/design/SCREENS.md.
##
## Decoupling (CLAUDE.md): gameplay does NOT call this to end a run. GameState emits the
## run terminals on the Events bus (`run_completed` / `grid_collapsed`); SceneManager
## listens and swaps to the Results screen. Screens call the public `goto_*` / `start_run`
## / `pause_run` methods on a button press — that's the only inbound coupling.
##
## Registered LAST in the autoload order (after GameState) so the singletons it leans on
## already exist. The main scene is Boot, so on launch `state` is BOOT and Boot calls
## `goto_title()` once loading finishes.

enum State { BOOT, TITLE, RUN, PAUSED, RESULTS, GARAGE, SPLICE, SETTINGS, HOW_TO_PLAY }

## Full-scene targets. RESULTS reads its stats from GameState; PAUSED is an overlay the
## Run scene raises (no scene swap), so it has no entry here.
const SCENES := {
	State.BOOT: "res://assets/ui/boot.tscn",
	State.TITLE: "res://assets/ui/title.tscn",
	State.RUN: "res://assets/levels/run.tscn",
	State.RESULTS: "res://assets/ui/results.tscn",
	State.GARAGE: "res://assets/ui/garage.tscn",
	State.SPLICE: "res://assets/ui/splice.tscn",
	State.SETTINGS: "res://assets/ui/settings.tscn",
	State.HOW_TO_PLAY: "res://assets/ui/how_to_play.tscn",
}

var state: int = State.BOOT


func _ready() -> void:
	wire_events()


## Connect the run terminals. Public + idempotent for the same reason as GameState.wire_events:
## under the headless `-s` loop autoload _ready is deferred past _initialize, so verify scripts
## call this explicitly. Events is the first autoload, always present here.
func wire_events() -> void:
	if not Events.run_completed.is_connected(_on_run_terminal):
		Events.run_completed.connect(_on_run_terminal)
	if not Events.grid_collapsed.is_connected(_on_grid_collapsed):
		Events.grid_collapsed.connect(_on_grid_collapsed)


# --- Flow transitions --------------------------------------------------------

func goto_title() -> void:
	_change(State.TITLE)


## Begin a fresh run. GameState.start_run() is driven by the Run scene's _ready, so this
## only swaps the scene + resets state (and clears any lingering pause).
func start_run() -> void:
	_change(State.RUN)


func goto_garage() -> void:
	_change(State.GARAGE)


func goto_splice() -> void:
	_change(State.SPLICE)


func goto_settings() -> void:
	_change(State.SETTINGS)


## Show the HOW TO PLAY rules card (#69). A Title branch; its back chevron routes to Title.
func goto_how_to_play() -> void:
	_change(State.HOW_TO_PLAY)


## Show the Results screen (win or loss — the screen reads `GameState.run_won`). Called by
## the run-terminal handlers; RETRY/MENU on Results route back to start_run()/goto_title().
func show_results() -> void:
	_change(State.RESULTS)


# --- Pause (in-run, overlay — no scene swap) ---------------------------------

## Freeze the run and flip to PAUSED. The Run scene raises its pause overlay (PROCESS_MODE_
## ALWAYS) so it survives the tree pause. Idempotent / only valid while running.
func pause_run() -> void:
	if state != State.RUN:
		return
	state = State.PAUSED
	get_tree().paused = true
	Events.game_paused.emit()


func resume_run() -> void:
	if state != State.PAUSED:
		return
	state = State.RUN
	get_tree().paused = false
	Events.game_resumed.emit()


# --- Internals ---------------------------------------------------------------

func _on_run_terminal(_final_score: int, _distance: float) -> void:
	show_results()


func _on_grid_collapsed() -> void:
	show_results()


## Swap to the scene for `next`, always clearing any pause first so the new scene runs.
## `change_scene_to_file` is deferred by the engine (safe to call from within the outgoing
## scene's _process / a signal). Logs and bails if the target is missing rather than crashing.
func _change(next: int) -> void:
	if get_tree().paused:
		get_tree().paused = false
	state = next
	var path: String = SCENES.get(next, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("SceneManager: no scene for state %d (%s)" % [next, path])
		return
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_warning("SceneManager: change_scene_to_file(%s) failed: %d" % [path, err])
