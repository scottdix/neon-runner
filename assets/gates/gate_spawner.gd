class_name GateSpawner
extends Node2D
## Places authored Split Choice gate formations along the finite track (#56) and
## fires the one the ship steered through. Each formation is two gates side by side
## (left/right half of the lane); the ship's x at the moment the formation reaches
## the crossing line picks which one applies — instant mental-math choice.
##
## The formation schedule is now authored on the LevelDef (#13): Run passes
## `level.gate_formations` to build_formations() after the level loads. Each spec uses
## STRING ops ("add"/"sub"/"mul"/"div"); we map them via Gate.op_from_string. (GAME_SCOPE
## §8: MVP = authored segment list on the level; data-driven .tres director is v0.5.0.)
## Formations scroll on the shared TrackView projection so they move in lockstep with
## the finish line, and are RECYCLED (freed) once they scroll well past the ship line.
##
## `update(distance, ship_x)` is pure logic (positions + crossing trigger + recycle) so
## it runs/asserts headless; _process just feeds it GameState.distance + the latest
## steer x. Triggering only calls gate.trigger(): the gate emits gate_passed and
## GameState applies the economy effect (swarm volume + battery). The spawner holds
## no GameState mutation — fully decoupled via the Events bus.

const GATE := preload("res://assets/gates/gate.gd")
const TRACK := preload("res://assets/levels/track.gd")

const LANE_SPLIT := 540.0           # left/right boundary (half of 1080)
const LEFT_CENTER := 280.0
const RIGHT_CENTER := 800.0
const RECYCLE_MARGIN := 220.0       # px below the screen before a passed formation is freed

var _formations: Array = []         # [{track_m, left:Gate, right:Gate, triggered:bool}, ...]
var _trigger_y := 1680.0            # ship line — a formation fires as it crosses this
var _ship_x := 540.0
var _design := Vector2(1080, 1920)
var triggers: int = 0               # gates fired so far (debug/verify)
var recycled: int = 0               # formations freed after passing the player (debug/verify)

## Gate-hijack (#53). Every gate gets a stable id (for the occupant + multiply-through
## band identity); hijacked gates queue here until Targets parks an occupant on them.
var _next_gate_id: int = 0
var _pending_hijacks: Array = []    # [{id, x}, ...] gates awaiting a parked enemy

## Boss-arena STANCE gates (#82/#83). Unlike scrolling formation gates, these are PARKED at a
## fixed y at the flanks of the arena for the WHOLE boss fight — the player steers through them
## to flip stance at will (the only way to switch mid-boss, since the formation schedule has run
## out by the climax). Each entry: {gate:Gate, band_min, band_max, armed:bool}. A gate FIRES once
## as the ship enters its band, then DISARMS; it RE-ARMS (and resets gate.has_been_triggered) once
## the ship leaves the band, so passing back and forth re-flips stance for the entire fight.
const BOSS_GATE_Y_FRAC := 0.62        # parked y as a fraction of design height (mid-low arena)
const BOSS_GATE_SPRAY_X := 150.0      # left-flank SPRAY (+) gate centre x
const BOSS_GATE_LANCE_X := 930.0      # right-flank LANCE (÷) gate centre x
const BOSS_GATE_HALF_BAND := 170.0    # x half-width that counts as "through" the parked gate
var _boss_gates: Array = []           # [{gate, band_min, band_max, armed}, ...]


## Run calls this with the ship's canvas y before adding us to the tree.
func setup(trigger_y: float) -> void:
	_trigger_y = trigger_y


func _ready() -> void:
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	Events.player_steered.connect(func(x: float, _n: float): _ship_x = x)


func _process(_delta: float) -> void:
	update(GameState.distance, _ship_x)


## Instantiate the level's Split Choice schedule (`level.gate_formations`). Each spec is
## `{"m": metres, "l": [op_string, value], "r": [op_string, value]}`. Replaces any
## existing formations (frees their gates). Choices escalate across the track.
func build_formations(specs: Array) -> void:
	_clear_formations()
	for s in specs:
		var l: Array = s["l"]
		var r: Array = s["r"]
		var left: Node2D = GATE.new()
		left.name = "GateL_%d" % int(s["m"])
		left.configure(GATE.op_from_string(l[0]), float(l[1]), 0.0, LANE_SPLIT, LEFT_CENTER)
		left.hijack_id = _next_gate_id
		_next_gate_id += 1
		var right: Node2D = GATE.new()
		right.name = "GateR_%d" % int(s["m"])
		right.configure(GATE.op_from_string(r[0]), float(r[1]), LANE_SPLIT, 1080.0, RIGHT_CENTER)
		right.hijack_id = _next_gate_id
		_next_gate_id += 1
		# Optional gate-hijack (#53): "hijack": "l"|"r" parks an Entropy occupant on that
		# gate; its splice is denied until the occupant is destroyed. Targets pulls the
		# pending list (take_pending_hijacks) and spawns the enemy bound to the gate id.
		match String(s.get("hijack", "")):
			"l":
				left.hijacked = true
				_pending_hijacks.append({"id": left.hijack_id, "x": LEFT_CENTER})
			"r":
				right.hijacked = true
				_pending_hijacks.append({"id": right.hijack_id, "x": RIGHT_CENTER})
		add_child(left)
		add_child(right)
		_formations.append({"track_m": s["m"], "left": left, "right": right, "triggered": false})


