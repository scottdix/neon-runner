extends SceneTree
## Headless verification for the screen flow + state machine (#60/#8, docs/design/SCREENS.md).
## Two parts:
##   1. Every menu screen scene loads, instantiates, and builds its UI in _ready without a
##      GDScript parse/runtime error (the headless dummy renderer is fine for Control trees).
##   2. SceneManager's state transitions are correct: BOOT→TITLE→RUN, pause/resume, the
##      run terminals route to RESULTS, and the Title branches reach GARAGE/SPLICE/SETTINGS.
##
##   tools/run-headless.sh res://tools/verify_flow.gd /tmp/verify_flow_result.txt
##
## NOTE: under `-s` the autoload nodes aren't attached to the tree during _initialize, so
## `get_tree()` (used by SceneManager) is null and node _ready is deferred. We therefore do
## all the work from _process — by the first idle frame the tree + autoloads are live, the
## same pattern verify_scene.gd uses. State enum: BOOT=0 TITLE=1 RUN=2 PAUSED=3 RESULTS=4
## GARAGE=5 SPLICE=6 SETTINGS=7 HOW_TO_PLAY=8.

const RESULT_PATH := "/tmp/verify_flow_result.txt"
const SCREENS := {
	"boot": "res://assets/ui/boot.tscn",
	"title": "res://assets/ui/title.tscn",
	"results": "res://assets/ui/results.tscn",
	"garage": "res://assets/ui/garage.tscn",
	"splice": "res://assets/ui/splice.tscn",
	"settings": "res://assets/ui/settings.tscn",
	"how_to_play": "res://assets/ui/how_to_play.tscn",
}

var _lines: Array[String] = []
var _ok := true
var _sm: Node = null
var _frame := 0
var _done := false


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false        # let the tree + autoloads come fully online first
	if _done:
		return true
	_done = true
	_run_checks()
	_lines.append("RESULT=%s" % ("PASS" if _ok else "FAIL"))
	_write()
	return true


func _run_checks() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_sm = root.get_node_or_null("SceneManager")
	if gs == null or _sm == null:
		_fail("autoload missing: GameState=%s SceneManager=%s" % [gs != null, _sm != null])
		return
	gs.call("wire_events")
	_sm.call("wire_events")

	# Part 1 — every screen builds its UI.
	for key in SCREENS:
		_smoke_screen(key, SCREENS[key])

	# Part 2 — state machine.
	if int(_sm.get("state")) != 0:
		_fail("initial state is not BOOT (got %s)" % _sm.get("state"))
	_sm.call("goto_title"); _expect(1, "goto_title → TITLE")
	_sm.call("start_run"); _expect(2, "start_run → RUN")
	_sm.call("pause_run"); _expect(3, "pause_run → PAUSED")
	if not paused:
		_fail("pause_run did not pause the tree")
	_sm.call("resume_run"); _expect(2, "resume_run → RUN")
	if paused:
		_fail("resume_run did not unpause the tree")

	# Win terminal routes to Results.
	gs.call("start_run"); gs.call("complete_run")
	_expect(4, "complete_run → RESULTS")
	if not bool(gs.get("run_won")):
		_fail("complete_run did not set run_won")

	# Loss terminal routes to Results.
	gs.call("start_run"); gs.call("fail_run")
	_expect(4, "fail_run → RESULTS")
	if bool(gs.get("run_won")):
		_fail("fail_run left run_won true")

	# Title branches.
	_sm.call("goto_garage"); _expect(5, "goto_garage → GARAGE")
	_sm.call("goto_splice"); _expect(6, "goto_splice → SPLICE")
	_sm.call("goto_settings"); _expect(7, "goto_settings → SETTINGS")
	_sm.call("goto_how_to_play"); _expect(8, "goto_how_to_play → HOW_TO_PLAY")
	_sm.call("goto_title"); _expect(1, "goto_title → TITLE")


func _smoke_screen(key: String, path: String) -> void:
	var packed: Variant = load(path)
	if packed == null:
		_fail("%s load FAIL: %s" % [key, path]); return
	var inst: Node = packed.instantiate()
	if inst == null:
		_fail("%s instantiate FAIL" % key); return
	root.add_child(inst)            # live tree → _ready runs synchronously, builds the UI
	var n := inst.get_child_count()
	_lines.append("screen %s: built %d children" % [key, n])
	if n < 2:
		_fail("%s built no UI" % key)
	inst.free()


func _expect(want: int, label: String) -> void:
	var got := int(_sm.get("state"))
	_lines.append("%s (state=%d)" % [label, got])
	if got != want:
		_fail("%s — expected state %d, got %d" % [label, want, got])


func _fail(msg: String) -> void:
	_lines.append("  FAIL: " + msg)
	_ok = false


func _write() -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	quit()
