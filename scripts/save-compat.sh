#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

LUA=${LUA:-luajit}
OUT=${SAVE_COMPAT_OUT:-${TMPDIR:-/tmp}/pokeport-save-compat}
OUT=${OUT%/}
PKHEX_ROOT=${PKHEX_ROOT:-$ROOT/../PKHeX-master}
OPENHOME_ROOT=${OPENHOME_ROOT:-$ROOT/../OpenHome}
WANT_PKHEX=1
WANT_OPENHOME=1
BLESS=0
EXPECTED=${SAVE_COMPAT_EXPECTED:-$ROOT/tests/fixtures/save/expected}

for arg in "$@"; do
  case "$arg" in
    --pkhex-only) WANT_OPENHOME=0 ;;
    --openhome-only) WANT_PKHEX=0 ;;
    --bless) BLESS=1 ;;
    --help|-h)
      echo "usage: scripts/save-compat.sh [--pkhex-only|--openhome-only] [--bless]"
      echo "  --bless          rewrite tests/fixtures/save/expected/*.json from this run"
      echo "  SAVE_COMPAT_OUT  work dir (default \$TMPDIR/pokeport-save-compat)"
      echo "  PKHEX_ROOT       PKHeX checkout holding PKHeX.Core (default ../PKHeX-master)"
      echo "  OPENHOME_ROOT    OpenHome checkout with node_modules (default ../OpenHome)"
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT/files" || exit 1
echo "-- dumping fixtures and their exports into $OUT/files"
"$LUA" tools/save-compat/dump_fixtures.lua "$OUT/files" || exit 1
LIST="$OUT/files/list.txt"

FAILED=0
IGNORE=()
[ -f "$OUT/files/skipped.txt" ] && while IFS= read -r g; do IGNORE+=("$g"); done <"$OUT/files/skipped.txt"

reconcile() {
  local kind="$1" actual="$2"
  local expected="$EXPECTED/$kind.json"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "   expected-result diff skipped (no python3 on PATH)"
    return 0
  fi
  if [ "$BLESS" = 1 ]; then
    python3 tools/save-compat/summarize.py bless "$kind" "$actual" "$expected" || return 1
  else
    python3 tools/save-compat/summarize.py compare "$kind" "$actual" "$expected" ${IGNORE[@]+"${IGNORE[@]}"} || return 1
  fi
}

run_pkhex() {
  if ! command -v dotnet >/dev/null 2>&1; then
    echo "-- PKHeX probe: skipped (no dotnet on PATH)"
    return 0
  fi
  if [ ! -f "$PKHEX_ROOT/PKHeX.Core/PKHeX.Core.csproj" ]; then
    echo "-- PKHeX probe: skipped (no PKHeX.Core under $PKHEX_ROOT; set PKHEX_ROOT)"
    return 0
  fi
  echo "-- PKHeX probe: building against $PKHEX_ROOT"
  mkdir -p "$OUT/pkhex-src" "$OUT/probe-src"
  rsync -a --delete --exclude bin --exclude obj "$PKHEX_ROOT/PKHeX.Core/" "$OUT/pkhex-src/PKHeX.Core/" || return 1
  for f in Directory.Build.props icon.png; do
    [ -f "$PKHEX_ROOT/$f" ] && cp "$PKHEX_ROOT/$f" "$OUT/pkhex-src/$f"
  done
  rsync -a --delete --exclude bin --exclude obj tools/save-compat/PkhexProbe/ "$OUT/probe-src/" || return 1
  if ! dotnet build "$OUT/probe-src/PkhexProbe.csproj" -c Release -o "$OUT/pkhex-probe" -nologo -v quiet \
      >"$OUT/pkhex-build.log" 2>&1; then
    echo "   build failed, see $OUT/pkhex-build.log"
    tail -5 "$OUT/pkhex-build.log"
    return 1
  fi
  local tsv="$OUT/pkhex.tsv"
  if ! tr '\n' '\0' <"$LIST" | xargs -0 dotnet "$OUT/pkhex-probe/PkhexProbe.dll" >"$tsv" 2>"$OUT/pkhex-run.log"; then
    echo "   probe failed, see $OUT/pkhex-run.log"
    return 1
  fi
  local total unrecognized bad
  total=$(awk -F'\t' '$1 != "file" { n++ } END { print n + 0 }' "$tsv")
  unrecognized=$(grep -c "NOT RECOGNIZED" "$tsv" || true)
  bad=$(awk -F'\t' '$1 != "file" && $6 == "False" { n++ } END { print n + 0 }' "$tsv")
  echo "   $total files: $unrecognized not recognized, $bad with invalid checksums ($tsv)"
  awk -F'\t' '$1 != "file" && ($4 == "NOT RECOGNIZED" || $6 == "False") { printf "   %s %s %s\n", $1, $4, $7 }' "$tsv" \
    | sed "s#$OUT/files/##" | head -40
  reconcile pkhex "$tsv"
}

run_openhome() {
  if ! command -v node >/dev/null 2>&1; then
    echo "-- OpenHome probe: skipped (no node on PATH)"
    return 0
  fi
  local vitest="$OPENHOME_ROOT/node_modules/.bin/vitest"
  if [ ! -x "$vitest" ] || [ ! -d "$OPENHOME_ROOT/pkm_rs/pkg" ]; then
    echo "-- OpenHome probe: skipped (needs $OPENHOME_ROOT with node_modules and a built pkm_rs/pkg)"
    return 0
  fi
  echo "-- OpenHome probe: $OPENHOME_ROOT"
  local jsonl="$OUT/openhome.jsonl"
  if ! (cd "$OPENHOME_ROOT" && SAV_LIST="$LIST" OUT_JSONL="$jsonl" OPENHOME_ROOT="$OPENHOME_ROOT" \
    "$vitest" run --config "$ROOT/tools/save-compat/openhome/vitest.batch.config.mjs" >"$OUT/openhome-run.log" 2>&1); then
    echo "   probe failed, see $OUT/openhome-run.log"
    tail -5 "$OUT/openhome-run.log"
    return 1
  fi
  if [ ! -s "$jsonl" ]; then
    echo "   no results, see $OUT/openhome-run.log"
    tail -5 "$OUT/openhome-run.log"
    return 1
  fi
  local total unrecognized
  total=$(wc -l <"$jsonl" | tr -d ' ')
  unrecognized=$(grep -c '"detected":"UNRECOGNIZED"' "$jsonl" || true)
  echo "   $total files: $unrecognized unrecognized ($jsonl)"
  grep -E '"detected":"(UNRECOGNIZED|AMBIGUOUS)"' "$jsonl" | sed -E 's/^\{"file":"([^"]+)".*"detected":"([A-Z]+)".*/   \1 \2/' | head -40
  reconcile openhome "$jsonl"
}

[ "$WANT_PKHEX" = 1 ] && { run_pkhex || FAILED=1; }
[ "$WANT_OPENHOME" = 1 ] && { run_openhome || FAILED=1; }
exit $FAILED
