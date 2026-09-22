#!/usr/bin/env bash
# Unified test entry point (21-testing-and-ci §CI).
#
# Runs every tier that this checkout can run and exits non-zero if any of
# them fails.  The tier split is what makes that possible: T1/T2/T4 need
# nothing but the committed fixture dataset, so they run anywhere --
# including CI, which has no ROM.  T3 asserts Pokemon Red facts and needs
# data/generated/ or an imported Red cache, so it is skipped automatically
# when neither exists rather than failing the run.
#
#   scripts/test.sh                 every tier this checkout can run
#   scripts/test.sh --quick         skip the slow content tier
#   scripts/test.sh --bless         re-pin the fingerprint goldens
#   WITH_SHOTS=1 scripts/test.sh    also capture and diff golden shots
#                                   (fails today -- see the T5 block below)
#
# LUA overrides the interpreter (luajit here; CI installs lua5.4 too, but
# the engine targets LuaJIT/5.1 semantics so luajit is the default).
#
# POKEPORT_TEST_CACHES points at one LOVE identity holding an imported cache
# per version (red/ blue/ yellow/ gold/ silver/ crystal/); each is exported as
# RED_CACHE .. CRYSTAL_CACHE for the suites that read one.  Build it with:
#   POKEPORT_IDENTITY=pokeport-test-caches POKEPORT_VERSION=<version> \
#   POKEPORT_IMPORT_ONLY=1 POKEPORT_IMPORT_ROM="<rom>" love .
# An explicit RED_CACHE/GOLD_CACHE/... in the environment always wins.
#
# T6 runs every top-level tests/game3_*.lua suite (the game3 scenario
# coverage: battle, capture, menus, overworld, script specials, save).
# Suites self-skip with exit 0 when an artifact they need is absent, so
# the tier runs anywhere; nothing is ever skipped by name.  Failures not
# in KNOWN_GAME3_FAILURES (the docs/game3/game3-suite-sweep-v113.md
# baseline) fail the gate; listed ones print as known.  GAME3_JOBS sets
# suite parallelism (default 8; GAME3_JOBS=1 serializes).
#
# A failing suite prints its first [FAIL] line (or first crash/error line,
# or a dead-worker notice when it produced no output at all) so the cause
# is on the terminal, and the per-suite logs are KEPT (path printed) for
# triage instead of deleted.  No retries anywhere: every failure stands.

set -uo pipefail

cd "$(dirname "$0")/.."

LUA=${LUA:-luajit}
LUA54=${LUA54:-lua5.4}
BLESS=0
QUICK=0
SHOTS=${WITH_SHOTS:-0}

for arg in "$@"; do
  case "$arg" in
    --bless) BLESS=1 ;;
    --bless-shots) SHOTS=1; BLESS=1 ;;
    --quick) QUICK=1 ;;
    --help|-h) sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v "$LUA" >/dev/null 2>&1; then
  echo "no lua interpreter '$LUA' on PATH (set LUA=...)" >&2
  exit 2
fi

# The save-directory sandbox (conf.lua reads POKEPORT_IDENTITY) is scoped
# to the shot tier, which is the only one that starts a real LOVE process
# and could write into a developer's save folder.  Exporting it for the
# whole run instead would change what SaveIO.defaultPath() returns, and the
# save-editor suite pins that to the default identity.
SANDBOX_IDENTITY="ci-$$"

# Per-version caches.  POKEPORT_TEST_CACHES names one LOVE identity holding an
# imported cache per version (red/ blue/ yellow/ gold/ silver/ crystal/).
CACHE_IDENTITY=${POKEPORT_TEST_CACHE_IDENTITY:-pokeport-test-caches}
if [ -n "${POKEPORT_TEST_CACHES:-}" ]; then
  CACHE_ROOT="$POKEPORT_TEST_CACHES"
elif [ -d "$HOME/Library/Application Support/LOVE/$CACHE_IDENTITY" ]; then
  CACHE_ROOT="$HOME/Library/Application Support/LOVE/$CACHE_IDENTITY"
else
  CACHE_ROOT="$HOME/.local/share/love/$CACHE_IDENTITY"
fi

