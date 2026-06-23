# Neon Splice — Visual Design Spec (v0 directions)

> Source of truth: Claude Design project **"Ad-Free Gaterunner Game Design"**
> (`projectId 82b7ff81-700d-4d53-a356-a1d0acfa5bda`, owner Scott), file
> `Neon Splice Directions.dc.html` + `screenshots/`. That HTML renders only in the
> claude.ai/design runtime (it uses the `x-dc` component framework + `support.js`);
> this doc is the durable, engine-facing extraction. Re-pull the source via the
> DesignSync tool if it changes.
>
> Status: **second art direction pass.** First pass captured 2026-06-20; **palette +
> enemy/grid/haptics direction revised 2026-06-23** from the `style-guide/` reference
> drop (an "optimized design investigation" PNG sheet + a Google AI Studio "design
> studio" React app). The keepers from that drop are now folded in below (new palette,
> Entropy faction render-map, reactive grid, haptics + AMOLED). The artifact's
> orientation (it simulated landscape 2400×1080), renderer (GLES), and name drift
> ("Neon Splic**er**") were **rejected** — see "Resolved decisions." Two items here
> diverge from `IMPLEMENTATION_PLAN.md` — see the bottom; do not silently encode them.

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
color — scale up to taste for the in-engine glow pass. **Values updated 2026-06-23**
to the brighter "entropy-coded" set from the `style-guide/` drop (old softer values in
the rightmost column for reference). The organizing idea is now **Order (cool) vs.
Entropy (hot):** the ship + swarm read cool/gold; the enemy faction reads hot rose.

