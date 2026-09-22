# Game3 test baseline v3 (pre-fix-wave)

Captured: 2026-09-22 10:17 IST by QA and Test Engineer (team G1R_Deluxe_Gen3).
Checkout: `/Users/shanemcgovern/dev/gen1recomp` (read-only run; no `src/` edits).
Revision: **no `.git` directory in this checkout**, so no SHA/`git describe` is
available. Everything below is pinned by command + output, not by revision.

This is the reference the Gen 3 fix wave is measured against. Re-run the same
commands after the wave and diff the tier table and failure list.

## 1. Environment snapshot

| Item | State |
| --- | --- |
| `.git` | **absent** (missing → 1 expected privacy-gate failure, see §4) |
| `data/generated/` (Red dataset) | absent |
| `$RED_CACHE` / other per-version caches | unset; `~/Library/Application Support/LOVE/pokeport-test-caches` does not exist |
| `tests/fixture_data/` | present (`maps.lua` + fixture data) |
| `luajit` | `/opt/homebrew/bin/luajit` |
| `luacheck` | present (T0 lint gate ran, not skipped) |
| `lua5.4` | **not on PATH** (oversize-save vendor oracle cannot run) |
| `love` | not exercised (shots tier not requested) |

## 2. Exact commands

Full gate (background, full output captured):

```sh
cd /Users/shanemcgovern/dev/gen1recomp
./scripts/test.sh > /private/var/folders/ff/4j_0xvl94ls07d2zzzr0b0r00000gn/T/opencode/g1r_test_baseline.log 2>&1
echo "EXIT=$?"     # EXIT=1
```

Game3 spot runs (per-suite path; run with and without `POKEPORT_DATA_DIR`,
results were identical):

```sh
cd /Users/shanemcgovern/dev/gen1recomp
for s in bag encounters_lookup battle_move_effects stitchcoll_dynamic_warp national_dex; do
  POKEPORT_DATA_DIR="$PWD/tests/fixture_data" luajit "tests/game3_${s}_test.lua"
done
```

## 3. Per-tier results — `./scripts/test.sh` (EXIT=1)

| Tier | Result |
| --- | --- |
| T0 luacheck gate (undefined globals, unreachable code) | PASS — 0 warnings / 0 errors in 978 files |
| T0 ROM builder version routing | PASS |
| T0 ROM manifest generator pin/overrides | PASS |
| T0 Yellow title OBP eye remap | PASS |
| T0 Crystal manifest + specials coverage | PASS |
| T0 switch CI workflow content gate | PASS |
| T0 switch transfer docs gate | PASS |
| T0 ShaderFX bridge packaging gate | PASS |
| T0 NX asset overlay fallback | PASS |
| T0 NX generated-path static guard | PASS |
| T0 NX Yellow/Blue boot (dynamic paths) | PASS |
| T0 NX Gold cache load (maps.lua prefix) | PASS |
| T0 touch-controls pad cursor | PASS |
| T0 URI launch arguments | PASS |
| T1/T2 engine invariants + parity gates (`tests/run_engine.lua`) | **FAIL** — 1 suite, see §4 |
| T2 Gen 2 / Crystal suites (`tests/run_gen2.lua`) | PASS — 146 suite lines ok, 0 FAIL |
| T4 mod-SDK (`tests/run_modkit.lua`) | PASS — 37 suite lines ok, 0 FAIL |
| T4 title checkpoint cold restart (integration shell) | PASS |
| T3 content behavior (Red) | **skipped at capture** — no `data/generated/`, no `RED_CACHE` (superseded: now **PASS**, see Update below) |
| T3 save editor × 8 + T5 link loopback | **skipped at capture** (same T3 gate; superseded: now **PASS**) |
| T3 save oversize vendor oracle | **skipped** — no `lua5.4` (only reachable inside T3 anyway; still skipped) |
| T5 golden shots | not requested (`WITH_SHOTS` unset) |

T1/T2 detail: `tests/run_engine.lua` globs `tests/engine/*.lua` (616 files,
24 of them `game3_*`). 622 `ok` lines, exactly one failing suite.

## 4. Full failure list

1. `tests/engine/mew_dock_private_artifact_gate.lua` — **expected environment
   artifact, not a code bug.** Check `privacy gate inspects a real Git
   publication set instead of passing vacuously` fails (`2/3 checks passed,
   1 FAILURES`). The gate wants a real `.git` publication set and this
   checkout has none. Steward is fixing git; it should flip to PASS with a
   real clone and must not be "fixed" in `src/`.
2. `tests/game3_battle_move_effects_test.lua` — **genuine game3 suite failure**
   (not part of `./scripts/test.sh`; direct `luajit` run only).
   `125 passed, 1 failed`:
   - `[FAIL] Knock Off removes the item for the battle only`
   - Probe of the same setup: `st4.enemy.item == 0` (correct, battle-only
     removal) but `st4.foeParty[1].item == nil`, expected `200`. Knock Off
     (move 282, effect 188) clears the held item from the **party entry**
     instead of only suppressing it for the battle. The companion check
     `ITEM_KNOCKOFF anim + message` passes.

No other failing suite/check in any tier that ran.

## 5. Game3 spot-run results (direct `luajit`, 5 suites)

