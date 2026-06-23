# Session 010 Handoff

**Date:** 2026-06-23
**Milestone:** v0.2.0 - Playable Prototype  ·  **Epic:** #53 — Entropy enemy faction

## Completed This Session
- **#13 — segment-driven spawner.** The level now owns a single authored schedule
  (`LevelDef.gate_formations` + `enemy_waves`, string ops/kinds so the resource has
  no Gate/Targets dependency), streamed by **two decoupled consumers** — no fat
  director node (matches the Events-bus architecture; `Run` wires both after
  `start_run()`):
  - **`GateSpawner`** — `build_formations(specs)` reads the level's formations (via
    new `Gate.op_from_string`) and **recycles** (frees) formations that scroll past
    the ship line.
  - **`Targets`** — now **wave-driven + finite**: waves spawn by `track_m` at
    **world-x** (spread across the playfield, NOT lane indices), and killed/breached/
    offscreen enemies are **removed** — the endless random respawn is gone. `set_schedule`
    duplicates each wave dict so the shared LevelDef array never gets a `spawned` flag.
- **Tests.** New `tools/verify_spawner.gd` (op-string mapping, formation build, gate
  recycle fires-once-then-freed, waves spawn at the mark + world-x spread, finite
  removal). Updated verify_run (formations from the level) / verify_combat (clean-kill
  removes vs respawns; scale test tops up each frame) / verify_scene (assert schedule
  wired; window bumped so a wave actually spawns). All FOUR verifiers PASS.
- **Code review (high) + 2 fixes.** No correctness bugs shipped; conventions clean;
  no regressions. Applied two latent-edge robustness fixes: a wave defers (never
  silently lost) if the field is full; gate recycle no longer depends on `triggered`.

## Next Task
**#53 — cross-cutting enemy behaviours.** With archetypes (s9) + scheduled waves (s10)
in place, build the two interactions the epic still wants: **gate-hijack** (an enemy
parks inside a gate; it must be destroyed before the upgrade can be claimed) and
**multiply-through-positive-gate** (an enemy that crosses a + gate duplicates).

## Notes / Blockers
- **Not device-validated.** Glow + real FPS still need a phone; #54 acceptance #2
  (60fps dense fleet + swarm on a real mid-range phone) is **still open** — next
  TestFlight ship is **build #11**. All s9/s10 logic is headless-proven only.
- **Untracked `style-guide/` (5.7M of art-direction PNGs)** is NOT part of this commit —
  it's design reference (entropy faction, ship/bulletstream, reactive grid, typography,
  environmental phases). Commit it separately (e.g. `docs: import art-direction style
  guide`) or wire it into DESIGN_SPEC.
- **Schedule-as-`@export`-default footgun:** `LevelDef.gate_formations`/`enemy_waves`
  are code-authored defaults; opening + saving `level_01.tres` in the Godot editor could
  bake them into the .tres and pin them. Kept `@export` (v0.5.0 data-driven director will
  override per-level via .tres); fine while working headless. Switch to script `const`s
  only if hand-editing levels in the editor becomes common.
- **Balance is a first guess** — first enemy wave at 18 m; 7 waves escalate to a dense
  mixed close before the 320 m finish. Tune after a device playtest.
- Still open from prior sessions: remove `Xcode-16.4.0.app` (safe to drop).
