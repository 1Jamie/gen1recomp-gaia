# Game3 external-artifact conversions (anim/audio, ROM-path, pret, named caches)

Follow-up to `game3-suite-sweep-v113.md`. Captured: 2026-09-22 10:32 IST.
**Read-only task: no `src/` or `tests/` edits.** Every conversion below was
achieved with environment variables, argv, a temporary symlink, or a temporary
cache marker — all removed again afterwards.

Second-level context: while this work ran, other teammates landed src fixes
(the `objects.lua` lazy-`Collision` fix among them). A default re-sweep at the
end therefore moved far beyond artifact conversion — see §5. This document
separates **what my conversion runs prove** from **what the default re-sweep
now shows**.

## 1. Exact configuration per category

```sh
C="$HOME/Library/Application Support/LOVE/qa-firered-v113/firered/data/generated/gba"
ID="$HOME/Library/Application Support/LOVE/qa-firered-v113"
ROM="/Users/shanemcgovern/Downloads/1636 - Pokemon Fire Red (U)(Squirrels).gba"
P=/Users/shanemcgovern/dev/pokefirered
```

| Category | Suite | Mechanism used |
| --- | --- | --- |
| anim | `anim_port_g1`, `anim_port_g2` | `POKEPORT_ANIM_PACK=$C/pokemon/battle_anims/pack.lua` |
| anim | `anim_port_g4` | `G4_ANIM_PACK=$C/pokemon/battle_anims/pack.lua` |
| anim | `battle_anim_palette` | `FIRERED_ROM=$ROM POKEFIRERED=$P` |
| audio | `se_length` | `POKEPORT_IDENTITY=qa-firered-v113` |
| ROM | `help_rom`, `object_interactions_rom`, `quest_log_rom` | ROM path as `arg[1]` |
| ROM | `map_preview_extract`, `tm_case_berry_pouch_extract`, `town_map` | run from a temp cwd containing a symlink named `1636 - Pokemon Fire Red (U)(Squirrels).gba` (their hardcoded relative path), with `LUA_PATH` pointing at the repo |
| ROM | `object_interactions_cache` | cache root as `arg[1]` (`$ID/firered`) |
| pret | all 12 | none — clone now exists at `$P` (`../pokefirered`, git `c75f35230`) |
| named | `battle_music`, `void_fill` | temporary symlink `~/Library/Application Support/LOVE/firered-sep20` → `$ID` (removed after) |
| named | `region_map_assets` | temporary `$C/region_map/extract_status.json` marker (removed after) |

All runs performed **twice** (with `POKEPORT_DATA_DIR=tests/fixture_data`);
every result below reproduced identically. No flakes.

## 2. Per-category before → after

### Anim/audio (5) — all converted

| Suite | Before (v113 sweep) | After |
| --- | --- | --- |
| `game3_anim_port_g1_test.lua` | PARTIAL | **PASS** — 5326 passed, 0 failed (1296 script runs) |
| `game3_anim_port_g2_test.lua` | PARTIAL | **PASS** — 2032 passed, 0 failed (448 script runs) |
| `game3_anim_port_g4_test.lua` | PARTIAL | **PASS** — 318 passed, 0 failed |
| `game3_battle_anim_palette_test.lua` | PARTIAL | **PASS** — 159 passed, 0 failed |
| `game3_se_length_test.lua` | SKIP | **PASS** — all SE length checks passed |

The packs were already inside the v113 cache the import created
(`pokemon/battle_anims/pack.lua`, `audio/index.lua`); no export step is
missing. The suites only look at hardcoded legacy identities
(`firered-sep18fx`, `firered-sep20`) or their env vars — so these conversions
are **per-run configuration**, not sticky.

### ROM-path (5) — 4 PASS, 1 FAIL

