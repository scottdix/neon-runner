class_name Boss
extends Node2D
## The end-of-RUN climax (#82): a multi-phase boss the swarm must crack to WIN. This is the
## "Spend" beat — after a run of banking volume + tokens, the player pours all of it into one
## fat target. It is NOT an endless spawner: it has HP, a fixed phase ladder, and a single death
## terminal (run.gd consumes boss_defeated -> GameState.complete_run()).
##
## Architecture (mirrors Fleet/Targets):
##   • ALL simulation lives in `step(delta)` so it runs + asserts HEADLESS with no GPU. _process
##     just calls step() then _render().
##   • Collision is a SINGLE FAT damage volume resolved by Fleet.consume_volumes (verified #54.8d):
##     one big circle, NO per-bullet Area2D bodies. Run injects the Fleet (set_fleet); Boss queries
##     it each frame for the bullet hits inside its hull, exactly like Targets does.
##   • Damage honours the #79 STANCE per-hit WEIGHT just like an armored Rhombus: the ARMORED phase
##     reuses RHOMBUS_PER_HIT_FLOOR semantics, so a light SPRAY bullet only CHIPS the hull and the
##     player must focus into a heavy LANCE to crack it (the phase telegraphs "switch to LANCE").
##   • Decoupled via the Events bus: emits boss_spawned / boss_phase_changed / boss_defeated. It
##     never reaches into GameState (run.gd owns the boss_active guard + the WIN call).
##
## Phase ladder (DRIVEN PURELY by step(), advanced on HP + time thresholds — emit ONCE each):
##   PHASE_TELEGRAPH — invulnerable wind-up (a fixed timer): the boss arrives + warns. No damage taken.
##   PHASE_ARMORED   — armored hull: SPRAY only chips (per-hit floor), forces a LANCE to make progress.
##   PHASE_ADD_SWARM — at an HP threshold the hull opens up + SPAWNS ADDS (Targets enemies), and a
##                     wide SPRAY is now the better answer (clear the adds) — the stance pendulum.
##   PHASE_DEFEATED  — HP hit 0: emit boss_defeated ONCE; run.gd calls GameState.complete_run().
##
## Subclasses (singularity.gd) override the mechanic hooks (gravity field, visual) but inherit the
## phase ladder + collision so every boss shares one battle-loop implementation.

# --- Phases ------------------------------------------------------------------
enum { PHASE_TELEGRAPH, PHASE_ARMORED, PHASE_ADD_SWARM, PHASE_DEFEATED }
const PHASE_NAMES := {
	PHASE_TELEGRAPH: "TELEGRAPH",
	PHASE_ARMORED: "ARMORED",
	PHASE_ADD_SWARM: "ADD_SWARM",
	PHASE_DEFEATED: "DEFEATED",
}

# --- Tuning (subclasses may override before spawn) ---------------------------
const DEFAULT_MAX_HP := 6000.0
## How long the invulnerable wind-up lasts (s). The hull takes NO damage during it (the warn-up).
const TELEGRAPH_TIME := 2.0
## HP fraction at/below which the boss opens into the ADD_SWARM phase. The ARMORED phase runs
## from 100%% down to here; the swarm phase runs from here to 0.
const ADD_SWARM_HP_FRAC := 0.5
## The fat hull collision radius (px) — boss-scale, resolved as ONE volume by Fleet.consume_volumes
## (no per-bullet bodies, verified #54.8d). Roughly a third of the screen wide.
const HULL_RADIUS := 360.0
## Damage per absorbed bullet — same base as a normal target so the swarm's DPS reads consistently.
const DAMAGE_PER_BULLET := 10.0
## ARMORED-phase per-hit WEIGHT FLOOR (reuses the Rhombus semantics, #79): a single bullet's stance
## weight must reach this to deal full damage. SPRAY (1.0) is sub-floor -> CHIP only; LANCE (6.0)
## clears it -> full damage. So the ARMORED phase FORCES a LANCE, exactly like cracking a Rhombus.
const ARMORED_PER_HIT_FLOOR := 5.0
## Sub-floor chip fraction during ARMORED (a thin SPRAY still grinds, no hard lockout — mirrors #74).
const ARMORED_CHIP_FRACTION := 0.15
## ADD_SWARM: how many adds the hull spits out when it opens, and the minimum gap (s) between waves.
const ADD_SPAWN_COUNT := 3
const ADD_SPAWN_INTERVAL := 2.5

