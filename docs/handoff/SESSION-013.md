# Session 013 Handoff

**Date:** 2026-06-23
**Milestone:** v0.2.0 - Playable Prototype  ·  **Epic:** #40 Phase 8 — UI & Release Polish

## Completed This Session
- **Adopted the Claude Design "Neon Runner Directions" 6-screen flow** (imported to
  `docs/design/SCREENS.md`; wordmark kept **NEON SPLICE** per the locked name). Filed
  **#67 Garage**, **#68 Splice Lab**, **#69 How To Play**.
- **#60 SceneManager + #8 state machine** — `autoload/scene_manager.gd`: app state
  (BOOT/TITLE/RUN/PAUSED/RESULTS/GARAGE/SPLICE/SETTINGS/HOW_TO_PLAY), decoupled via the
  Events bus (listens for run terminals → Results). Main scene now `boot.tscn`.
- **Seven screens built** on a shared neon UI kit (`assets/ui/ui_kit.gd`): Boot (#48),
  Title (#41), Results (#44, replaces run.gd's inline overlay), Settings (#45, toggles
  wired to the Settings autoload), Pause (#43), Garage (#67), Splice (#68), How To Play
  (#69). Run HUD restyled to the design (SCORE / COMBO ×N) + pause button.
- **Garage data model (#67)** — `Loadout` autoload (hull/trail/engine, persisted; emits
  `loadout_changed`); the chosen hull recolours the in-run ship live (`player.gd`).
- **Splice data model (#68)** — `SpliceMod` resource + `SpliceLab` autoload (seeded
  inventory, 2 slots, `splice()` fusion → output, persisted; emits `splice_changed`);
  `splice.gd` is data-driven.
- New Palette menu tokens; Settings persists `best_score`; GameState tracks Results peaks.
- **Process:** the Garage/Splice/How-To-Play round ran as an **ultracode Workflow** —
  3 disjoint slices authored in parallel, then a serialized verify stage.
- **Verification:** all **7 headless suites PASS** (`flow`/run/scene/combat/spawner/
  interactions/style; new `tools/verify_flow.gd`), clean `--import`. Title/Splice/How-To-
  Play/Garage rendered to PNG for layout confirmation (glow still device-only).

## Next Task
**#54 device perf pass (60fps dense fleet+swarm, TestFlight build #11) + apply the new
data models to gameplay** — the Splice output isn't consumed by the fleet yet (#68 deeper
half) and Garage trail/engine are stored but not yet applied (#67). The screens + models
exist; the gameplay hookup is the next codeable slice. Then **#64** (glow-capable box) to
validate the device-only backlog.

## Notes / Blockers
- **Device-only backlog unchanged** — menu/screen glow, the new palette/rose under bloom,
  font rendering, haptic feel, and FPS-at-scale are all unproven on hardware (this box
  can't render bloom). Needs iPhone (#47/#54) or the Bazzite box (#64).
- **#42 HUD** kept open — core readout is on-design (SCORE/COMBO/battery/finish/pause);
  score popups (#27) + juice are a later pass.
- **#67/#68 kept open** — data model + screen landed; gameplay application is the remainder.
  `SpliceLab.equip_next` replaces slot B when both are full (tap-to-fill UX — confirm vs intent).
- Splice/menu **glow on a CanvasLayer** uses LDR tokens (crisp, out of bloom by design);
  soft neon halos on menus are a device-validated enhancement, not done here.
- Still open from prior: remove `Xcode-16.4.0.app`; build #10 awaiting Beta App Review.
