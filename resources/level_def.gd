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
