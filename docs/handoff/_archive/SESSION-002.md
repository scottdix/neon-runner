# Session 002 Handoff

**Date:** 2026-06-20
**Milestone:** v0.1.0 - Proof of Concept  ·  **Epic:** #1 — Phase 1-2: Foundation & Project Architecture

## Completed This Session
- **Dev environment migrated to the mac-mini** (`ssh mac-mini`, user `scottdix`). It becomes the
  primary, headless dev box; Claude Code runs **natively there** inside a tmux session the user
  starts — the M2 laptop is no longer involved in Neon Runner dev.
- **Provisioned the mac-mini** (Intel i5-8500B, 6c, 64 GB RAM, macOS 15.7.7), userspace / no Homebrew:
  - Repo cloned at `~/Documents/neon-runner`.
  - **Godot 4.7-mono** at `~/Applications/Godot_mono.app` → symlinked `~/.local/bin/godot` (quarantine cleared, runs headless).
  - **.NET SDK 8.0.422** at `~/.dotnet`.
  - PATH + `DOTNET_ROOT` added to `~/.zshrc` (`# neon-runner toolchain` marker) so a login-shell instance picks them up.
  - Already present: Xcode 16.4 (iOS Simulator), Android `emulator`/`adb`, `node`, `gh`, `java`.
- **Credentials verified working:** `gh` authed as `scottdix` (ADMIN on repo; scopes `repo, workflow, gist, read:org`),
  wired as the global git credential helper → HTTPS push/pull works (`git push --dry-run` clean).
  Git identity `Scott Dix <scott.dix@gmail.com>`.
- **No project code yet** — #2 was not started. Stack confirmed: stay **Godot/.NET** (the EAS/emulator
  tooling on the box was incidental, not a stack change).

## Next Task
**#2 — Initialize Godot 4.x project with folder structure** (not started; still `current_issue`).
Build it **on the mac-mini** (Godot 4.7 satisfies the plan's "4.3+"). Then #3 (Events autoload).

## Notes / Blockers
- **First thing on the mac-mini:** `cd ~/Documents/neon-runner && git pull` to get this handoff, then `/session-start`.
- The mac-mini's Claude Code has its own `~/.claude` — it will NOT inherit the M2 laptop's project
  memory. The repo (`PROJECT_STATE.yaml` + `docs/handoff/`) is the only cross-box context.
- Non-interactive `ssh mac-mini 'cmd'` does NOT load the toolchain PATH; only relevant if driving
  remotely. A locally-running Claude Code (login shell) has it automatically — not a concern.
- None blocking.
