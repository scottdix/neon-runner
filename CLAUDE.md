# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Neon Splice** — a premium (paymium, no-ads) mobile game (iOS + Android) that takes the
"multiplier-gate runner" mechanic and builds a **free-steer, continuous-fire, vector bullet-hell
survival shooter** (Geometry-Wars-style neon) on top of it. Built in **Godot 4.7 (.NET/mono
build), GDScript-first**. As of session 5 the repo is still mostly plan + PM scaffolding; game
code is just beginning (Phase 1–2 foundation).

**Read `docs/design/GAME_SCOPE.md` first** — it is the authoritative source for *what the game
is* (full system catalog, the 4 locked core decisions, MVP cut line, delivery roadmap). It
reconciles the original plan against the full game concept (session 5). `IMPLEMENTATION_PLAN.md`
is now a **technical reference / code-stub appendix** whose lane-runner gameplay model is partly
superseded (analog steer not lanes, stream-economy gates, enemy faction, etc. — see GAME_SCOPE §8);
when they conflict, **GAME_SCOPE wins**. `docs/design/DESIGN_SPEC.md` owns *how it looks*.

## Hard-won environment gotchas (read first — these cost a full session once)

This is the **mac-mini** (`Macmini.localdomain`, Intel x86_64, macOS 15.7), the designated headless
dev box. Godot is at `~/.local/bin/godot`.