## APPEND one ad-hoc Split Choice formation mid-run (#86 Walled Gauntlet lane gates), WITHOUT
## clearing the authored schedule (unlike build_formations). A left gate spans the left lane (0..540)
## and a right gate the right lane (540..1080); as the formation crosses the line, update()'s existing
## contains_x logic fires ONLY the gate in the lane the ship is committed to — exactly the lane choice
## the gauntlet wants. Reuses the normal Gate path (configure + trigger -> gate_passed -> GameState),
## so there is no parallel economy code. `*_op` are Gate op strings ("add"/"sub"/"mul"/"div").
func spawn_split(track_m: float, left_op: String, left_val: float, right_op: String, right_val: float) -> void:
	var left: Node2D = GATE.new()
	left.name = "GauntletGateL_%d" % int(track_m)
	left.configure(GATE.op_from_string(left_op), left_val, 0.0, LANE_SPLIT, LEFT_CENTER)
	left.hijack_id = _next_gate_id
	_next_gate_id += 1
	var right: Node2D = GATE.new()
	right.name = "GauntletGateR_%d" % int(track_m)
	right.configure(GATE.op_from_string(right_op), right_val, LANE_SPLIT, 1080.0, RIGHT_CENTER)
	right.hijack_id = _next_gate_id
	_next_gate_id += 1
	add_child(left)
	add_child(right)
	_formations.append({"track_m": track_m, "left": left, "right": right, "triggered": false})


## Newly-built hijacked gates still needing a parked occupant; returned ONCE then
## cleared (Targets pulls these each step and spawns one enemy per id).
func take_pending_hijacks() -> Array:
	var out: Array = _pending_hijacks
	_pending_hijacks = []
	return out


## Inject the two PERSISTENT boss-arena stance gates (#82/#83) — run.gd calls this once when the
## boss ARMS. A SPRAY (+) gate on the left flank and a LANCE (÷) gate on the right flank are PARKED
## at a fixed mid-arena y for the whole fight. They reuse the normal Gate (configure + trigger ->
## gate_passed -> GameState flips stance), so there is no parallel stance path. update() re-arms them
## as the ship steers in/out, so the player can flip stance freely all fight. Idempotent — a second
## call is a no-op (the gates already exist). The bands are wide + on the flanks so the bottom-screen
## ship can always reach BOTH by steering to an edge.
func spawn_boss_stance_gates() -> void:
	if not _boss_gates.is_empty():
		return
	var y: float = _design.y * BOSS_GATE_Y_FRAC
	var spray: Node2D = GATE.new()
	spray.name = "BossGateSpray"
	# A "+1" gate: POSITIVE -> GameState._on_gate_passed sets SPRAY. value 1 keeps the economy nudge
	# tiny so the gate is a stance toggle, not a volume cheat during the climax.
	spray.configure(GATE.op_from_string("add"), 1.0, 0.0, 0.0, BOSS_GATE_SPRAY_X)
	spray.position.y = y
	spray.hijack_id = _next_gate_id
	_next_gate_id += 1
	add_child(spray)
	_boss_gates.append({
		"gate": spray,
		"band_min": BOSS_GATE_SPRAY_X - BOSS_GATE_HALF_BAND,
		"band_max": BOSS_GATE_SPRAY_X + BOSS_GATE_HALF_BAND,
		"armed": true,
	})
	var lance: Node2D = GATE.new()
	lance.name = "BossGateLance"
	# A "÷1" gate: NEGATIVE/focusing -> GameState._on_gate_passed sets LANCE. value 1 is IDENTITY on the
	# volume (÷1 leaves it untouched) so the gate is a pure stance toggle, not a volume cheat. NOTE: as
	# a negative gate it DOES cost one DRAIN_PER_NEGATIVE_GATE per ENTRY (GameState owns that), but the
	# gate only re-fires after the ship LEAVES the band — so focusing for a whole phase costs one drain,
	# not a per-frame bleed. That's an intentional "focusing has a price" risk; tune on device (#82/#83).
	lance.configure(GATE.op_from_string("div"), 1.0, 0.0, 0.0, BOSS_GATE_LANCE_X)
	lance.position.y = y
	lance.hijack_id = _next_gate_id
	_next_gate_id += 1
	add_child(lance)
	_boss_gates.append({
		"gate": lance,
		"band_min": BOSS_GATE_LANCE_X - BOSS_GATE_HALF_BAND,
		"band_max": BOSS_GATE_LANCE_X + BOSS_GATE_HALF_BAND,
		"armed": true,
	})


