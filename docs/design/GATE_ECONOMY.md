# Neon Splice — Gate Economy & Combat Depth (design note)

> **Status:** Captured **2026-06-23** from a design review of TestFlight feedback (tester:
> Patrick) + a 5-agent deep-research pass (gate-runner genre, build-craft bullet-hells,
> roguelite economies, decision theory, game-feel). This note is the reasoning record behind
> the depth pass on the weapon/gate economy. When it firms up, fold the locked parts into
> `GAME_SCOPE.md` §4.2–§4.3 (deferred until the "math theme" open question is also resolved —
> both touch the same sections).

## The problem we're solving

The gate economy is **monotonic**: the only currency is projectile *volume*, and more is always
strictly better. So positive gates are "always grab," negative gates are "always dodge," and the
signature Split-Choice formation is a non-decision. A tester asked *"when would I ever want fewer
bullets?"* — and in the current design, never. Decision theory (Sid Meier, Keith Burgun, Cliffski)
is unanimous: **a choice is only real when the right answer is situational, not global.**

## The fix (cross-validated by all 5 research lanes)

Add a **second axis — concentration — that volume trades against**, and put enemies on the board
that each axis cannot beat. *"The smaller number must buy something the bigger number physically
cannot"* (piercing/precision), and *there must be threats the bigger number cannot beat at all.*

### Core model — Spray ↔ Lance STANCE (discrete, flippable)

The ship is always in **one of two visibly different states**, set by the gate it last passed
(**Decision: Option A, "switch", flippable often** — readable on a small screen; you re-choose
constantly as the threat board changes, which is where the depth compounds):

- **Spray stance** (positive/× gate): more projectiles, wider arc, faster fire — **but each
  projectile is lighter** (the Nova Drift "Fusillade tax": adding bullets lowers per-hit damage).
  Shreds crowds; cannot punch a single tough target.
- **Lance stance** (÷/focus gate): fewer projectiles converged into a heavy, piercing, longer-range
  lance — high per-hit weight. The only thing that cracks armor.

Neither is globally better; the two are **incomparable by construction** (coverage vs piercing),
which is what stops one from dominating.

### The threat triangle (the enemies make the axis matter — they already exist in scope)

- **Glitch swarm →** Spray wins (coverage).
- **Looming Rhombus (armored) →** Lance wins. It has a **per-hit damage floor**: sub-threshold
  (taxed-thin spray) fire is absorbed/bounces; only concentrated fire clears it. *Immunity, not
  slower-kill* — if a big enough spray eventually kills it, concentration is never required and the
  choice collapses back to monotonic.
- **Fractal Swarm (splitter) →** spray **feeds it** (more hits = more splits). A clean, teachable
  "more bullets is actively worse" beat.

### Difficulty-scaled immunity (Decision)

The Rhombus's per-hit floor scales with difficulty (new easy/medium/hard system — see its own issue):

- **Easy / Medium:** Lance is clearly *faster/better* vs the Rhombus, but spray can still grind it
  down. The lesson ("concentrate to beat armor") is *taught* but not *enforced*.
- **Hard:** the Rhombus is fully **immune** to sub-threshold fire — Lance is the only answer.

This keeps the design legible at every tier (everyone learns the axis) while only penalizing the
player for ignoring it at the top end. Matches the premium "take the sting out of failure" ethos.

### Keep the axis orthogonal to the 5 tiers

Tiers = *behavior* unlocks (Line → Chevron → Triangle/pierce → Square/explode → Fractal/split).
Stance = *how that behavior is delivered* (wide vs concentrated). Map enemies to the **axis**, not
the tier — so "highest tier" stops being universally correct, and build variety comes for free
without changing the tier ladder.

### Red gates = deal-with-the-devil, not punishment

