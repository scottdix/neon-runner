# Gate / Stance / Projectile Redesign — Research Capture (session 22)

> **Status:** Research only — **no design locked, no plan agreed.** Captured 2026-06-24 from a
> 3-lane subagent research pass (Geometry Wars, gate-runner gate mechanics, bullet-hell projectile
> feel) triggered by on-device testing of build #16. The designer's verdict on the first synthesis:
> the simple two-lane "steer through Wide/Lance" stance gate is **too simplistic** — the stance
> switching needs a richer design. This doc records what we learned and the open questions so the
> next session doesn't start cold. It does NOT supersede `GATE_ECONOMY.md`; it's the input to a
> rethink of it. Related issues: gate redesign, stance redesign, projectile richness, #85 (boss HUD).

## Why we're here (the problem)

On-device testing of build #16 confirmed three things:
1. **The +/×/−/÷ "math gates" are bland.** Every design source agrees on the reason (below).
2. **The "divide-gate → Lance stance" trigger is disliked** — it forces you to *shrink yourself*
   to get the focused weapon, and it's invisible.
3. **The projectile swarm looks unrefined** as it grows — a flat, uniform mass, not a rich
   neon bullet-hell.
A first proposed fix (a two-lane "steer into Spray or Lance" gate) was judged **too simplistic** —
the stance system needs more depth than a binary lane pick.

## Lane 1 — Geometry Wars (the touchstone)

- **The default gun already encodes spray-vs-lance:** 3-round bursts at ~30 rps in a tight
  triangular spread, **center bullet faster + farther** than the flanking two. A useful visual
  anchor for a Spray↔Lance morph (wide scatter ⇄ collapse to the fast center shaft).
- **GW has NO player weapon-switching** in the classic games (correction to an earlier assumption:
  GW3 has **drones** + expendable **supers**, not named "ships"). Our stance is genuinely our own
  idea — there's no GW precedent for player-driven stance, only the gun's built-in geometry.
- **Smart Bomb:** scarce (start 3, cap 9), one-button screen-clear that **scores ZERO but the dead
  enemies still drop their geoms** → it's a panic button AND a multiplier-harvest tool in one
  decision. Massive sensory "reset": grid wipe + bloom flash + brief audio cutout.
- **Multiplier/geom loop (the tension engine):** kills drop geoms; each geom = +1× multiplier;
  geoms **despawn in ~3s** so collecting pulls you toward the danger you just created; death resets
  the multiplier. "Stay alive AND keep diving into the kill-zone."
- **Enemy roster forces tactic-switching:** volume-answer (grunts/hordes), precision-answer
  (snakes = head-only, dashers = invulnerable front), don't-kill/manage (black holes, red walls).
- **Feel:** hand-built simple silhouettes for readability; **color = information** (enemies
  color-coded to the multicolor reactive grid); the **spring-mass warping grid** as a free
  force-visualizer; additive HDR bloom; rainbow death particles; reactive music + per-enemy
  spawn-sound cues.
- Sources: Wikipedia (RE2, GW3); GameFAQs RE guide (burst/center-bullet); GW Wiki (Bomb, Geoms,
  Super, Gravity Well); Game Developer "The Color and the Shape" (Bizarre Creations); Tuts+ warping-grid.

## Lane 2 — Gate-runner gate mechanics (why ours is bland + what's good)

