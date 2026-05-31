#!/usr/bin/env bash
# Called by Claude Code hooks. Writes ONE word into the state file, atomically,
# then returns immediately. Must stay microsecond-fast so it never slows Claude.
#   usage: set-state.sh busy|wait|done|idle
set -euo pipefail

dir="${HOME}/.claude/statuslight"
state="${dir}/state"
word="${1:-idle}"

case "$word" in
  busy|wait|done|idle) ;;
  *) word="idle" ;;
esac

# atomic write: temp file + mv, so the GUI never reads a half-written value
tmp="$(mktemp "${dir}/.state.XXXXXX")"
printf '%s' "$word" > "$tmp"
mv -f "$tmp" "$state"
