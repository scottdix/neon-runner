# Session 004 Handoff

**Date:** 2026-06-20
**Milestone:** v0.1.0 - Proof of Concept  ·  **Epic:** #1 — Phase 1-2: Foundation & Project Architecture

## Completed This Session
Design-led planning session (no gameplay code; real dev deferred to next session by user).
- **Imported the first art-direction pass** from the Claude Design project "Ad-Free
  Gaterunner Game Design" (`projectId 82b7ff81-…`, via the DesignSync tool — it 403s to
  normal fetch) into **`docs/design/DESIGN_SPEC.md`**: full palette (hex), 4 fonts, the
  four screens (Boot → Title → Run → Results), terminology, and resolved decisions.
- **Two core-gameplay decisions locked (override IMPLEMENTATION_PLAN.md):**
  (1) **finite, distance-based levels** with a FINISH line / "RUN COMPLETE" — NOT endless;
  (2) **firing is a core mechanic** — the gold-orb swarm/fleet are projectiles the ship fires.
- **New issues:** #47 iOS build+deploy pipeline (POC) · #48 boot screen · #49 typography+color
  Theme · #50 no-ads IAP (paymium) · #51 level/finish-line system · #52 fleet firing system.
- **Re-scoped/annotated:** #44→RESULTS screen · #41 menu · #42 HUD · #9 ship+swarm ·
  #29 Phase-6 endless→per-level · #10 add FIRE · #12 active firing · #13 level-segment spawner.
- **POC fast-path agreed:** standard (non-.NET) Godot build for the POC; sign with the paid
  Apple Developer account; iOS Simulator first, real iPhone second. Only #6 + #47 needed for a
  first on-phone POC — #4/#5 deferred.

## Next Task
**#3 — verify Events autoload loads in the editor GUI** (still unverified from session 3),
then **real dev: #6 (POC glow scene, doubling as a MultiMesh stress test) + #47 (iOS deploy
pipeline)** to get pixels on the iPhone/Simulator.

## Notes / Blockers
- Headless-Godot gotchas unchanged (hangs at shutdown; no `timeout` on this mac-mini) — validate
  via editor GUI or background-run-to-logfile + poll + `pkill`. See CLAUDE.md.
- Physical-iPhone deploy needs the phone connected to the headless mac-mini; if unreachable,
  iOS Simulator is the fallback "phone".
- Firing × growing swarm raises entity counts — hold to the MultiMesh/one-logical-blob batching
  plan; the #6 POC should stress-test it early.
- `project.godot` mobile config + Events registration still not runtime-validated (carried from S3).
