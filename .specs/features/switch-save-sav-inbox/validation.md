# switch-save-sav-inbox Validation

**Date**: 2026-08-03
**Spec**: `.specs/features/switch-save-sav-inbox/spec.md`
**Diff range**: `3c62814^..fe4491a` (3c62814, 5d1e7ff, 74f6b68, 4afb54c, 7e0c64c, 8120f11, 105bf65, fe4491a)
**Verifier**: independent sub-agent (author ≠ verifier)
**Re-validation after**: `fe4491a` — `test(nx): strengthen saves inbox RES-01 and edge coverage`

---

## Task Completion

| Task | Status  | Notes |
| ---- | ------- | ----- |
| T1   | ✅ Done | Saves inbox helpers + resilience suite |
| T2   | ✅ Done | `chooseSaveImport` NX branch + default hint |
| T3   | ✅ Done | NX `exportSave` MTP notice / no openURL |
| T4   | ✅ Done | switch-install/transfer/development + launcher |
| T5   | ✅ Done | AD-012 in STATE.md |
| T6   | ✅ Done | Suite wired; gate green |
| Fix  | ✅ Done | `fe4491a` — RES-01 parent assert + ROM-not-ready + workState edges |

---

## Spec-Anchored Acceptance Criteria

### P1: NX `.sav` import inbox

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| ------------------------- | -------------------- | ----------------------- | ------ |
| NXSAV-01: Import save ensures `imports/saves/` (parent `imports/` first — RES-01) and scans non-hidden `*.sav` (RES-02) | `ensureSavesInboxDir` calls `ensureImportsDir` then creates `imports/saves/`; scan skips `.*` | `tests/rom_importer_nx_saves_inbox_test.lua:104-107` — `createdDirs.imports == true` **and** `createdDirs["imports/saves"] == true`; scan `:128-129` `#savs==1` / path under `imports/saves/` | ✅ PASS |
| NXSAV-02: Empty / AppleDouble-only → MTP notice; no HostShell (RES-04/06) | `saveNotice` set with save-dir + `imports/saves/` MTP hint; 0 HostShell | `:176-178` `saveNotice.red ~= nil` + `imports/saves/`; `:185-187` AppleDouble-only; `:271` `hostShellCalls==0` | ✅ PASS |
| NXSAV-03: Valid `.sav` + ROM ready → importToSlot, refresh, success notice, retain (RES-05) | New slot path; refresh; ok notice; bytes retained; no remove | `:196-203` `#importCalls==1`, `_refreshed`, `saveNotice.ok`, `not removed[...]`, `read == "GOODSAV"` | ✅ PASS |
| NXSAV-04: Import fail → red notice; retain `.sav` (RES-05) | Error notice; file kept | `:212-218` `not saveNotice.ok`, text has `32768`, retain checks | ✅ PASS |
| NXSAV-05: Branch `isNX` only; no desktop/Android picker (RES-06/07) | `isNX=true`, `android=false`; HostShell unused; inbox rescan | `:96-97` fixture flags; `:279-283` chooseSaveImport imports from inbox, `hostShellCalls==0` | ✅ PASS |
| NXSAV-06: `._foo.sav` beside real → import real only; no false “failed” (RES-03) | One import of real file; notice ok without `failed` | `:245-250` `#importCalls==1`, source `cart.sav`, `not text:find("failed")` | ✅ PASS |
| NXSAV-07: Default SAVE FILES hint mentions `imports/saves/` MTP, not picker (RES-11) | Hint contains `imports/saves/` + MTP; not “system file picker” | `:343-348` `_savesDefaultHint()` finds | ✅ PASS |

### P1: NX export path notice

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| ------------------------- | -------------------- | ----------------------- | ------ |
| NXSAV-08: Export writes `exports/gen1recomp-<version>-<slotId>.sav` via existing SaveFileIO | Calls `exportActiveSlot(version)` (existing glue) | `:382-383` `#exportCalls==1`, `exportCalls[1]=="red"` (stub returns expected path form) | ✅ PASS (NX wiring; filename owned by existing SaveFileIO) |
| NXSAV-09: Success → exports path + MTP hint; no `openURL` / no open-folder `dir` (RES-09) | Notice mentions `exports` + MTP; `dir==nil`; openURL unused | `:384-391` | ✅ PASS |
| Export fails → failure notice (not silent) | Clear error notice | `:400-403` `not ok`, text finds `No save` | ✅ PASS |

