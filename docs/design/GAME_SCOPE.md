# Neon Splice — Game Scope (authoritative gameplay/systems reference)

> **Status:** Reconciled scope, captured **2026-06-20 (session 5)** from the full
> game-concept handoff + a tiger-team assessment of the repo, the existing 52 GitHub
> issues, `IMPLEMENTATION_PLAN.md`, and genre/technical research.
>
> **Authority:** This doc is the source of truth for **what Neon Splice is** (scope,
> systems, win/loss, cut line). `docs/design/DESIGN_SPEC.md` remains the source of truth
> for **how it looks** (palette, fonts, screens). `IMPLEMENTATION_PLAN.md` is now a
> **technical reference / code-stub appendix** — its lane-runner gameplay model is
> partially superseded by this doc (see §8). When they conflict, **this doc wins.**

---

## 1. What the game is (one paragraph)

Neon Splice is a premium (paymium — no ads, one-time IAP), portrait **1080×1920**
iOS+Android **vector-neon arcade survival shooter**, built in Godot 4.7 GDScript-first
with HDR bloom as the core look (a Geometry-Wars homage). You pilot an **auto-forward
ship** that **continuously auto-fires a dense stream of neon projectiles** ("the fleet /
swarm"). You **slide left/right to steer, which aims both the ship and the bullet stream
at once** — dodging and aiming are a single action. **Multiplier gates are the
weapon-upgrade economy**: passing the stream through positive gates (×2/+50, magenta/
green) spikes projectile volume + fire rate; negative gates (−10/÷5, red) decimate output
and drain health. Projectile volume drives a **5-tier weapon evolution**. Runs are
**finite ~5-minute, 4-phase crescendos**; the end of the final phase is the **finish
line** ("RUN COMPLETE"). An **enemy faction** blocks lanes, hijacks gates, and multiplies
through positive gates. Health is a **Glow Battery** — zero = the grid collapses and the
run ends.

## 2. The genre reconciliation (why this doc exists)

The original `IMPLEMENTATION_PLAN.md` + issues #1–#46 describe an **endless, discrete
3-lane, swipe-to-switch gate-runner with firing bolted on**. The full concept is a
**free-steer, continuous-fire, vector bullet-hell survival shooter** where gates are the
weapon economy and there's an enemy faction to shoot at. That is a larger, partly
different game. This doc captures the merged target so we scaffold for the real scope, not
the old one. **Four resolved tensions** drive most of the change — see §3.

## 3. Resolved core decisions (LOCKED — do not relitigate without cause)

These extend the two session-4 locks (finite levels; firing is core) and the paymium /
portrait / no-custom-engine locks.

| # | Decision | Consequence |
|---|----------|-------------|
| **D1 — Analog steering** | Continuous **slide-to-steer** (touch-x → ship-x, smoothed/clamped); steering aims **both ship and bullet stream**. NOT discrete lanes. | "Lanes" survive only as **visual grid columns** for level design, decoupled from movement. Supersedes lane controller (#9), swipe input (#10), lane-indexed spawner math (#13). |
| **D2 — One win, one loss** | A run is **one finite distance track** whose segments ARE the 4 pacing phases; the **finish line sits at the end of Phase 4**. Win = cross finish ("RUN COMPLETE"). Loss = Glow Battery hits 0. | "Reach finish" and "survive Phase 4" are the *same event* — build one win condition, not two. Distance ≈ elapsed time via (mostly constant) scroll speed. |
| **D3 — Two collision models** | Keep **one logical blob** for ship-vs-gate/hazard (player survivability stays near-constant cost). Add a **separate batched projectile→enemy layer**: enemies are few fat colliders queried against a handful of "beam/volume" damage emitters (one per active tier band), NOT thousands of bullet bodies. | This is the project's **#1 technical risk** and the explicit thing the POC (#6) must validate before any enemy work proceeds. |
| **D4 — Authored phases, not adaptive scaling** | Difficulty is a **hand-authored 4-phase crescendo** driven by a pacing director, NOT a deaths/successes adaptive feedback loop. | Demotes the Phase-6 adaptive-difficulty epic (#29–#33); promotes an authored phase director + per-level intensity curves. |

## 4. System catalog (the full scope)

Legend: **[MVP]** in the first playable slice · **[v0.x]** later phase · **[CUT/DEFER]**
explicitly out of MVP per scope-risk research.

### 4.1 Player & input
- **Auto-forward ship** — constant forward scroll; cyan vector arrow (DESIGN_SPEC). **[MVP]**
- **Analog slide-steer** — touch-drag maps to ship-x, smoothed + clamped; aims ship + stream. **[MVP]**
- **Always-on fire** — the bullet stream is automatic/continuous, not a button. Steering is the only player input. **[MVP]**

### 4.2 Weapon / projectiles (the "fleet / swarm")
- **Pooled projectile fleet** — MultiMesh-rendered, one draw call; `projectile_count` is the gated scalar. **[MVP]**
- **5-tier evolution** — auto-transform at volume thresholds with a "shatter" anim:
  T1 Vector Line → T2 Chevron (wider) → T3 Triangle (pierce) → T4 Square (explode/shockwave)
  → T5 Fractal (splinters into screen-filling T1 shotgun on a max gate). **[MVP = 2 tiers; T3–T5 v0.3.0+]**
- **Per-tier behaviors** (pierce/explode/shockwave/fractal-split). **[v0.3.0+]**

### 4.3 Gates & economy
- **Math gates** ×/+/−/÷, **positive (magenta/green) vs negative (red)**. **[MVP = one + and one −]**
- **Stream-crossing trigger** — gates act on whichever entity passes through (ship-stream OR enemy), mutating `projectile_count` + fire rate; negatives also drain Glow Battery. **[MVP]**
- **Gate formations** as authored puzzles: **Split Choice** (side-by-side, instant mental math), **Gauntlet** (big positive gate guarded by oscillating moving negative walls), **Funnel** (converging terrain drags ship toward danger). **[Split = MVP; Gauntlet/Funnel v0.2.0+]**

### 4.4 Enemies — "The Void" / Entropy faction
- **Glitch** — flickering pixel-cluster swarm, minimal HP, shields larger threats. **[MVP = the one enemy]**
- **Looming Rhombus** — dense slow diamonds; absorb low-tier projectiles, force a weapon upgrade to crack. **[v0.4.0]**
- **Fractal Swarm** — spinning stars; split into smaller faster hostiles if hit with insufficient firepower. **[v0.4.0]**
- **Singularity (miniboss)** — collapsing vortex; gravity field drags projectiles off positive gates and the ship toward negatives. **[CUT/DEFER — highest risk; content update]**
- **Enemy↔gate interaction** — enemies hijack gates (park inside a ×5, must destroy first) and **multiply through positive gates** (flooding the lane). **[Hijack v0.4.0; multiply v0.5.0]**

### 4.5 Level / run structure
- **Finite level + finish line + "RUN COMPLETE"** win. **[MVP]**
- **Phase pacing director** — sequences the 4-phase crescendo (spawn tables, gate-formation schedule, grid behavior, gravity events per phase): Matrix (0–1:00) → Quickening (1:00–2:30) → Singularity (2:30–4:00) → Overdrive (4:00+). **[MVP = hardcoded segment list; data-driven director v0.5.0]**
- **Segment-driven spawner** — world-x placement along the track (NOT lane indices). **[MVP]**

### 4.6 Health / fail-win state
- **Glow Battery** — 0–100; damage/negative-gate collision dims it. **[MVP = bar + loss at 0]**
- **Battery secondary effects** — on damage: dim bloom, low-pass filter the music, downgrade projectile tier. **[CUT/DEFER — v0.4.0+]**
- **Game state machine** — Boot → Title → Run → Results, with Win (finish) and Loss (battery 0) terminal states. **[MVP = minimal]**

### 4.7 Visuals / neon (identity)
- **HDR bloom + WorldEnvironment glow** (already configured: `hdr_2d=true`, Mobile renderer). **[MVP]** — *gotcha:* isolate HUD on a CanvasLayer **excluded from glow** from day one.
- **Reactive vector grid** — spring-mass vertex displacement (the Geometry-Wars feel; cheap, high impact). Ripple v1 from gate/impact events. **[MVP = portrait-flipped ripple grid]**
- **Elastic lane deformation** — sustained per-lane bulge/compress driven by firepower (shader v2 on top of ripple). **[v0.3.0]**
- Neon trails (Line2D), explosion/collect particles (GPUParticles2D), neon styling, Theme + fonts. **[v0.2.0–v0.3.0]**

### 4.8 Audio
- **SFX + music manager** (AudioManager autoload, buses). **[MVP = basic]**
- **Music-reactive / adaptive audio** — grid pulses to bass; intensity layering; health-driven DSP low-pass. Ship **"fake adaptive"** (add/remove a stem on intensity) for v1; true adaptive deferred. **[v0.4.0]**

### 4.9 Game feel, UI, monetization, infra
- Feedback (shake/flash), combo, score popups, milestone celebrations. **[v0.4.0]**
- Screens: Boot (#48), Title/Menu (#41), HUD (#42, + Glow Battery + tier indicator), Results (#44, win+loss), Pause (#43), Settings (#45). **[Run+minimal Results = MVP; rest v0.x]**
- **Paymium IAP** — one-time no-ads unlock (#50). **[v1.0.0]**
- Infra: iOS deploy pipeline (#47) **[MVP]**, Android pipeline **[v1.0.0]**, device testing (#46).

## 5. The MVP cut line (vertical slice)

The slice exists to answer two questions **in order**:
1. **Can we render + collide the swarm-vs-enemies at count on a real mid-range phone?** (D3)
2. **Is steer-to-aim-the-stream-through-gates actually fun?**

**Gate all NET-NEW content systems (enemies×4, tiers×5, gravity, reactive audio, elastic
grid) behind a "yes" to #1.**

MVP contains: glow POC as a MultiMesh + projectile→enemy collision stress test (#6/#47) ·
analog steer ship + always-on stream · one + and one − gate acting on stream volume · **2**
projectile tiers · **1** enemy (Glitch) + the batched damage layer · Glow Battery (bar +
loss at 0) · one finite level + finish line + minimal "RUN COMPLETE" · portrait
ripple grid. Everything in §4 marked [v0.x] or [CUT/DEFER] is explicitly out.

## 6. Technical strategy & risk (from research)

- **Rendering chaos is a solved batching problem.** MultiMesh (one draw call) +
  GPUParticles2D + constant-cost full-screen bloom + **cosmetic-blob collision**. Realistic
  GDScript ceilings: ~40–160 naïve bullets, **~300–500 with a centralized manager**;
  thousands only with a compiled plugin (PerfBullets/BlastBullets2D) — keep that as an
  escape hatch, not a starting point.
- **The trap is per-entity GDScript logic/physics** — never give bullets individual
  physics bodies; keep movement/collision centralized.
- **Godot glow gotchas:** on mobile, lower the glow HDR threshold (HDR off by default for
  perf); WorldEnvironment glow hits *everything* — exclude the HUD CanvasLayer; glow
  downsample sample-count is a direct perf knob. Budget all three on a real phone at #6.
- **Scope risk = AMBER.** A 5-min/4-phase/4-enemy/5-tier premium game is a realistic solo
  target **only** with the MVP cuts above (miniboss, 3 of 5 tiers, 2 of 4 enemies, true
  adaptive music). Solo games die from scope overwhelm — build the *frameworks* (one
  projectile system, one enemy framework, one collision model); treat tiers/enemies/bosses
  as *content* layered on.

## 7. Commercial flag (not a build-plan input)

The multiplier-gate mechanic is engineered for **ad-funded, low-retention, viral-install**
economics. **Premium + this mechanic is a near-empty market quadrant.** The viable ad-free
home for this kind of depth is **curated subscription (Apple Arcade / Netflix Games)**,
which pays upfront for craft. Our differentiation (bullet-hell depth, designed finite
levels, firing) is exactly what justifies leaving hypercasual behind — position
accordingly. Monetization stays locked as paymium; revisit Apple Arcade as a distribution
target nearer to ship.

## 8. What this supersedes in IMPLEMENTATION_PLAN.md

Still valid: autoload backbone & contracts, project/render config, Events bus, MultiMesh/
batching mandate, folder layout, HDR-neon direction, finite-run framing.

Superseded / reframed (this doc wins):
- **Lane controller** (`player.gd`, lane_count/move_left/move_right) → analog steer (D1).
- **Swipe input** → continuous touch-drag + always-on fire.
- **Lane-indexed spawner** (`_lane_to_x`) → world-x segment placement.
- **Gate `trigger(count)` on ship-cross** → stream/entity-cross trigger; +/− polarity; negatives drain battery.
- **Adaptive difficulty controller** (recent_deaths/successes, rest zones) → authored phase director (D4).
- **Landscape grid shader** `vec2(1920,1080)` → portrait `vec2(1080,1920)` + elastic v2.
- **"Game Over"** → "RUN COMPLETE / Results" (win + loss paths).
- **Net-new systems the plan never had:** enemy faction, 5-tier evolution, Glow Battery, phase director, gate formations, reactive/adaptive audio, batched projectile→enemy collision.

## 9. Delivery roadmap (maps to milestones)

- **Phase 0 / v0.1.0 — Feasibility gate:** verify Events (#3) → glow scene as MultiMesh +
  projectile→enemy collision stress test (#6) → iOS deploy (#47). *Gate: D3 holds on a phone?*
- **Phase 1 / v0.2.0 — Core-loop vertical slice:** 4 autoloads · analog steer + stream ·
  one ± gate on volume · Glow Battery · one finite level + finish + minimal Results. *Gate: is it fun?*
- **Phase 2 / v0.3.0 — Identity:** portrait reactive grid · 2-tier evolution · bloom polish ·
  Glitch enemy + gate-hijack · neon Theme/fonts.
- **Phase 3 / v0.4.0–v0.5.0 — Depth:** remaining tiers · remaining enemies · phase pacing
  director · gate formations · fake-adaptive audio · game feel.
- **Phase 4 / v1.0.0 — Ship:** miniboss (if at all) · full reactive audio · IAP · screen
  polish · Android · store prep.
</content>
</invoke>
