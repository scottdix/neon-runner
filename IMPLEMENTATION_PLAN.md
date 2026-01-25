# Neon Runner: Implementation Plan

> A high-octane reimagining of the 'multiplier gate' genre, built with the soul of a classic arcade vector-shooter.

---

## Table of Contents

1. [Stack Recommendation](#stack-recommendation)
2. [Project Architecture](#project-architecture)
3. [Phase 1: Foundation](#phase-1-foundation)
4. [Phase 2: Project Setup](#phase-2-project-setup)
5. [Phase 3: Core Mechanics](#phase-3-core-mechanics)
6. [Phase 4: Neon Aesthetic](#phase-4-neon-aesthetic)
7. [Phase 5: Game Feel](#phase-5-game-feel)
8. [Phase 6: Difficulty Progression](#phase-6-difficulty-progression)
9. [Phase 7: Mobile Optimization](#phase-7-mobile-optimization)
10. [Technical Reference](#technical-reference)

---

## Stack Recommendation

### Primary Choice: Godot 4.x with GDScript

| Factor | Why Godot Wins |
|--------|----------------|
| **HDR 2D Glow** | WorldEnvironment handles bloom out of the box. Set RGB values > 1.0 and objects glow automatically. |
| **Shader Language** | GLSL-like syntax, lightweight, perfect for the reactive grid effect. |
| **Mobile Performance** | Dedicated Mobile renderer optimized for iOS/Android. |
| **Object Pooling** | Clean patterns that integrate well with the node system. |
| **Cost** | MIT license, no royalties, no licensing concerns. |
| **Learning Curve** | GDScript is Python-like; approachable for developers new to game dev. |

### When to Use C# Instead of GDScript

| Use GDScript For | Use C# For |
|------------------|------------|
| Scene scripts (player, gates, UI) | Object pooling system (if performance issues arise) |
| Autoloads (game state, events) | Complex math algorithms |
| Visual effects and particles | Large data processing |
| Rapid prototyping | Systems you might reuse in other projects |

**Recommendation:** Start 100% GDScript. Only introduce C# if profiling reveals bottlenecks.

---

## Project Architecture

### Folder Structure

```
neon_runner/
├── project.godot
├── .gitignore
│
├── addons/                          # Third-party plugins (if any)
│
├── autoload/                        # Singleton scripts (registered in Project Settings)
│   ├── events.gd                    # Global event bus
│   ├── game_state.gd                # Score, multiplier, settings
│   ├── audio_manager.gd             # Sound playback
│   ├── scene_manager.gd             # Scene transitions
│   └── object_pool.gd               # Projectile/effect pooling
│
├── assets/
│   ├── player/
│   │   ├── player.tscn
│   │   ├── player.gd
│   │   └── player_trail.tscn
│   │
│   ├── projectiles/
│   │   ├── projectile.tscn
│   │   ├── projectile.gd
│   │   └── projectile_sprite.png
│   │
│   ├── gates/
│   │   ├── gate_base.tscn
│   │   ├── gate_base.gd
│   │   ├── gate_multiply.tscn
│   │   └── gate_add.tscn
│   │
│   ├── obstacles/
│   │   ├── obstacle_base.tscn
│   │   └── obstacle_base.gd
│   │
│   ├── effects/
│   │   ├── explosion_particles.tscn
│   │   ├── collect_burst.tscn
│   │   ├── trail_segment.tscn
│   │   └── neon_glow.tres
│   │
│   ├── ui/
│   │   ├── hud/
│   │   │   ├── hud.tscn
│   │   │   ├── hud.gd
│   │   │   ├── score_display.tscn
│   │   │   └── multiplier_display.tscn
│   │   ├── main_menu/
│   │   │   ├── main_menu.tscn
│   │   │   └── main_menu.gd
│   │   └── game_over/
│   │       ├── game_over.tscn
│   │       └── game_over.gd
│   │
│   └── levels/
│       ├── game_world.tscn          # Main gameplay scene
│       └── game_world.gd
│
├── shaders/
│   ├── reactive_grid.gdshader       # Background grid with ripple effects
│   ├── neon_outline.gdshader        # Outline glow effect
│   └── pulse.gdshader               # Pulsing intensity effect
│
├── resources/                        # Custom Resource class definitions
│   ├── gate_data.gd
│   ├── difficulty_config.gd
│   └── player_data.gd
│
├── data/                             # Resource instances (.tres files)
│   ├── gates/
│   │   ├── multiply_2x.tres
│   │   ├── multiply_3x.tres
│   │   ├── add_5.tres
│   │   └── subtract_3.tres
│   └── difficulty/
│       ├── easy.tres
│       ├── normal.tres
│       └── hard.tres
│
└── audio/
    ├── music/
    │   ├── menu_theme.ogg
    │   ├── gameplay_loop.ogg
    │   └── game_over.ogg
    └── sfx/
        ├── gate_multiply.wav
        ├── gate_add.wav
        ├── gate_subtract.wav
        ├── explosion.wav
        ├── combo_up.wav
        └── ui_select.wav
```

### Autoload Registration Order

Register these in **Project > Project Settings > Autoload** in this order:

1. `Events` - res://autoload/events.gd
2. `GameState` - res://autoload/game_state.gd
3. `ObjectPool` - res://autoload/object_pool.gd
4. `AudioManager` - res://autoload/audio_manager.gd
5. `SceneManager` - res://autoload/scene_manager.gd

---

## Phase 1: Foundation

**Goal:** Get comfortable with Godot and prove the core aesthetic works.

### Tasks

1. **Install Godot 4.3+** (use the .NET version for future C# flexibility)
2. **Create a new project** named `neon_runner`
3. **Build a proof-of-concept scene:**
   - Black background (ColorRect or clear color)
   - WorldEnvironment node with glow enabled
   - A Line2D drawing a simple shape (hexagon, triangle)
   - HDR color values (e.g., `Color(0, 2.0, 2.5, 1.0)` for cyan glow)
   - Simple shader to make it pulse

### Proof of Concept: Glowing Shape

```gdscript
# test_glow.gd - Attach to a Line2D node
extends Line2D

func _ready():
    # Draw a hexagon
    var points_array: PackedVector2Array = []
    for i in range(6):
        var angle = i * TAU / 6
        points_array.append(Vector2(cos(angle), sin(angle)) * 100)
    points_array.append(points_array[0])  # Close the shape
    points = points_array

    # HDR color for glow (values > 1.0 trigger bloom)
    default_color = Color(0, 2.5, 3.0, 1.0)
    width = 3.0

    # Additive blending
    var mat = CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    material = mat

func _process(delta: float):
    # Pulse effect
    var pulse = (sin(Time.get_ticks_msec() * 0.005) + 1.0) / 2.0
    default_color = Color(0, 2.0 + pulse, 2.5 + pulse, 1.0)
```

### WorldEnvironment Setup

1. Add a `WorldEnvironment` node to your scene
2. Create a new `Environment` resource
3. Configure:
   - **Background > Mode:** Canvas
   - **Glow > Enabled:** Yes
   - **Glow > Intensity:** 1.5
   - **Glow > Bloom:** 0.2
   - **Glow > Blend Mode:** Additive
   - **Glow > HDR Threshold:** 1.0

### Deliverable

A glowing, pulsing geometric shape on a black background. This validates that the neon aesthetic will work.

---

## Phase 2: Project Setup

**Goal:** Establish the architectural foundation before building gameplay.

### Events Bus (autoload/events.gd)

```gdscript
extends Node

# Player events
signal player_died
signal player_lane_changed(new_lane: int)

# Gate events
signal gate_passed(gate_type: String, value: float, new_count: int)
signal gate_spawned(gate: Node2D)

# Game flow
signal game_started
signal game_paused
signal game_resumed
signal game_over(final_score: int)

# Scoring
signal score_changed(new_score: int)
signal multiplier_changed(new_multiplier: float)
signal combo_updated(combo_count: int)

# Effects
signal spawn_particles(position: Vector2, type: String)
signal trigger_screen_shake(intensity: float, duration: float)
signal trigger_grid_ripple(position: Vector2, is_implosion: bool)
```

### Game State (autoload/game_state.gd)

```gdscript
extends Node

# Run state
var current_score: int = 0
var high_score: int = 0
var projectile_count: int = 1
var combo_count: int = 0
var multiplier: float = 1.0
var distance_traveled: float = 0.0

# Settings
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0

const SAVE_PATH = "user://save.json"

func add_score(base_points: int) -> void:
    var actual_points = int(base_points * multiplier)
    current_score += actual_points
    Events.score_changed.emit(current_score)

func update_projectile_count(new_count: int) -> void:
    projectile_count = new_count
    # Check for milestones
    if projectile_count >= 100 and projectile_count < 110:
        Events.spawn_particles.emit(Vector2.ZERO, "milestone")
    elif projectile_count >= 500 and projectile_count < 510:
        Events.spawn_particles.emit(Vector2.ZERO, "milestone_large")

func increment_combo() -> void:
    combo_count += 1
    multiplier = min(10.0, 1.0 + combo_count * 0.1)
    Events.combo_updated.emit(combo_count)
    Events.multiplier_changed.emit(multiplier)

func break_combo() -> void:
    combo_count = 0
    multiplier = 1.0
    Events.combo_updated.emit(combo_count)
    Events.multiplier_changed.emit(multiplier)

func reset_run() -> void:
    if current_score > high_score:
        high_score = current_score
        save_data()
    current_score = 0
    projectile_count = 1
    combo_count = 0
    multiplier = 1.0
    distance_traveled = 0.0

func save_data() -> void:
    var data = {
        "high_score": high_score,
        "master_volume": master_volume,
        "sfx_volume": sfx_volume,
        "music_volume": music_volume
    }
    var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))

func load_data() -> void:
    if FileAccess.file_exists(SAVE_PATH):
        var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
        if file:
            var data = JSON.parse_string(file.get_as_text())
            if data:
                high_score = data.get("high_score", 0)
                master_volume = data.get("master_volume", 1.0)
                sfx_volume = data.get("sfx_volume", 1.0)
                music_volume = data.get("music_volume", 1.0)

func _ready() -> void:
    load_data()
```

### Object Pool (autoload/object_pool.gd)

```gdscript
extends Node

var _pools: Dictionary = {}      # { "pool_name": [available_objects] }
var _active: Dictionary = {}     # { "pool_name": [active_objects] }
var _scenes: Dictionary = {}     # { "pool_name": PackedScene }

func register_pool(pool_name: String, scene: PackedScene, initial_count: int = 10) -> void:
    _scenes[pool_name] = scene
    _pools[pool_name] = []
    _active[pool_name] = []

    for i in initial_count:
        var obj = scene.instantiate()
        obj.set_meta("pool_name", pool_name)
        _deactivate_object(obj)
        _pools[pool_name].append(obj)

func get_object(pool_name: String) -> Node:
    if not pool_name in _pools:
        push_error("Pool '%s' not registered" % pool_name)
        return null

    var obj: Node
    if _pools[pool_name].size() > 0:
        obj = _pools[pool_name].pop_back()
    else:
        # Pool exhausted, create new instance
        obj = _scenes[pool_name].instantiate()
        obj.set_meta("pool_name", pool_name)

    _active[pool_name].append(obj)
    _activate_object(obj)
    return obj

func return_object(obj: Node) -> void:
    var pool_name = obj.get_meta("pool_name", "")
    if pool_name.is_empty():
        push_error("Object has no pool_name metadata")
        obj.queue_free()
        return

    _deactivate_object(obj)
    _active[pool_name].erase(obj)
    _pools[pool_name].append(obj)

func return_all(pool_name: String) -> void:
    if pool_name in _active:
        for obj in _active[pool_name].duplicate():
            return_object(obj)

func get_active_count(pool_name: String) -> int:
    if pool_name in _active:
        return _active[pool_name].size()
    return 0

func _activate_object(obj: Node) -> void:
    obj.set_process(true)
    obj.set_physics_process(true)
    if obj is Node2D:
        obj.visible = true
    if obj.has_method("reset"):
        obj.reset()

func _deactivate_object(obj: Node) -> void:
    obj.set_process(false)
    obj.set_physics_process(false)
    if obj is Node2D:
        obj.visible = false
        obj.position = Vector2(-9999, -9999)
    if obj.get_parent():
        obj.get_parent().remove_child(obj)
```

---

## Phase 3: Core Mechanics

**Goal:** Playable prototype with basic gameplay loop.

### Game State Machine

```gdscript
# game_controller.gd
extends Node

enum State { MENU, PLAYING, PAUSED, GAME_OVER }

var current_state: State = State.MENU

func change_state(new_state: State) -> void:
    _exit_state(current_state)
    current_state = new_state
    _enter_state(new_state)

func _exit_state(state: State) -> void:
    match state:
        State.PLAYING:
            get_tree().paused = true
        State.PAUSED:
            pass

func _enter_state(state: State) -> void:
    match state:
        State.MENU:
            SceneManager.transition_to("res://assets/ui/main_menu/main_menu.tscn")
        State.PLAYING:
            get_tree().paused = false
            Events.game_started.emit()
        State.PAUSED:
            get_tree().paused = true
            Events.game_paused.emit()
        State.GAME_OVER:
            Events.game_over.emit(GameState.current_score)
```

### Lane-Based Movement

```gdscript
# player.gd
extends Node2D

@export var lane_count: int = 3
@export var lane_width: float = 100.0
@export var move_speed: float = 15.0

var current_lane: int = 1  # Start in center
var target_x: float = 0.0

func _ready() -> void:
    target_x = get_lane_position(current_lane)
    position.x = target_x

func _process(delta: float) -> void:
    # Smooth movement to target lane
    position.x = lerp(position.x, target_x, move_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenDrag or event is InputEventScreenTouch:
        # Handle swipe detection (simplified)
        pass

func move_left() -> void:
    if current_lane > 0:
        current_lane -= 1
        target_x = get_lane_position(current_lane)
        Events.player_lane_changed.emit(current_lane)

func move_right() -> void:
    if current_lane < lane_count - 1:
        current_lane += 1
        target_x = get_lane_position(current_lane)
        Events.player_lane_changed.emit(current_lane)

func get_lane_position(lane: int) -> float:
    var total_width = lane_width * (lane_count - 1)
    var start_x = -total_width / 2.0
    return start_x + lane * lane_width
```

### Swipe Detection

```gdscript
# swipe_detector.gd
extends Node

signal swipe_left
signal swipe_right
signal swipe_up
signal swipe_down

const SWIPE_THRESHOLD: float = 50.0
const TIME_THRESHOLD: float = 300.0  # milliseconds

var start_position: Vector2
var start_time: float

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            start_position = event.position
            start_time = Time.get_ticks_msec()
        else:
            _check_swipe(event.position)

func _check_swipe(end_position: Vector2) -> void:
    var duration = Time.get_ticks_msec() - start_time
    if duration > TIME_THRESHOLD:
        return  # Too slow

    var delta = end_position - start_position
    if delta.length() < SWIPE_THRESHOLD:
        return  # Too short

    if abs(delta.x) > abs(delta.y):
        if delta.x > 0:
            swipe_right.emit()
        else:
            swipe_left.emit()
    else:
        if delta.y > 0:
            swipe_down.emit()
        else:
            swipe_up.emit()
```

### Gate System

```gdscript
# gate_base.gd
extends Area2D

enum Operation { ADD, SUBTRACT, MULTIPLY, DIVIDE }

@export var operation: Operation = Operation.MULTIPLY
@export var value: float = 2.0
@export var gate_color: Color = Color.CYAN

var has_been_triggered: bool = false

func apply(current_count: int) -> int:
    match operation:
        Operation.ADD:
            return current_count + int(value)
        Operation.SUBTRACT:
            return max(1, current_count - int(value))
        Operation.MULTIPLY:
            return current_count * int(value)
        Operation.DIVIDE:
            return max(1, current_count / int(value))
    return current_count

func get_display_text() -> String:
    match operation:
        Operation.ADD:
            return "+%d" % int(value)
        Operation.SUBTRACT:
            return "-%d" % int(value)
        Operation.MULTIPLY:
            return "x%d" % int(value)
        Operation.DIVIDE:
            return "/%d" % int(value)
    return ""

func trigger(projectile_count: int) -> int:
    if has_been_triggered:
        return projectile_count

    has_been_triggered = true
    var new_count = apply(projectile_count)

    Events.gate_passed.emit(Operation.keys()[operation], value, new_count)
    Events.trigger_grid_ripple.emit(global_position, operation == Operation.DIVIDE)

    return new_count
```

### Projectile Manager

```gdscript
# projectile_manager.gd
extends Node2D

const POOL_NAME = "projectile"
const INITIAL_POOL_SIZE = 300

var active_projectiles: Array[Node2D] = []

func _ready() -> void:
    ObjectPool.register_pool(
        POOL_NAME,
        preload("res://assets/projectiles/projectile.tscn"),
        INITIAL_POOL_SIZE
    )

    Events.gate_passed.connect(_on_gate_passed)

func spawn_projectile(pos: Vector2) -> Node2D:
    var projectile = ObjectPool.get_object(POOL_NAME)
    if projectile:
        projectile.position = pos
        add_child(projectile)
        active_projectiles.append(projectile)
    return projectile

func remove_projectile(projectile: Node2D) -> void:
    active_projectiles.erase(projectile)
    ObjectPool.return_object(projectile)

func _on_gate_passed(_type: String, _value: float, new_count: int) -> void:
    var current_count = active_projectiles.size()

    if new_count > current_count:
        # Spawn additional projectiles
        var to_spawn = new_count - current_count
        for i in to_spawn:
            var offset = Vector2(randf_range(-20, 20), randf_range(-10, 10))
            spawn_projectile(active_projectiles[0].position + offset)
    elif new_count < current_count:
        # Remove excess projectiles
        var to_remove = current_count - new_count
        for i in to_remove:
            if active_projectiles.size() > 1:
                var projectile = active_projectiles.pop_back()
                ObjectPool.return_object(projectile)

    GameState.update_projectile_count(new_count)
```

---

## Phase 4: Neon Aesthetic

**Goal:** Transform the prototype into the intended visual style.

### Reactive Grid Shader (shaders/reactive_grid.gdshader)

```glsl
shader_type canvas_item;

// Grid appearance
uniform vec4 grid_color : source_color = vec4(0.04, 0.08, 0.2, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float grid_spacing = 40.0;
uniform float line_thickness = 1.5;

// World mapping
uniform vec2 grid_world_size = vec2(1920.0, 1080.0);
uniform float time_sec = 0.0;

// Ripple system (up to 8 simultaneous ripples)
const int MAX_RIPPLES = 8;
uniform int active_ripple_count = 0;
uniform vec2 ripple_origins[MAX_RIPPLES];
uniform float ripple_start_times[MAX_RIPPLES];
uniform float ripple_types[MAX_RIPPLES];  // 1.0 = outward, -1.0 = inward

// Ripple parameters
uniform float ripple_speed = 800.0;
uniform float ripple_width = 60.0;
uniform float ripple_strength = 30.0;
uniform float ripple_decay_distance = 1200.0;

// Ambient wave
uniform float ambient_wave_strength = 2.0;
uniform float ambient_wave_speed = 0.5;

vec2 calculate_displacement(vec2 world_pos) {
    vec2 total_displacement = vec2(0.0);

    // Process each active ripple
    for (int i = 0; i < MAX_RIPPLES; i++) {
        if (i >= active_ripple_count) break;

        float elapsed = time_sec - ripple_start_times[i];
        if (elapsed < 0.0) continue;

        vec2 origin = ripple_origins[i];
        float dist = distance(world_pos, origin);
        float wave_front = elapsed * ripple_speed;

        float wave_start = wave_front - ripple_width;
        float wave_end = wave_front;

        if (dist >= wave_start && dist <= wave_end) {
            float t = (dist - wave_start) / ripple_width;
            float wave_shape = sin(t * 3.14159);
            float fade = max(0.0, 1.0 - dist / ripple_decay_distance);
            fade = fade * fade;

            vec2 direction = normalize(world_pos - origin);
            float strength = wave_shape * ripple_strength * fade * ripple_types[i];
            total_displacement += direction * strength;
        }
    }

    // Ambient background waves
    float ambient_x = sin(world_pos.y * 0.01 + time_sec * ambient_wave_speed) * ambient_wave_strength;
    float ambient_y = cos(world_pos.x * 0.008 + time_sec * ambient_wave_speed * 0.7) * ambient_wave_strength;
    total_displacement += vec2(ambient_x, ambient_y);

    return total_displacement;
}

void fragment() {
    vec2 world_pos = UV * grid_world_size;
    vec2 displacement = calculate_displacement(world_pos);
    vec2 grid_pos = world_pos + displacement;

    // Calculate grid lines
    float x_line = mod(grid_pos.x, grid_spacing);
    float y_line = mod(grid_pos.y, grid_spacing);

    float half_thickness = line_thickness * 0.5;
    float x_dist = min(x_line, grid_spacing - x_line);
    float y_dist = min(y_line, grid_spacing - y_line);

    float x_alpha = 1.0 - smoothstep(0.0, half_thickness, x_dist);
    float y_alpha = 1.0 - smoothstep(0.0, half_thickness, y_dist);
    float line_alpha = max(x_alpha, y_alpha);

    // Color based on distortion
    float effect_strength = length(displacement) / (ripple_strength + ambient_wave_strength);
    effect_strength = clamp(effect_strength, 0.0, 1.0);

    vec4 final_color = mix(grid_color, highlight_color, effect_strength * 0.5);
    final_color.rgb *= (1.0 + effect_strength * 2.0);

    COLOR = vec4(final_color.rgb, line_alpha * final_color.a);
}
```

### Grid Controller Script

```gdscript
# reactive_grid.gd
extends ColorRect

const MAX_RIPPLES = 8

var ripple_origins: Array[Vector2] = []
var ripple_start_times: Array[float] = []
var ripple_types: Array[float] = []
var current_time: float = 0.0

func _ready() -> void:
    for i in range(MAX_RIPPLES):
        ripple_origins.append(Vector2.ZERO)
        ripple_start_times.append(-999.0)
        ripple_types.append(1.0)

    material.set_shader_parameter("grid_world_size", size)
    Events.trigger_grid_ripple.connect(_on_trigger_ripple)

func _process(delta: float) -> void:
    current_time += delta
    material.set_shader_parameter("time_sec", current_time)
    material.set_shader_parameter("ripple_origins", ripple_origins)
    material.set_shader_parameter("ripple_start_times", ripple_start_times)
    material.set_shader_parameter("ripple_types", ripple_types)
    material.set_shader_parameter("active_ripple_count", _get_active_count())

func _on_trigger_ripple(position: Vector2, is_implosion: bool) -> void:
    var oldest_idx = 0
    var oldest_time = ripple_start_times[0]

    for i in range(MAX_RIPPLES):
        if ripple_start_times[i] < oldest_time:
            oldest_time = ripple_start_times[i]
            oldest_idx = i

    ripple_origins[oldest_idx] = position
    ripple_start_times[oldest_idx] = current_time
    ripple_types[oldest_idx] = -1.0 if is_implosion else 1.0

func _get_active_count() -> int:
    var count = 0
    for t in ripple_start_times:
        if current_time - t < 3.0:
            count += 1
    return count
```

### Neon Trail System

```gdscript
# neon_trail.gd
extends Line2D

@export var max_points: int = 50
@export var point_spacing: float = 5.0
@export var trail_lifetime: float = 0.5
@export var trail_color: Color = Color(0, 2.0, 2.5, 1.0)

var point_ages: Array[float] = []
var target: Node2D

func _ready() -> void:
    width = 4.0

    # Tapered width
    var width_curve = Curve.new()
    width_curve.add_point(Vector2(0.0, 1.0))
    width_curve.add_point(Vector2(0.5, 0.6))
    width_curve.add_point(Vector2(1.0, 0.0))
    self.width_curve = width_curve

    # Color gradient
    var grad = Gradient.new()
    grad.set_color(0, trail_color)
    grad.set_color(1, Color(trail_color.r * 0.3, trail_color.g * 0.3, trail_color.b * 0.3, 0.0))
    gradient = grad

    begin_cap_mode = Line2D.LINE_CAP_ROUND
    end_cap_mode = Line2D.LINE_CAP_ROUND
    joint_mode = Line2D.LINE_JOINT_ROUND

    var mat = CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    material = mat

func _process(delta: float) -> void:
    if target == null:
        return

    var target_pos = target.global_position

    if get_point_count() == 0 or target_pos.distance_to(get_point_position(0)) >= point_spacing:
        add_point(target_pos, 0)
        point_ages.insert(0, 0.0)

    var i = point_ages.size() - 1
    while i >= 0:
        point_ages[i] += delta
        if point_ages[i] >= trail_lifetime:
            remove_point(i)
            point_ages.remove_at(i)
        i -= 1

    while get_point_count() > max_points:
        remove_point(get_point_count() - 1)
        point_ages.pop_back()
```

---

## Phase 5: Game Feel

**Goal:** Make every action feel impactful through feedback.

### Feedback System

```gdscript
# feedback_manager.gd
extends Node

@onready var screen_flash: ColorRect = $ScreenFlash
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
    Events.gate_passed.connect(_on_gate_passed)
    Events.player_died.connect(_on_player_died)
    Events.trigger_screen_shake.connect(_on_screen_shake)

func _on_gate_passed(gate_type: String, value: float, new_count: int) -> void:
    match gate_type:
        "MULTIPLY":
            _flash_screen(Color(0, 1, 1, 0.3), 0.1)
            if value >= 3:
                _shake_screen(0.3, 0.2)
            AudioManager.play_sfx("gate_multiply")
        "ADD":
            _flash_screen(Color(0, 1, 0, 0.2), 0.08)
            AudioManager.play_sfx("gate_add")
        "SUBTRACT", "DIVIDE":
            _flash_screen(Color(1, 0, 0, 0.2), 0.1)
            AudioManager.play_sfx("gate_subtract")

    # Combo feedback
    if gate_type in ["MULTIPLY", "ADD"]:
        GameState.increment_combo()
    else:
        GameState.break_combo()

func _on_player_died() -> void:
    _shake_screen(0.5, 0.3)
    _flash_screen(Color(1, 0, 0, 0.5), 0.2)
    AudioManager.play_sfx("explosion")

func _flash_screen(color: Color, duration: float) -> void:
    screen_flash.color = color
    screen_flash.visible = true
    var tween = create_tween()
    tween.tween_property(screen_flash, "color:a", 0.0, duration)
    tween.tween_callback(func(): screen_flash.visible = false)

func _shake_screen(intensity: float, duration: float) -> void:
    var original_offset = camera.offset
    var tween = create_tween()

    var shake_count = int(duration / 0.05)
    for i in shake_count:
        var offset = Vector2(
            randf_range(-intensity, intensity) * 10,
            randf_range(-intensity, intensity) * 10
        )
        tween.tween_property(camera, "offset", offset, 0.05)

    tween.tween_property(camera, "offset", original_offset, 0.05)

func _on_screen_shake(intensity: float, duration: float) -> void:
    _shake_screen(intensity, duration)
```

### Audio Manager

```gdscript
# audio_manager.gd
extends Node

const MAX_SFX_PLAYERS = 8

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []

var music_tracks: Dictionary = {}
var sfx_sounds: Dictionary = {}

func _ready() -> void:
    music_player = AudioStreamPlayer.new()
    music_player.bus = "Music"
    add_child(music_player)

    for i in MAX_SFX_PLAYERS:
        var player = AudioStreamPlayer.new()
        player.bus = "SFX"
        add_child(player)
        sfx_players.append(player)

    _load_audio()

func _load_audio() -> void:
    # Load music
    music_tracks["menu"] = preload("res://audio/music/menu_theme.ogg")
    music_tracks["gameplay"] = preload("res://audio/music/gameplay_loop.ogg")
    music_tracks["game_over"] = preload("res://audio/music/game_over.ogg")

    # Load SFX
    sfx_sounds["gate_multiply"] = preload("res://audio/sfx/gate_multiply.wav")
    sfx_sounds["gate_add"] = preload("res://audio/sfx/gate_add.wav")
    sfx_sounds["gate_subtract"] = preload("res://audio/sfx/gate_subtract.wav")
    sfx_sounds["explosion"] = preload("res://audio/sfx/explosion.wav")
    sfx_sounds["combo_up"] = preload("res://audio/sfx/combo_up.wav")

func play_music(track_name: String, fade_duration: float = 0.5) -> void:
    if track_name in music_tracks:
        var tween = create_tween()
        tween.tween_property(music_player, "volume_db", -80, fade_duration)
        await tween.finished
        music_player.stream = music_tracks[track_name]
        music_player.play()
        tween = create_tween()
        tween.tween_property(music_player, "volume_db", 0, fade_duration)

func play_sfx(sound_name: String) -> void:
    if sound_name in sfx_sounds:
        for player in sfx_players:
            if not player.playing:
                player.stream = sfx_sounds[sound_name]
                player.play()
                return
        sfx_players[0].stream = sfx_sounds[sound_name]
        sfx_players[0].play()
```

---

## Phase 6: Difficulty Progression

**Goal:** Keep players engaged across runs with dynamic challenge.

### Difficulty Controller

```gdscript
# difficulty_controller.gd
extends Node

# Base parameters
var base_scroll_speed: float = 5.0
var current_difficulty: float = 0.0

# Scaling parameters (modified by difficulty)
var scroll_speed_multiplier: float = 1.0
var obstacle_frequency: float = 0.3
var gate_complexity: int = 1
var negative_gate_chance: float = 0.2

# Adaptive difficulty
var recent_deaths: int = 0
var recent_successes: int = 0

func _ready() -> void:
    Events.gate_passed.connect(_on_gate_passed)
    Events.player_died.connect(_on_player_died)

func update(distance_traveled: float) -> void:
    # Base difficulty from distance
    var base_difficulty = distance_traveled / 1000.0

    # Apply adaptive adjustment
    var adaptive_modifier = (recent_successes - recent_deaths * 2) * 0.05
    adaptive_modifier = clamp(adaptive_modifier, -0.3, 0.3)

    current_difficulty = max(0, base_difficulty + adaptive_modifier)

    # Update parameters
    scroll_speed_multiplier = 1.0 + (current_difficulty * 0.1)
    scroll_speed_multiplier = min(scroll_speed_multiplier, 2.5)

    obstacle_frequency = 0.3 + (current_difficulty * 0.05)
    obstacle_frequency = min(obstacle_frequency, 0.8)

    gate_complexity = int(current_difficulty / 3.0) + 1
    gate_complexity = min(gate_complexity, 3)

    negative_gate_chance = 0.2 + (current_difficulty * 0.03)
    negative_gate_chance = min(negative_gate_chance, 0.5)

func get_scroll_speed() -> float:
    return base_scroll_speed * scroll_speed_multiplier

func should_spawn_obstacle() -> bool:
    return randf() < obstacle_frequency

func should_spawn_negative_gate() -> bool:
    return randf() < negative_gate_chance

func _on_gate_passed(type: String, _value: float, _count: int) -> void:
    if type in ["MULTIPLY", "ADD"]:
        recent_successes += 1
        if recent_successes > 20:
            recent_successes = 20
    else:
        recent_successes = max(0, recent_successes - 2)

func _on_player_died() -> void:
    recent_deaths += 1
    if recent_deaths > 5:
        recent_deaths = 5
    recent_successes = 0
```

### Spawner with Rest Zones

```gdscript
# spawner.gd
extends Node2D

@export var spawn_distance: float = 1000.0
@export var min_gate_spacing: float = 200.0
@export var rest_zone_length: float = 400.0

var last_spawn_z: float = 0.0
var challenges_since_rest: int = 0
var max_challenges_before_rest: int = 5

@onready var difficulty: DifficultyController = $DifficultyController

func _process(_delta: float) -> void:
    var player_z = get_player_z()

    while last_spawn_z < player_z + spawn_distance:
        if _should_spawn_rest():
            _spawn_rest_zone()
            challenges_since_rest = 0
        else:
            _spawn_challenge()
            challenges_since_rest += 1

func _should_spawn_rest() -> bool:
    if challenges_since_rest < max_challenges_before_rest:
        return false
    # Pseudo-random with increasing chance
    var chance = (challenges_since_rest - max_challenges_before_rest + 1) * 0.2
    return randf() < chance

func _spawn_rest_zone() -> void:
    last_spawn_z += rest_zone_length

func _spawn_challenge() -> void:
    # Spawn gate pair
    var left_gate = _create_gate(0)
    var right_gate = _create_gate(2)

    left_gate.position.z = last_spawn_z
    right_gate.position.z = last_spawn_z

    add_child(left_gate)
    add_child(right_gate)

    last_spawn_z += min_gate_spacing + randf_range(0, 100)

func _create_gate(lane: int) -> Node2D:
    var gate = preload("res://assets/gates/gate_base.tscn").instantiate()
    gate.position.x = _lane_to_x(lane)

    if difficulty.should_spawn_negative_gate():
        gate.operation = Gate.Operation.SUBTRACT
        gate.value = randi_range(1, 3)
    else:
        if randf() < 0.6:
            gate.operation = Gate.Operation.MULTIPLY
            gate.value = randi_range(2, 3)
        else:
            gate.operation = Gate.Operation.ADD
            gate.value = randi_range(3, 10)

    return gate

func _lane_to_x(lane: int) -> float:
    return (lane - 1) * 100.0

func get_player_z() -> float:
    # Implement based on your coordinate system
    return 0.0
```

---

## Phase 7: Mobile Optimization

**Goal:** Consistent 60fps on mid-range mobile devices.

### Performance Targets

| Metric | Target | Warning Threshold |
|--------|--------|-------------------|
| Draw Calls | < 100 | > 150 |
| Physics Bodies | < 200 | > 300 |
| Visible Particles | < 1000 | > 1500 |
| Script Time | < 5ms | > 8ms |
| Frame Time | < 16.67ms | > 20ms |

### Optimization Checklist

- [ ] **Texture Atlas:** Combine all projectile/effect sprites into one atlas
- [ ] **Object Pooling:** Pre-allocate 300+ projectiles, 50+ particles effects
- [ ] **GPUParticles2D:** Use for explosions (50+ particles)
- [ ] **CPUParticles2D:** Use for small effects (< 20 particles)
- [ ] **Collision Layers:** Only enable necessary layer/mask combinations
- [ ] **Off-screen Processing:** Disable for objects outside viewport
- [ ] **MultiMesh:** Consider for 200+ identical sprites
- [ ] **Shader Optimization:** Pre-compute values in vertex shader where possible

### Performance Monitoring

```gdscript
# debug_overlay.gd
extends CanvasLayer

@onready var label: Label = $Label

var update_interval: float = 0.5
var time_since_update: float = 0.0

func _process(delta: float) -> void:
    time_since_update += delta
    if time_since_update >= update_interval:
        time_since_update = 0.0
        _update_stats()

func _update_stats() -> void:
    var fps = Performance.get_monitor(Performance.TIME_FPS)
    var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
    var objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
    var physics_2d = Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
    var memory = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

    label.text = """FPS: %d
Draw Calls: %d
Objects: %d
Physics Bodies: %d
Memory: %.1f MB""" % [fps, draw_calls, objects, physics_2d, memory]
```

### Renderer Selection

| Renderer | Use Case |
|----------|----------|
| **Mobile** | Primary choice for iOS/Android |
| **Compatibility** | Fallback for older devices, WebGL |
| **Forward+** | Desktop/PC only |

Set in **Project Settings > Rendering > Renderer > Rendering Method**.

---

## Technical Reference

### Key Godot 4 Concepts

| Concept | Description |
|---------|-------------|
| **Autoload** | Singleton scripts available globally |
| **Signals** | Event system for decoupled communication |
| **Tweens** | Programmatic animations |
| **Shaders** | GPU programs for visual effects |
| **Resources** | Reusable data containers |

### Useful Godot Plugins

| Plugin | Purpose |
|--------|---------|
| **[PerfBullets](https://godotengine.org/asset-library/asset/2053)** | High-performance bullet system |
| **[godot-debug-menu](https://github.com/godot-extended-libraries/godot-debug-menu)** | In-game performance overlay |

### Color Reference (HDR Values)

| Color | RGB Values | Use |
|-------|-----------|-----|
| Neon Cyan | `(0, 2.0, 2.5)` | Player, positive gates |
| Neon Magenta | `(2.5, 0, 2.0)` | Multiply gates |
| Neon Green | `(0, 2.5, 0.5)` | Add gates |
| Neon Red | `(2.5, 0.3, 0)` | Negative gates, danger |
| Neon Orange | `(2.5, 1.5, 0)` | Combo effects |

---

## Development Timeline

| Phase | Focus | Key Milestone |
|-------|-------|---------------|
| 1 | Foundation | Glowing shape renders correctly |
| 2 | Architecture | Project structure in place, autoloads working |
| 3 | Mechanics | Playable prototype (ugly but functional) |
| 4 | Aesthetic | Looks like the final game |
| 5 | Feel | Satisfying to play |
| 6 | Progression | Replayable, engaging difficulty curve |
| 7 | Optimization | Runs at 60fps on target devices |

---

## Next Steps

1. **Initialize Godot project** with the folder structure above
2. **Build Phase 1** proof-of-concept (glowing shape)
3. **Implement autoloads** (Events, GameState, ObjectPool)
4. **Build minimal gameplay loop** (one lane, one gate type)
5. **Iterate** based on how it feels

---

*Document generated from tiger team research - January 2026*
