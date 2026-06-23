# Session 009 Handoff

**Date:** 2026-06-22
**Milestone:** v0.2.0 - Playable Prototype  ·  **Epic:** #53 — Entropy enemy faction

## Completed This Session
- **Review debt #1–#3 — gate economy decoupled.** Gate effects no longer applied by
  `GateSpawner` reaching into `GameState`. Now: a gate emits `Events.gate_passed`;
  `GameState._on_gate_passed` commits the new swarm volume **and** drains the Glow
  Battery on a negative gate. Spawner only calls `gate.trigger()`. `gate.trigger()`
  floors the emitted count at 0 (was pre-clamp). `GameState` connects the bus in
  `_ready`→`wire_events()` (public + idempotent; verify scripts call it explicitly
  because autoload `_ready` is deferred past `_initialize` under headless `-s`).
- **#53 — enemy archetypes.** `targets.gd` rewritten: **Glitch** (fast low-HP swarm),
  **Looming Rhombus** (slow, dense, **armored**), **Fractal** (splits), **Fractling**
  (the shards). Per-archetype stats (`STATS`), HDR colours (`COLORS`), HP/size/speed/
  points/breach-cost.
- **#54 — tier-aware batched collision (D3).** New `Fleet.consume_volumes()` resolves
  ALL enemy hit-volumes against the live bullets in a SINGLE pass with an x-band cull
  (one survivor rebuild, not one-per-enemy). `consume_near()` is now a thin delegate
  (one collision impl). Tier behaviour: a Rhombus only takes hits **above** its armor
  (thin stream can't crack it); a Fractal **splits** into two fractlings when killed
  with the swarm volume below the split tier, dies cleanly above it.
- **#14 — collision hardening at scale.** Headless assertion: max enemies (48) + a 2000
  swarm for 600 frames → live bullets stay bounded (peak ~131, fire-rate capped), enemy
  count capped, kills happen. Cost stays ~O(bullets).
- **Combat loop closed (#53/#55).** Enemies crossing the ship line **breach** → drain
  the Glow Battery (`Events.enemy_breached`); ignoring the swarm now costs you.
- **Kill-combo scoring.** Consecutive kills ramp a multiplier (`GameState.register_kill`
  + `_tick_combo` decay), wiring the previously-dormant `combo_updated`/`multiplier_changed`
  signals; HUD shows combo ×N. Kills route through `register_kill`, not `add_score`.
- **Test harnesses.** New `tools/verify_combat.gd` (batched collision, archetypes, armor,
  split, breach, combo, scale, run-over guard) and `tools/verify_scene.gd` (headless
  integration smoke of `run.tscn` — exercises `_ready`/`_render` paths the step() tests
  skip). All three verifiers (run/combat/scene) **PASS**.
- **Code review (high) + fix.** Found 1 real bug: a battery-failing breach mid-`step()`
  could phantom-count a later 0-HP enemy as a kill (scored 0 but bumped `kills`/emitted
  `enemy_destroyed`). Fixed with a per-iteration `run_active` guard; locked by a new
  deterministic regression test. Conventions clean (diff *fixes* the decoupling rule);
  no regressions.

## Next Task
**#13 — segment-driven spawner.** Migrate placement into level data: the `GateSpawner`
formations are hardcoded and `Targets` respawns endlessly. Make a `LevelDef`-driven
schedule that streams gate **and** enemy formations by `track_m` along the finite track
(shared `TrackView` projection), recycling past the player. This replaces both ad-hoc
spawners with one data-driven director.

## Notes / Blockers
- **Not validated on device.** Glow + real FPS still can't render on this mini (Intel UHD
  630). #54's acceptance #2 (60fps with dense fleet + swarm on a real phone) is **still
  open** — needs the next TestFlight build (#11). Logic + bounded-cost are headless-proven.
- **#53 epic is partial** (intentional): archetypes + tier behaviour done; the cross-cutting
  behaviours remain — **gate-hijack** (enemy parks in a gate, must be killed to claim it)
  and **multiply-through-positive-gate** (enemy duplicates through a + gate). Miniboss
  (Singularity) still deferred.
- **MVP balance is rough.** 4 negative gates OR enough breaches empty the battery; combo
  decay window 2.5s; armor/split tiers are first guesses. Tune after a device playtest.
- **Targets still respawns endlessly** (not finite). #13 makes spawning finite/scheduled.
- Build #10 external Beta App Review status unchanged from session 8; next ship is #11.
- Still open from prior sessions: remove `Xcode-16.4.0.app` (safe to drop).