# --- Live state (pure sim — the source of truth) -----------------------------
var boss_name: String = "BOSS"
var max_hp: float = DEFAULT_MAX_HP
var hp: float = DEFAULT_MAX_HP
var phase: int = PHASE_TELEGRAPH
var _telegraph_t: float = 0.0
var _add_timer: float = 0.0
var _armed: bool = false            # boss_spawned emitted once (spawn() called)
var _defeated_emitted: bool = false # boss_defeated emitted exactly once
## Pending adds the ADD_SWARM phase wants Targets to spawn this frame. run.gd drains this each frame
## (take_pending_adds) and feeds Targets — Boss never holds a Targets reference (one-way, bus-style).
## Each entry: {kind:String, x:float}.
var _pending_adds: Array[Dictionary] = []

var _fleet: Node2D = null           # injected by run.gd; queried for bullet hits (no back-ref)
var _design := Vector2(1080, 1920)

# --- Rendering (skipped headless) --------------------------------------------
const HULL_TEX_SIZE := 96
var _sprite: Sprite2D
var _flash: float = 0.0


func _ready() -> void:
	_design = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	_build_sprite()


func _process(delta: float) -> void:
	step(delta)
	_render()


## The fleet whose bullets damage the boss hull (run.gd injects it; like Targets.set_fleet, the two
## never reference each other directly). Null-safe: a bare unit-test Boss with no fleet just doesn't
## take fire-damage (the verify drives _absorb_hits / step thresholds directly instead).
func set_fleet(fleet: Node2D) -> void:
	_fleet = fleet


## Arm the boss (#82): seed HP, enter the TELEGRAPH wind-up, and announce boss_spawned ONCE so the
## HUD bar seeds + run.gd flips GameState.boss_active. Idempotent — a second call is a no-op.
func arm() -> void:
	if _armed:
		return
	_armed = true
	hp = max_hp
	phase = PHASE_TELEGRAPH
	_telegraph_t = 0.0
	_add_timer = 0.0
	_defeated_emitted = false
	Events.boss_spawned.emit(boss_name, max_hp)
	Events.boss_phase_changed.emit(PHASE_TELEGRAPH, PHASE_NAMES[PHASE_TELEGRAPH])


## Advance the battle one frame (PURE / headless). Order: (1) absorb the swarm's bullets into the
## hull as damage (skipped while telegraphing — invulnerable), (2) run the active phase's mechanic,
## (3) evaluate phase transitions on HP + time thresholds (each emits boss_phase_changed ONCE).
## No-op before arm() or after DEFEATED.
func step(delta: float) -> void:
	if not _armed or phase == PHASE_DEFEATED:
		return
	_flash = maxf(0.0, _flash - delta / 0.08)

	if phase == PHASE_TELEGRAPH:
		_telegraph_t += delta
		_step_mechanic(delta)
		if _telegraph_t >= TELEGRAPH_TIME:
			_enter_phase(PHASE_ARMORED)
		return

	# Damage-taking phases (ARMORED / ADD_SWARM): absorb the swarm's fire, then run the mechanic.
	_absorb_hits()
	_step_mechanic(delta)

	if phase == PHASE_ARMORED:
		if hp <= max_hp * ADD_SWARM_HP_FRAC:
			_enter_phase(PHASE_ADD_SWARM)
	elif phase == PHASE_ADD_SWARM:
		_step_add_swarm(delta)

	if hp <= 0.0 and phase != PHASE_DEFEATED:
		_enter_phase(PHASE_DEFEATED)


## Absorb the swarm's bullets inside the fat hull volume as damage (#54.8d single-volume path). Reads
## the live stance WEIGHT + pierce off the Fleet exactly like Targets._apply_damage: in ARMORED a
## sub-floor SPRAY bullet only CHIPS, a LANCE clears the floor for full damage. Null-safe without a
## fleet (the verify drives _apply_hits directly). One consume_volumes call, no per-bullet bodies.
func _absorb_hits() -> void:
	if _fleet == null:
		return
	var positions := PackedVector2Array([global_position])
	var radii := PackedFloat32Array([HULL_RADIUS])
	var hits: PackedInt32Array = _fleet.call("consume_volumes", positions, radii)
	if hits[0] <= 0:
		return
	var hw: float = float(_fleet.call("hit_weight")) if _fleet.has_method("hit_weight") else 1.0
	_apply_hits(hits[0], hw)


