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

# --- Entropy faction (enemies, danger band) ----------------------------------
## Faction base #ff007f. Per-archetype variants are now DISTINCT BY HUE (reversing the
## session-12 "one hue, vary by intensity" choice — #88: enemies were unreadable when only
## luminance separated them). All four sit in the reserved RED→MAGENTA→VIOLET "danger" band
## (gates avoid this band) and stay clearly OFF the gold swarm + cyan ship axes, but each
## archetype owns a recognisable HUE: Glitch = hot pink/magenta-rose, Rhombus = deep crimson
## (reads most dangerous), Fractal = violet/purple, Fractling = a pale dim shard of the violet.
const ENEMY_ROSE := Color(3.9, 0.05, 1.95, 1.0)
## Glitch — hot pink / magenta-rose (the bread-and-butter swarm target).
const ENEMY_GLITCH := Color(3.9, 0.10, 2.4, 1.0)
## Rhombus — deep crimson / red-leaning (the armored bruiser; reads most dangerous).
const ENEMY_RHOMBUS := Color(3.9, 0.05, 0.6, 1.0)
## Rhombus ARMORED CORE — near-white-hot crimson tint the armor tell blends toward, so a
## still-armored Rhombus rim reads brighter/hotter than a cracked one (#88).
const ENEMY_RHOMBUS_CORE := Color(5.4, 1.6, 1.9, 1.0)
## Fractal — violet / purple, clearly distinct from the Glitch pink.
const ENEMY_FRACTAL := Color(2.6, 0.06, 3.6, 1.0)
## Fractling — a pale, dim shard of the Fractal violet.
const ENEMY_FRACTLING := Color(1.9, 0.10, 2.6, 1.0)

# --- Gates (3 distinct operator colours — explicit decision, see DESIGN_SPEC) -
## ×N multiply. magenta #ff2bd6 (kept distinct from +; collision-free now enemies
## are rose, not magenta).
const GATE_MULTIPLY := Color(3.6, 0.6, 3.0, 1.0)
## +N add / success. acid green #39ff14.
const GATE_ADD := Color(0.8, 3.8, 0.3, 1.0)
## −/÷ negative + hazard. red #ff3333.
const GATE_NEGATIVE := Color(3.8, 0.75, 0.75, 1.0)

# --- Gate FAMILIES (#86 ring-frame system — 5 augment/effect families) --------
## Per-family ring-frame HDR hues (the textured/additive path so the ring blooms).
## EVERY family sits OUTSIDE the reserved enemy RED→MAGENTA→VIOLET danger band — they
## live on the green / cyan / amber / teal / orange axes so a gate never reads as a
## threat. MATH gates inherit a family from their op (Add/Mul → SPRAY_AUG green,
## Sub/Div → LANCE_AUG cyan) so the existing ×/+/−/÷ look stays coherent.
## SPRAY_AUG — acid green (same family as GATE_ADD: open-up / volume augments).
const GATE_FAMILY_SPRAY := Color(0.8, 3.8, 0.3, 1.0)
## LANCE_AUG — cyan (the ship-family HDR: focusing / converge augments).
const GATE_FAMILY_LANCE := Color(0.1, 3.7, 3.9, 1.0)
## GEOM — amber / gold (geometry charge; violet-free + clear of the enemy band).
const GATE_FAMILY_GEOM := Color(3.7, 2.4, 0.25, 1.0)
## UTILITY — teal / mint (universal utility caches; sits between green and cyan).
const GATE_FAMILY_UTILITY := Color(0.25, 3.7, 2.6, 1.0)
## DEVIL — orange, barbed (Overclock / high-risk; reserved). NEVER red or magenta so it
## stays distinct from the GATE_NEGATIVE red and the enemy danger band.
const GATE_FAMILY_DEVIL := Color(3.9, 1.7, 0.15, 1.0)

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
