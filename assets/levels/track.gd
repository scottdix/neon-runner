class_name TrackView
extends RefCounted
## Shared track→screen projection (#51/#56). One place that maps a world distance
## "track_m" (metres along the finite level) to a canvas y, so EVERYTHING that
## scrolls — the finish line, gate formations, later the spawner/grid — moves at
## the same rate. Diverging scroll rates read as broken, so they share this.
##
## Pure/static: never instantiated. Preload it and call TrackView.screen_y(...).

## Canvas pixels per world metre. With LevelDef scroll (~8 m/s) this sets the
## on-screen scroll speed; tuned so an object is visible approaching for ~3-4 s.
const PIXELS_PER_METER := 66.0


## Canvas y for an object authored at `track_m`, given the run's current
## `distance`. It sits exactly on `trigger_y` (the ship line) when the run reaches
## it; before that it's above (toward the top), after it scrolls on past the bottom.
static func screen_y(track_m: float, distance: float, trigger_y: float) -> float:
	return trigger_y - (track_m - distance) * PIXELS_PER_METER
