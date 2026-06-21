# Neon Runner — Visual Design Spec (v0 directions)

> Source of truth: Claude Design project **"Ad-Free Gaterunner Game Design"**
> (`projectId 82b7ff81-700d-4d53-a356-a1d0acfa5bda`, owner Scott), file
> `Neon Runner Directions.dc.html` + `screenshots/`. That HTML renders only in the
> claude.ai/design runtime (it uses the `x-dc` component framework + `support.js`);
> this doc is the durable, engine-facing extraction. Re-pull the source via the
> DesignSync tool if it changes.
>
> Status: **first art direction pass.** Captured 2026-06-20. Real implementation
> begins next session. Two items here **diverge from `IMPLEMENTATION_PLAN.md`** —
> see "Open questions / plan divergences" at the bottom; do not silently encode them.

## The product, per the design

A **screen-flow mockup** of four portrait screens establishing the arcade-vector
neon look: **01 Boot → 02 Title → 03 Run → 04 Results.** Frames are drawn at
340×720 (rounded-corner phone with a home-indicator pill) — proportions only; the
real target stays **1080×1920 portrait** with safe-area-aware layout.

**Monetization is now explicit and on-brand:** *"NO ADS · EVER · ONE-TIME UNLOCK ·
PLAY FOREVER."* This is a paymium (single IAP unlock, zero ads) model — a product
decision the plan didn't previously record.

## Color palette (HDR-ready neon)

The game uses `viewport/hdr_2d=true`; for glowing elements, push these RGB values
**> 1.0** so the WorldEnvironment bloom catches them. Hex below is the *display*
color from the mockup — scale up to taste for the in-engine glow pass.

| Role | Hex | Notes |
|------|-----|-------|
| **Primary neon — cyan** | `#22e7ff` | Player ship, UI accents, PLAY/RETRY buttons, lane lines, rings |
| Cyan lights | `#9bf3ff` `#dffaff` `#eaffff` `#bfe9f5` `#9fd9e6` | Highlights, logo fill, button text |
| **Multiply gate — magenta** | `#ff2bd6` | `×N` gates; peak-multiplier stat. Light `#ffd6f5` |
| **Add gate / success — green** | `#2bff9e` | `+N` gates; "RUN COMPLETE". Light `#c9ffe7` |
| **Combo / accent — orange** | `#ff9d2b` | Combo `×N`, BEST score, NEW BEST badge |
| **Swarm orbs — gold** | radial `#fffbe0 → #ffe14d → #f59e1b` | The fleet/projectiles; glow `#ffd23d` |
| Deep blue ring | `#1b3a6b` | Far perspective ring |
| Screen interior | `#02030a` / `#04050c` | Near-black gameplay bg |
| Page / chrome bg | `#101216` | |
| Muted text | `#6f9ec0` `#9fb4c6` `#7a93a6` `#4f6678` `#46627a` `#5a7186` | Labels, subtitles |

## Typography (Google Fonts — bundle as assets, don't rely on web fetch on device)

| Font | Weights | Use |
|------|---------|-----|
| **Press Start 2P** | — | Arcade pixel font: scores, combos, button labels, HUD readouts, badges |
| **Orbitron** | 500 / 700 / 900 | Logo wordmark, big final-score number |
| **Rajdhani** | 500 / 600 / 700 | Default UI sans: subtitles, stat labels |
| **Share Tech Mono** | — | Mono captions, taglines, screen-flow labels |

> Action: download these `.ttf`s into `assets/fonts/` and register a Godot `Theme` —
> mobile builds must ship fonts, not link Google Fonts.

## Screens

### 01 · BOOT (cold start, logo + asset load)
- Pulsing/rippling concentric cyan rings centered.
- Vector **ship mark** (arrow/chevron polygon, cyan stroke + white core, cyan
  exhaust fins) above the wordmark.
- **NEON / RUNNER** wordmark (Orbitron 900, cyan glow).
- Cyan **loading bar** (gradient `#22e7ff→#9bf3ff`) + blinking "LOADING ASSETS"
  (Press Start 2P).
- `v0.1.0` top-right; **"NO ADS · EVER / ONE-TIME UNLOCK · PLAY FOREVER"** badge bottom.

