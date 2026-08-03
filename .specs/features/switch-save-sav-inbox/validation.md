# switch-save-sav-inbox Validation

**Date**: 2026-08-03
**Spec**: `.specs/features/switch-save-sav-inbox/spec.md`
**Diff range**: `3c62814^..8120f11` (3c62814, 5d1e7ff, 74f6b68, 4afb54c, 7e0c64c, 8120f11)
**Verifier**: independent sub-agent (author ≠ verifier)

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

---

## Spec-Anchored Acceptance Criteria

### P1: NX `.sav` import inbox

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| ------------------------- | -------------------- | ----------------------- | ------ |
| NXSAV-01: Import save ensures `imports/saves/` (parent `imports/` first — RES-01) and scans non-hidden `*.sav` (RES-02) | `ensureSavesInboxDir` calls `ensureImportsDir` then creates `imports/saves/`; scan skips `.*` | `tests/rom_importer_nx_saves_inbox_test.lua:103-106` — `createdDirs.imports or createdDirs["imports/saves"]` + `createdDirs["imports/saves"]`; scan `:127-128` `#savs==1` / path under `imports/saves/` | ⚠️ Spec-precision gap (RES-01) — OR allows nested create without parent ensure; sensor mutant survived. Scan/AppleDouble side ✅ |
| NXSAV-02: Empty / AppleDouble-only → MTP notice; no HostShell (RES-04/06) | `saveNotice` set with save-dir + `imports/saves/` MTP hint; 0 HostShell | `:174-177` `saveNotice.red ~= nil` + `imports/saves/`; `:183-186` AppleDouble-only; `:269-270` `hostShellCalls==0` | ✅ PASS |
| NXSAV-03: Valid `.sav` + ROM ready → importToSlot, refresh, success notice, retain (RES-05) | New slot path; refresh; ok notice; bytes retained; no remove | `:195-202` `#importCalls==1`, `_refreshed`, `saveNotice.ok`, `not removed[...]`, `read == "GOODSAV"` | ✅ PASS |
| NXSAV-04: Import fail → red notice; retain `.sav` (RES-05) | Error notice; file kept | `:211-217` `not saveNotice.ok`, text has `32768`, retain checks | ✅ PASS |
| NXSAV-05: Branch `isNX` only; no desktop/Android picker (RES-06/07) | `isNX=true`, `android=false`; HostShell unused; inbox rescan | `:96-97` fixture flags; `:278-282` chooseSaveImport imports from inbox, `hostShellCalls==0` | ✅ PASS |
| NXSAV-06: `._foo.sav` beside real → import real only; no false “failed” (RES-03) | One import of real file; notice ok without `failed` | `:244-249` `#importCalls==1`, source `cart.sav`, `not text:find("failed")` | ✅ PASS |
| NXSAV-07: Default SAVE FILES hint mentions `imports/saves/` MTP, not picker (RES-11) | Hint contains `imports/saves/` + MTP; not “system file picker” | `:296-301` `_savesDefaultHint()` finds | ✅ PASS |

### P1: NX export path notice

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| ------------------------- | -------------------- | ----------------------- | ------ |
| NXSAV-08: Export writes `exports/gen1recomp-<version>-<slotId>.sav` via existing SaveFileIO | Calls `exportActiveSlot(version)` (existing glue) | `:335-336` `#exportCalls==1`, `exportCalls[1]=="red"` (stub returns expected path form) | ✅ PASS (NX wiring; filename owned by existing SaveFileIO) |
| NXSAV-09: Success → exports path + MTP hint; no `openURL` / no open-folder `dir` (RES-09) | Notice mentions `exports` + MTP; `dir==nil`; openURL unused | `:338-344` | ✅ PASS |
| Export fails → failure notice (not silent) | Clear error notice | `:353-356` `not ok`, text finds `No save` | ✅ PASS |

