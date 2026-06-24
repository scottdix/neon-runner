# Design-Brainstorm Prompt — Stance / Gate / Combat Depth

> Reusable prompt. Paste the section below (everything under the line) into an AI to generate a
> spread of distinct design options for the stance + gate-choice + combat-depth system. It is
> self-contained — the AI does not need the rest of the repo. Companion reading: `REDESIGN_RESEARCH.md`
> (the research these options should draw on), `GATE_ECONOMY.md` (the prior, now-being-revised design).

---

You are a senior game designer specializing in arcade action, the "gate-runner" mobile genre, and
bullet-hell shooters. I'm going to describe my game, how it currently plays, and a problem with its
core combat depth. **Your job is to generate MULTIPLE distinct, fully-developed design options** that
I can compare and iterate on — not one answer. Make the options genuinely *different from each other*
(different philosophies), each with real trade-offs, so they give me a decision to make.

## The game: "Neon Splice"

A premium (paymium, **no ads ever**, single one-time unlock) mobile game for **iOS + Android**,
**portrait** orientation. It is a **free-steer, continuous-fire, vector bullet-hell survival shooter**
— an explicit **homage to Geometry Wars** (glowing neon vector look, HDR bloom, additive glow, a
reactive grid floor, particle-shower deaths). Built in Godot 4.7; the projectile swarm is rendered
with MultiMeshInstance2D (one draw call for thousands) so it can scale.

### How it plays right now
- **One thumb, one input.** You drag left/right to steer a single ship along the **bottom** of the
  screen. **Fire is always on.** There is no aiming and no second input — steering is everything.
- The ship emits a **swarm of projectiles** that streams **upward**. The swarm can grow to hundreds
  of bullets.
- A run is a **finite, distance-based level** (not endless) that **crescendos into a boss** at the end.
- You survive on a **Glow Battery** that drains when an enemy reaches your line (a "breach") or when
  you take a bad gate; hit zero and the run ends.
- As you travel, you pass through **GATES** that modify your swarm, and you fight an enemy faction
  (the "Entropy") flowing down toward you.

### The gate economy (the part that's too shallow)
- Gates are currently literal **math gates**: `+8`, `×2`, `−5`, `÷2`. They change the swarm's
  **VOLUME** (how many projectiles you have). More projectiles = more damage.
- This is **monotonic and bland**: "more is always better," so positive gates are an automatic grab
  and negative gates an automatic dodge — there's no real decision, just a tap-tax.

### The stance system (the core mechanic we want to deepen)
There are two firing **stances**, meant to be the source of real, situational decisions:
- **SPRAY** — many bullets, fanned **wide**, fast fire, but each bullet is **light**. The answer to
  **crowds** of weak enemies. Useless against a single armored target (light fire is absorbed).
- **LANCE** — few bullets, collapsed into a **narrow, piercing, heavy** beam. The only thing that
  **cracks armor** / punches a single tough target. Useless against a scattered crowd (it misses most).
Neither is globally better — the right one depends on the threat in front of you, so you should be
**re-choosing constantly**. That's the intended depth.

