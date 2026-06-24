# Session 021 Handoff

**Date:** 2026-06-23
**Milestone:** v0.5.0 - Complete Game  ·  **Epic:** #84 Combat & Economy Depth (CLOSED this session)

## Completed This Session
Cleared the **entire codeable half of v0.5.0** in one ultracode pass (two sequential
multi-agent workflows: spine → additive, ~21 agents) and shipped **build #15** to TestFlight
(internal + external/Patrick both distributed). Epic **#84 is closed**.

- **#79 — Spray↔Lance stance (KEYSTONE).** Discrete flippable stance set by the last gate (+/× → Spray, −/÷ → Lance); Fusillade tax (Spray = more/wider/faster but per-hit weight 1.0; Lance = fewer/converged/piercing, weight 6.0). Rhombus **per-hit armor FLOOR** (5.0) = immunity not slow-kill; Fractal-feed-on-spray. `verify_stance.gd` + extended `verify_combat.gd`.
- **#80 — Easy/Med/Hard.** New `Difficulty` autoload + `DifficultyProfile` resource; mode-scales the #79 chip fraction (Easy 0.45 grinds → Hard 0.0 true immunity/Lance-mandatory), drain, archetype bias. `Settings.difficulty` persisted; selector on Settings screen. `verify_difficulty.gd`.
- **#82 — Boss framework.** `assets/bosses/boss.gd` — end-of-run climax, phases TELEGRAPH→ARMORED(Lance)→ADD_SWARM(Spray)→DEFEATED, fat collider via batched `consume_volumes`, one-thumb. Arms above the finish; `boss_defeated → complete_run`, gated by `LevelDef.has_boss` so the run can't auto-complete out from under it. `verify_boss.gd`.
- **#83 — Singularity (first boss).** `singularity.gd` on the #82 framework — collapsing-vortex gravity field, wired live via `Fleet.apply_gravity_bias` + `run._apply_boss_gravity` (drags bullets to core / off + gates, pulls ship toward negatives). Reuses `Events.gravity_shift`.
- **#78 — Splice Lab economy.** Enemy token drops (drift + ship-touch absorb + magnetism radius), between-run RNG perk draft folded into `SpliceLab` (offer-N/pick-1 + SKIP + escalating reroll + Brotato lock, seeded RNG), earned-only wallet, banks on both terminals. New shop UI on the #68 screen. `verify_economy.gd`.
- **#59 — Phase director.** `phase_director.gd` + `PhaseDef`, distance-keyed Matrix→Quickening→Singularity→Overdrive, emits `phase_changed(config)` + `gravity_shift` once per boundary (emit-only v1). `verify_director.gd`.
- **#38 culling + #35 perf overlay.** `viewport_cull.gd` (honest instrumentation seam — skips the batched MultiMesh scrollers) + `perf_overlay.gd` (Performance monitors, toggle). `verify_perf.gd`.

**Validation:** independent `--import` clean + **25/25 headless verifies PASS** (re-ran in the main loop, not just trusting the workflow). The adversarial review caught + fixed 5 blocker/major bugs before ship — notably the boss arming race and the Singularity gravity shipping as **dead code**.

**Shipped:** export_presets `14 → 15`; Godot iOS export (exit 1 expected); `fastlane ios ship` → build #15 VALID (~180s); `fastlane ios beta_submit build:15` → external distributed (no spaceship description bug this time).

## Next Task
**Device validation pass on build #15** (needs a real iPhone). All remaining v0.5.0 work is
device-gated and tracked by the kept-open issues under epic **#34**: **#54** (60fps with dense
fleet+swarm), **#39** (profile + fix — the #35 overlay is the seam), **#37** (particle opt),
**#36** (texture-atlas draw-call reduction). None are codeable further on the mini.

## Notes / Blockers
- **Closed:** #79, #80, #82, #83, #78, #59, #38, #35, epic #84. **Kept OPEN (code done, device-blocked):** #54, #39, #37, #36, epic #34 — each commented with why.
- **Device-only, unvalidated on the mini:** all combat-economy *feel* + bloom/FPS/haptics — stance tint, boss/gravity visuals, beat-pulse (#61), real framerate. The Intel UHD 630 + MoltenVK box can't render glow or read true FPS. Build #15 on a physical iPhone is the surface for all of it (and Patrick's external feedback).
- **Tuning that wants a device:** Rhombus floor vs Lance weight balance, perk power curve, boss arm offset (`ship_pos.y - 600`), difficulty knobs — all sane defaults, none device-confirmed.
- Deploy path unchanged + proven this session. Re-ship if a build is invisible >25 min (Apple stall).
- Standing ops debt: rotate the keychain password; remove `Xcode-16.4.0.app` (rollback condition long met).