A pure-loss red gate is dodged 100% of the time (still monotonic, inverted). Instead: red shifts you
off your invested axis **and** drains battery, but is **bundled with a reward you might want** — drops
tokens (→ #78), reveals a perk, or opens a brief score-multiplier / glass-cannon window — at a
**visible, quantified** cost (Balatro "show the stakes" + Slay-the-Spire deal-with-the-devil). Now
"take the red" is a real greed read, not avoidance.

### The skill layer (the moat a run-through clone cannot copy)

Because the player **aims the stream**, the multiply can be a skill:

- **Aim quality:** center-hit = full value, graze = partial.
- **Sustained-contact gates:** hold the stream inside a wide gate to ramp it — native to
  continuous fire.
- **Ladders of small gates beat one big gate** (×2 ×2 ×2 along a tightening line): spreads the
  dopamine, rewards holding a line under fire.
- **Telegraph the threat mix before each gate cluster** so stance choice is an informed *prediction*
  (the skill), not a coin-flip — this is the fairness valve for the immunity mechanic.
- **End every phase in a SPEND** (enemy wall / boss that visibly drains accumulated stream).
  Number-go-up is meaningless without number-go-down; the empty-and-refill cycle is the run's shape.

### Juice (scales to magnitude)

One tunable "impact" function — hitstop (2–6 frames), screenshake, HDR bloom-flash, haptic,
rising-pitch audio sting — all scaling with gate/tier weight, peaking at tier-ups. Music stems tied
to the 4 phases / 5 tiers so the player *hears* themselves leveling. (Device-only to validate, per
the bloom/FPS constraint.)

## Open questions (parked)

- **The "math" theme.** The literal ×2/+50/−10/÷5 arithmetic framing is the most generic,
  clone-adjacent part of the concept, and the stance mechanic underneath does not *require* literal
  math. Reskin candidate. **Decision deferred** — the mechanic above is written theme-agnostic so it
  survives whatever we choose.
- Discrete stance feel: how fast/cheap is a flip? Is there a cost to flipping, or is it free on every
  gate pass?
- Overflow ceiling (does maxed volume reduce readability / make a fatter target?) — optional top-of-
  curve cap, not yet decided.

## MVP implication

Bake the **two-axis gate model + Fusillade tax** into the gate/projectile system **now** (not a
retrofit), even though the enemies that fully exploit it land in v0.4.0. Add **one simple armored
obstacle to the MVP** so there's a single "I need to concentrate right now" moment to test the thesis
on a real device. Otherwise the MVP can't tell us if the idea is fun.

---

## Research highlights by lane

**1. Gate-runner genre (Mob Control / Last War / Count Masters lineage).** Our closest living relative
is the *Last War / Mob Control "shoot-the-stream-into-the-gate"* loop ($200M+), not run-through gates —
and we already merge aim+dodge+multiply into one thumb, the genre's holy grail. Rule of the genre:
*challenge linear, rewards exponential.* The whole moment lives in the ~150ms "snap" after gate contact.
Monotonic economy is the genre's fatal flaw and why these games are loved for a week (D7 retention <8%).
Best formations: the Greedy Corner (juicy gate beside a drain), the Ladder/combo line, the Guarded gate,
the Sustained-contact gate (ours, uncopyable), and always ending build-up in a Spend.

**2. Build-craft bullet-hells (Nova Drift is the rosetta stone).** Nova Drift's **Fusillade** literally
ships our fix: +projectiles but −15% damage, −size, −velocity, +spread — so volume isn't free and is
strictly bad vs single armored targets. Weapons form an explicit spread→focus spectrum (Flak/Torrent vs
Dart/Railgun). **Armor as a per-hit threshold** (not an HP sponge) is the textbook way to make the
Rhombus fair and teachable: a piercing-0 weapon needs 25–100% more DPS than piercing-1 vs armor.
RoR2 "proc coefficient": one heavy hit procs effects ~3× a small one — concentration = *heavier*, not
just *fewer*. Run spread/focus orthogonal to tiers; make each tier a behavior, not a stat.

**3. Roguelite economy & draft (→ folded into #78).** Offer-N-pick-1 **with a SKIP** (the skip is what
makes it a decision). The **Brotato lock** (freeze a shelf item across rerolls / into next session at
its price) is the genre's most-loved economy verb. **Escalating reroll cost**, unlimited (self-limiting).
Meta must be **horizontal** (new options into the pool), *not* vertical stat-creep — vertical is the #1
community complaint and would trivialize a finite skill run. Single earned currency; tokens physically
collected (our drift-down-and-touch is exactly right); be **generous** (Hades). Frictionless restart.

**4. Decision theory / non-monotonic economies.** Meier: a clearly-dominant option is "not a decision."
The cleanest precedents for "fewer is correct": **Ikaruga polarity** (the safe state is *mandatory* vs
certain enemies — immunity, not slower-kill), **Touhou/Mega Man focus-vs-spread**, push-your-luck with
*quantified* risk (Balatro Glass Cards), deal-with-the-devil (StS curses, Hades Pacts). Two failure modes
to avoid: (a) concentration must not be buyable by enough volume → hard-gate the Rhombus; (b) the player
must be able to *predict* which mode they'll need → telegraph the threat before the gate.

**5. Addictiveness & game-feel.** Hitstop scaled to impact is the single highest-leverage feel tool.
Screenshake proportional to event weight (kill < gate < tier-up; never nauseate on a phone). Geometry
Wars multiplier-chain + risk-of-losing-it is the tension engine. "Screen full of death" Phase-4 crest.
Variable reward is fine **when the variance comes from skill/emergence, not RNG/loot** — that's the
dark-pattern line, and our no-ads premium stance is the structural guardrail. Sub-2-second restart;
end every run on the crescendo afterglow.

## Sources

Full source lists from each research lane are preserved in the session transcript. Key references:
Supersonic / PocketGamer gate-runner design guides; Voodoo "Mob Control's $200M rise"; Nova Drift wiki
(Fusillade/Barrage, Weapons, Bodies); Risk of Rain 2 Proc Coefficient wiki; Brotato wiki (Shop/lock,
Materials); Balatro economy guides; Slay the Spire card-reward/merchant wikis; Hades Mirror/Pact;
Sid Meier "interesting decisions" (GDC 2012); Keith Burgun *Game Design Theory*; Cliffski "unsure
trade-offs"; Ikaruga / Touhou shmups wiki; Vlambeer "Art of Screenshake"; Sakurai "Thinking About
Hitstop"; Vampire Survivors / Downwell / Geometry Wars feel analyses.