# Only a cache with the importer's completion marker is offered: a half-written
# one would fail suites that are meant to self-skip.
adopt_cache() {
  local var="$1" dir="$CACHE_ROOT/$2"
  [ -z "${!var:-}" ] || return 0
  [ -f "$dir/rom-cache.complete" ] || return 0
  export "$var=$dir"
  echo "   $var=$dir"
}

echo ""
echo "-- per-version caches under $CACHE_ROOT"
adopt_cache RED_CACHE red
adopt_cache BLUE_CACHE blue
adopt_cache YELLOW_CACHE yellow
adopt_cache GOLD_CACHE gold
adopt_cache SILVER_CACHE silver
adopt_cache CRYSTAL_CACHE crystal

FAILED=()
run_tier() {
  local label="$1"; shift
  echo ""
  echo "=============================================================="
  echo "  $label"
  echo "=============================================================="
  if "$@"; then
    echo "-- $label: PASS"
  else
    echo "-- $label: FAIL"
    FAILED+=("$label")
  fi
}

# ------- ROM-free tiers: these are what CI runs

if command -v luacheck >/dev/null 2>&1; then
  run_tier "T0 luacheck gate (undefined globals, unreachable code)" \
    ./scripts/lint.sh --gate
else
  echo ""
  echo "-- T0 luacheck gate: skipped (no luacheck on PATH --"
  echo "   luarocks install luacheck; CI installs and gates on it regardless)"
fi

run_tier "T0 ROM builder version routing" python3 tests/build_rom_data_cli_test.py
run_tier "T0 ROM manifest generator pin/overrides" python3 tests/rom_manifest_generator_test.py
run_tier "T0 Yellow title OBP eye remap" python3 tests/title_pikachu_obp_test.py
run_tier "T0 Crystal manifest + specials coverage" "$LUA" tests/crystal_import_test.lua
run_tier "T0 switch CI workflow content gate" "$LUA" tests/switch_ci_workflows_test.lua
run_tier "T0 switch transfer docs gate" "$LUA" tests/switch_transfer_docs_test.lua
run_tier "T0 ShaderFX bridge packaging gate" "$LUA" tests/shaderfx_bridge_packaging_test.lua
# NX Blue/Yellow asset overlay: ROM-free, must run on every checkout so a
# Sound.lua / overlay regression is not gated only on switch-changes paths.
run_tier "T0 NX asset overlay fallback" "$LUA" tests/engine/assets_version_fallback_test.lua
run_tier "T0 NX generated-path static guard" "$LUA" tests/engine/nx_generated_guard_test.lua
run_tier "T0 NX Yellow/Blue boot (dynamic paths)" "$LUA" tests/engine/nx_yellow_boot_test.lua
run_tier "T0 NX Gold cache load (maps.lua prefix)" "$LUA" tests/engine/cache_fs_gold_nx_load_test.lua
run_tier "T0 touch-controls pad cursor" "$LUA" tests/engine/touch_controls_pad_cursor_test.lua
run_tier "T0 URI launch arguments" "$LUA" tests/engine/launch_uri_args_test.lua
run_tier "T1/T2 engine invariants + parity gates" "$LUA" tests/run_engine.lua
# Gen 2 / Crystal: ROM-free (own fixtures, or a self-skip on a missing cache),
# so it runs here rather than behind the Red content gate below.
run_tier "T2 Gen 2 / Crystal suites" "$LUA" tests/run_gen2.lua
run_tier "T4 mod-SDK" "$LUA" tests/run_modkit.lua

