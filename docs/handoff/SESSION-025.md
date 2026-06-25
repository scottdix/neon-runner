# Session 025 Handoff

**Date:** 2026-06-25
**Milestone:** v0.5.0 - Complete Game  ·  **Epic:** #89 HORDE mode — twin-lane survival (the core game)

## Completed This Session
- **THE PIVOT: Neon Splice is now a twin-lane HORDE survival shooter, locked as the core game.** Removed the COMBAT (POC) mode selector; `Settings.poc_mode` forced to HORDE (LEGACY/KINETIC/GEOM parked, reversible).
- **HORDE built (ultracode, 2 workflows: H0–H5 then the visuals/Debug/gates batch):** permanent center divider as a *firing boundary* (`lane_arena.gd`), ramping fodder both lanes + 20s lane-boss (`KIND_LANEBOSS`), **firepower-as-health** (breaches drain `projectile_count`, +/× gates rebuild it, lose at 0).
- **Visuals:** thin **cyan** divider; **hollow neon** enemies (Glitch hot-pink / Rhombus neon-green / Fractal violet) via a transparent-core texture.
- **Debug menu** (pause overlay, new `autoload/debug.gd`): Tokens/Enemies/Gates toggles; Density/Speed/Strength/Firepower-Loss/Cap steppers (density+cap unbounded; MultiMesh buffer 1024 so cap can push past 256); 3 Bullet-Passthrough placeholders.
- **+/× gates** authored in `data/level_horde.tres` (firepower recovery; enemies ignore gates).
- **Two device-found bugs fixed:** (1) Debug menu rendered all rows on one line — GDScript lambda captured the Y cursor by value; moved to an instance member. (2) Firepower bar never moved — `_relabel_battery_as_firepower()` was defined but never called in the HORDE setup.
- **Validation (main loop, not trusting the workflows):** caught 10 stale verifies the per-agent self-checks missed → reconciled (force-LEGACY for parked paths / color-intent updates). **42/42 verifies PASS** + `--import` clean.
- **Shipped build #19** to TestFlight (both testers) — first HORDE build on a device.

## Next Task
**Patrick's device read on build #19 (#89).** The #1 unknown is **framerate** with the swarm at the 256 cap on a real iPhone — then readability of the neon look under bloom, and tuning the lose/recover loop (density / strength / firepower-loss / gate values — all live-tunable via the Debug menu). Dial `MAX_ENEMIES`/cap down if FPS suffers.

## Notes / Blockers
- **Mini→Air loop is the iteration surface:** edit on mini → `tools/sync-to-air.sh` → run on Air (`~/.local/bin/godot --path ~/Documents/neon-runner res://assets/ui/boot.tscn`). The Air renders real M2 bloom; the mini cannot. `tools/shot_debug_menu.gd` PNG-captures flat UI for layout checks (worked for the Debug-menu bug).
- HORDE epic is **#89** (in-code comments say `#90` — a planning guess, harmless). #86/#87/#88 commented as superseded/parked/partial.
- Parked LEGACY/KINETIC/GEOM modes + their verifies stay (force-LEGACY in the reconciled verifies). Delete both together if the pivot is ever made permanent.
- Deferred: per-archetype enemy SILHOUETTES (#88), the Bullet-Passthrough behavior (placeholders only), device-gated perf cluster #54/#39/#37/#36.
