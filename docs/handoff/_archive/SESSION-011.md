# Session 011 Handoff

**Date:** 2026-06-23
**Milestone:** v0.2.0 - Playable Prototype  ·  **Epic:** #53 — Entropy enemy faction

## Completed This Session
- **Design-direction session (no code).** Assessed the `style-guide/` reference drop —
  a 6-PNG "optimized design investigation" sheet **plus** a Google AI Studio React app
  (`style-guide/neon-splicer-design-studio/`). Fanned out 3 sub-agents (2 Sonnet, 1 Haiku)
  to explore it; key finding: the app is a **Gemini *text* co-designer** (shaders/GDScript),
  **not** an image generator.
- **Folded the keepers into `docs/design/DESIGN_SPEC.md`** (now "second art direction pass")
  per Scott's rulings:
  - **Name = Neon Splice** (rejected the artifact's "Splicer"; kept the "splice" verb +
    "Entropy faction" naming).
  - **Adopted the brighter palette** — ship `#00f3ff`, enemies hot-rose `#ff007f` (new
    role), add-gate acid `#39ff14`, grid blue `#1a1aff`, hazard `#ff3333`. Kept **3
    distinct gate colors** (green `+` / magenta `×` / red `÷`); studio's positive/negative
    collapse recorded as the fallback. Magenta freed up since enemies are now rose.
  - **New sections:** Entropy faction (archetype → mobile render strategy), Reactive vector
    grid, Platform feel (**haptics + AMOLED, both in scope for v0.2.0**).
  - **Rejected as artifact noise:** landscape 2400×1080 (we're locked portrait 1080×1920),
    GLES claims (we use Mobile/Vulkan), AI-gen shader snippets (validate on device).
- Updated memory `design-directions-artifact` to point at the second pass.

## Next Task
**#53 — cross-cutting enemy behaviours** (unchanged; not started). Build **gate-hijack**
(enemy parks in a gate; must be killed before the upgrade applies) and
**multiply-through-positive-gate** (enemy crossing a `+` gate duplicates). The new design
direction corroborates both: the studio describes the Looming Rhombus *"splits upon gate
splicing"* and the Dread Singularity *"pulls the gold bullet stream"* — use as concept
input. Optionally pair with the #53 **visual pass** (apply the new archetype colors +
render strategies) since the look is now specced.

## Notes / Blockers
- **Two new issues are PENDING creation** (not yet filed — Scott ran /handoff before
  confirming): **Haptics** (light/medium/heavy = 15/35/80ms tiers) and **AMOLED/low-power
  display mode** (toggle → `#000000` clear, avoid heaviest bloom). Both flagged v0.2.0 in
  DESIGN_SPEC "Platform feel" + "How this maps to issues." File them next session.
- **`style-guide/` is now committed** as design reference (5.9M — mostly PNGs + the AI
  Studio app source). Previously untracked.
- **Gate-operator color = explicit decision, watch in playtest.** 3 distinct colors kept;
  if too noisy on a real screen, fall back to the studio's 2-color positive/negative scheme.
- **Still device-unproven.** New enemy/grid render strategies (particles/sprite+shader/
  baked-UV/parallax) + glow/FPS all need a phone — #54 acceptance #2 still open; next ship
  is TestFlight build #11. Build #10 still awaiting external Beta App Review.
- Still open from prior sessions: remove `Xcode-16.4.0.app` (safe to drop).