# ------- T6: every top-level tests/game3_*.lua suite (273 files)
#
# Discovery is the tests/game3_*.lua glob -- the same convention the sweep
# docs use -- run as standalone "$LUA" <suite> processes.  Suites self-skip
# with exit 0 when an artifact they need (imported cache, ../pokefirered,
# a ROM path, an anim pack) is absent, so a missing artifact never fails
# the tier and no suite is ever skipped by name here.  A non-zero exit is a
# failure: it prints below and fails the tier UNLESS the suite is listed in
# KNOWN_GAME3_FAILURES.  GAME3_JOBS (default 8) batches the processes.
#
# KNOWN_GAME3_FAILURES is the frozen 25-failure baseline from
# docs/game3/game3-suite-sweep-v113.md minus the two stale G1-contract stubs
# fixed this pass (game3_link_session, game3_save_trainer_card) = 23 names,
# as a CEILING: a listed suite may fail without failing the gate while the
# fix wave burns the list down, and a failure in any suite NOT listed always
# fails the gate.  Delete a name the moment its suite goes green so a later
# regression there fails again.
KNOWN_GAME3_FAILURES='game3_battle_ai_test
game3_special_events_test
game3_special_trade_test
game3_cerulean_block_exits_test
game3_cerulean_policeman_bill_test
game3_collision_npc_dir_test
game3_emote_movement_test
game3_item_use_and_parcel_test
game3_map_onload_test
game3_mapscripts_test
game3_npc_player_collision_test
game3_objects_perm_reset_test
game3_runtime_camera_object_test
game3_static_encounter_test
game3_stitchcoll_escape_warp_test
game3_stitchcoll_ghost_ctx_test
game3_stitchcoll_move_kinds_test
game3_stitchcoll_run_speed_test
game3_stitchfield_ground_test
game3_vermilion_trash_cans_test
game3_viridian_gym_door_test
game3_oaks_lab_save_reload_test
game3_trainer_sight_test'