| Suite | Before | After |
| --- | --- | --- |
| `game3_help_rom_test.lua` | SKIP | **PASS** — 177 articles, 36 contexts verified |
| `game3_object_interactions_rom_test.lua` | SKIP | **PASS** — 28 scripts + Wall Town Map |
| `game3_map_preview_extract_test.lua` | PARTIAL | **PASS** — ALL LOCATION PREVIEW TESTS PASSED |
| `game3_tm_case_berry_pouch_extract_test.lua` | PARTIAL | **PASS** — ALL EXTRACTION TESTS PASSED |
| `game3_town_map_test.lua` | PARTIAL | **FAIL** — 1 check, see §3.1 |

These suites deliberately gate on a licensed ROM being supplied (argv or a
ROM present at the path they hardcode); they are not meant to run ROM-less.
The temp cwd/symlink approach left the repo untouched.

### pret (12) — 6 full PASS, 6 still PARTIAL on build artifacts

The steward's clone at `/Users/shanemcgovern/dev/pokefirered`
(git `c75f35230`) is a real checkout with `src/`, `data/`, `graphics/`.

Fully converted (were 4×PARTIAL + 2×SKIP):
`battle_anims_pret_parity` (27 checks), `corner_prize`, `corner_screen`,
`corner_slots`, `import2_mt_ember_collision`, `special_ids`.

Still PARTIAL, but only because a **built ROM** is missing from the pret
checkout — all 6 exit 0 and ran their non-ROM checks twice:

| Suite | Remaining skip |
| --- | --- |
| `revision_view` | `no pret builds under ../pokefirered` (needs `pokefirered.gba` + `pokefirered_rev1.gba`) |
| `stitchimp_alt_layouts` | `../pokefirered/pokefirered.gba not present` |
| `stitchimp_braille_text` | `cart byte check: no ../pokefirered/pokefirered.gba` |
| `stitchimp_chrome_keys` | `sources or ROM not present` |
| `stitchimp_condominiums` | `../pokefirered/pokefirered.gba not present` |
| `stitchimp_heal_locations` | `sources or ROM not present` |

These need `make` in the pret clone (build toolchain), not a config knob. This
is the one pret artifact the team must provide if full ROM-vs-source diffing
is wanted.

### Named caches / other (5)

| Suite | Before | After |
| --- | --- | --- |
| `game3_quest_log_rom_test.lua` | SKIP | **PASS** — strings, placeholders, offsets, cache |
| `game3_battle_music_test.lua` | PARTIAL | **PASS** — all battle music checks (via temp `firered-sep20` link) |
| `game3_void_fill_test.lua` | PARTIAL | **PASS** — canonical mids verified |
| `game3_region_map_assets_test.lua` | PARTIAL | **PASS with temp marker**; skipped by default, see §3.3 |
| `game3_object_interactions_cache_test.lua` | SKIP | **FAIL** — see §3.2 |

## 3. New findings for the fix wave (reported, not fixed)

All three are backed by the pret checkout at `c75f35230` (evidence tier c) plus
engine-internal lines (tier b) and observed runs (tier a).

### 3.1 `town_map` expectation is off by one asset

- Observed: `RegionMapExtract.run` returns `detail.count = 10`; the suite
  asserts `detail.count == 9` (`tests/game3_town_map_test.lua:222`).
- The 10 counted assets: kanto/sevii123/sevii45/sevii67 maps, cursor,
  dungeon_icon, dungeon_icon_visited, fly_icon, player_red, player_leaf.
- pret ground truth supports all 10: `pokefirered/src/region_map.c:395-396,
  405-406` INCBINs `player_icon_red` / `player_icon_leaf`;
  `region_map.c:425` INCBINs `fly_icon`; `region_map.c:424` `dungeon_icon`
  (files also present in `pokefirered/graphics/region_map/`).
- Verdict: stale test expectation (or an intentional extractor addition) —
  owner should decide 9 → 10; **not** a confirmed src bug.

### 3.2 `object_interactions_cache`: screen-only special never releases the VM

- Observed: with a real cache root, the suite fails at
  `tests/game3_object_interactions_cache_test.lua:80`:
  `furniture did not release control CableClub_EventScript_ShowBattleRecords`.
