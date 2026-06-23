class_name LevelDef
extends Resource
## A finite, distance-based level definition (#51). Owns the run's LENGTH and how
## fast the world scrolls; together these make a run finite (D2, GAME_SCOPE §4.5:
## "one finite distance track ... finish line sits at the end"). Distance ≈ elapsed
## time via a mostly-constant scroll speed.
##
## MVP holds length + scroll speed only. The authored 4-phase pacing curve and the
## gate/obstacle layout along the track are the pacing director's + spawner's job
## (#13/#56, deferred) — this resource grows those fields when they land.

## Display name (Results / level-select later).
@export var display_name: String = "Level 01"

## Total run length in metres. Crossing this distance = win ("RUN COMPLETE").
## 320 m matches the DESIGN_SPEC Results stat example (screen 04).
@export var length_m: float = 320.0

## World scroll speed in metres/second. distance(t) = scroll_speed_mps * t, so the
## MVP run lasts length_m / scroll_speed_mps seconds (320 / 8 = 40 s — a tunable
## first-playtest length; the full ~5-min crescendo is the director's job, #13).
@export var scroll_speed_mps: float = 8.0

## --- Segment schedule (#13) --------------------------------------------------
## What appears along the track and WHERE (by `m` = metres into the run). This is
## the single authored source the GateSpawner + Targets both stream from (GAME_SCOPE
## §8: "segment-driven spawner — world-x placement, NOT lane indices"). Ops/kinds are
## STRINGS so this resource needs no dependency on Gate/Targets; each system maps them.
##
## MVP authors the schedule here as the script default (GAME_SCOPE: "MVP = hardcoded
## segment list; data-driven director v0.5.0"). A per-level .tres can override these
## later — until then level_01.tres just uses these defaults.

## Split Choice gate formations: `{"m": metres, "l": [op, value], "r": [op, value],
## "hijack"?: "l"|"r"}`. `op` is "add" | "sub" | "mul" | "div"; the ship's x at the
## crossing picks l vs r. `hijack` parks an Entropy occupant on that gate (#53) — its
## splice is DENIED unless the occupant is destroyed before the gate reaches the line.
@export var gate_formations: Array = [
	{"m": 45.0,  "l": ["mul", 2.0],  "r": ["add", 8.0]},   # ×2 vs +8 (count-dependent)
	{"m": 90.0,  "l": ["add", 15.0], "r": ["sub", 5.0]},   # grow vs trap
	{"m": 135.0, "l": ["mul", 3.0],  "r": ["div", 2.0], "hijack": "l"},  # the ×3 is hijacked — clear it to claim
	{"m": 180.0, "l": ["div", 2.0],  "r": ["mul", 2.0]},   # mirror — trap on the left
	{"m": 225.0, "l": ["add", 25.0], "r": ["mul", 3.0]},
	{"m": 270.0, "l": ["sub", 10.0], "r": ["add", 30.0]},
	# Back half (run length doubled to 640 m): the escalation continues so the extended
	# run stays populated instead of coasting to an empty finish.
	{"m": 315.0, "l": ["mul", 2.0],  "r": ["add", 10.0]},
	{"m": 365.0, "l": ["add", 20.0], "r": ["sub", 8.0]},
	{"m": 415.0, "l": ["mul", 3.0],  "r": ["div", 2.0], "hijack": "r"},
	{"m": 465.0, "l": ["div", 2.0],  "r": ["mul", 2.0]},
	{"m": 515.0, "l": ["add", 30.0], "r": ["mul", 3.0]},
	{"m": 565.0, "l": ["sub", 12.0], "r": ["add", 40.0]},
	{"m": 610.0, "l": ["mul", 3.0],  "r": ["add", 50.0]},
]

## Enemy waves: `{"m": metres, "kind": name, "count": n, "x"?: centre, "spread"?: px}`.
## `kind` is "glitch" | "rhombus" | "fractal" | "mixed". Without `x`, the wave is
## spread evenly across the playfield; with `x`, it clusters around that world-x.
## Escalates: light glitch probes early → fractals + a rhombus mid → dense mixed late.
@export var enemy_waves: Array = [
	{"m": 18.0,  "kind": "glitch",  "count": 4},
	{"m": 60.0,  "kind": "glitch",  "count": 5},
	{"m": 105.0, "kind": "fractal", "count": 2},
	{"m": 150.0, "kind": "mixed",   "count": 5},
	{"m": 200.0, "kind": "rhombus", "count": 1, "x": 540.0},
	{"m": 240.0, "kind": "mixed",   "count": 6},
	{"m": 290.0, "kind": "glitch",  "count": 7},
	# Back half (run length doubled to 640 m): denser, harder waves to the finish.
	{"m": 330.0, "kind": "fractal", "count": 3},
	{"m": 380.0, "kind": "mixed",   "count": 6},
	{"m": 430.0, "kind": "rhombus", "count": 2, "x": 540.0},
	{"m": 480.0, "kind": "mixed",   "count": 7},
	{"m": 530.0, "kind": "fractal", "count": 3},
	{"m": 580.0, "kind": "mixed",   "count": 8},
	{"m": 620.0, "kind": "glitch",  "count": 8},
]