## Step the persistent boss stance gates against the ship's x (called from update). A gate FIRES once
## as the ship enters its band (flips stance via gate_passed), then DISARMS; it RE-ARMS — resetting
## gate.has_been_triggered so trigger() works again — once the ship leaves the band. So steering to the
## left flank sets SPRAY, to the right flank sets LANCE, freely, all fight. Pure logic (headless).
func _update_boss_gates(ship_x: float) -> void:
	for bg in _boss_gates:
		var inside: bool = ship_x >= bg["band_min"] and ship_x < bg["band_max"]
		if inside and bg["armed"]:
			bg["armed"] = false
			bg["gate"].has_been_triggered = false   # allow this re-entry to fire
			bg["gate"].trigger(GameState.projectile_count)
			triggers += 1
		elif not inside and not bg["armed"]:
			bg["armed"] = true                       # left the band — ready to fire again on re-entry


## Whether the persistent boss stance gates are live (verify/run.gd readability).
func boss_gate_count() -> int:
	return _boss_gates.size()


## Live POSITIVE gate bands for the multiply-through interaction (#53): each
## {id, x_min, x_max, y} in canvas space. Cheap snapshot — only a handful are ever live.
func positive_gate_bands() -> Array:
	var bands: Array = []
	for f in _formations:
		for g in [f["left"], f["right"]]:
			if g.is_positive():
				bands.append({"id": g.hijack_id, "x_min": g.span_min, "x_max": g.span_max, "y": g.position.y})
	return bands


## Current state of gate `id` so a parked occupant can ride it: {alive, pos}. `alive` is
## false once the gate recycled, so Targets drops the orphaned occupant.
func gate_info(id: int) -> Dictionary:
	for f in _formations:
		for g in [f["left"], f["right"]]:
			if int(g.hijack_id) == id:
				return {"alive": true, "pos": g.position}
	return {"alive": false, "pos": Vector2.ZERO}


## Targets reports gate `id`'s occupant was destroyed → its splice is now claimable.
func notify_hijack_cleared(id: int) -> void:
	for f in _formations:
		for g in [f["left"], f["right"]]:
			if int(g.hijack_id) == id:
				g.hijack_cleared = true
				return


## Scroll every formation to its current y, fire any that just crossed the line, and
## RECYCLE (free) any that have scrolled well past the ship — keeping only the
## formations still in play (#13: "recycles gates that pass behind the player").
func update(distance: float, ship_x: float) -> void:
	_ship_x = ship_x
	var survivors: Array = []
	for f in _formations:
		var y: float = TRACK.screen_y(f["track_m"], distance, _trigger_y)
		f["left"].position.y = y
		f["right"].position.y = y
		if not f["triggered"] and y >= _trigger_y:
			f["triggered"] = true
			var chosen: Node2D = f["left"] if f["left"].contains_x(ship_x) else f["right"]
			# Fire the chosen gate. It emits gate_passed; GameState applies the effect
			# (new swarm volume + battery drain on a negative gate). The spawner no
			# longer mutates GameState directly — decoupling (CLAUDE.md / review debt).
			chosen.trigger(GameState.projectile_count)
			triggers += 1
		# Recycle once it's well past the bottom, regardless of triggered: with monotonic
		# distance any formation reaching here has already crossed (and fired at) the ship
		# line, so this only adds robustness — a passed formation is never re-projected
		# forever, even if its crossing frame were ever skipped.
		if y > _design.y + RECYCLE_MARGIN:
			f["left"].queue_free()
			f["right"].queue_free()
			recycled += 1
		else:
			survivors.append(f)
	_formations = survivors
	# Persistent boss-arena stance gates (#82/#83): re-arm/fire against the same ship x so the player
	# can flip stance freely throughout the climax (no-op until run.gd injects them via spawn_boss_stance_gates).
	if not _boss_gates.is_empty():
		_update_boss_gates(ship_x)


func _clear_formations() -> void:
	for f in _formations:
		f["left"].queue_free()
		f["right"].queue_free()
	_formations.clear()
