#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

help_text() {
  cat <<EOF
usage: tools/run_driver.sh <version> <identity> <driver.lua> [shotdir]

Runs tools/driver_preflight.lua, reimports a stale identity with
tools/reimport.sh --force, then runs the driver under a RUN_DRIVER_ALARM
second alarm (default 300) and exits with the driver's exit code.
Relative driver and shotdir paths resolve against the current directory.
EOF
}

case "${1:-}" in
  -h|--help) help_text; exit 0 ;;
esac
if [ $# -lt 3 ]; then
  help_text >&2
  exit 2
fi
abspath() {
  local dir
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)"
  if [ -n "$dir" ]; then
    echo "$dir/$(basename "$1")"
    return
  fi
  case "$1" in
    /*) echo "$1" ;;
    *) echo "$PWD/$1" ;;
  esac
}
VERSION="$1"
IDENT="$2"
DRIVER="$3"
SHOTS="${4:-}"
ALARM="${RUN_DRIVER_ALARM:-300}"
case "$ALARM" in
  ''|*[!0-9]*|0*) echo "RUN_DRIVER_ALARM must be a positive integer" >&2; exit 2 ;;
esac
[ -z "$SHOTS" ] || SHOTS="$(abspath "$SHOTS")"
if [ ! -f "$DRIVER" ] && [ -f "$ROOT/$DRIVER" ]; then
  DRIVER="$ROOT/$DRIVER"
fi
DRIVER="$(abspath "$DRIVER")"
case "$DRIVER" in
  "$ROOT"/*) DRIVER="${DRIVER#"$ROOT"/}" ;;
esac

check="$(luajit "$ROOT/tools/driver_preflight.lua" "$IDENT" "$VERSION")"
echo "preflight $VERSION [$IDENT]: $check"
if [ "${check%% *}" != "READY" ]; then
  "$ROOT/tools/reimport.sh" "$VERSION" --identity "$IDENT" --force || exit 1
  check="$(luajit "$ROOT/tools/driver_preflight.lua" "$IDENT" "$VERSION")"
  echo "preflight $VERSION [$IDENT]: $check"
  [ "${check%% *}" = "READY" ] || exit 1
fi

[ -z "$SHOTS" ] || mkdir -p "$SHOTS"
cd "$ROOT" || exit 1
env POKEPORT_IDENTITY="$IDENT" POKEPORT_VERSION="$VERSION" POKEPORT_DRIVER="$DRIVER" \
  ${SHOTS:+POKEPORT_SHOT_DIR="$SHOTS"} \
  perl -e "alarm $ALARM; exec @ARGV" python3 "$ROOT/tools/pty_run.py" love .
code=$?
echo "driver $DRIVER exited $code"
exit "$code"