### P1: Inbox isolation

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| ------------------------- | -------------------- | ----------------------- | ------ |
| NXSAV-10: Save scan ignores `.gb`/`.gbc`/`.zip` (RES-08) | Only `*.sav` candidates | `:128-129` one `.sav` despite gb/zip/txt | ✅ PASS |
| NXSAV-10: ROM/mod scans ignore `imports/saves/*.sav` (RES-08) | No `.sav` / no `imports/saves/` in ROM/mod lists | `:137-141`, `:150-153` | ✅ PASS |

### P1: Docs

| Criterion | Spec-defined outcome | Evidence | Result |
| --------- | -------------------- | -------- | ------ |
| NXSAV-11 / install | Document `.sav` → `imports/saves/` + Import save + pull `exports/` | `docs/switch-install.md:72-80` | ✅ PASS |
| NXSAV-11 / transfer | Destinations table lists save inbox + exports | `docs/switch-transfer.md:26-27` (+ `:130-131`, `:152`) | ✅ PASS |
| NXSAV-11 / development | Note NX save inbox beside ROM/mod | `docs/switch-development.md:47`, `:383-391` | ✅ PASS |
| NXSAV-11 / launcher | Import/Export mentions NX inbox | `docs/launcher.md:163-167`, `:189-191` | ✅ PASS |
| RES-10 MTP tip `._*.sav` | Switch MTP tips mention `._*.sav` | `docs/switch-install.md:80`; `docs/switch-transfer.md:152`; `docs/switch-development.md:88`, `:373`, `:391`; `docs/launcher.md:166-167` | ✅ PASS |

### P2: AD-012

| Criterion | Spec-defined outcome | Evidence | Result |
| --------- | -------------------- | -------- | ------ |
| NXSAV-12 | STATE.md active AD-012: inbox + Import rescan + export MTP + RES-01..11 | `.specs/STATE.md:93-99` | ✅ PASS |

### Resilience guards (explicit)

| Guard | Spec outcome | Evidence | Result |
| ----- | ------------ | -------- | ------ |
| RES-01 | `ensureImportsDir` before `imports/saves/` | `:104-107` requires `createdDirs.imports == true` **and** `createdDirs["imports/saves"]`; impl `RomImporter.lua:380-381` | ✅ PASS (prior weak OR fixed in `fe4491a`) |
| RES-02 | Skip `._*`; AppleDouble-only ≡ empty | `:185-187` | ✅ PASS |
| RES-03 | AppleDouble not counted as failure | `:245-250` | ✅ PASS |
| RES-04 | Empty NX Import always sets `saveNotice` | `:176`, `:291-292` | ✅ PASS |
| RES-05 | Retain inbox bytes success/fail | `:201-203`, `:216-218` | ✅ PASS |
| RES-06 | No HostShell/`chooseSav` on NX | `:271`, `:280` | ✅ PASS |
| RES-07 | `isNX` only (`android=false`) | `:96-97` | ✅ PASS |
| RES-08 | Inbox isolation | `:128-153` | ✅ PASS |
| RES-09 | Export MTP notice; no openURL/`dir` | `:384-391` | ✅ PASS |
| RES-10 | Docs `._*.sav` | docs cites above | ✅ PASS |
| RES-11 | Default NX hint `imports/saves/` | `:343-348` | ✅ PASS |

**Status**: ✅ All ACs covered — prior RES-01 precision gap closed by `fe4491a`

---

## Discrimination Sensor

Scratch method: backup `/tmp/RomImporter.lua.verifier.bak` → mutate `src/import/RomImporter.lua` → run suite → restore (verified `cmp` clean; post-restore gate 73/73).

| Mutation | File:line | Description | Killed? |
| -------- | --------- | ----------- | ------- |
| 1 (prior survivor) | `ensureSavesInboxDir` (~381) | Skip `ensureImportsDir` only | ✅ Killed — RES-01 parent assert (`createdDirs.imports`) |
| 2 | `listSavPaths` (~470) | AppleDouble/hidden skip off (`if true`) | ✅ Killed — RES-02/03 (4 assertions) |
| 3 | `rescanSavesAction` empty branch (~557) | Leave empty `saveNotice` nil (skip `_setNxSavesInboxNotice`) | ✅ Killed — RES-04 (`saveNotice.red` nil) |