run_game3_tier() {
  local jobs=${GAME3_JOBS:-8}
  case "$jobs" in ''|*[!0-9]*) jobs=8 ;; esac
  [ "$jobs" -ge 1 ] || jobs=8

  local suites=(tests/game3_*.lua)
  if [ ! -f "${suites[0]:-}" ]; then
    echo "-- T6 game3: no tests/game3_*.lua suites found"
    return 1
  fi
  local total=${#suites[@]}
  echo "-- T6 game3: running $total top-level suites, $jobs at a time"

  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/game3gate.XXXXXX") || return 1

  local suite base i=0
  for suite in "${suites[@]}"; do
    base=${suite##*/}
    base=${base%.lua}
    (
      "$LUA" "$suite" >"$tmp/$base.log" 2>&1
      echo $? >"$tmp/$base.rc"
    ) &
    i=$((i + 1))
    [ $((i % jobs)) -eq 0 ] && wait
  done
  wait

  local passed=0 known=0 fresh=0
  local fresh_list=""
  for suite in "${suites[@]}"; do
    base=${suite##*/}
    base=${base%.lua}
    local rc
    if [ -f "$tmp/$base.rc" ]; then
      rc=$(cat "$tmp/$base.rc" 2>/dev/null || echo "?")
    else
      rc="NO-EXIT-CODE"
    fi
    if [ "$rc" = "0" ]; then
      passed=$((passed + 1))
      continue
    fi
    if printf '%s\n' "$KNOWN_GAME3_FAILURES" | grep -qx "$base"; then
      known=$((known + 1))
      echo "   known-fail $suite (exit $rc)"
    else
      fresh=$((fresh + 1))
      fresh_list="$fresh_list $suite"
      echo "   FAIL $suite (exit $rc)"
      # Name the cause on the spot: assertion vs crash vs dead worker, so a
      # parallel-only anomaly is classifiable from the tier output alone.
      if [ ! -s "$tmp/$base.log" ]; then
        echo "       | EMPTY OUTPUT: the worker never printed anything" \
          "(exit $rc; 137/143 = killed, NO-EXIT-CODE = worker never ran) --" \
          "environment/parallelism problem, NOT a suite assertion"
      else
        local cause
        cause=$(grep -m1 '^\[FAIL\]' "$tmp/$base.log" || true)
        if [ -n "$cause" ]; then
          echo "       | assert: $cause"
        else
          cause=$(grep -m1 -E 'stack traceback|\.lua:[0-9]+:|Too many open files|not enough memory' \
            "$tmp/$base.log" || true)
          echo "       | crash: ${cause:-non-zero exit with no recognized cause (see log tail)}"
        fi
        tail -6 "$tmp/$base.log" | sed 's/^/       | /'
      fi
    fi
  done

  echo "-- T6 game3: $total run, $passed passed, $known known failure(s), $fresh new failure(s)"
  if [ "$fresh" -gt 0 ]; then
    echo "   new failures (not in the sweep-v113 baseline):$fresh_list"
  fi

  local ok=1
  [ "$fresh" -eq 0 ] && ok=0
  if [ "$fresh" -gt 0 ]; then
    echo "   per-suite logs kept for triage: $tmp"
  else
    rm -rf "$tmp"
  fi
  return $ok
}
run_tier "T6 game3 top-level scenario suites" run_game3_tier

run_tier "T4 title checkpoint cold restart" \
  bash tests/integration/title_checkpoint_cold_start.sh

# The modded-link desync suite (symmetric mod, handshake fail-closed,
# extra-bag round trip) is ROM-free and runs inside the T4 tier above, as
# tests/modkit/cases/link_desync.lua.
#
# tests/run_link_tests.lua is a different matter: it calls Data:load() at
# :27 and so needs data/generated/.  It is grouped with the content tier
# until that bootstrap can take an injected dataset.
# ------- content tier: only meaningful with an imported ROM


# tests/run_tests.lua is expected to be clean.  It used to carry two stale
# chip-audio assertions on the allowlist below (Pikachu cry WAV exists /
# low-health alarm sfx extracted); both have since been fixed, so the
# baseline is zero and any failure fails the tier.  Keep the allowlist
# mechanism rather than ignoring the exit code -- that would hide every
# future content regression.
KNOWN_CONTENT_FAILURES=0
KNOWN_CONTENT_LINES=""

run_content_behavior() {
  local out
  out=$("$LUA" tests/run_tests.lua 2>&1)
  local count
  count=$(printf '%s\n' "$out" | grep -c '^FAIL ' || true)
  local lines
  lines=$(printf '%s\n' "$out" | grep '^FAIL ' | sort)

  if [ "$count" -eq "$KNOWN_CONTENT_FAILURES" ] \
     && [ "$lines" = "$(printf '%s\n' "$KNOWN_CONTENT_LINES" | sort)" ]; then
    printf '%s\n' "$out" | tail -3
    if [ "$KNOWN_CONTENT_FAILURES" -gt 0 ]; then
      echo "(the $KNOWN_CONTENT_FAILURES known stale assertions, unchanged)"
    fi
    return 0
  fi

  printf '%s\n' "$out" | grep '^FAIL ' || true
  printf '%s\n' "$out" | tail -2
  echo "expected exactly $KNOWN_CONTENT_FAILURES known failures; got $count"
  return 1
}

# The Red dataset is the source tree's when tools/build_data.py wrote one, and
# otherwise the imported Red cache, through Data:load's POKEPORT_DATA_DIR hook.
HAVE_RED_DATA=0
if [ -f data/generated/maps.lua ]; then
  HAVE_RED_DATA=1
elif [ -n "${RED_CACHE:-}" ] && [ -f "$RED_CACHE/data/generated/maps.lua" ]; then
  HAVE_RED_DATA=1
  export POKEPORT_DATA_DIR="$RED_CACHE/data/generated"
  echo ""
  echo "-- T3 content: reading Red from $POKEPORT_DATA_DIR"
fi

if [ "$HAVE_RED_DATA" = "1" ]; then
  if [ "$QUICK" = "1" ]; then
    echo ""
    echo "-- T3 content: skipped (--quick)"
  else
    run_tier "T3 content behavior (Red)" run_content_behavior
    # The save editor ships inside every build (the launcher's Edit button on
    # a save row opens it), so its panel suites run in CI rather than by hand.
    run_tier "T3 save editor" "$LUA" tests/run_save_editor_tests.lua
    run_tier "T3 save editor: boxes + items" "$LUA" tests/save_editor_task6_tests.lua
    run_tier "T3 save editor: events + dex" "$LUA" tests/save_editor_task7_tests.lua
    run_tier "T3 save editor: map browser" "$LUA" tests/save_editor_task8_tests.lua
    run_tier "T3 save editor: mod awareness" "$LUA" tests/save_editor_mod_tests.lua
    run_tier "T3 save editor: gold / gen2" "$LUA" tests/save_editor_gen2_tests.lua
    run_tier "T3 save editor: wheel scrolling" "$LUA" tests/save_editor_wheel_bug595_test.lua
    run_tier "T3 save editor: pad / NX input" "$LUA" tests/save_editor_pad_input_test.lua
    run_tier "T5 link (loopback lockstep)" "$LUA" tests/run_link_tests.lua
    # The oversize-save vendor oracle (tests/save_oversize_vendor_test.lua)
    # cross-checks the launcher's footer-truncation import against the
    # INDEPENDENT PKHeX-derived gen1lib codec, which cannot run under luajit
    # (native 5.3+ operators).  Needs a stock Lua 5.3/5.4; skip when absent.
    if command -v "$LUA54" >/dev/null 2>&1; then
      run_tier "T3 save oversize vendor oracle" "$LUA54" tests/save_oversize_vendor_test.lua
    else
      echo ""
      echo "-- T3 save oversize vendor oracle: skipped (no '$LUA54' on PATH; set LUA54=...)"
    fi
  fi
else
  echo ""
  echo "-- T3 content + run_link_tests: skipped (no data/generated/ and no"
  echo "   RED_CACHE -- import a ROM to run them; the modded-link cases ran"
  echo "   in T4 and the Gen 2 suites in T2)"
fi

# ------- golden screenshots: needs love + a display

if [ "$SHOTS" = "1" ]; then
  SHOT_DIR=${SHOT_DIR:-/tmp/pokeport-shots}
  export SHOT_DIR
  mkdir -p "$SHOT_DIR"
  SHOT_DRIVER=tests/drivers/shots_fixture.lua

  # The fixture goldens are not capturable yet.  A driver only ever runs
  # after main.lua's bootGame(), so it cannot redirect Data:load(), and
  # src/core/Data.lua has no POKEPORT_DATA_DIR branch -- 21-testing-and-ci
  # §"Engine changes" specifies one, but it is not implemented, so a LOVE
  # process has no way to boot tests/fixture_data.  On a ROM-less checkout
  # main.lua does not even reach the game: RomImporter.isReady() is false
  # and it opens the importer instead.
  #
  # WITH_SHOTS is opt-in, so asking for a tier that cannot run is an error,
  # not a skip.  Reporting "pass" here is what made the whole pipeline look
  # delivered while never diffing a single pixel.
  if [ ! -f "$SHOT_DRIVER" ]; then
    echo ""
    echo "-- T5 shots: NOT WIRED ($SHOT_DRIVER does not exist)."
    echo "   Fixture capture needs the POKEPORT_DATA_DIR override in"
    echo "   src/core/Data.lua so LOVE can boot tests/fixture_data."
    FAILED+=("T5 shots (requested but not wired)")
  elif ! command -v love >/dev/null 2>&1; then
    echo ""
    echo "-- T5 shots: love is not on PATH but WITH_SHOTS was requested"
    FAILED+=("T5 shots (love missing)")
  else
    RUNNER="love ."
    command -v xvfb-run >/dev/null 2>&1 && RUNNER="xvfb-run -a love ."
    run_tier "T5 shot capture" \
      env POKEPORT_IDENTITY="$SANDBOX_IDENTITY" POKEPORT_DRIVER="$SHOT_DRIVER" $RUNNER
    if [ "$BLESS" = "1" ]; then
      run_tier "T5 shot bless" \
        python3 tools/compare_shots.py tests/goldens/shots "$SHOT_DIR" --bless
    else
      run_tier "T5 shot diff" \
        python3 tools/compare_shots.py tests/goldens/shots "$SHOT_DIR"
    fi
  fi
fi

# ------- fingerprint blessing

if [ "$BLESS" = "1" ] && [ "$SHOTS" != "1" ]; then
  echo ""
  echo "re-pinning fingerprint goldens (deliberate parity change -- record it"
  echo "in docs/known-differences.md or docs/new-features.md)"
  "$LUA" tests/bless_fingerprints.lua || FAILED+=("fingerprint bless")
fi

# ------- verdict

echo ""
echo "=============================================================="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "  ALL TIERS PASSED"
  echo "=============================================================="
  exit 0
fi

echo "  ${#FAILED[@]} TIER(S) FAILED"
for tier in "${FAILED[@]}"; do echo "    - $tier"; done
echo "=============================================================="
exit 1