- pret script (`pokefirered/data/scripts/cable_club.inc:566-575`):
  `lockall / fadescreen / setvar / special ShowBattleRecords / waitstate /
  releaseall / end`; special registered at `pokefirered/data/specials.inc:207`,
  implemented at `pokefirered/src/battle_records.c:83`.
- Engine handler: `src/core/game3/scripting/natives_tower.lua:567-579`. When
  the screen module is unavailable (`recordsScreen()` nil) it runs
  `takeScreenForPartyMenu()()` and `return false` without completing the
  `waitstate`, so the VM stays running — exactly what the headless test hits.
- Verdict: src bug candidate in the no-screen fallback path (tier b/pret-cited).

### 3.3 `region_map/extract_status.json` is not written by the import path used

- Observed: the fresh v113 cache contains `intro/`, `audio/`, `naming/`
  `extract_status.json` but **not** `pokemon/` or `region_map/` ones.
  `tests/game3_cache.lua` gates on `region_map/extract_status.json`, so
  `game3_region_map_assets_test.lua` skips by default with
  `2 imported FireRed cache(s) found, none at cache v113`.
- With a temporary marker the suite **passes all checks twice**.
- Engine-internal: `src/import/RomExtractorGen3.lua:626,637,648` writes those
  markers only in the `-- Fallback sequential execution path`; the import run
  in this session used a path that wrote only the three per-feature markers.
- Verdict: import-path gap (tier b); fixing it converts
  `region_map_assets` to real coverage.

### 3.4 Import byte-determinism: clause upgraded **UNREACHABLE → MET** (ticket `01a0c8f7`, fixed)

- Root cause: three writers emitted JSON object keys in Lua `pairs()` order,
  which varies per process on this LuaJIT build — content identical, key order
  different run to run (920 of 7269 files: 917 `map_tree/*.json` + `census.json`
  + `meta.json`/`maps.json` + `connections.lua`; all `.bin` blobs including
  `grid.bin` were already stable). Not the quantizer/RNG/timestamps.
- Fix (2026-09-22, all in `src/import/`): new `src/import/canonical_json.lua`
  (sorted-key encoder delegating scalar formatting to `src/link/Json.lua`)
  wired into `map_tree_extract.write_json` and `RomExtractorGen3.writeJson`;
  `extract_island1`'s inline `write_json` sorts object keys; both
  `connections.lua` builders sort the direction keys.
- Proof: two fresh imports of the same ROM (scratch identity
  `finisher-determinism`, cache wiped between runs), sha256 inventory diff →
  **0 differing files — 7269/7269 byte-for-byte identical**; T6.2 gate form
  re-passed (`import_id:"firered"`, md5 `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc`,
  `region_map/extract_status.json` present).
- Verdict: the literal byte-identical import clause (T6.2 gate form,
  `rse-seams.md` wave log) now holds — status **MET**, replacing the earlier
  UNREACHABLE reading.

## 4. Config summary: sticky vs per-run

- **Sticky now:** pret 12 improve without any env var, because the clone is on
  disk (`../pokefirered`).
- **Still needed per run:** `POKEPORT_ANIM_PACK`, `G4_ANIM_PACK`,
  `FIRERED_ROM`/`POKEFIRERED`, `POKEPORT_IDENTITY=qa-firered-v113`, ROM argv
  for 3 suites, cache root argv for 1 suite, ROM at the hardcoded relative
  path for 3 suites. The suites' own self-discovery does not know about the
  v113 identity.
- **Blocked on missing artifacts:** built `pokefirered.gba` /
  `pokefirered_rev1.gba` (6 suites); `region_map/extract_status.json` written
  by the importer (1 suite).

## 5. Default re-sweep after everything (all 273 files, no env/args)

Run with the same harness as `game3-suite-sweep-v3.md`:

| Verdict | v113 sweep (before this task) | Default re-sweep (after) |
| --- | --- | --- |
| PASS | 220 | **248** |
| PARTIAL | 20 | **16** |
| SKIP | 7 | **5** |
| FAIL | 25 | **3** |
| n/a (helper) | 1 | 1 |