| Suite | Plain | With `POKEPORT_DATA_DIR=tests/fixture_data` | Result |
| --- | --- | --- | --- |
| `tests/game3_bag_test.lua` | EXIT=0 | EXIT=0 | PASS — `All bag tests passed.` |
| `tests/game3_encounters_lookup_test.lua` | EXIT=0 | EXIT=0 | PASS — `ALL TESTS PASSED` |
| `tests/game3_battle_move_effects_test.lua` | EXIT=1 | EXIT=1 | **FAIL** — 125 passed, 1 failed (§4.2) |
| `tests/game3_stitchcoll_dynamic_warp_test.lua` | EXIT=0 | EXIT=0 | PASS — `[test] all passed` |
| `tests/game3_national_dex_test.lua` | EXIT=0 | EXIT=0 | PASS — `=== ALL NATIONAL DEX GATING TESTS PASSED! ===` |

`POKEPORT_DATA_DIR` had no effect on these five: none of the 273 top-level
`tests/game3_*.lua` suites reference `Data:load`, `POKEPORT_DATA_DIR` or
`tests/fixture_data` (checked by grep), so the variable is inert for them.
It only matters for suites that call `Data:load()` (e.g. `tests/run_tests.lua`,
`tests/run_link_tests.lua`), which need `data/generated/` or an imported
`RED_CACHE` and are skipped in this checkout.

## 6. Coverage caveats for the fix wave

1. **`./scripts/test.sh` does not run the 273 top-level `tests/game3_*.lua`
   suites.** Its only game3 coverage is the 24 `tests/engine/game3_*.lua`
   suites inside the T1/T2 glob. A fix-wave "green gate" therefore says
   nothing about the other 249 game3 suites; they must be run per-suite
   (as in §2) or via a new runner.
2. ROM-dependent suites self-skip in this checkout: `*_rom_test.lua` /
   `*_cache*` suites either print `SKIP` without an explicit ROM/cache
   argument or are not reached by the gate. Green here ≠ ROM-path coverage.
3. `love`/visual behavior is not exercised headlessly (no shots tier); draw
   regressions must be confirmed in-game.
4. The full gate log referenced in §2 lives in the session temp dir; if it
   is gone, re-run §2 exactly and compare to the tables above.

## 7. Baseline verdict

Baseline is **red in exactly two known places**: one expected `.git`
environment artifact and one genuine game3 bug (`game3_battle_move_effects`
Knock Off party-item persistence). Everything else that this ROM-less
checkout can run is green. The fix wave target is: both become PASS while
§3/§5 stay unchanged.

## Update 2026-09-22 — T3 activated: last content tier closed

The T3 gate conditions that made this document's capture read "skipped" are now
satisfied **without any repo-side data cache** (see `game3-artifact-conversions-v3.md`
§8 for the reproducible recipe):

1. **RED_CACHE (data half):** an imported Red cache at
   `~/Library/Application Support/LOVE/qa-red-data/red` (headless import of
   `Pokemon - Red Version (USA, Europe).gb`, SHA-1 `ea9bcae6…`), supplied as
   `RED_CACHE=… ./scripts/test.sh`. The `rom-cache.complete` marker makes
   test.sh export `POKEPORT_DATA_DIR`, so all content checks run against the
   real 222-map Red dataset. App-data only; `data/generated/` stays absent.
2. **assets/generated symlink bridge (file half):** the three T3 checks that
   `io.open` cwd-relative asset paths now resolve through a gitignored real
   directory whose *entries* are symlinks into the import:

   ```sh
   SRC="$HOME/Library/Application Support/LOVE/qa-red-data/red/assets/generated"
   mkdir -p assets/generated
   ln -sfn "$SRC/title"   assets/generated/title
   ln -sfn "$SRC/emotes.png" assets/generated/emotes.png
   ln -sfn "$SRC/slots"   assets/generated/slots
   ```

   `.gitignore:7-8` (`data/generated/`, `assets/generated/`) make this a
   zero-footprint addition: `git status --short` count was unchanged before
   and after, with no `assets/` entry.

**Result — full gate run twice, both green:**

| Run | Command | Exit | Verdict |
| --- | --- | --- | --- |
| 1 | `RED_CACHE=… ./scripts/test.sh` | **0** | ALL TIERS PASSED |
| 2 | `RED_CACHE=… ./scripts/test.sh` | **0** | ALL TIERS PASSED |

- **T3 content behavior (Red): PASS** (was skipped at capture); T3 save editor
  ×8: PASS; T5 link (loopback): PASS.
- **T6 game3 tier: 281 run, 281 passed, 0 known failures, 0 new failures —
  both runs.** The 22-name `KNOWN_GAME3_FAILURES` list no longer fires at all
  (0 `known-fail` lines), and the known flake class did not trip in either run.
- Only remaining gaps: **T3 save oversize vendor oracle** (needs `lua5.4` on
  PATH) and **T5 golden shots** (opt-in via `WITH_SHOTS=1`).

**Reproducibility after reboot/reclone:** both halves are machine-local and
untracked (the `qa-red-data` import identity and the `assets/generated`
symlinks), so a fresh clone must rebuild them — re-run the Red import command
and the three `ln -sfn` lines above; both are recorded step-by-step in
`docs/game3/game3-artifact-conversions-v3.md` §8.
