#!/usr/bin/env bash
# Nintendo Switch packaging entry point.
#
# Usage:
#   scripts/build_switch.sh --loose [path/to/game.love]
#
# Additional modes (fused NRO) are added in later tasks.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOOSE=0
GAME_LOVE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --loose) LOOSE=1; shift ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [ -z "$GAME_LOVE" ]; then
        GAME_LOVE="$1"
      else
        echo "unknown argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ "$LOOSE" -eq 1 ]; then
  if [ -n "$GAME_LOVE" ]; then
    exec "$ROOT/scripts/switch/assemble_loose.sh" "$GAME_LOVE"
  else
    exec "$ROOT/scripts/switch/assemble_loose.sh"
  fi
fi

echo "error: specify --loose (fused build not implemented yet)" >&2
exit 2