### P1: Inbox isolation

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| ------------------------- | -------------------- | ----------------------- | ------ |
| NXSAV-10: Save scan ignores `.gb`/`.gbc`/`.zip` (RES-08) | Only `*.sav` candidates | `:127-128` one `.sav` despite gb/zip/txt | ✅ PASS |
| NXSAV-10: ROM/mod scans ignore `imports/saves/*.sav` (RES-08) | No `.sav` / no `imports/saves/` in ROM/mod lists | `:135-140`, `:148-152` | ✅ PASS |

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
| RES-01 | `ensureImportsDir` before `imports/saves/` | `:103-106` weak OR; impl `RomImporter.lua:380-381` does call parent | ⚠️ Spec-precision gap + ❌ sensor survived |
| RES-02 | Skip `._*`; AppleDouble-only ≡ empty | `:183-186` | ✅ PASS |
| RES-03 | AppleDouble not counted as failure | `:244-249` | ✅ PASS |
| RES-04 | Empty NX Import always sets `saveNotice` | `:175`, `:290-291` | ✅ PASS |
| RES-05 | Retain inbox bytes success/fail | `:200-202`, `:215-217` | ✅ PASS |
| RES-06 | No HostShell/`chooseSav` on NX | `:269-270`, `:279` | ✅ PASS |
| RES-07 | `isNX` only (`android=false`) | `:96-97` | ✅ PASS |
| RES-08 | Inbox isolation | `:127-152` | ✅ PASS |
| RES-09 | Export MTP notice; no openURL/`dir` | `:338-344` | ✅ PASS |
| RES-10 | Docs `._*.sav` | docs cites above | ✅ PASS |
| RES-11 | Default NX hint `imports/saves/` | `:296-301` | ✅ PASS |

**Status**: ❌ Gaps present — RES-01 assertion does not enforce parent-first ensure; two listed edge cases lack automated evidence

---

## Discrimination Sensor

Scratch method: backup `/tmp/RomImporter.lua.verifier.bak` → mutate `src/import/RomImporter.lua` → run suite → restore (verified `cmp` clean; post-restore gate 59/59).

| Mutation | File:line | Description | Killed? |
| -------- | --------- | ----------- | ------- |
| 1 | `listSavPaths` (~470) | Stop skipping hidden/`._*` names | ✅ Killed — RES-02/03 fails (4 assertions) |
| 2a | `ensureSavesInboxDir` (~381) + empty branch (~556) | Skip `ensureImportsDir` **and** leave empty `saveNotice` nil | ✅ Killed — RES-04 (`saveNotice.red` nil) |
| 2b | `ensureSavesInboxDir` only (~381) | Skip `ensureImportsDir` only (nested create still stubbed true) | ❌ Survived — 59/59 still passed |
| 3 | `exportSave` NX branch (~1494) | Set `dir=` + omit MTP/`exports` from notice text | ✅ Killed — RES-09 MTP + `dir==nil` |

**Sensor depth**: lightweight (3 targeted + 1 isolate of RES-01)
**Result**: 3/4 killed (1 survived) — FAIL ❌

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
| Spec-anchored outcome check | ⚠️ RES-01 assertion too weak vs spec “parent first” |
| Per-layer Coverage Expectation | ⚠️ Domain mostly 1:1; edge ROM-not-ready / `workState` missing tests |
| Every test maps to a spec AC / edge / Done-when | ✅ Suite maps to NXSAV/RES; desk hint smoke maps to non-NX edge |
| Documented guidelines followed | ✅ Mirror of `rom_importer_nx_mods_inbox_test.lua` / tasks matrix |

---

## Edge Cases

- [x] AppleDouble-only / hidden → empty MTP notice (RES-02/04) — `:183-186`
- [ ] ROM not imported for panel version → “Import the … ROM before importing a save” — **no evidence** in `rom_importer_nx_saves_inbox_test.lua` (impl exists `RomImporter.lua:1419-1422`)
- [x] Multiple `.sav` → attempt each; success wins; real failures surface; AppleDouble never failure — `:227-235`, `:244-249`
- [x] Non-NX default hint stays picker/drop-oriented — `:304-309` (partial: chooseSaveImport/exportSave non-NX path not re-asserted in this suite)
- [ ] `workState == "working"` → Import/Export no-op without clearing notice — **no evidence** (impl early-returns at `:552`, `:1439`, `:1487`)