**How stance is switched today (and why it's wrong):** stance is a hidden side-effect of the gate's
sign — a positive (`+`/`×`) gate flips you to Spray, a negative (`−`/`÷`) gate flips you to Lance.
This is **disliked**: to get Lance you must drive through a gate that *shrinks your own swarm*, so
choosing the focused weapon feels like self-punishment, and the switch is invisible (no on-screen tell).

**Already rejected as too simplistic:** a "two-lane Stance Gate" where the gate splits into a SPRAY
lane and a LANCE lane and you just steer through the one you want. It's clean and one-thumb, but it's
a flat binary with no depth or dopamine. We want more.

### The enemies (they're meant to force stance decisions)
- **Glitch swarm** — cheap, many; Spray's job.
- **Looming Rhombus** — armored, has a **per-hit damage floor**: light Spray fire is absorbed, only a
  heavy Lance hit cracks it (immunity, not slow-kill; the floor scales with difficulty).
- **Fractal swarm** — a splitter; Spray *feeds* it (more hits = more splits), a clean "more is worse" beat.
- **Boss: the Singularity** — a collapsing-vortex **gravity field** that drags your bullets off
  positive gates and pulls your ship toward negative gates, inverting the economy while you fight it.

### Surrounding systems (context — you may use or ignore these)
- **Tokens** drop from killed enemies, drift down, and are absorbed on touch; they fund a **between-run
  Splice Lab** RNG perk draft (roguelite shop: offer-N / pick-1 / reroll / lock).
- **Difficulty** modes (Easy/Med/Hard) scale the armor immunity and other knobs.
- A **combo/score multiplier**, and heavy **juice** (screen shake, HDR flash, haptics, procedural
  audio, a beat-reactive grid pulse).
- Premium stance means **all variance must come from skill/emergence, not loot/RNG dark patterns**.

## What I want you to fix

The combat is **too shallow and not dopaminergic enough.** I want to add **depth** (real, situational
decisions — the kind Sid Meier/Keith Burgun call "interesting": no dominant option, trade-offs,
state-dependent) **AND dopamine** (the build-up → spend rhythm, multiplier chains you can lose,
panic-clears, escalation, "screen full of death" crescendos) — the way the best **gate-runners**
(Mob Control, Last War, Count Masters, Tall Man Run) and **bullet-hells / arcade shooters**
(**Geometry Wars** above all, plus Ikaruga's polarity, Nova Drift's spread-vs-focus builds, Gradius'
Double-vs-Laser, Enter the Gungeon, Vampire Survivors) do. Lean into the **Geometry Wars homage** —
its smart-bomb (scarce screen-clear that scores nothing but harvests multiplier fuel), its
geom-collect multiplier tension, its enemies-that-force-different-tactics, its warping reactive grid,
and its readable neon shape language are all fair game to adapt.

## Constraints (every option MUST respect these)
- **One thumb only.** The vocabulary is drag-to-steer + tap + hold. No second stick, no aiming, no
  buttons that demand a second finger in the heat of action (a single occasional tap/hold/swipe-gesture
  is OK if it's hard to misfire).
- **Readable on a small portrait phone.** Any choice must be parseable ~250ms *before* the commit
  point; pair color with shape/icon (colorblind-safe).
- **Premium, no pay-to-win.** Depth from skill, not purchased power or loot RNG.
- **Performance:** the swarm is MultiMesh-batched; keep solutions batch-friendly (no per-bullet nodes).
- **Keep the pillars:** free-steer + always-on fire + finite distance run + neon Geometry-Wars feel.

## What to deliver

Generate **4–6 DISTINCT design options** for the stance + gate-choice + combat-depth system. Make them
philosophically different (e.g. one might lean into a resource/charge economy, one into build/loadout
identity, one into pure moment-to-moment reads, one into a Geometry-Wars panic-and-harvest loop, etc.)
— do not give six variations of the same idea. For **each option**, cover:

1. **The pitch** — one paragraph: the core idea and what makes it feel great.
2. **How stance works** — what Spray/Lance (or your replacement/extension of them) *are*, and exactly
   **how the player switches**, moment to moment, with one thumb.
3. **How gates work** — what replaces the bland math gates; the actual *choices* a gate poses and why
   each is non-trivial (situational / trade-off / risk / build).
4. **Where the DEPTH comes from** — the interesting decisions, and why there's no dominant option.
5. **Where the DOPAMINE comes from** — the build-up/spend rhythm, the chain you can build and lose,
   the panic/escalation/crescendo beats; how it borrows from Geometry Wars specifically.
6. **How it uses the enemies** (Glitch/Rhombus/Fractal/boss) and the surrounding systems
   (tokens/Splice Lab/multiplier) — or how it would change them.
7. **A 10-second play-by-play** showing it in action.
8. **Trade-offs & risks** — what's hard, what could confuse players, what we'd have to cut.

End with a short **comparison table** (the options × the axes above) and your **recommendation** with
reasoning. Be concrete, opinionated, and specific — I want options I can actually choose between and
prototype, not generic advice.
