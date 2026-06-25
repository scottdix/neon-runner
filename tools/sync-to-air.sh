#!/usr/bin/env bash
# sync-to-air.sh — push the live working tree to the M2 MacBook Air for native-bloom preview.
#
# WHY: this mini (Intel UHD 630) CANNOT render Godot's glow/bloom — the game's core neon effect —
# so every visual decision here is blind (see CLAUDE.md). The M2 Air renders Metal bloom natively.
# Division of labour: BUILD + headless-validate on the mini; SEE it on the Air. TestFlight stays the
# final on-device check.
#
# USAGE (from the mini, repo root or anywhere):
#   tools/sync-to-air.sh            # rsync working tree -> Air, then reimport there
#   AIR_HOST=other-host tools/sync-to-air.sh
#
# Then ON THE AIR: keep the Godot editor open (it auto-reloads changed files) and press Play (F5),
#   or run:  ~/.local/bin/godot --path ~/Documents/neon-runner   (opens the project)
#
# Mid-iteration changes are uncommitted (commit cadence = /handoff), so this syncs the WORKING TREE
# via rsync, NOT git. It never touches the Air's .git, its .godot import cache, or its build/ dir
# (all excluded), so the Air keeps its own platform state.
set -euo pipefail

AIR="${AIR_HOST:-macbook-air}"
SRC="/Users/scottdix/Documents/neon-runner/"
DST_PATH="/Users/scottdix/Documents/neon-runner"

echo "==> rsync working tree -> ${AIR}"
rsync -az --delete \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude '.godot/' \
  --exclude '.DS_Store' \
  "$SRC" "${AIR}:${DST_PATH}/"

echo "==> reimport on ${AIR} (incremental; first run is slower)"
ssh "$AIR" "~/.local/bin/godot --headless --path '${DST_PATH}' --import" >/dev/null 2>&1 \
  && echo "    reimport OK" \
  || echo "    reimport returned nonzero (often fine — open the editor on the Air to finish import)"

echo "==> done. On the Air: press Play (F5) in the open editor, or run:"
echo "      ~/.local/bin/godot --path ${DST_PATH}"