**Attribution:** most of the FAIL drop is *not* from this task — other
teammates landed src fixes while it ran (e.g. `src/core/game3/objects.lua`
changed at 10:28, cluster A is gone; `battle_ai`, `special_events` also pass
now). This task's contribution is the pret-clone-driven conversion
(4 PARTIAL + 2 SKIP → PASS, sticky) and the measurements above.

Remaining 3 FAIL in the default sweep: `game3_link_session_test.lua`,
`game3_save_trainer_card_test.lua`, `game3_special_trade_test.lua` (all
carried over; none are artifact-blocked).

Remaining 16 PARTIAL + 5 SKIP map 1:1 to the config table in §1/§4 — every one
was individually converted (and re-verified) except the 6 pret built-ROM cases
and `town_map` (which converts to the §3.1 FAIL) and `object_interactions_cache`
(which converts to the §3.2 FAIL).

## 6. Artifacts touched (all restored)

- temp symlink `LOVE/firered-sep20` — created, used, **removed** (verified gone).
- temp marker `$C/region_map/extract_status.json` — written, used, **removed**.
- temp cwd with ROM symlink under the session temp dir (outside the repo).
- No repo files created or edited; user caches untouched.

## 7. pret modern-build attempt (lead-authorized): built with a second on-disk toolchain, suites still fail on bytes

Attempted to unblock the 6 pret-ROM suites
(`revision_view`, `stitchimp_alt_layouts`, `stitchimp_braille_text`,
`stitchimp_chrome_keys`, `stitchimp_condominiums`, `stitchimp_heal_locations`).

### 7a. First attempt (Homebrew toolchain): no newlib

```sh
cd /Users/shanemcgovern/dev/pokefirered
make -j8 firered_modern      # exit 2
```

All 7 errors are one class:

```
include/gba/gba.h:4:10: fatal error: string.h: No such file or directory
```

Homebrew `arm-none-eabi-gcc 16.2.0` is built without newlib (tier b):
`-print-sysroot` empty, `-print-file-name=libc.a` returns the unresolved name
`libc.a`, no `string.h` under the formula, no newlib/devkitARM package
installed, and pret's `MODERN=1` link line needs `-lc -lgcc -lnosys`
(`Makefile:88-95`).

### 7b. Second attempt: Arm GNU Toolchain 13.3 already on disk (no install, no system change)

A complete newlib toolchain was found at
`~/dev/toolchains/arm-gnu-toolchain-13.3.rel1-darwin-arm64-arm-none-eabi`
(Arm GNU Toolchain 13.3.Rel1; `libc.a`, `libnosys.a`, `libgcc.a`, `string.h`
all resolve). Using it via `PATH` only:

```sh
export PATH="$HOME/dev/toolchains/arm-gnu-toolchain-13.3.rel1-darwin-arm64-arm-none-eabi/bin:$PATH"
cd ~/dev/pokefirered && rm -rf build/firered_modern
make -j8 firered_modern        # exit 0 -> pokefirered_modern.gba (16 MiB, 0 errors)
make -j8 firered_rev1_modern   # exit 0 -> pokefirered_rev1_modern.gba (16 MiB)
```

**Build: SUCCESS** (both ROMs, `gbafix` ran, `BPRE` rev 0 and rev 1).

Symlinks created exactly as authorized (then removed, see 7c):

```
pokefirered.gba      -> pokefirered_modern.gba
pokefirered_rev1.gba -> pokefirered_rev1_modern.gba
```

### 7c. Suite results (each run twice, identical both passes) and decision

| Suite | Exit | Result |
| --- | --- | --- |
| `revision_view` | 1 | FAIL — 1 failed (reads both ROMs) |
| `stitchimp_alt_layouts` | 1 | FAIL — 5 checks (`build seeded four alt layouts (0 == 4)`, alt_264/278/279/319 not built) |
| `stitchimp_braille_text` | 1 | FAIL — 1 check (`ROM 0x1A92C5 decodes to pret's literal, got "?????? ?????"`) |
| `stitchimp_chrome_keys` | 0 | PASS but still 1 `[skip]` (its source/ROM branch) |
| `stitchimp_condominiums` | 1 | FAIL — 6 checks (condominium + hideout B2F maps not registered) |
| `stitchimp_heal_locations` | 1 | FAIL — crash `src/import/gba/heal_locations_extract.lua:133: attempt to index local 'plan' (a nil)` + 7 FAIL lines |

