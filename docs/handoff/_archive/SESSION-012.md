# Session 012 Handoff

**Date:** 2026-06-23
**Milestone:** v0.2.0 - Playable Prototype  ·  **Epic:** #53 — Entropy enemy faction

## Completed This Session
- **#53 cross-cutting enemy↔gate interactions (the current issue — DONE).**
  - **Gate-hijack:** an Entropy occupant (tough Rhombus) parks on a flagged gate and
    rides it; if alive at the ship line the splice is **denied** (`gate_hijack_blocked`,
    no economy change, red flash, heavy haptic). Kill it first → upgrade applies.
  - **Multiply-through:** a free enemy crossing a **positive** gate band duplicates once
    (`enemy_multiplied`); negative gates never multiply.
  - Clean one-way injection: Targets queries an injected GateSpawner
    (`take_pending_hijacks` / `positive_gate_bands` / `gate_info` / `notify_hijack_cleared`);
    the spawner holds no Targets ref. Hijack flag authored on the m=135 ×3 gate.
  - New `tools/verify_interactions.gd` — **PASS** (blocked-while-alive, ×3-once-cleared,
    duplicate-exactly-once, negative-no-multiply).
- **Design-token foundation — colour + typography (the session-11 "integrate the styles" ask).**
  - **Palette** (`autoload/palette.gd`): HDR tokens (bloom path) + HUD tokens (<=1); all
    entities recolored to `Palette.*` to the new palette (ship `#00f3ff`, swarm gold,
    3 distinct gate hues, finish acid-green). **Entropy faction → hot rose `#ff007f`**,
    varied by intensity per archetype (glitch/rhombus/fractal/fractling).
  - **Fonts** (`autoload/fonts.gd`): 4 Google fonts bundled (OFL) in `assets/fonts/` +
    roles (arcade/display/ui/ui_bold/mono) + default Theme; gate digits, HUD, Results
    route through `Fonts.apply()`.
  - **Reactive vector grid** (`shaders/reactive_grid.gdshader` + `assets/levels/grid_floor.gd`):
    scrolling HDR-blue grid, ambient + ripple warp (poked by `trigger_grid_ripple` on
    kill/breach), AMOLED low-power dim.
  - **Haptics** (`autoload/haptics.gd`, 15/35/80ms tiers) + **AMOLED mode**
    (`autoload/settings.gd`, persisted; `run.gd` swaps clear→`#000000` + low bloom + dim grid).
  - Filed **#65 (Haptics)** + **#66 (AMOLED)**; `tools/verify_style.gd` — **PASS**.
- **All six headless suites PASS:** interactions, style, combat, run, scene, spawner
  (scene smoke now exercises gates + targets + live hijack + grid + fonts together).

## Next Task
**Device perf pass for #54 (60fps dense fleet+swarm on iPhone, TestFlight build #11) +
#8 game state machine (Menu/Playing/Paused/GameOver) to wrap the run in a proper flow.**
Then: bring up a glow-capable box (**#64** Bazzite) to finally validate the pile of
device-only work below.

## Notes / Blockers
- **Large device-validation backlog (this box can't render glow).** Unproven on hardware:
  the new palette/rose under bloom, the reactive grid (glow + warp), haptic feel, real
  font rendering, and FPS at scale. All need the iPhone (#47/#54) or a glow-capable dev
  box (#64). The headless suites only prove logic/wiring.
- **#65 / #66 are foundation-landed, not closed** — durations + OLED power/look still need
  device tuning; AMOLED toggle still needs the Settings-screen UI (#45).
- **#53 epic kept open** — the faction's interactions + visual pass are done, but the epic
  spans more (e.g. Singularity "pulls the swarm" is concept-only, not built).
- Font sidecars: Rajdhani uses Medium+Bold static weights; Orbitron is the variable font
  (per-weight 900 wordmark tuning is a later polish pass). `.import`/`.uid` sidecars are
  committed (Godot needs them in builds).
- Still open from prior: remove `Xcode-16.4.0.app`; build #10 awaiting Beta App Review.
