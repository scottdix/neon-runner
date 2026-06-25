# Session 024 Handoff

**Date:** 2026-06-24
**Milestone:** v0.5.0 - Complete Game  ·  **Epic:** Combat/gate/stance DEPTH REDESIGN

## Completed This Session
- **Shipped build #18** to TestFlight (internal + external/Patrick) with a build-specific "What to Test" — the session-23 "feelable" combat surface (enemy hues / 5 gate family rings / ghosting / Geom Cache / Tungsten / Efficiency / 0.13 brake) reaches testers for the first time. Clean `beta_submit` (no spaceship description-bug this time).
- **#37 particle budget — closed the integration gap.** `effect_layer._emit()` now consults `ParticleBudget.grant()` with per-emitter live-particle accounting + decay (was a unit-tested island). New `verify_particles` budget-seam assertions. **30/30 headless verifies + integration playtest PASS.**
- **#35 perf overlay → bottom-right.** Re-anchored `perf_overlay.gd` to the bottom-right, right-aligned, 140px bottom inset (clears the home indicator). `verify_perf` PASS.
- **Tracker hygiene:** honest status comments + `status: blocked` (device-gated) flag on all 6 v0.5.0 issues (#54/#36/#39/#34/#37/#85). Surfaced the **#85 stale-premise** finding.
- **Enemy "no visual difference" root-caused (#88):** all archetypes share ONE soft-diamond mesh (differ only by size + HDR color); additive+bloom washes the hues to white. The design's distinct silhouettes were never built — a real content gap, logged to #88.
- **THE BIG ONE — fixed the blind-visual loop.** Stood up a **mini→Air native-bloom preview pipeline**: installed Godot 4.7 (same build) on the M2 MacBook Air, wrote **`tools/sync-to-air.sh`** (~12s rsync+reimport), and confirmed the game **runs on the Air via Metal/M2 with the real glow and ZERO compute-pipeline errors** (the mini's hard blocker). Documented in CLAUDE.md + a memory.

## Next Task
**Enemy visual differentiation (#88), now iterable with the new mini→Air loop + Gemini-mockup → Claude-spec → Claude-Code workflow.** Give each archetype a distinct *silhouette* (Glitch cluster / Rhombus plated diamond / Fractal star) on the textured/MultiMesh path + a dark-core/hard-edge so the shape survives bloom (the gate "color+silhouette=family, dark-core-vs-bloom" lesson, never applied to enemies). Iterate by `sync-to-air.sh` + Play on the Air. STILL pending: the device read on build #18 → **lock #87 (KINETIC vs GEOM)**.

## Notes / Blockers
- **Blind loop is fixed** for design iteration: build on mini → `tools/sync-to-air.sh` → Play on the Air (real bloom). TestFlight stays the final on-iPhone check.
- **iOS Simulator NOT set up** on the Air (no runtimes/templates) and wouldn't beat native Play on glow — deferred.
- Device-gated v0.5.0 cluster (#54/#36/#39/#34) closes only on a TestFlight perf pass; #85 premise needs a device read.
- Deferred backlog unchanged: Overclock Devil's-Bargain gate (reuses the phase-buff seam), per-gate dark-core glyphs, perf cluster, #85 boss HP-bar.
