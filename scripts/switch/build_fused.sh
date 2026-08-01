#!/usr/bin/env bash
# Build fused gen1recomp Switch NRO (romfs game.love + nacp + icon).
#
# Usage: scripts/switch/build_fused.sh GAME_LOVE VERSION OUT_NRO

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOVE_NX_TAG="11.5-nx1"
LOVE_NX_DIR="$ROOT/.bazinga/love-nx/$LOVE_NX_TAG"
LOVE_ELF="$LOVE_NX_DIR/love.elf"
ICON="$ROOT/assets/switch/icon.jpg"
APP_NAME="gen1recomp"
BUNDLE_ID="com.theboisclub.pokemonred"

GAME_LOVE="${1:-}"
VERSION="${2:-}"
OUT_NRO="${3:-}"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -n "$GAME_LOVE" ] && [ -n "$VERSION" ] && [ -n "$OUT_NRO" ] \
  || fail "usage: $0 GAME_LOVE VERSION OUT_NRO"

[ -f "$GAME_LOVE" ] || fail "missing game.love at $GAME_LOVE"

"$ROOT/scripts/switch/verify_love_nx.sh"

command -v nacptool >/dev/null \
  || fail "nacptool not found (install devkitPro switch-dev; never download love-nx latest)"
command -v elf2nro >/dev/null \
  || fail "elf2nro not found (install devkitPro switch-dev; never download love-nx latest)"

[ -f "$ICON" ] || fail "missing Switch icon at $ICON"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gen1recomp-fused.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

ROMFS_DIR="$WORK/romfs"
mkdir -p "$ROMFS_DIR"
cp "$GAME_LOVE" "$ROMFS_DIR/game.love"

NACP="$WORK/control.nacp"
nacptool --create "$APP_NAME" "$BUNDLE_ID" "$VERSION" "$NACP"

say "building fused NRO with pinned love.elf"
elf2nro "$LOVE_ELF" "$OUT_NRO" \
  --icon="$ICON" \
  --nacp="$NACP" \
  --romfsdir="$ROMFS_DIR"

mkdir -p "$(dirname "$OUT_NRO")"
shasum -a 256 "$OUT_NRO" | awk '{print $1}' > "${OUT_NRO}.sha256"
say "fused NRO: $OUT_NRO"
say "sha256: $(cat "${OUT_NRO}.sha256")"