| Role | Hex (current) | Notes | Was |
|------|-----|-------|-----|
| **Player ship — cyan** | `#00f3ff` | Ship arrow, UI accents, PLAY/RETRY, rings. "CHRONO BLUE" | `#22e7ff` |
| Cyan lights | `#9bf3ff` `#dffaff` `#eaffff` `#bfe9f5` `#9fd9e6` | Highlights, logo fill, button text | — |
| **Entropy enemies — hot rose** | `#ff007f` | The enemy faction (all archetypes' stroke + glow). NEW role | *(unspecced)* |
| **Multiply gate — magenta** | `#ff2bd6` | `×N` gates; peak-multiplier stat. Kept distinct from `+`; collision-free now that enemies are rose, not magenta. Light `#ffd6f5` | — |
| **Add gate / success — acid green** | `#39ff14` | `+N` gates; "RUN COMPLETE". Light `#c9ffe7` | `#2bff9e` |
| **Divide / hazard gate — red** | `#ff3333` | `÷N` (negative) gates; damage/penalty | *(implied)* |
| **Combo / accent — orange** | `#ff9d2b` | Combo `×N`, BEST score, NEW BEST badge | — |
| **Swarm orbs — gold** | core `#ffcb00`, radial `#fffbe0 → #ffe14d → #f59e1b` | The fleet/projectiles ("Bullet Swarm"); glow `#ffd23d` | — |
| **Reactive grid floor — blue** | `#1a1aff` @ ~13% alpha | The warping vector grid lines (drawn faint). NEW | *(unspecced)* |
| Deep blue ring | `#1b3a6b` | Far perspective ring | — |
| Screen interior | `#02030a` / `#04050c` | Near-black gameplay bg (standard) | — |
| **AMOLED interior** | `#000000` | Pitch-black clear in AMOLED/low-power mode (see Platform feel) | NEW |
| Page / chrome bg | `#101216` | | — |
| Muted text | `#6f9ec0` `#9fb4c6` `#7a93a6` `#4f6678` `#46627a` `#5a7186` | Labels, subtitles | — |

> **Gate operator colors — explicit decision (2026-06-23).** Three distinct operator
> colors are retained: **`+` acid green**, **`×` magenta**, **`÷` red**. The studio
> artifact collapsed all *positive* gates (`+` and `×`) into one green and used red only
> for negatives; we **rejected the collapse** because the ×-vs-+ distinction is
> gameplay-meaningful and worth a hue. If a later playtest shows three gate colors is
> too noisy, the fallback is the studio's 2-color scheme (positive green / negative red).

> Ship-customization accents (post-MVP cosmetic unlock the studio hinted at):
> `#ff00ff` "CORRUPT PINK", `#39ff14` "OVERCLOCKED ACID" — not the default ship color,
> just palette options. Parked as a future feature, not a v0.2.0 commitment.

## Typography (Google Fonts — bundle as assets, don't rely on web fetch on device)

| Font | Weights | Use |
|------|---------|-----|
| **Press Start 2P** | — | Arcade pixel font: scores, combos, button labels, HUD readouts, badges |
| **Orbitron** | 500 / 700 / 900 | Logo wordmark, big final-score number |
| **Rajdhani** | 500 / 600 / 700 | Default UI sans: subtitles, stat labels |
| **Share Tech Mono** | — | Mono captions, taglines, screen-flow labels |

> DONE (session 12): the `.ttf`s are bundled in `assets/fonts/` (OFL, fetched from
> google/fonts) and registered via the `Fonts` autoload (named roles + a default Theme);
> mobile builds ship them. Rajdhani uses the Medium + Bold static weights; Orbitron is the
> variable font (per-weight tuning, e.g. 900 for the wordmark, is a later polish pass).

## Entropy faction (enemies) — look + render strategy

The enemies are the **Entropy faction** (thematic foil to the player's "Order"). All
archetypes share the **hot-rose `#ff007f`** stroke + glow. These map 1:1 onto the
archetypes already coded in session 9 (`assets/.../targets`), and each carries a
**render strategy chosen for mobile batching** — this is the load-bearing part: render
via textures / particles / baked UV, **not** live `draw_*` geometry (per CLAUDE.md +
the [`glow-immediate-draw-no-bloom`] note, 2D bloom only catches MultiMesh / additive-
textured HDR, and this box can't validate glow — prove on device).

| Archetype | Identity | Godot render strategy |
|-----------|----------|------------------------|
| **Glitch** | Pixel-corruption particle cloud | `GPUParticles2D` / batch — low-overhead, no per-frame geo |
| **Looming Rhombus** | Armored rotating diamond; **splits when spliced through a gate** | `Sprite2D` + `canvas_item` shader, cheap edge glow |
| **Fractal Orbit** | Slowly rotating bloom; the splitter tier | Pre-rendered texture + rotating UV offset — no realtime geometry |
| **Dread Singularity** | Vortex that **pulls the gold bullet stream inward** | Parallax texture stack + vortex-fade shader |

Two of these descriptions (Rhombus *split-on-splice*, Singularity *pulls the swarm*) are
exactly the **#53 cross-cutting interactions** (multiply-through-gate, gate-hijack) we're
about to build — treat them as concept corroboration, not yet as spec.

## Reactive vector grid (the floor)

A faint **blue (`#1a1aff`, ~13% alpha)** vector grid that scrolls toward the player and
**warps/deforms** Geometry-Wars style under nearby action. Implementation direction:
**baked mesh-deform animations / `MeshInstance2D` warp**, not live per-frame shader
deformation — same batching-over-cleverness rule as everything else. This supersedes the
"perspective rings + dashed lane line" floor treatment from the first pass as the primary
ground signature (rings can remain as a secondary accent).

## Platform feel: haptics + AMOLED (in scope for v0.2.0)

Two premium-feel commitments adopted 2026-06-23 (both reinforce the paymium, no-ads
positioning — the game should *feel* expensive):

- **Haptics.** Three tactile tiers wired to gameplay events. Start here; tune on device:
  | Tier | Duration | Trigger |
  |------|----------|---------|
  | light  | ~15 ms | minor hit / swarm grazing a particle |
  | medium | ~35 ms | **gate splice** (passing a gate) |
  | heavy  | ~80 ms | death / hard collision |

  iOS uses the Taptic engine; Android the vibrator API. New issue needed (no existing
  one covers haptics) — foundational-but-small, can land alongside the HUD work.
- **AMOLED / low-power mode.** A toggle that swaps the near-black gameplay bg (`#02030a`)
  for **pitch `#000000`** so OLED pixels switch fully off → battery savings + deeper
  contrast for the neon. In this mode, **avoid the heaviest bloom** (low-power path).
  Default mode stays the standard near-black; AMOLED is a settings opt-in.

## Screens

### 01 · BOOT (cold start, logo + asset load)
- Pulsing/rippling concentric cyan rings centered.
- Vector **ship mark** (arrow/chevron polygon, cyan stroke + white core, cyan
  exhaust fins) above the wordmark.
- **NEON / SPLICE** wordmark (Orbitron 900, cyan glow).
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
- The game is **Neon Splice** (canonical). The `style-guide/` artifact's "Neon
  Splic**er**" is **rejected** — but its **"splice" verb is adopted**: passing a gate is a
  **"splice"** ("gate splice"), the enemies are the **Entropy faction**.
- The player is a **ship** (cyan vector arrow), not an abstract blob.
- The growing `projectile_count` is the **swarm / fleet** of **gold orbs**
  ("GROW THE SWARM"; stat "FLEET PEAK"). Consider renaming/aliasing
  `projectile_count` → fleet/swarm in HUD-facing text.
- End-of-run screen is **"RUN COMPLETE" / RESULTS**, not "Game Over".
- Run summary stats to track: peak multiplier, fleet peak, distance, best combo.

## How this maps to existing GitHub issues
- **NEW — Boot/loading screen:** no existing issue (menu/HUD/pause/game-over/settings
  = #41–#45 don't cover boot). → new issue.
- **Design tokens (colour + type) — LANDED (session 12):** colour is centralised in
  `autoload/palette.gd` (HDR tokens for the bloom path + HUD tokens kept <=1) and every
  entity references `Palette.*`. Typography is centralised in `autoload/fonts.gd` — the 4
  Google fonts are bundled (OFL) in `assets/fonts/` and exposed as roles (arcade/display/
  ui/ui_bold/mono) + a default Theme; gate digits, the HUD readout, and the Results
  wordmark route through `Fonts.apply()`. Full design-token foundation complete.
- **Reactive vector grid — LANDED (session 12):** `shaders/reactive_grid.gdshader` +
  `assets/levels/grid_floor.gd` (scrolling HDR-blue grid, ambient + ripple warp, AMOLED
  low-power dim). Device-unproven (glow/warp need a phone, #47/#54).
- **NEW — No-ads one-time unlock (IAP):** product feature, no existing issue. → new issue
  (later milestone, but tracked).
- **Haptics (light/medium/heavy) — #65** (foundation landed session 12; device tuning open).
- **AMOLED / low-power display mode — #66** (foundation landed session 12; Settings-screen
  UI + on-device power/look check open). Settings toggle UI belongs with #45.
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

## Resolved decisions (2026-06-23 — `style-guide/` reference drop)
3. **Name is "Neon Splice."** The artifact's "Neon Splic**er**" drift is rejected; the
   "splice" verb (gate splice / Entropy faction) is adopted into terminology.
4. **Adopt the brighter "entropy-coded" palette** (ship `#00f3ff`, enemies `#ff007f`,
   add-gate `#39ff14`, grid `#1a1aff`, hazard `#ff3333`) — see the palette table.
   Three distinct gate-operator colors retained (green `+` / magenta `×` / red `÷`);
   the studio's positive/negative 2-color collapse is the documented fallback only.
5. **Haptics + AMOLED mode are in scope for v0.2.0** — see "Platform feel."
6. **Render-via-batching for enemies + grid** (textures/particles/baked UV, not live
   `draw_*`) — the artifact's per-archetype render strategy is adopted as the
   implementation default; still **unproven on this box** (glow/FPS need a device).
7. **Rejected as artifact noise:** landscape `2400×1080` viewport (we are **locked
   portrait 1080×1920**), GLES/OpenGL-ES claims (we use the **Mobile/Vulkan** renderer),
   and the AI-generated shader/GDScript snippets (inspiration only — validate on device).
