# Screen Flow — "Neon Runner Directions"

**Source:** Claude Design project *Ad-Free Gaterunner Game Design*, file `Neon Runner Directions.dc.html`
(<https://claude.ai/design/p/82b7ff81-700d-4d53-a356-a1d0acfa5bda?file=Neon+Runner+Directions.dc.html>).
Imported session 13 (2026-06-23). The rendered reference screenshots (`01-flow-lower.png`,
`01-02-ship.png`, `02-02-ship.png`, `arcade-orbs.png`, …) live in that project under `screenshots/`.

This is the **arcade direction** for the core screen flow. It is downstream of `DESIGN_SPEC.md`
(palette/typography rules); where a literal hex in the design differs from a locked Palette token,
**Palette wins** (the design is a mock; the autoload is the source of truth).

> **Naming:** the design wordmark reads "NEON RUNNER". The game name is **Neon Splice** (locked
> session 11 — `config/name`, bundle `com.scottdix.neonsplice`, and the Splice Lab screen itself).
> Screens use the design's layout/colours with the **NEON SPLICE** wordmark.

## Flow

```
BOOT ──auto──▶ TITLE ──PLAY──▶ RUN ──finish/collapse──▶ RESULTS ──RETRY──▶ RUN
                 │                                          └──MENU──▶ TITLE
                 ├─ HOW TO PLAY (overlay, later)
                 ├─ SETTINGS  (#45)
                 ├─ GARAGE    (#67)
                 └─ SPLICE    (#68)
RUN ──pause──▶ PAUSE overlay ──resume / quit──▶ RUN / TITLE
```

Driven by `SceneManager` (#60); in-run Playing/Paused/GameOver is the state machine (#8).

## Shared visual language

- **Phone frame:** 340×720 mock cards → our 1080×1920 portrait. Screen bg `#02030a` (≈ `Palette.BG_STANDARD`),
  blueprint/grid variants slightly lighter.
- **Fonts** (all already bundled — `Fonts.*`): Orbitron 900 = logo + big score (`display`); Press Start 2P
  = scores/combos/buttons/labels (`arcade`); Rajdhani = subtitles/stat labels (`ui`); Share Tech Mono =
  taglines/captions (`mono`).
- **Accents:** cyan `#22e7ff` (primary / ship / default buttons), gold `#ffe14d`–`#ff9d2b` (swarm orbs,
  BEST, combo), magenta `#ff2bd6` (×multiply, MOD A), acid/mint green `#2bff9e`/`#39ff14` (+add, success,
  RESULTS), red `#ff3333` (hazard). Map to `Palette.*` HUD/HDR tokens; new menu HUD tokens added this session.
- **Motion:** faint pulsing rings, dashed scrolling lane, thrust flicker under the ship, glow-pulse on the
  primary button, rising gold orbs (the swarm), falling confetti orbs (Results).
- **Glow:** the design fakes neon with CSS shadows. In-engine, glow is bloom and only catches the
  textured/MultiMesh HDR path (see memory `glow-immediate-draw-no-bloom`). Menu-screen glow fidelity is a
  **device-validation** item (#47/#64); this pass nails layout/copy/colour/fonts, HDR on hero accents.

## Screens

### 01 · BOOT (#48)
Cold start. Faint concentric rings + ripple, version tag (top-right), ship vector mark, **NEON / SPLICE**
logo (Orbitron 900, cyan glow), loading bar (`nr-load`), `LOADING ASSETS` (blink), and the **NO ADS · EVER /
ONE-TIME UNLOCK · PLAY FOREVER** badge (paymium, [[monetization-no-ads]]). Auto-advances to Title when load
completes.

### 02 · TITLE (#41)
Main menu. Faint dashed lane + ring, **BEST 84,200** (top-right, gold). **NEON / SPLICE** logo + tagline
`RUN THE GATES · GROW THE SWARM`. Idle gold orbs bob; the ship hovers with thrust flicker. **PLAY** (big cyan
glow-pulse button) → Run. Secondary row: **HOW TO PLAY**, **SETTINGS**. Bottom badge `NO ADS · EVER ·
ONE-TIME UNLOCK`. (Garage + Splice entries reachable here too.)

### 03 · RUN — HUD (#42)
Live gameplay. Top status: `9:41 / P1`, **SCORE** (top-left, Press Start 2P) + **COMBO ×N** (top-right, gold).
Scrolling dashed centre lane; pulsing target rings at the ship line. The checkered **FINISH** bar scrolls in
from the top. Two gate chips mid-screen: magenta **×2** (multiply) and green **+5** (add). The gold orb swarm
rises from the ship; ship vector + thrust at bottom. Footer hints `< MOVE >` / `FIRE ^`. (Battery bar +
finish logic already exist in `run.gd`; this restyles the readout.)

### 04 · RESULTS (#44)
Round complete — **win or loss**. Falling confetti orbs, **RUN COMPLETE** (mint) header, **NEW BEST** badge
(rotated, gold) when applicable, big **FINAL SCORE** (Orbitron 900). Stats grid: PEAK MULTIPLIER (×16, magenta),
FLEET PEAK (248, gold), DISTANCE (320m, cyan), BEST COMBO (×4, orange). **RETRY** (cyan glow button) → Run,
**MENU** (outline) → Title. Loss variant: `GRID COLLAPSE` header (red) on a darkened backdrop.

### 05 · GARAGE (#67, new)
Vector garage. Back chevron + **SHIP GARAGE** title. Circular cyan grid plate with a rotating dashed orbit
ring; ship preview bobs + fires test bullets. Tuning sheet: **HULL COLOR** (cyan/magenta/green/orange
swatches), **TRAIL STYLE** (SLEEK/HELIX/RIBBON), **ENGINE** (STD/PULSAR/WARP). **EQUIP** button. Selections
persist via the save path.

### 06 · SPLICE LAB (#68, new)
The namesake screen. Blueprint grid, back chevron + **SPLICE LAB** title. Node graph with animated dashed
cables: **INPUT** (BASE GUN) → **MOD A** (×2 SPEED, magenta) + **MOD B** (+5 SHOTS, orange) → **SPLICED
OUTPUT** (GOLD SPREAD · 10 SHOTS · ×2 RATE, gold glow). **INVENTORY** drawer of mod cards (SPREAD FIRE /
SHIELD GATE / GRID BURST / +). **SPLICE** button (gold). Needs a modifier/fusion data model (follow-up).
