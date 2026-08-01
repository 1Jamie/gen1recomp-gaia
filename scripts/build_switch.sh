#!/usr/bin/env bash
# Nintendo Switch packaging entry point.
#
# Usage:
#   scripts/build_switch.sh --loose [path/to/game.love]
#   scripts/build_switch.sh --fused [--version X.Y.Z]
#
# Loose mode copies pinned love.nro + game.love. Fused mode builds a single
# gen1recomp-<ver>-switch.nro via devkitPro nacptool/elf2nro (requires tools).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.bazinga/work"
DIST="$ROOT/dist/switch"
LOOSE=0
FUSED=0
GAME_LOVE=""
VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --loose) LOOSE=1; shift ;;
    --fused) FUSED=1; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [ -z "$GAME_LOVE" ]; then
        GAME_LOVE="$1"
      else
        fail "unknown argument: $1"
      fi
      shift
      ;;
  esac
done

if [ "$LOOSE" -eq 1 ] && [ "$FUSED" -eq 1 ]; then
  fail "choose one of --loose or --fused"
fi

pack_game_love() {
  mkdir -p "$WORK" "$DIST"
  local build_info="$WORK/build-info.json"
  "$ROOT/scripts/switch/write_build_info.sh" "$build_info" "$VERSION"
  local love_out="$WORK/game.love"
  local listing="$WORK/love-listing.txt"
  "$ROOT/scripts/pack_love.sh" \
    --output "$love_out" \
    --listing "$listing" \
    --build-info "$build_info" >/dev/null
  cp "$build_info" "$DIST/build-info.json"
  cp "$build_info" "$DIST/gen1recomp-${VERSION}-build-info.json"
  printf '%s' "$love_out"
}

if [ "$LOOSE" -eq 1 ]; then
  if [ -z "$GAME_LOVE" ]; then
    GAME_LOVE="$(pack_game_love)"
  else
    pack_game_love >/dev/null
  fi
  exec "$ROOT/scripts/switch/assemble_loose.sh" "$GAME_LOVE"
fi

if [ "$FUSED" -eq 1 ]; then
  GAME_LOVE="$(pack_game_love)"
  OUT_NRO="$DIST/gen1recomp-${VERSION}-switch.nro"
  "$ROOT/scripts/switch/build_fused.sh" "$GAME_LOVE" "$VERSION" "$OUT_NRO"
  cp "$WORK/build-info.json" "$DIST/gen1recomp-${VERSION}-build-info.json"
  say "done. See $DIST/"
  exit 0
fi

fail "specify --loose or --fused"