**Bytes-vs-semantic finding:** every failure is a *data-address/layout*
mismatch — the suites read fixed cart offsets or require maps/alt-layouts at
the retail build's addresses, while `MODERN=1` compiles with gcc 13 and its own
link script (`ld_script_modern.ld`), so addresses shift. Nothing indicates the
engine code under test is wrong; the ROM is simply not the retail-layout
artifact these checks are written against.

**Decision applied:** suites FAIL from byte/layout mismatch → **symlinks
removed** (verified: only `pokefirered_modern.gba` /
`pokefirered_rev1_modern.gba` remain; the 6 suites are back to their PARTIAL
state with no regression-looking FAIL rows in sweeps).

### 7d. Requirement that remains (tier b)

For unsuffixed retail-layout `pokefirered.gba` / `pokefirered_rev1.gba` the
user must install **devkitARM** (devkitPro pacman installer) and build
**agbcc** per pret INSTALL.md
(`git clone https://github.com/pret/agbcc && cd agbcc && ./build.sh &&
./install.sh ../pokefirered`), then `make firered` and `make firered_rev1`.
The modern-toolchain ROMs stay available as untracked build artifacts but do
not satisfy these 6 suites' byte-level checks.

State left behind: pret clone tracked tree clean (HEAD `c75f35230`); untracked
`build/`, `pokefirered_modern.gba`, `pokefirered_rev1_modern.gba` (+ `.elf`,
`.map`, `.sym`); symlinks removed; nothing committed, pushed, or published.

### 7e. User-ordered retail build (devkitARM task `01a0c8d9`) — ALL 6 SUITES CONVERTED

**Installs**
- **devkitARM/devkitPro pacman: BLOCKED at sudo.** No brew cask exists
  (`brew info --cask devkitpro-pacman` → unavailable), the official installer
  needs root (`sudo -n installer` → `sudo: a password is required`), and
  `/opt/devkitpro` does not exist. Latest release: **devkitPro pacman v6.0.2**,
  `https://github.com/devkitPro/pacman/releases/download/v6.0.2/devkitpro-pacman-installer.pkg`.
  Per pret INSTALL.md macOS the remaining user-run steps are:
  `sudo installer -pkg devkitpro-pacman-installer.pkg /`, then
  `sudo dkp-pacman -Sy && sudo dkp-pacman -S gba-dev && sudo dkp-pacman -S devkitarm-rules`,
  then export `DEVKITPRO=/opt/devkitpro` + `DEVKITARM=$DEVKITPRO/devkitARM`.
- **agbcc: INSTALLED.** `git clone https://github.com/pret/agbcc ~/dev/agbcc`
  (HEAD `da598c1`), `./build.sh` exit 0, `./install.sh ../pokefirered` exit 0 →
  `~/dev/pokefirered/tools/agbcc/bin/{agbcc, agbcc_arm, old_agbcc}`.

**Retail-layout builds (MODERN=0)**

```sh
cd ~/dev/pokefirered && rm -rf build/firered
make firered        # exit 0, 0 errors
make firered_rev1   # exit 0, 0 errors
```

| ROM | Size | SHA-1 | Retail target | Verdict |
| --- | --- | --- | --- | --- |
| `pokefirered.gba` | 16,777,216 B | `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc` | FireRed v1.0 | **byte-identical (matching build)** |
| `pokefirered_rev1.gba` | 16,777,216 B | `dd5945db9b930750cb39d00c84da8571feebf417` | FireRed v1.1 | **byte-identical (matching build)** |

