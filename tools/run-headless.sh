#!/usr/bin/env bash
# Run a Godot tool script headless on the mac-mini and read its result reliably.
#
#   tools/run-headless.sh res://tools/verify_events.gd [/tmp/result.txt] [max_seconds]
#
# Why this exists (see CLAUDE.md "environment gotchas"):
#   - Use the STANDARD (non-mono) Godot build; the mono build hangs at headless startup.
#   - Godot block-buffers stdout AND can hang at shutdown, so we don't trust stdout markers.
#     The script should write its verdict to RESULT_FILE via FileAccess before quit();
#     this wrapper polls for that file, then force-kills Godot.
#   - No `timeout` on this box, so we bound the wait with a counted sleep loop.
#
# Exit status: 0 if RESULT_FILE appeared, 1 on timeout/parse-error.

set -uo pipefail

SCRIPT="${1:?usage: run-headless.sh <res://script.gd> [result-file] [max-seconds]}"
RESULT_FILE="${2:-/tmp/godot_headless_result.txt}"
MAX_SECONDS="${3:-30}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
LOG="/tmp/godot_headless.log"

rm -f "$RESULT_FILE" "$LOG"
"$GODOT" --headless -s "$SCRIPT" --path "$PROJECT_DIR" >"$LOG" 2>&1 &
GPID=$!

ticks=$(( MAX_SECONDS * 2 ))
n=0
until [ -f "$RESULT_FILE" ] \
   || grep -qE "SCRIPT ERROR|Parse Error|ERROR: |Failed to (load|instantiate|parse)" "$LOG" 2>/dev/null \
   || [ "$n" -ge "$ticks" ]; do
  sleep 0.5; n=$((n+1))
done

echo "==== run-headless: $SCRIPT (waited ~$((n/2))s) ===="
if [ -f "$RESULT_FILE" ]; then
  echo "---- result ($RESULT_FILE) ----"; cat "$RESULT_FILE"; rc=0
else
  echo "---- NO result file; log tail ----"; tail -15 "$LOG"; rc=1
fi

kill -9 "$GPID" 2>/dev/null
pkill -9 -f "godot --headless" 2>/dev/null
exit "$rc"
