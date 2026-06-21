# Session 006 Handoff

**Date:** 2026-06-21
**Milestone:** v0.1.0 - Proof of Concept  ·  **Epic:** #1 — Phase 1-2: Foundation & Project Architecture

## Completed This Session
- **#47 DONE — iOS build + on-device deploy pipeline.** First build **uploaded to TestFlight**
  (`fastlane ios ship` succeeded; ASC app id **6782516475**, bundle `com.scottdix.neonsplice`).
  The whole chain now runs on the Intel mini: Xcode 26.6 → Godot iOS export → signed archive →
  signed `.ipa` → TestFlight.
- **Toolchain blocker killed.** The session-005 plan (upgrade mini → macOS Tahoe) was **impossible**
  (Tahoe drops the 2018 mini) and **unnecessary**: Xcode 26's floor is Sequoia 15.6 (mini runs
  15.7.7) and Apple ships a **Universal** Xcode 26 `.xip` with an x86_64 slice. Installed **Xcode
  26.6 RC2** to `/Applications/Xcode-26.6.app` side-by-side with 16.4; `-downloadPlatform iOS` for
  the iOS 26.5 SDK. The `MTLTensorDomain`/`CADynamicRange` undefined-symbols link error is gone.
- **Signing reconciled (rename debt).** `make_profile` → new App Store profile for `…neonsplice`
  (old one was for the orphaned `…neonrunner` bundle); fixed `build/exportOptions.plist`; re-exported
  the Godot project (stale — was built for the old bundle) → `neon_splice.xcodeproj`. Solved Godot's
  Automatic-vs-Distribution signing conflict by forcing **manual signing via `xcargs`** in the
  Fastfile `ship` lane (survives every re-export).
- **Confirmed `../virtus-focus` is unaffected** — it's Expo/React-Native building on **EAS cloud**,
  zero local-Xcode dependency. (Also: EAS can't build Godot; cloud analog would be GH Actions
  `macos-26` / Codemagic.)
- Docs corrected: CLAUDE.md iOS gotcha rewritten (RESOLVED + 16.4-removal TODO); SESSION-005 carries
  a correction note. Memories updated.

## Next Task
**MVP gameplay slice** (not device-gated; builds/validates on standard Godot now) — analog steer +
always-on fire (#9/#10/#52), one ± gate on stream volume (#11/#56), Glow Battery (#55), finite level
+ finish (#51). Visuals confirm via the now-working TestFlight build on a real iPhone / the M2 Air.

## Notes / Blockers
- **Xcode 16.4 kept as rollback insurance** (`sudo xcode-select -s /Applications/Xcode-16.4.0.app/Contents/Developer`).
  **TODO: remove `Xcode-16.4.0.app` once the TestFlight build has been verified on a device** (it can't
  build this project, so its only value is insurance against an RC-build quirk).
- **Glow/bloom + real FPS still un-renderable on this Intel mini** (UHD 630 / MoltenVK). The TestFlight
  build on a physical iPhone is now the path to validate them — this also closes out #6's device check.
- Signing crib (cert ids, profile UUID, keychain password, the manual-signing xcargs) is in the
  CLAUDE.md gotcha + agent memory if the pipeline ever regresses.
- `fastlane/` API key `.p8` remains outside the repo at `~/.appstoreconnect/private_keys/AuthKey_67B57UX826.p8`.
