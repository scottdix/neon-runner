extends Node
## Palette — the single source of truth for colour (autoload singleton: `Palette`).
##
## Session-12 design-token foundation (DESIGN_SPEC "second art direction pass",
## 2026-06-23). Until now every entity hardcoded its own `Color()` literals; this
## centralises them so a palette swap (or the documented gate-colour fallback) is one
## edit, not seven. Reference at RUNTIME as `Palette.SHIP_CYAN` — these are plain
## `const`s, so they resolve the instant the script parses (no _ready needed), which is
## why they work under the headless `-s` loop where autoload _ready is deferred.
##
## TWO colour spaces live here, and they are NOT interchangeable:
##   • HDR (RGB pushed > 1.0) — for anything rendered through the additive/MultiMesh
##     TEXTURED path. Values > 1 clear the WorldEnvironment `glow_hdr_threshold` (1.0)
##     so the bloom catches them. This is the core neon effect. (See CLAUDE.md +
##     memory glow-immediate-draw-no-bloom: only textured/MultiMesh additive HDR blooms;
##     `draw_*` polylines never do.)
##   • HUD/LDR (RGB <= 1.0) — for CanvasLayer UI text/bars kept deliberately OUT of the
##     bloom so the readout stays crisp. Suffixed `_HUD`.
##
## The display hexes from DESIGN_SPEC are in the comments; the Color() is that hue
## scaled up for the glow pass (hue preserved, luminance pushed past threshold).

# --- Player / order (cool) ---------------------------------------------------
## Ship arrow + cyan accents. #00f3ff ("CHRONO BLUE").
const SHIP_CYAN := Color(0.1, 3.7, 3.9, 1.0)

# --- Swarm / fleet (gold) ----------------------------------------------------
## The gold-orb projectile swarm. core #ffcb00.
const SWARM_GOLD := Color(3.6, 2.9, 0.4, 1.0)
## Bigger white-hot impact spark (scaled by life at the call site).
const SWARM_SPARK := Color(5.5, 5.0, 3.2, 1.0)

# --- Entropy faction (enemies, hot rose) -------------------------------------
## Faction base #ff007f. Per-archetype variants stay in the ROSE family (chosen
## direction: "rose base, vary by shape/intensity") so the four read as one faction
## but stay tellable apart by brightness — not by hue. Glitch = bright/pink, Rhombus =
## deep/red-leaning (reads dangerous), Fractal = mid, Fractling = pale dim shard.
const ENEMY_ROSE := Color(3.9, 0.05, 1.95, 1.0)
const ENEMY_GLITCH := Color(3.9, 0.18, 2.3, 1.0)
const ENEMY_RHOMBUS := Color(3.9, 0.02, 1.0, 1.0)
const ENEMY_FRACTAL := Color(3.7, 0.10, 1.9, 1.0)
const ENEMY_FRACTLING := Color(3.2, 0.08, 1.7, 1.0)

# --- Gates (3 distinct operator colours — explicit decision, see DESIGN_SPEC) -
## ×N multiply. magenta #ff2bd6 (kept distinct from +; collision-free now enemies
## are rose, not magenta).
const GATE_MULTIPLY := Color(3.6, 0.6, 3.0, 1.0)
## +N add / success. acid green #39ff14.
const GATE_ADD := Color(0.8, 3.8, 0.3, 1.0)
## −/÷ negative + hazard. red #ff3333.
const GATE_NEGATIVE := Color(3.8, 0.75, 0.75, 1.0)

# --- Shared neon -------------------------------------------------------------
## White-hot pulse for trigger flashes / impact pops (lerp target).
const FLASH_WHITE := Color(6.0, 5.5, 6.0, 1.0)
## "RUN COMPLETE" finish bar — acid green per DESIGN_SPEC (same family as +gate).
const SUCCESS_GREEN := Color(0.8, 3.8, 0.3, 1.0)

# --- Reactive grid floor (blue) ----------------------------------------------
## Faint warping vector grid. #1a1aff. HDR-blue so the lines bloom faintly; the
## ~13% "faintness" is applied as line intensity in the shader, not baked here.
const GRID_BLUE := Color(0.30, 0.30, 3.8, 1.0)

# --- Backgrounds -------------------------------------------------------------
## Standard near-black gameplay clear.
const BG_STANDARD := Color(0.008, 0.012, 0.04)
## AMOLED / low-power: pitch black so OLED pixels switch fully off.
const BG_AMOLED := Color(0.0, 0.0, 0.0)

# --- HUD / UI (kept <= 1.0 — deliberately out of the bloom) ------------------
const HUD_CYAN := Color(0.85, 0.95, 1.0)        # default readout text
const HUD_WHITE := Color(1.0, 1.0, 1.0)         # crisp gate digits
const COMBO_ORANGE_HUD := Color(1.0, 0.62, 0.17)# combo ×N / BEST. #ff9d2b
const WIN_GREEN_HUD := Color(0.7, 1.0, 0.85)    # "RUN COMPLETE" overlay text
const LOSS_RED_HUD := Color(1.0, 0.5, 0.45)     # "GRID COLLAPSE" overlay text
const BATTERY_LOW_HUD := Color(1.0, 0.3, 0.3)   # empty battery (red)
const BATTERY_HIGH_HUD := Color(0.35, 1.0, 0.6) # full battery (green)
const BATTERY_TRACK_HUD := Color(0.06, 0.08, 0.12)

# --- Menu / screen UI (the 6-screen flow, docs/design/SCREENS.md) ------------
## These are the LDR (<= 1.0) tokens for the BOOT/TITLE/RESULTS/GARAGE/SPLICE/SETTINGS
## CanvasLayer screens — crisp UI, deliberately out of the bloom (same discipline as the
## in-run HUD). Soft neon halos on menus are a device-validated enhancement (#47/#64); the
## colour identity is locked here. Hexes from docs/design/SCREENS.md.
const ACCENT_CYAN_HUD := Color(0.13, 0.91, 1.0)  # #22e7ff — primary accent / default buttons
const MENU_GOLD_HUD := Color(1.0, 0.88, 0.30)    # #ffe14d — swarm orbs / BEST / engine accent
const MENU_MAGENTA_HUD := Color(1.0, 0.17, 0.84) # #ff2bd6 — ×multiply / MOD A
const MENU_MINT_HUD := Color(0.17, 1.0, 0.62)    # #2bff9e — +add / RUN COMPLETE
const SCREEN_PANEL_HUD := Color(0.05, 0.07, 0.10)# tuning-sheet / panel fill
const TEXT_MUTED_HUD := Color(0.62, 0.71, 0.78)  # #9fb4c6 — subtitles / stat labels
const TEXT_DIM_HUD := Color(0.36, 0.49, 0.56)    # #5d7d8f — faint captions / section labels