## Apply a frame's bullet hits to the hull (PURE — the verify calls this directly). The ARMORED phase
## reuses the Rhombus per-hit FLOOR (#79): a sub-floor per-hit weight (SPRAY 1.0) only chips; an
## above-floor weight (LANCE 6.0) deals full count*weight damage. The ADD_SWARM phase has the hull
## OPEN, so it takes full weighted damage from EITHER stance (the wide SPRAY is now viable again).
func _apply_hits(hits: int, hit_weight: float) -> void:
	if hits <= 0 or phase == PHASE_TELEGRAPH or phase == PHASE_DEFEATED:
		return
	_flash = 1.0
	if phase == PHASE_ARMORED and hit_weight < ARMORED_PER_HIT_FLOOR:
		# Sub-floor on the armored hull: chip grind only (forces the LANCE), never a clean crack.
		hp = maxf(0.0, hp - ARMORED_CHIP_FRACTION * DAMAGE_PER_BULLET)
	else:
		hp = maxf(0.0, hp - float(hits) * hit_weight * DAMAGE_PER_BULLET)


## Commit a phase transition: set the phase + announce it ONCE on the bus. DEFEATED additionally
## emits boss_defeated exactly once (the run's WIN terminal — run.gd calls complete_run on it).
## Each phase is entered at most once because step() only ever advances DOWN the ladder.
func _enter_phase(new_phase: int) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	Events.boss_phase_changed.emit(phase, PHASE_NAMES[phase])
	if phase == PHASE_ADD_SWARM:
		_on_enter_add_swarm()
	elif phase == PHASE_DEFEATED:
		if not _defeated_emitted:
			_defeated_emitted = true
			Events.boss_defeated.emit(boss_name, global_position)


## ADD_SWARM entry: open the hull + immediately spit the first add wave so the phase reads instantly.
func _on_enter_add_swarm() -> void:
	_add_timer = 0.0
	_queue_adds()


## ADD_SWARM upkeep: drip a fresh add wave every ADD_SPAWN_INTERVAL so the player must split attention
## between clearing adds (wants SPRAY) and chipping the now-open hull. Pure timer; run.gd drains the
## queue into Targets each frame.
func _step_add_swarm(delta: float) -> void:
	_add_timer += delta
	if _add_timer >= ADD_SPAWN_INTERVAL:
		_add_timer -= ADD_SPAWN_INTERVAL
		_queue_adds()


## Queue a wave of adds for run.gd to hand to Targets. Spread across the playfield width; "glitch"
## kind so they read as fast Entropy fodder the SPRAY clears. Boss never spawns enemies itself —
## it only declares intent (decoupling: Targets owns enemy lifecycle).
func _queue_adds() -> void:
	for i in ADD_SPAWN_COUNT:
		var x: float = lerpf(220.0, _design.x - 220.0, float(i) / float(maxi(1, ADD_SPAWN_COUNT - 1)))
		_pending_adds.append({"kind": "glitch", "x": x})


## Drain the pending adds (run.gd calls this each frame and feeds Targets). Returns + clears the
## queue. Mirrors GateSpawner.take_pending_hijacks — a one-way pull, no back-reference.
func take_pending_adds() -> Array[Dictionary]:
	var out := _pending_adds
	_pending_adds = []
	return out


## Subclass mechanic hook — runs every step() frame (incl. TELEGRAPH so a wind-up can foreshadow the
## mechanic). Base boss has no special mechanic; Singularity overrides this to pulse its gravity field.
func _step_mechanic(_delta: float) -> void:
	pass


# --- Observables (the headless verify asserts on these) ----------------------

func hp_fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


func current_phase() -> int:
	return phase


func is_defeated() -> bool:
	return phase == PHASE_DEFEATED


func pending_add_count() -> int:
	return _pending_adds.size()


# --- Rendering (skipped under headless; the sim above is the source of truth) -

func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Hull"
	_sprite.texture = _make_hull_texture()
	_sprite.modulate = _hull_color()
	# Scale the 96px texture up to roughly the hull diameter so the visual matches the collider.
	var diameter: float = HULL_RADIUS * 2.0
	_sprite.scale = Vector2(diameter / float(HULL_TEX_SIZE), diameter / float(HULL_TEX_SIZE))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # additive HDR -> blooms on device
	_sprite.material = mat
	add_child(_sprite)


func _render() -> void:
	if _sprite == null:
		return
	_sprite.visible = _armed and phase != PHASE_DEFEATED
	var col: Color = _hull_color()
	if _flash > 0.0:
		col = col.lerp(Palette.FLASH_WHITE, _flash * 0.8)
	_sprite.modulate = col


## Subclass-overridable hull tint (HDR so it clears the bloom threshold). Base = the Entropy rose.
func _hull_color() -> Color:
	return Palette.ENEMY_ROSE


## A soft radial hull disc (textured/additive so it blooms — draw_* never glows, memory gotcha).
func _make_hull_texture() -> ImageTexture:
	var img := Image.create(HULL_TEX_SIZE, HULL_TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := (HULL_TEX_SIZE - 1) * 0.5
	for y in HULL_TEX_SIZE:
		for x in HULL_TEX_SIZE:
			var d := Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