- **Why math gates are bland (unanimous):** `+8 vs ×2` is a *single-axis, dominant-strategy* choice
  — both branches do the same thing ("more"), one is computably better at a glance. Meier ("a
  decision where players always pick the same option isn't interesting"), Burgun ("a knowable best
  answer is a *calculation*, not a decision"), Sirlin ("options must accomplish *different* things"),
  Johnson ("players optimize the fun out"). The arithmetic framing **is** the bland part — not just
  the divide-by.
- **The fix is less *obviousness*, not more *randomness*.** Break the single-number comparison by:
  **axis** (spread vs pierce), **state** (add beats multiply when the swarm is big), **risk**
  (look-alike good/bad pair), **cost** (cursed give-to-get / purge), or **build** (class tags).
- **Interesting gates that exist in the genre:** state-dependent add-vs-multiply (Crowd Runners,
  Mob Control); look-alike good/bad pair (Last War); two-axis transform (Tall Man Run: taller vs
  thicker); least-bad dilemma gate; color/state-match key gate (Color Switch/Road); merge/tier
  weapon gate (Merge Gun Run).
- **Cross-pollination worth stealing:** Hades **door-symbol telegraph** (you see the reward *type*
  before you commit) + pick-1-of-N forfeit-rest + synergy boons + Chaos delayed give-to-get; Slay
  the Spire **skip/purge**; Brotato **class tags** (stack set bonuses w/ penalties, bias future
  spawns); RoR2 stacking + converter; Ikaruga **polarity** (one tap flips color; matching absorbs +
  charges, opposite takes 2× — unifies dodge/aim/resource); Gradius **Double vs Laser** (mutually
  exclusive spread vs pierce); Nova Drift Split vs Flak; R-Type Force orb; VS evolutions + slot cap.
- **One-thumb budget:** verbs are tap, hold, drag. "Steer-as-choice" (lateral position picks the
  gate) and "tap-to-toggle-state" are both genre-proven. Anything must be readable **≥250 ms before
  the commit point**; pair color with an icon/glyph (colorblind).
- Sources: genre aggregators (Mob Control/Last War/Count Masters/Tall Man/Color Switch guides);
  GDC 2012 Sid Meier; Burgun (InformIT); Sirlin; Designer Notes (Johnson); Hades/StS/Brotato/RoR2/
  Nova Drift/Ikaruga/Gradius wikis; thumb-zone UX (Smashing Magazine).

## Lane 3 — Projectile richness (the bullet-hell feel)

- **Why ours looks unrefined:** every bullet travels straight up at one speed with zero rotation —
  a picket fence, not a swarm.
- **What the genre does:** per-bullet **jitter** (angle/speed/size/rotation); **motion streaks**
  (stretch the quad along velocity → neon tracers, not dots); **shape language** (round → faceted →
  chevron → star per tier/weapon); **white-hot core + colored halo** for readability at any density
  (Enter the Gungeon literally scaled bullets up twice for visibility); **trails** (Housemarque
  ribbon trails on *leaders only*); **muzzle/spawn flash**; **gentle field flow/curve** (GW's
  signature aliveness); density as a **tunable knob** that escalates with volume (keep low-volume
  scenes clean).
- **Map our systems to distinct visual channels:** **stance → shape** (Spray = round scattered
  orbs; Lance = long hot spears) — this *also* solves "I can't tell which stance I'm in"; **tier →
  color + facets + trail**; **volume → streak length + jitter + trail density**.
- **Godot 4.7 technique (stays in ~1 draw call):** `MultiMesh.use_custom_data = true` → pack 4
  floats/bullet (`set_instance_custom_data`) read as `INSTANCE_CUSTOM` in a vertex/fragment shader
  for per-instance color/rotation/streak/shape-atlas-cell. Promote `_proj: Array[Vector2]` to a
  small per-bullet struct (`pos, vel, rot, spin, seed`) and march by `vel` in `step()`. Keep the
  sim headless-testable; **richness is a render concern** — do NOT touch `consume_volumes` /
  `live_count` / `spark_count` / economy (verify_combat must stay green).
- **Perf:** stay batched (1 MultiMesh + shape atlas; optional 2nd for a separate shape; tiny ribbon
  pool for leaders only — NEVER per-bullet GPUParticles2D/Line2D). Bloom + real FPS are **device-only**
  (this Mac's Intel UHD 630/MoltenVK can't compile the glow pipelines).
- **Cheapest first PR (transforms the swarm):** custom-data enable + per-bullet vel/jitter + motion
  streaks + per-instance variance; then stance-as-shape, then the per-tier shape atlas.
- Sources: Enter the Gungeon wiki (projectiles, bullet-hell density); Geometry Wars (Grokipedia/wiki);
  PlayStation Blog + 80.lv (Returnal/Resogun NGP ribbon trails); Nex Machina review; GodotShaders
  (MultiMeshInstance2D animation variance); Godot docs (MultiMesh / INSTANCE_CUSTOM).

## Open questions to resolve (no answers yet)

1. **Gate framing.** Retire the literal +/×/−/÷ math entirely for a *choice* vocabulary, keep math
   but de-monotonize it, or a hybrid? (The "math theme" was already a parked open question in
   `GATE_ECONOMY.md` — this is where it gets decided.)
2. **Stance switching — the hard one.** The binary two-lane gate is **too simplistic**. What's the
   richer model? Candidates not yet explored in depth: a *third* stance or a spectrum; stance as a
   chargeable/spendable resource (Ikaruga polarity); stance tied to a build/loadout rather than a
   moment-to-moment gate; a tap-to-toggle on the fly; stance with a meaningful *cost* to switching.
   **This needs a dedicated design pass, not a quick pick.**
3. **Smart bomb / "Splice Burst."** Adopt a GW-style scarce screen-clear that scores zero but
   harvests tokens, with the grid-wipe/bloom/audio-cut reset? In or out, and what's the one-thumb trigger?
4. **Multiplier/geom loop.** Do we deepen our token economy toward GW's collect-to-multiply +
   despawn-timer tension, or keep tokens purely as the Splice Lab currency?
5. **Enemy → stance mapping.** Make the roster explicitly force stance switches (volume vs pierce
   vs don't-kill), à la GW. Partly in scope already (Glitch/Rhombus/Fractal); needs to be made legible.
6. **Boss (from #16 device testing):** boss dies too fast once you're in Lance; the Lance flank
   gate drains battery per flip; the parked flank gates read as "stuck." All ride on the stance
   redesign above. HP-bar layout tracked separately in #85.