Toolchain used (tier b): `CC1 = tools/agbcc/bin/agbcc` (MODERN=0 path,
Makefile:81-84) plus the system `arm-none-eabi-*` binutils on PATH
(Makefile:12-20 documents this fallback), so the retail ROMs were produced
**without** devkitARM present — the devkitARM install is still outstanding for
the user's standing order but is not required for these builds.

**6 previously-blocked suites, run twice each, no symlinks, plain
`luajit tests/game3_<x>_test.lua` from the engine root (read-only on the
engine side):**

| Suite | Before | Run 1 | Run 2 | Skips now |
| --- | --- | --- | --- | --- |
| `revision_view` | PARTIAL (needs both ROMs) | EXIT 0 `all passed` | EXIT 0 `all passed` | 0 |
| `stitchimp_alt_layouts` | PARTIAL | EXIT 0 `[test] all passed` | EXIT 0 | 0 |
| `stitchimp_braille_text` | PARTIAL | EXIT 0 `[test] all passed` | EXIT 0 | 0 |
| `stitchimp_chrome_keys` | PARTIAL (1 residual skip) | EXIT 0 `ALL PASS` | EXIT 0 | **0** |
| `stitchimp_condominiums` | PARTIAL | EXIT 0 `[test] all passed` | EXIT 0 | 0 |
| `stitchimp_heal_locations` | PARTIAL | EXIT 0 `[test] all passed` | EXIT 0 | 0 |

**All 6 convert PARTIAL → PASS with zero failures and zero skip lines on both
runs.** Their expectations were written against exactly these retail ROMs and
all hold — no findings on either side.

**Computed new default-sweep totals** (from the last full default sweep
248/16/5/3 plus these 6 measured conversions): **PASS 254 / PARTIAL 10 /
SKIP 5 / FAIL 3** (+1 helper). Remaining PARTIAL/SKIP: the anim/audio+ROM
argv suite set (config-dependent, §2/§4), `region_map_assets` (importer
marker, §3.3), and `town_map`/`object_interactions_cache` whose conversions
need their own ROM-at-relative-path / cache-root args.

State: engine repo unchanged except this documentation append (task step 5);
no `src/` or `tests/` edits; suite runs read-only; pret clone still tracked-clean
(untracked `build/`, agbcc install dir, and the three ROMs/ELFs stay in place).

## 8. Gen1 T3 activation recipe (reproducible on a fresh machine)

The T3 content tier needs two halves; both are machine-local/untracked, so
after a reboot that keeps app data they persist, but after a **reclone** they
must be rebuilt:

**1. Import Red (data half, app-data only):**

```sh
cd /Users/shanemcgovern/dev/gen1recomp
POKEPORT_IDENTITY=qa-red-data POKEPORT_VERSION=red POKEPORT_IMPORT_ONLY=1 \
  POKEPORT_IMPORT_ROM="$HOME/Downloads/Pokemon - Red Version (USA, Europe).gb" \
  love .
# requires the supported Red v1.0 SHA-1 ea9bcae617fdf159b045185467ae58b2e4a48b9a
```

**2. Point the gate at it:**

```sh
RED_CACHE="$HOME/Library/Application Support/LOVE/qa-red-data/red" ./scripts/test.sh
```

(the import's `rom-cache.complete` marker makes test.sh export
`POKEPORT_DATA_DIR`; no repo-side `data/generated/` is created)

**3. assets/generated symlink bridge (file half, gitignored — zero status):**

```sh
SRC="$HOME/Library/Application Support/LOVE/qa-red-data/red/assets/generated"
mkdir -p assets/generated
ln -sfn "$SRC/title"      assets/generated/title
ln -sfn "$SRC/emotes.png" assets/generated/emotes.png
ln -sfn "$SRC/slots"      assets/generated/slots
```

Verifies `git status --short` is unchanged (`.gitignore:7-8` cover both the
dir content and `data/generated/`). With both halves, the full gate is
ALL TIERS PASSED (verified twice, exit 0/0 on 2026-09-22); the only remaining
gaps are the lua5.4 vendor oracle and opt-in screenshots.

Cleanup note: to remove, `rm -rf assets/generated` (only the symlinks live
there) — never touches the import.