---

## Gate Check

- **Gate command**: `luajit tests/rom_importer_nx_saves_inbox_test.lua`
- **Result**: 59 passed, 0 failed, 0 skipped
- **Test count before feature**: 0 (file did not exist at `3c62814^`)
- **Test count after feature**: 59 checks
- **Delta**: +59
- **Skipped tests**: none
- **Failures**: none

---

## Fix Plans (if issues found)

### Fix 1: Strengthen RES-01 assertion (surviving mutant)

- **Root cause**: Test accepts `createdDirs.imports or createdDirs["imports/saves"]`, so skipping `ensureImportsDir()` still passes when the FS stub always succeeds on nested `createDirectory("imports/saves")`.
- **Fix task**: Assert `createdDirs.imports == true` **and** `createdDirs["imports/saves"] == true` after `ensureSavesInboxDir` on a fresh stub (and/or spy that `ensureImportsDir` was invoked). Optionally stub nested create to fail unless parent exists.
- **Verify**: Re-run mutation 2b — must FAIL; clean suite must PASS.
- **Priority**: Major (RES-01 / NXSAV-01 discrimination)

### Fix 2: Cover ROM-not-ready edge

- **Root cause**: No asserting test for `_importSave` / rescan when `ready[version]==false`.
- **Fix task**: Add case: inbox has `.sav`, `ready.red=false` → notice text matches “Import the … ROM before importing a save”; no silent no-op; file retained.
- **Priority**: Major (listed edge case; evidence-or-zero)

### Fix 3: Cover `workState == "working"` no-op

- **Root cause**: No asserting test for Import/Export early return.
- **Fix task**: Set prior `saveNotice`, `workState="working"`, call `chooseSaveImport` / `exportSave` / `rescanSavesAction` → notice unchanged; no import/export calls.
- **Priority**: Minor/Major (listed edge case)

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| NXSAV-01 | Implementing | ⚠️ Needs Fix (RES-01 test discrimination) |
| NXSAV-02 | Implementing | ✅ Verified |
| NXSAV-03 | Implementing | ✅ Verified |
| NXSAV-04 | Implementing | ✅ Verified |
| NXSAV-05 | Implementing | ✅ Verified |
| NXSAV-06 | Implementing | ✅ Verified |
| NXSAV-07 | Implementing | ✅ Verified |
| NXSAV-08 | Implementing | ✅ Verified |
| NXSAV-09 | Implementing | ✅ Verified |
| NXSAV-10 | Implementing | ✅ Verified |
| NXSAV-11 | Implementing | ✅ Verified |
| NXSAV-12 | Implementing | ✅ Verified |
| RES-01 | — | ❌ Needs Fix (surviving mutant) |
| Edge: ROM not ready | — | ❌ Needs Fix (no evidence) |
| Edge: workState working | — | ❌ Needs Fix (no evidence) |

---

## Summary

**Overall**: ❌ Not Ready

**Spec-anchored check**: 11/12 NXSAV stories matched; 1 RES-01 precision gap; 2 edge cases uncovered
**Sensor**: 3/4 mutations killed (1 survived: skip `ensureImportsDir`)
**Gate**: 59 passed

**What works**: Inbox scan/rescan, AppleDouble skip, retain, HostShell avoidance, NX export MTP notice, isolation, docs, AD-012; primary suite green.

**Issues found**: RES-01 test does not discriminate parent-first ensure; missing tests for ROM-not-ready and `workState=="working"` edges.

**Next steps**: Implement Fix 1–3; re-verify (orchestrator → lessons.py for surviving mutant / gaps).
