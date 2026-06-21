# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Neon Runner** — a mobile game (iOS + Android) in the "multiplier-gate runner" genre with a
neon arcade-vector aesthetic. Built in **Godot 4.7 (.NET/mono build), GDScript-first**. As of
session 2 the repo is still mostly plan + project-management scaffolding; actual game code is just
beginning (Phase 1–2 foundation). `IMPLEMENTATION_PLAN.md` is the authoritative design doc (7
phases, folder structure, autoload contracts, reference code stubs) — read it before building any
gameplay system.

## Hard-won environment gotchas (read first — these cost a full session once)

This is the **mac-mini** (`Macmini.localdomain`, Intel x86_64, macOS 15.7), the designated headless
dev box. Godot is at `~/.local/bin/godot` (symlink to `~/Applications/Godot_mono.app`).

- **Headless Godot does NOT exit cleanly on this machine.** `--editor`, `--import`,
  `--check-only --script`, and even a script that calls `quit()` all do their work but then **hang
  at shutdown**. Do not wait on them to terminate.
- **macOS here has no `timeout`/`gtimeout`.** Wrapping a command in `timeout` silently fails to
  run it; combined with `... | grep ... || echo "OK"` this produces **false passes**. Never trust a
  validation built that way.
- **Piping Godot through `grep` hides output**, because grep only flushes when the (hung) process
  exits. To see Godot's output, redirect to a **log file** and read the file while it runs.
- **Reliable validation pattern:** run Godot in the background writing to a log
  (`godot --headless --script res://path.gd > /tmp/out.log 2>&1`), poll the log for an expected
  marker your script `print()`s *before* `quit()`, then `pkill -9 -f "godot --headless"`.
- **Preferred validation is the GUI:** opening the project in the Godot editor instantly surfaces
  parse errors and confirms autoload registration (Project → Project Settings → Autoload). When a
  human is available, that beats fighting the headless CLI.

## Solo project-management workflow (the operating system for this repo)

This repo runs a lightweight session-memory system. **GitHub Issues is the canonical task tracker**
(`gh` CLI; ~46 issues, 7 phase epics, 6 version milestones). Cross-session state lives in the repo,
not in any machine's local Claude memory (dev may move between machines).

- `PROJECT_STATE.yaml` — the heartbeat manifest. `focus.current_issue` / `next_issue` define what
  to work on (one issue at a time). `last_updated.notes` + `previous_notes` hold a depth-2 summary
  history. Read at session start, advanced at handoff.
- `docs/handoff/SESSION-NNN.md` — per-session handoff docs; older ones in `_archive/`.
  `docs/handoff/session-number.txt` is the last *completed* session number.
- Skills in `.claude/skills/`: **`/session-start`** (read manifest + last handoff, short greeting),
  **`/handoff`** (validate → write handoff → advance `PROJECT_STATE.yaml` → update GitHub issues →
  commit + push), **`/plan`** (architecture planning). Always run `/handoff` to end a session.
- **Commit cadence:** work is committed at `/handoff` (session boundaries), directly to `main`
  (solo repo). Don't commit mid-session unless asked.
- **Sync discipline:** the human sometimes forgets to push from another machine. At session start,
  `git fetch` and reconcile before building — the local manifest may be stale.

## Architecture (the big picture)

**Autoload singletons are the backbone.** Register in this exact order (later ones depend on
earlier ones) in `project.godot`'s `[autoload]` block — `Name="*res://autoload/x.gd"`:

1. `Events` (`autoload/events.gd`) — global signal bus, **signals only, no state/logic**
2. `GameState` (`autoload/game_state.gd`) — score, multiplier, combo, projectile count, save/load
3. `ObjectPool` (`autoload/object_pool.gd`) — projectile/effect pooling
4. `AudioManager` (`autoload/audio_manager.gd`) — sound playback
5. `SceneManager` (`autoload/scene_manager.gd`) — scene transitions

**Decoupling via the Events bus.** Systems never hold direct references to each other. A gate emits
`Events.gate_passed.emit("multiply", 2.0, new_count)`; the HUD, audio, and particle systems each
`Events.gate_passed.connect(...)`. Add `signal`s to `events.gd` rather than wiring nodes together.
`GameState` is the one place that mutates run state and re-emits scoring signals
(`add_score`, `increment_combo`, etc.).

**Two foundational decisions (don't relitigate without cause):**

- **Portrait orientation, iOS + Android.** Base resolution **1080×1920**
  (`display/window/handheld/orientation=1`), stretch `canvas_items` + `expand`. NOTE: the
  `reactive_grid` shader in `IMPLEMENTATION_PLAN.md` hardcodes `vec2(1920.0, 1080.0)` (landscape) —
  **flip that to 1080×1920 when implementing it.**
- **No custom engine.** High/growing entity counts are a *batching* problem, not an engine problem:
  solve in Godot with `MultiMeshInstance2D` (one draw call for thousands), `GPUParticles2D`, and
  full-screen bloom (cost ≈ constant regardless of count). Treat the projectile swarm as cosmetic
  followers of **one logical blob** so collision stays near-constant. The POC glow scene (issue #6)
  should double as a MultiMesh stress test on a real mid-range phone before committing to Phase 3+.

**Rendering for mobile** (already set in `project.godot`): Mobile renderer, `viewport/hdr_2d=true`
(so `Color` RGB values > 1.0 feed the WorldEnvironment glow/bloom — this is the core neon effect),
ETC2/ASTC texture compression, 2× MSAA 2D, touch-from-mouse emulation for desktop testing.

## Directory layout

`autoload/` (singletons) · `assets/` (scenes + scripts by entity: player, projectiles, gates,
obstacles, effects, ui, levels) · `shaders/` (`.gdshader`) · `resources/` (custom `Resource` class
defs) · `data/` (`.tres` instances) · `audio/`. Empty dirs hold `.gitkeep`; remove it once a real
file lands.

## Language policy

Start **100% GDScript** (scene scripts, autoloads, effects). Only introduce C# if profiling reveals
a genuine bottleneck (e.g. object pooling, heavy math). The mono build is used for future C#
flexibility, not because C# is required now.
