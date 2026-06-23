# Session 016 Handoff

**Date:** 2026-06-23
**Milestone:** v0.4.0 - Game Feel  ·  **Epic:** #22 — Phase 5: Game Feel (Juice)

## Completed This Session
A **device-feedback → fix → ship** session (a detour from #23, which is untouched and
remains the next coding focus). Two rounds of TestFlight feedback on shipped builds.

- **TestFlight feedback retrieval established.** Beta screenshot feedback lives in the
  ASC API (`betaFeedbackScreenshotSubmissions`, app id `6782516475`), authed via Spaceship
  + the signing key. Method captured in agent-memory `testflight-feedback-retrieval.md`.
- **Logged + fixed all 6 build-#11 feedback items** (#70–#75) via an ultracode Workflow
  (5 file-disjoint slices) + serialized headless verify:
  - **#70** grid black band — `grid_floor.gd` rect now fills the real viewport (FULL_RECT +
    re-fit), not the fixed 1920. **#71** grid restyle (depth falloff, calmer warp).
  - **#72** ship == Garage (shared `build_ship_preview` path). **#73** Splice Lab — hardened
    tap targets + **fixed a real ordering bug** (`apply_splice()` ran before `_volume` seed).
    **#74** Rhombus armor lockout → chip-damage floor. **#75** battery → thin top strip.
  - Caught 2 harness bugs during verify (MultiMesh readback is black headless; `_ready`
    doesn't fire under `-s`) and fixed the two tests; **new `tools/verify_splice.gd`**.
- **Shipped TestFlight build #12** (the 6 fixes). It stalled in Apple ingestion (>16 min,
  never appeared) — superseded by #13.
- **Round-2 device feedback fixed** (extends #72 + a length request):
  - Ship was stuck high / too small / pointing down → ship line now from the **real
    viewport height** (near actual bottom), `SHIP_QUAD` 96→**168**, and `img.flip_y()` so
    the nose points **up** (QuadMesh renders textures V-flipped).
  - **Run length +100%**: `level_01.tres` `length_m` 320→**640** (40s→80s) + extended the
    schedule into the back half (now **13 gate formations / 14 enemy waves**).
- **Shipped TestFlight build #13** (all of the above) → **VALID** (user-confirmed; black
  band confirmed gone on device).
- **Verify:** full headless suite green — 13 suites incl. `verify_scene` (real `run.tscn`,
  420 frames) and the new `verify_splice` (neutral 50 → spliced 200 shots through `step()`).

## Next Task
**#23 — [Gameplay] FeedbackManager (screen shake, flash)** — the v0.4.0 Game Feel
foundation; untouched this session. Wire the already-declared `Events.trigger_screen_shake`
(+ a white-flash hook) into the Run scene, emitted by enemy_destroyed/breached/gate events.

## Notes / Blockers
- **Device-validation tail on build #13** (Intel mini can't render bloom): confirm the ship
  reads as a big, low, cyan, **upward-pointing** arrow matching the Garage; grid restyle;
  Splice Lab **tappability** (#73 fix is defensive — couldn't repro headless); Rhombus now
  killable; battery out of the way; longer run feels right. #71/#72 left open as that tail.
- **Tree committed at this handoff** (10 source/data files + 5 verify scripts). Build #12
  is a dead/stalled upload — ignore it; #13 is the live build.
- **Ops carryover:** rotate the keychain password (history scrubbed but rotation is the real
  fix); remove `Xcode-16.4.0.app` (rollback condition long met).