- **USE THE STANDARD (non-mono) BUILD for the GDScript dev/validation loop** — symlink points to
  `~/Applications/Godot.app` (`4.7.stable.official`). **The `_mono` build (`Godot_mono.app`) HANGS at
  headless startup on this box** — it sleeps at 0% CPU during .NET-runtime init and never runs your
  `-s` script at all (no output, no `_initialize()`). This cost sessions 3–4 ("Events autoload
  unverified"). The standard build runs `--headless -s` cleanly, flushes stdout, and exits. Keep the
  mono app on disk only for the day C# is ever introduced; switch the symlink back then.
- **macOS here has no `timeout`/`gtimeout`.** Wrapping a command in `timeout` silently fails to run
  it; combined with `... | grep ... || echo "OK"` this produces **false passes**. Never trust a
  validation built that way. Bound a wait with a counted `until ...; do sleep 0.5; n=$((n+1)); done`
  loop instead (run it backgrounded — the harness blocks foreground `sleep`).
- **Don't rely on stdout markers; write a result FILE.** Godot block-buffers stdout to a pipe/file,
  so `print()`ed markers can lag. The robust pattern (see `tools/verify_events.gd`): the script
  writes its verdict to an absolute path via `FileAccess` (flushed on `close()`, *before* `quit()`),
  and you **poll for that file**. Helper: **`tools/run-headless.sh <res://script> [result-file]`**
  runs Godot backgrounded, polls the result file, prints it, and `pkill`s. Autoloads DO load under
  `-s` (verified: `Events` present at `/root`).
- **GUI / VNC + windowed screenshots:** the dev can **VNC into the mini**, and the agent can render a
  scene to a PNG autonomously — `tools/screenshot.gd` run WITHOUT `--headless` (Vulkan/Forward-Mobile
  via MoltenVK comes up on the Intel UHD 630) saves `/tmp/poc_shot.png`. Good for confirming **layout,
  composition, additive blending**. (Filter the run log carefully — the normal `Vulkan …` banner is
  NOT an error; don't let a poll grep kill the process on it.)
- **THIS BOX CANNOT VALIDATE GLOW/BLOOM OR REAL FPS.** The mini's Intel UHD 630 under MoltenVK
  **fails to compile Godot's glow compute pipelines** (`[mvk-error] … AIR builtin function … no
  definition found` → `Couldn't create Vulkan compute pipelines`), so the WorldEnvironment bloom — the
  core neon effect — does **not** render here, and FPS readings are corrupted by per-frame error spam.
  Additive blending still works (overlapping orbs read white-hot), but **the actual glow + performance
  can only be confirmed on the iPhone/Simulator (#47)** — that is the real visual/perf surface, not a
  nicety. Don't trust this box for either.
- **iOS toolchain — RESOLVED on this mini (session 6).** Godot 4.7's iOS `libgodot.a` references iOS-26
  Metal/QuartzCore symbols (`MTLTensorDomain`, `CADynamicRange*`) absent from older SDKs, so **Xcode 16.4
  (iOS 18.5 SDK) couldn't link it** ("Undefined symbols for architecture arm64"). The fix did **NOT** need
  an OS upgrade, and the old plan to upgrade the mini to **macOS Tahoe 26 is impossible — Tahoe DROPS the
  2018 mini** (`Macmini8,1`; Tahoe's only Intel models are the 2019 Mac Pro, 2020 iMac, 2019 16" MBP,
  2020 4-port 13" MBP). Instead: Xcode 26's floor is macOS Sequoia **15.6** and this mini runs 15.7.7, and
  Apple ships a **Universal Xcode 26 `.xip`** with an x86_64 slice. Installed **Xcode 26.6** to
  `/Applications/Xcode-26.6.app` (download the Universal `.xip` manually from developer.apple.com/download —
  do **NOT** use the `xcodes` CLI on Intel, it grabs the arm64-only build → "Bad CPU type"). Base `.xip`
  ships without platform SDKs (Xcode 16+ change) → ran `xcodebuild -downloadPlatform iOS` to get the iOS
  26.5 device SDK. **Unsigned archive of `build/ios/neon_runner.xcodeproj` now SUCCEEDS — the mini builds
  iOS archives.** Active toolchain: `xcode-select -p` → Xcode-26.6.
  - **`Xcode-16.4.0.app` is kept ONLY as a rollback target** (`sudo xcode-select -s
    /Applications/Xcode-16.4.0.app/Contents/Developer`). **TODO: remove Xcode-16.4.0.app once a real
    TestFlight upload has succeeded end-to-end** (it cannot build this project, so its only value is
    insurance against an RC-build quirk during signing).
  - **Still blocked before TestFlight — SIGNING, not toolchain:** the profile + `build/exportOptions.plist`
    still reference the orphaned old bundle `com.scottdix.neonrunner` (live app is `…neonsplice`), the
    distribution cert isn't loaded in `build/neonrunner.keychain-db`, and the **App Store Connect app
    record must be created in the web UI** (Apple has no API for new-app creation — `fastlane`/agent can't).
  - Glow/FPS still un-renderable here (Intel UHD 630) — needs a real device or an Apple-Silicon Mac.

## Solo project-management workflow (the operating system for this repo)

This repo runs a lightweight session-memory system. **GitHub Issues is the canonical task tracker**
(`gh` CLI; ~46 issues, 7 phase epics, 6 version milestones). Cross-session state lives in the repo,
not in any machine's local Claude memory (dev may move between machines).

- `PROJECT_STATE.yaml` — the heartbeat manifest. `focus.current_issue` / `next_issue` define what
  to work on (one issue at a time). `last_updated.notes` + `previous_notes` hold a depth-2 summary
  history. Read at session start, advanced at handoff.
- `docs/handoff/SESSION-NNN.md` — per-session handoff docs; older ones in `_archive/`.
  `docs/handoff/session-number.txt` is the last *completed* session number.
- Skills in `.claude/skills/`: **`/session-start`** (read manifest + last handoff, short greeting),
  **`/handoff`** (validate → write handoff → advance `PROJECT_STATE.yaml` → update GitHub issues →
  commit + push), **`/plan`** (architecture planning). Always run `/handoff` to end a session.
- **Commit cadence:** work is committed at `/handoff` (session boundaries), directly to `main`
  (solo repo). Don't commit mid-session unless asked.
- **Sync discipline:** the human sometimes forgets to push from another machine. At session start,
  `git fetch` and reconcile before building — the local manifest may be stale.

## Architecture (the big picture)

**Autoload singletons are the backbone.** Register in this exact order (later ones depend on
earlier ones) in `project.godot`'s `[autoload]` block — `Name="*res://autoload/x.gd"`:

1. `Events` (`autoload/events.gd`) — global signal bus, **signals only, no state/logic**
2. `GameState` (`autoload/game_state.gd`) — score, multiplier, combo, projectile count, save/load
3. `ObjectPool` (`autoload/object_pool.gd`) — projectile/effect pooling
4. `AudioManager` (`autoload/audio_manager.gd`) — sound playback
5. `SceneManager` (`autoload/scene_manager.gd`) — scene transitions

**Decoupling via the Events bus.** Systems never hold direct references to each other. A gate emits
`Events.gate_passed.emit("multiply", 2.0, new_count)`; the HUD, audio, and particle systems each
`Events.gate_passed.connect(...)`. Add `signal`s to `events.gd` rather than wiring nodes together.
`GameState` is the one place that mutates run state and re-emits scoring signals
(`add_score`, `increment_combo`, etc.).

**Two foundational decisions (don't relitigate without cause):**

- **Portrait orientation, iOS + Android.** Base resolution **1080×1920**
  (`display/window/handheld/orientation=1`), stretch `canvas_items` + `expand`. NOTE: the
  `reactive_grid` shader in `IMPLEMENTATION_PLAN.md` hardcodes `vec2(1920.0, 1080.0)` (landscape) —
  **flip that to 1080×1920 when implementing it.**
- **No custom engine.** High/growing entity counts are a *batching* problem, not an engine problem:
  solve in Godot with `MultiMeshInstance2D` (one draw call for thousands), `GPUParticles2D`, and
  full-screen bloom (cost ≈ constant regardless of count). Treat the projectile swarm as cosmetic
  followers of **one logical blob** so collision stays near-constant. The POC glow scene (issue #6)
  should double as a MultiMesh stress test on a real mid-range phone before committing to Phase 3+.

**Rendering for mobile** (already set in `project.godot`): Mobile renderer, `viewport/hdr_2d=true`
(so `Color` RGB values > 1.0 feed the WorldEnvironment glow/bloom — this is the core neon effect),
ETC2/ASTC texture compression, 2× MSAA 2D, touch-from-mouse emulation for desktop testing.

## Directory layout

`autoload/` (singletons) · `assets/` (scenes + scripts by entity: player, projectiles, gates,
obstacles, effects, ui, levels) · `shaders/` (`.gdshader`) · `resources/` (custom `Resource` class
defs) · `data/` (`.tres` instances) · `audio/`. Empty dirs hold `.gitkeep`; remove it once a real
file lands.

## Language policy

Start **100% GDScript** (scene scripts, autoloads, effects). Only introduce C# if profiling reveals
a genuine bottleneck (e.g. object pooling, heavy math). The mono build is used for future C#
flexibility, not because C# is required now.