**Sensor depth**: lightweight (3 targeted — prior survivor + 2)
**Result**: 3/3 killed — PASS ✅

---

## Interactive UAT Results

Not performed (Verifier automated gate; hardware UAT optional P2 per spec).

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ Mirrors mods inbox (`ensureModsInboxDir` / `rescanModsAction` / list*Paths) |
| Surgical changes | ✅ NX branches in `chooseSaveImport` / `exportSave`; helpers colocated with ROM/mod inbox |
| No scope creep | ✅ Desktop/Android paths unchanged; no SaveConvert changes |
| Matches patterns | ✅ `isNX` not `android` (AD-002); retain policy; MTP notice style |
| Spec-anchored outcome check | ✅ RES-01 now requires parent `imports/` explicitly |
| Per-layer Coverage Expectation | ✅ Domain 1:1 ACs; ROM-not-ready + workState edges covered |
| Every test maps to a spec AC / edge / Done-when | ✅ Suite maps to NXSAV/RES/edges; desk hint smoke maps to non-NX edge |
| Documented guidelines followed | ✅ Mirror of `rom_importer_nx_mods_inbox_test.lua` / tasks matrix |

---

## Edge Cases

- [x] AppleDouble-only / hidden → empty MTP notice (RES-02/04) — `:185-187`
- [x] ROM not imported for panel version → “Import the … ROM before importing a save” — `:294-322` (`chooseSaveImport` + `rescanSavesAction`; exact notice text; retain)
- [x] Multiple `.sav` → attempt each; success wins; real failures surface; AppleDouble never failure — `:228-236`, `:245-250`
- [x] Non-NX default hint stays picker/drop-oriented — `:351-356` (partial: chooseSaveImport/exportSave non-NX path not re-asserted in this suite — acceptable smoke)
- [x] `workState == "working"` → Import/Export no-op without clearing notice — `:324-338` (choose/rescan), `:405-420` (export)

---

## Gate Check

- **Gate command**: `luajit tests/rom_importer_nx_saves_inbox_test.lua`
- **Result**: 73 passed, 0 failed, 0 skipped
- **Test count before feature**: 0 (file did not exist at `3c62814^`)
- **Test count after prior validation**: 59 checks
- **Test count after fix `fe4491a`**: 73 checks
- **Delta**: +73 from baseline; +14 vs prior FAIL report (RES-01 strengthen + ROM-not-ready + workState)
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans (if issues found)

None — clean PASS.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| NXSAV-01 | ⚠️ Needs Fix (RES-01) | ✅ Verified |
| NXSAV-02 | ✅ Verified | ✅ Verified |
| NXSAV-03 | ✅ Verified | ✅ Verified |
| NXSAV-04 | ✅ Verified | ✅ Verified |
| NXSAV-05 | ✅ Verified | ✅ Verified |
| NXSAV-06 | ✅ Verified | ✅ Verified |
| NXSAV-07 | ✅ Verified | ✅ Verified |
| NXSAV-08 | ✅ Verified | ✅ Verified |
| NXSAV-09 | ✅ Verified | ✅ Verified |
| NXSAV-10 | ✅ Verified | ✅ Verified |
| NXSAV-11 | ✅ Verified | ✅ Verified |
| NXSAV-12 | ✅ Verified | ✅ Verified |
| RES-01 | ❌ Needs Fix (surviving mutant) | ✅ Verified |
| Edge: ROM not ready | ❌ Needs Fix (no evidence) | ✅ Verified |
| Edge: workState working | ❌ Needs Fix (no evidence) | ✅ Verified |

---

## Summary

**Overall**: ✅ Ready

**Spec-anchored check**: 12/12 NXSAV ACs matched spec outcome; 0 spec-precision gaps; all RES-01..11 + listed edges evidenced
**Sensor**: 3/3 mutations killed (prior RES-01 survivor now dies)
**Gate**: 73 passed

**What works**: Parent-first inbox ensure (discriminating), scan/rescan, AppleDouble skip, retain, HostShell avoidance, NX export MTP notice, isolation, ROM-not-ready + workState edges, docs, AD-012.

**Issues found**: none

**Next steps**: none — feature validation complete; no lessons (clean PASS)
