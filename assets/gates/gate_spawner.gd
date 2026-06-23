class_name GateSpawner
extends Node2D
## Places authored Split Choice gate formations along the finite track (#56) and
## fires the one the ship steered through. Each formation is two gates side by side
## (left/right half of the lane); the ship's x at the moment the formation reaches
## the crossing line picks which one applies — instant mental-math choice.
##
## MVP is a hardcoded formation list (GAME_SCOPE §4.5: "MVP = hardcoded segment
## list; data-driven director v0.5.0"). Migrating placement into LevelDef and a
## streaming spawner is #13. Formations scroll on the shared TrackView projection
## so they move in lockstep with the finish line.
##
## `update(distance, ship_x)` is pure logic (positions + crossing trigger) so it
## runs/asserts headless; _process just feeds it GameState.distance + the latest
## steer x. Triggering mutates GameState.projectile_count -> the fleet's fire volume
## reacts via Events (projectile_count_changed); the gate also emits gate_passed.

const GATE := preload("res://assets/gates/gate.gd")
const TRACK := preload("res://assets/levels/track.gd")

const LANE_SPLIT := 540.0           # left/right boundary (half of 1080)
const LEFT_CENTER := 280.0
const RIGHT_CENTER := 800.0

var _formations: Array = []         # [{track_m, left:Gate, right:Gate, triggered:bool}, ...]
var _trigger_y := 1680.0            # ship line — a formation fires as it crosses this
var _ship_x := 540.0
var triggers: int = 0               # gates fired so far (debug/verify)


## Run calls this with the ship's canvas y before adding us to the tree.
func setup(trigger_y: float) -> void:
	_trigger_y = trigger_y


func _ready() -> void:
	build_formations()
	Events.player_steered.connect(func(x: float, _n: float): _ship_x = x)


func _process(_delta: float) -> void:
	update(GameState.distance, _ship_x)


## Author the MVP Split Choice schedule and instantiate each formation's two gates.
## Choices escalate: easy growth early, real trade-offs (grow vs trap, ×N vs ÷N)
## later. All sit before the finish line (LevelDef default length 320 m).
func build_formations() -> void:
	var O := GATE.Operation
	var specs := [
		{"m": 45.0,  "l": [O.MULTIPLY, 2.0], "r": [O.ADD, 8.0]},       # ×2 vs +8 (count-dependent)
		{"m": 90.0,  "l": [O.ADD, 15.0],     "r": [O.SUBTRACT, 5.0]},  # grow vs trap
		{"m": 135.0, "l": [O.MULTIPLY, 3.0], "r": [O.DIVIDE, 2.0]},    # triple vs halve
		{"m": 180.0, "l": [O.DIVIDE, 2.0],   "r": [O.MULTIPLY, 2.0]},  # mirror — trap on the left
		{"m": 225.0, "l": [O.ADD, 25.0],     "r": [O.MULTIPLY, 3.0]},
		{"m": 270.0, "l": [O.SUBTRACT, 10.0], "r": [O.ADD, 30.0]},
	]
	for s in specs:
		var left: Node2D = GATE.new()
		left.name = "GateL_%d" % int(s["m"])
		left.configure(s["l"][0], s["l"][1], 0.0, LANE_SPLIT, LEFT_CENTER)
		var right: Node2D = GATE.new()
		right.name = "GateR_%d" % int(s["m"])
		right.configure(s["r"][0], s["r"][1], LANE_SPLIT, 1080.0, RIGHT_CENTER)
		add_child(left)
		add_child(right)
		_formations.append({"track_m": s["m"], "left": left, "right": right, "triggered": false})


## Scroll every formation to its current y and fire any that just crossed the line.
func update(distance: float, ship_x: float) -> void:
	_ship_x = ship_x
	for f in _formations:
		var y: float = TRACK.screen_y(f["track_m"], distance, _trigger_y)
		f["left"].position.y = y
		f["right"].position.y = y
		if not f["triggered"] and y >= _trigger_y:
			f["triggered"] = true
			var chosen: Node2D = f["left"] if f["left"].contains_x(ship_x) else f["right"]
			GameState.set_projectile_count(chosen.trigger(GameState.projectile_count))
			# Negative (−/÷) gates also cost Glow Battery (#55) — the risk side of
			# the choice. Positive gates only grow the swarm.
			if not chosen.is_positive():
				GameState.drain_battery(GameState.DRAIN_PER_NEGATIVE_GATE)
			triggers += 1
