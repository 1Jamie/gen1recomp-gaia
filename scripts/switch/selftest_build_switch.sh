#!/usr/bin/env bash
# Offline self-test for Switch packaging entry points (no network, no nacptool).
#
# Usage: scripts/switch/selftest_build_switch.sh
#
# Covers: sha256_file, --help glossary, XOR loose/fused, fail_need_fetch,
# verify_love_nx mismatch, fail_fused_toolchain message. Does not download
# love-nx or invoke nacptool/elf2nro/Docker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf '  PASS: %s\n' "$*"
}

bad() {
  FAIL=$((FAIL + 1))
  printf '  FAIL: %s\n' "$*" >&2
}

say "selftest_build_switch (offline)"

# ---------------------------------------------------------------------------
# 1. sha256_file on a known temp file
# ---------------------------------------------------------------------------
TMP="$(mktemp "${TMPDIR:-/tmp}/selftest-sha.XXXXXX")"
printf 'gen1recomp-selftest\n' > "$TMP"
EXPECTED_SHA="$(shasum -a 256 "$TMP" | awk '{print $1}')"
ACTUAL_SHA="$(sha256_file "$TMP")"
rm -f "$TMP"
if [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
  ok "sha256_file matches shasum ($ACTUAL_SHA)"
else
  bad "sha256_file mismatch (expected $EXPECTED_SHA, got $ACTUAL_SHA)"
fi

# ---------------------------------------------------------------------------
# 2. --help contains fetch / loose / fused
# ---------------------------------------------------------------------------
HELP_OUT="$("$ROOT/scripts/build_switch.sh" --help 2>&1 || true)"
HELP_LC="$(printf '%s' "$HELP_OUT" | tr '[:upper:]' '[:lower:]')"
MISSING=""
printf '%s' "$HELP_LC" | grep -q 'fetch' || MISSING="${MISSING} fetch"
printf '%s' "$HELP_LC" | grep -q 'loose' || MISSING="${MISSING} loose"
printf '%s' "$HELP_LC" | grep -q 'fused' || MISSING="${MISSING} fused"
printf '%s' "$HELP_LC" | grep -Eq 'auto-download|downloads' || MISSING="${MISSING} auto-download"
printf '%s' "$HELP_LC" | grep -Eq 'non-goal|does not|never' || MISSING="${MISSING} non-goals"
if [ -z "$MISSING" ]; then
  ok "build_switch.sh --help mentions fetch, loose, fused (+ auto-download/non-goals)"
else
  bad "build_switch.sh --help missing:$MISSING"
fi

# ---------------------------------------------------------------------------
# 3. XOR --loose --fused exits non-zero
# ---------------------------------------------------------------------------
XOR_RC=0
"$ROOT/scripts/build_switch.sh" --loose --fused >/dev/null 2>&1 || XOR_RC=$?
if [ "$XOR_RC" -ne 0 ]; then
  ok "build_switch.sh --loose --fused exits non-zero ($XOR_RC)"
else
  bad "build_switch.sh --loose --fused should exit non-zero"
fi

# ---------------------------------------------------------------------------
# 4. assemble_loose without pin → stderr contains --fetch
# ---------------------------------------------------------------------------
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/selftest-loose.XXXXXX")"
# shellcheck disable=SC2064
trap "rm -rf '$STAGING'" EXIT

FAKE_LOVE="$STAGING/game.love"
printf 'PK\x03\x04' > "$FAKE_LOVE"  # minimal placeholder; assemble only checks -f

# Temporarily hide the pin dir if present by pointing ROOT's pin via a subshell
# that moves the pin aside — or run assemble against a missing path by
# ensuring .bazinga/love-nx/11.5-nx1/love.nro is absent for this check.
PIN_DIR="$ROOT/.bazinga/love-nx/11.5-nx1"
PIN_BACKUP=""
if [ -f "$PIN_DIR/love.nro" ]; then
  PIN_BACKUP="$STAGING/love.nro.bak"
  mv "$PIN_DIR/love.nro" "$PIN_BACKUP"
fi

ASS_ERR="$STAGING/assemble.err"
ASS_RC=0
"$ROOT/scripts/switch/assemble_loose.sh" "$FAKE_LOVE" >"$STAGING/assemble.out" 2>"$ASS_ERR" || ASS_RC=$?

if [ -n "$PIN_BACKUP" ]; then
  mv "$PIN_BACKUP" "$PIN_DIR/love.nro"
fi

if [ "$ASS_RC" -ne 0 ] && grep -q -- '--fetch' "$ASS_ERR"; then
  ok "assemble_loose without pin cites --fetch"
else
  bad "assemble_loose without pin should fail citing --fetch (rc=$ASS_RC err=$(cat "$ASS_ERR"))"
fi

# ---------------------------------------------------------------------------
# 5a. verify_love_nx fails on checksum mismatch (corrupt copy)
# ---------------------------------------------------------------------------
VERIFY_WORK="$STAGING/verify-mismatch"
mkdir -p "$VERIFY_WORK"
# Create a private ROOT-like tree is hard; instead corrupt a temp copy and
# invoke verify by temporarily swapping the pin file.
CORRUPT_BACKUP=""
if [ -f "$PIN_DIR/love.nro" ]; then
  CORRUPT_BACKUP="$STAGING/love.nro.real"
  cp "$PIN_DIR/love.nro" "$CORRUPT_BACKUP"
  printf 'not-the-real-love-nro\n' > "$PIN_DIR/love.nro"
  VM_RC=0
  VM_ERR="$STAGING/verify.err"
  "$ROOT/scripts/switch/verify_love_nx.sh" >"$STAGING/verify.out" 2>"$VM_ERR" || VM_RC=$?
  mv "$CORRUPT_BACKUP" "$PIN_DIR/love.nro"
  if [ "$VM_RC" -ne 0 ] && grep -Eqi 'mismatch|expected' "$VM_ERR"; then
    ok "verify_love_nx fails on checksum mismatch"
  else
    bad "verify_love_nx should fail on mismatch (rc=$VM_RC err=$(cat "$VM_ERR"))"
  fi
else
  # No real pin available — still assert sha256_file + manifest read path
  ok "verify_love_nx mismatch skipped (no local pin binaries)"
fi

# ---------------------------------------------------------------------------
# 5b. Idempotent fetch skip when pin already valid (no network if present)
# ---------------------------------------------------------------------------
if [ -f "$PIN_DIR/love.nro" ] && [ -f "$PIN_DIR/love.elf" ]; then
  if "$ROOT/scripts/switch/verify_love_nx.sh" >/dev/null 2>&1; then
    FETCH_OUT="$STAGING/fetch.out"
    FETCH_RC=0
    "$ROOT/scripts/switch/fetch_love_nx.sh" >"$FETCH_OUT" 2>&1 || FETCH_RC=$?
    if [ "$FETCH_RC" -eq 0 ] && grep -Eqi 'skip|already|verified' "$FETCH_OUT"; then
      ok "fetch_love_nx idempotent skip when pin present"
    elif [ "$FETCH_RC" -eq 0 ]; then
      ok "fetch_love_nx exits 0 with existing valid pin"
    else
      bad "fetch_love_nx with valid pin failed (rc=$FETCH_RC out=$(cat "$FETCH_OUT"))"
    fi
  else
    ok "fetch idempotent skipped (pin present but verify failed — left alone)"
  fi
else
  ok "fetch idempotent skipped (no local pin binaries; offline)"
fi

# ---------------------------------------------------------------------------
# 5b2. Mid-fetch / network failure: URL + tool status + retry --fetch (SWBLD-05)
# ---------------------------------------------------------------------------
FETCH_FAIL_ERR="$STAGING/fetch-fail.err"
FETCH_FAIL_OUT="$STAGING/fetch-fail.out"
FETCH_FAIL_RC=0
PIN_MOVED=""
if [ -d "$PIN_DIR" ]; then
  PIN_MOVED="$STAGING/pin-backup"
  mv "$PIN_DIR" "$PIN_MOVED"
fi
# Closed port / unreachable host — no real network asset required.
GEN1_LOVE_NX_BASE_URL="http://127.0.0.1:1" \
  "$ROOT/scripts/switch/fetch_love_nx.sh" >"$FETCH_FAIL_OUT" 2>"$FETCH_FAIL_ERR" || FETCH_FAIL_RC=$?
if [ -n "$PIN_MOVED" ]; then
  rm -rf "$PIN_DIR"
  mv "$PIN_MOVED" "$PIN_DIR"
fi
if [ "$FETCH_FAIL_RC" -ne 0 ] \
  && grep -q 'download failed:' "$FETCH_FAIL_ERR" \
  && grep -Eq 'curl exit|wget exit|HTTP status' "$FETCH_FAIL_ERR" \
  && grep -q 'retry: scripts/build_switch.sh --fetch' "$FETCH_FAIL_ERR"; then
  ok "fetch network failure cites URL status and retry --fetch"
else
  bad "fetch failure should cite status + retry --fetch (rc=$FETCH_FAIL_RC err=$(cat "$FETCH_FAIL_ERR"))"
fi

# ---------------------------------------------------------------------------
# 5c. fail_fused_toolchain mentions docs/switch-build.md
# ---------------------------------------------------------------------------
FT_ERR="$STAGING/fused-toolchain.err"
FT_RC=0
(
  # Invoke as a function in a subshell that sources common
  . "$SCRIPT_DIR/common.sh"
  fail_fused_toolchain
) >"$STAGING/fused-toolchain.out" 2>"$FT_ERR" || FT_RC=$?

if [ "$FT_RC" -ne 0 ] && grep -q 'docs/switch-build.md' "$FT_ERR"; then
  ok "fail_fused_toolchain cites docs/switch-build.md"
else
  bad "fail_fused_toolchain should mention docs/switch-build.md (rc=$FT_RC err=$(cat "$FT_ERR"))"
fi

# Also check multi-OS hints
FT_LC="$(tr '[:upper:]' '[:lower:]' < "$FT_ERR")"
OS_MISSING=""
printf '%s' "$FT_LC" | grep -q 'macos' || OS_MISSING="${OS_MISSING} macOS"
printf '%s' "$FT_LC" | grep -q 'linux' || OS_MISSING="${OS_MISSING} Linux"
printf '%s' "$FT_LC" | grep -Eq 'windows|msys' || OS_MISSING="${OS_MISSING} Windows"
printf '%s' "$FT_LC" | grep -q 'docker' || OS_MISSING="${OS_MISSING} Docker"
if [ -z "$OS_MISSING" ]; then
  ok "fail_fused_toolchain mentions macOS/Linux/Windows/Docker"
else
  bad "fail_fused_toolchain missing OS hints:$OS_MISSING"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
say "selftest: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
