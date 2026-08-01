#!/usr/bin/env bash
# Verify pinned love-nx binaries against the manifest checksums.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOVE_NX_TAG="11.5-nx1"
LOVE_NX_DIR="$ROOT/.bazinga/love-nx/$LOVE_NX_TAG"
MANIFEST="$ROOT/scripts/switch/love-nx-11.5-nx1.sha256"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

read_manifest_hash() {
  local name="$1"
  local line hash
  line="$(grep -E "^${name}[[:space:]]+" "$MANIFEST" | head -1 || true)"
  [ -n "$line" ] || fail "manifest missing entry for $name"
  hash="$(printf '%s' "$line" | awk '{print $2}')"
  case "$hash" in
    TBD_*|"") fail "manifest hash for $name is not filled in ($hash)" ;;
  esac
  printf '%s' "$hash"
}

verify_file() {
  local name="$1"
  local path="$LOVE_NX_DIR/$name"
  local expected actual
  expected="$(read_manifest_hash "$name")"
  [ -f "$path" ] || fail "missing pinned $name at $path — fetch per docs/switch-development.md"
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  [ "$actual" = "$expected" ] \
    || fail "$name checksum mismatch (expected $expected, got $actual)"
}

verify_file love.nro
verify_file love.elf
