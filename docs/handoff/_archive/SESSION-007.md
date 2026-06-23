# Session 007 Handoff

**Date:** 2026-06-22
**Milestone:** v0.1.0 - Proof of Concept  ·  **Epic:** #1 — Phase 1-2: Foundation & Project Architecture

## Completed This Session
- **TestFlight is actually installable now.** Build #1 (session 6) was packaged
  **iPad-only** (`UIDeviceFamily [2]`) — Godot `targeted_device_family=1` is *iPad* in
  its enum. Fixed to `2` (iPhone & iPad → `[1,2]`); the iPhone 12 Pro now installs.
  Created the internal TestFlight group + tester (`scottdix@gmail.com`, no dot) via API.
- **#6 POC device-validated + closeable** — on the iPhone 12 Pro: neon bloom renders and
  **FPS holds 59–60**. That was the only POC check the Intel mini couldn't do.
- **MVP gameplay slice on device (#9/#10/#52, partial #14).** New `GameState` autoload
  (#2, projectile_count/score/run), Events-bus extensions, and a new `Run` main scene
  (replaces the POC as `run/main_scene`): **analog slide-steer** ship, **always-on fire**
  stream (MultiMesh, one draw call), and **shootable targets** that explode. On-screen
  HUD (FPS/swarm/score/kills). All logic headless-validated (`tools/verify_run.gd`) +
  clean scene boot.
- **Game-feel iteration to a connected hit loop** (builds 2→7 on TestFlight): glow
  render-path fix, damage-column→stream-width match, then the real fix — **per-impact
  damage** (bullets are consumed on contact and deal the damage) + death bursts +
  per-impact flare. Confirmed on device: shoot → impact → destroy reads as one action.

## Next Task
**#11/#56 ± gates on stream volume + #55 Glow Battery + #51 finite level / finish line** —
the rest of the v0.2.0 core-loop slice. Gates mutate `GameState.projectile_count` (already
wired to fire volume); finish line ends the run ("RUN COMPLETE").

## Notes / Blockers
- **D3 attribution changed — flag for review.** Damage moved from the locked "beam/volume
  emitter" to **per-bullet-impact** (the only model that made hitting→dying feel connected,
  per repeated device playtests). D3's *perf* intent is preserved: live bullets are bounded
  by the fire-rate cap (~140), so collision stays O(enemies × ~live) and FPS held at 60.
  This is the deviation to sanity-check before enemy/tier work scales bullet counts.
- **iOS build gotchas (now routine):** every `fastlane ios ship` over SSH needs the keychain
  unlocked + `security set-key-partition-list … codesign:` first (session 6 got it free from
  its shell; build #2 failed `errSecInternalComponent` without it). `targeted_device_family`
  must stay `2`. Should be baked into the Fastfile `ship` lane.
- **Glow gotcha (memory: glow-immediate-draw-no-bloom):** 2D bloom only catches
  MultiMesh/additive-textured HDR; `draw_colored_polygon`/`draw_polyline` never glow. All
  neon art renders via the textured path. Headless dev loop also can't use bare `class_name`
  refs in the main scene (no import cache) — use `preload()` (see `run.gd`).
- Build #7 is the current live TestFlight build. Glow/FPS only verifiable on device, not the mini.
