# Session 005 Handoff

**Date:** 2026-06-20
**Milestone:** v0.1.0 - Proof of Concept  ·  **Epic:** #1 — Phase 1-2: Foundation & Project Architecture

## Completed This Session
- **Renamed game → "Neon Splice"** (Neon Runner was taken on the App Store). Bundle id
  `com.scottdix.neonsplice` registered with Apple. Repo slug stays `neon-runner`; `com.scottdix.neonrunner` is now orphaned.
- **Full scope reconciled → `docs/design/GAME_SCOPE.md`** (now authoritative; CLAUDE.md points to it).
  The game is a **free-steer, continuous-fire, vector bullet-hell survival shooter** (not the old endless
  lane-runner). 4 locked decisions: analog steer (not lanes), one win/one loss, two collision models (D3),
  authored phases (not adaptive).
- **Tracker re-baselined 52→64 issues:** enemy-faction epic #53 + #54–#63 (batched collision, Glow Battery,
  gate formations, tier evolution, Glitch enemy, phase director, SceneManager, reactive audio, MultiMesh,
  Android) + #64 (Bazzite dev box + Wake-on-LAN). Retitled #9/#10/#44; reconciliation comments on stale
  issues (#6–#8, #11, #13, #14, #16, #24, #29–#33, #52).
- **Dev loop fixed:** the installed `_mono` Godot **hangs at headless startup** on this box. Installed the
  **standard Godot 4.7** build, repointed `~/.local/bin/godot`. Reusable harness added: `tools/run-headless.sh`,
  `tools/verify_events.gd`, `tools/screenshot.gd` (result-to-file pattern; survives Godot's stdout buffering).
- **#3 Events autoload VERIFIED + CLOSED** (blocked 2 prior sessions — it was the mono binary all along).
- **#6 POC built** (`assets/poc/glow_stress.*`, set as `run/main_scene`): MultiMesh fleet + batched
  projectile→enemy collision. Headless **PASS** — per-frame logic cost flat (~30µs) across a 10× fleet scale
  (4k→40k), **proving decision D3**. Windowed screenshot confirms composition + additive look. **Glow/FPS
  cannot be validated on this mini** (Intel UHD 630 can't compile Godot's glow compute shaders under MoltenVK).
- **iOS/TestFlight pipeline built end-to-end** (`fastlane/`, `export_presets.cfg`): App Store Connect API-key
  auth, bundle-id registration, distribution cert in a dedicated keychain, App Store provisioning profile,
  Godot iOS export → a **valid Xcode project**. Account-holder accepted the updated PLA.

## Next Task
**#47 — iOS build + on-device deploy — BLOCKED on toolchain.** The final `xcodebuild archive` fails because
**Godot 4.7 requires Xcode 26 / the iOS 26 SDK** — the engine (`libgodot.a`) references `MTLTensorDomain` /
`CADynamicRange*`, which are **absent from Xcode 16.4's iOS 18.5 SDK** ("Undefined symbols for architecture
arm64"). Resolve by getting Xcode 26 onto a usable Mac:
- (a) **mini → macOS 26 Tahoe + Xcode 26** — Tahoe supports the 2018 mini, but Xcode 26 on Intel is uncertain and disk is tight (~67 GB free); **or**
- (b) **build on the MacBook Air M2** (Apple Silicon — clean for Xcode 26 *and* renders glow; 8 GB RAM is tight).

Then resume: `fastlane ios make_profile` → confirm the regenerated Xcode **scheme name** → `fastlane ios ship`
→ create the App Store Connect **app record** in the web UI (name "Neon Splice", bundle `com.scottdix.neonsplice`)
→ TestFlight. *(User deferred the toolchain upgrade to next session.)*

**Alternatively (NOT device-gated):** start the **MVP gameplay slice** — analog steer + always-on fire
(#9/#10/#52), one ± gate acting on stream volume (#11/#56), Glow Battery (#55), finite level + finish (#51).
Logic validates on the standard Godot build headlessly; visuals confirm on the M2 Air / VNC.

## Notes / Blockers
- **iOS toolchain is the headline blocker** — documented in CLAUDE.md gotchas. The whole TestFlight pipeline
  is built and working *except* the Xcode/SDK version.
- **Machines:** 2018 Intel mini (`Macmini8,1`, headless/build box — can't render glow, marginal for iOS) ·
  **MacBook Air M2** (Apple Silicon — the clean iOS + glow box; user's daily driver) · dual-boot Bazzite/Win
  PC w/ **Arc B580** (glow + Android + agent host; iOS impossible — see #64).
- **Signing artifacts** are in `build/` (gitignored): distribution cert + dedicated keychain
  `build/neonrunner.keychain-db` (password `REDACTED-KEYCHAIN-PW`) + profile, all bound to the mini. Building on the
  M2 Air redoes signing there; the account-level **bundle id + API key carry over** (`.p8` at
  `~/.appstoreconnect/private_keys/AuthKey_67B57UX826.p8`, **outside the repo**).
- `fastlane/` is committed (Key ID + Issuer ID are identifiers, not secrets; the `.p8` is not in the repo).
  The old `prep` lane's `produce(...)` fails (no Apple-ID); we use `register_id` (Spaceship) + manual cert.
- The `#6` POC's full visual/perf validation is pending the same toolchain fix (it's gated by getting onto a real device).