### 02 · TITLE / MENU
- Wordmark + tagline **"RUN THE GATES · GROW THE SWARM"**.
- **BEST** score top-right (orange, e.g. `84,200`).
- Hovering player **ship** with animated thrust plume; idle **gold orbs** bobbing.
- Big glowing **PLAY** button (Press Start 2P, cyan, pulsing glow).
- Secondary buttons: **HOW TO PLAY**, **SETTINGS** (cyan outline).
- Bottom badge: "NO ADS · EVER · ONE-TIME UNLOCK".

### 03 · RUN (live gameplay)
- **HUD:** status row (clock `9:41`, `P1`); **SCORE** top-left (Press Start 2P,
  cyan); **COMBO ×N** top-right (orange).
- **FINISH line:** checkered (conic-gradient) bar with "FINISH" label scrolling down.
- **Gates** side-by-side across the lane: left **`×2` magenta** (multiply),
  right **`+5` green** (add) — bordered top/bottom, inner glow, slow glow-pulse.
- **Player ship** bottom-center: cyan vector ship + thrust + trail, **surrounded by a
  swarm of ~20+ gold orbs** (the projectiles / "fleet") rising and following.
- Perspective **rings** emanate from the ship; center **dashed lane line** scrolls.
- Control hints: **`< MOVE >`** and **`FIRE ^`**.

### 04 · RESULTS (round complete)
- **"RUN COMPLETE"** header (green); rotated **NEW BEST** badge (orange).
- **FINAL SCORE** big (Orbitron 900, e.g. `186,420`); falling confetti orbs.
- Stat rows: **PEAK MULTIPLIER ×16** (magenta), **FLEET PEAK 248** (yellow),
  **DISTANCE 320m** (cyan), **BEST COMBO ×4** (orange).
- **RETRY** button (cyan, glowing) + **MENU** button (outline).

## Terminology the design establishes (use these names in code/UI)
- The player is a **ship** (cyan vector arrow), not an abstract blob.
- The growing `projectile_count` is the **swarm / fleet** of **gold orbs**
  ("GROW THE SWARM"; stat "FLEET PEAK"). Consider renaming/aliasing
  `projectile_count` → fleet/swarm in HUD-facing text.
- End-of-run screen is **"RUN COMPLETE" / RESULTS**, not "Game Over".
- Run summary stats to track: peak multiplier, fleet peak, distance, best combo.

## How this maps to existing GitHub issues
- **NEW — Boot/loading screen:** no existing issue (menu/HUD/pause/game-over/settings
  = #41–#45 don't cover boot). → new issue.
- **NEW — Typography + color theme (design tokens):** establish fonts + palette as a
  Godot `Theme` + shared constants. Foundational; pull early. → new issue.
- **NEW — No-ads one-time unlock (IAP):** product feature, no existing issue. → new issue
  (later milestone, but tracked).
- #41 Main menu ← screen 02 spec above.
- #42 In-game HUD ← screen 03 HUD spec (score/combo/finish + control hints).
- #44 Game over screen ← **rework as the RESULTS screen** (screen 04 stats + RETRY/MENU).
- #9 Player controller ← player is the **cyan vector ship**.
- #15–#21 Neon aesthetic ← palette + glow values above.

## Resolved decisions (2026-06-20 — these override the original plan)
1. **Finite / distance-based levels** (NOT endless). Runs end at a **FINISH line** /
   distance goal → **"RUN COMPLETE"** results screen with **DISTANCE** stat. This
   **reframes Phase 6**: #29–#33 shift from endless-adaptive-difficulty toward
   **level/stage design** (per-level distance, difficulty curve within a level, win
   condition + finish line). A new **level / finish-line system** issue is needed
   (and the spawner #13 becomes level-segment-driven).
2. **Firing is a CORE mechanic.** The fleet of gold orbs are real **projectiles** the
   ship fires (`FIRE ^`) at obstacles/enemies — not cosmetic followers. Expands:
   input #10 (add FIRE), projectiles #12 (actual firing/ballistics), collision #14
   (projectiles vs. targets), and implies **shootable obstacles/enemies**. New
   **fleet firing system** issue added. Note: this raises the entity-count/batching
   stakes — keep the MultiMesh/one-logical-blob plan from CLAUDE.md front of mind.
