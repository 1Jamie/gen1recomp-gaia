# Switch Save (.sav) Inbox — Tasks

**Spec:** `.specs/features/switch-save-sav-inbox/spec.md`  
**Context:** `.specs/features/switch-save-sav-inbox/context.md`  
**Status:** Execute nearly complete — T1–T5 done; pending T6 gate + Verifier

---

## Test Coverage Matrix

> Generated from codebase + spec resilience guards. Guidelines: mirror `tests/rom_importer_nx_mods_inbox_test.lua` / `tests/rom_importer_nx_inbox_test.lua`; suite via `tests/harness` + `scripts/test.sh` / `luajit tests/….lua`. Strong default: every AC + every RES-* has an asserting test (or explicit doc checklist for docs-only ACs).

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| RomImporter NX saves inbox | unit (stub FS) | All NXSAV import/export/isolation + RES-01..09, RES-11 | `tests/rom_importer_nx_saves_inbox_test.lua` | `luajit tests/rom_importer_nx_saves_inbox_test.lua` |
| SaveFileIO (unchanged glue) | existing unit | Size/checksum already covered — do not regress | `tests/engine/save_file_io_tests.lua` | via `scripts/test.sh` / run_tests |
| Docs / STATE | checklist | NXSAV-11, NXSAV-12, RES-10 | `docs/switch-*.md`, `docs/launcher.md`, `.specs/STATE.md` | manual review in T5/T6 |
| Desktop/Android regression | smoke assert in NX test | Non-NX `chooseSaveImport` still reaches picker path stub (no inbox force) | same NX test file (desk fixture) | same luajit command |

### Resilience test checklist (must all appear in T1 test file)

| ID | Assert |
| -- | ------ |
| RES-01 | `ensureSavesInboxDir` creates `imports/` then `imports/saves/` |
| RES-02 | `._x.sav` alone → empty path (MTP notice, zero imports) |
| RES-03 | `._x.sav` + `x.sav` → one import; notice ok without “failed” from AppleDouble |
| RES-04 | Empty NX Import save sets `saveNotice` (never nil) |
| RES-05 | Success and bad-size failure leave inbox bytes; no `remove` of user `.sav` |
| RES-06 | NX `chooseSaveImport` → 0 HostShell / `chooseSav` calls |
| RES-07 | Fixture uses `isNX=true`, `android=false` |
| RES-08 | `.gb`/`.zip` in `imports/saves/` ignored; `.sav` not returned by ROM/mod scans |
| RES-09 | NX `exportSave` success notice mentions `exports` + MTP; `openURL` not required |
| RES-11 | NX default SAVE FILES hint mentions `imports/saves/` |

---

## Phase 1 — Inbox + Import (NX)

### T1: NX saves inbox scan/rescan + resilience tests ⭐ ✅
- **What**: Add `imports/saves/` helpers (`ensureSavesInboxDir`, list/scan, `_setNxSavesInboxNotice`, `rescanSavesAction`) and `tests/rom_importer_nx_saves_inbox_test.lua` covering the resilience checklist above (tests may land first or with implementation in same commit if tightly coupled — prefer tests asserting desired outcomes, then wire).
- **Done when**: `luajit tests/rom_importer_nx_saves_inbox_test.lua` passes RES-01..08 (+ empty/success/fail/retain/AppleDouble/isolation).
- **Requires**: —  
- **Reqs**: NXSAV-01, NXSAV-02, NXSAV-03, NXSAV-04, NXSAV-06, NXSAV-10  
- **Commit**: `test+feat(nx): saves inbox scan with AppleDouble/retain guards`
- **Status**: ✅ complete

### T2: Wire chooseSaveImport on NX + default hint (RES-06/07/11) ✅
- **What**: `chooseSaveImport` early `isNX` branch → ensure + `rescanSavesAction`; SAVE FILES default hint on NX mentions `imports/saves/` MTP (not picker wording); never `android` flag.
- **Done when**: Test asserts `chooseSaveImport` on NX rescans inbox, HostShell unused; default hint string contains `imports/saves/`.
- **Requires**: T1  
- **Reqs**: NXSAV-05, NXSAV-07  
- **Commit**: `feat(nx): Import save uses imports/saves inbox`
- **Status**: ✅ complete

---

## Phase 2 — Export notice

### T3: NX exportSave MTP notice (no openURL) ✅
- **What**: On `isNX`, after successful `exportActiveSlot`, set `saveNotice` with exports path + MTP hint; do not set `dir` for open-folder / do not call `openURL`.
- **Done when**: Test covers RES-09 + NXSAV-08/09.
- **Requires**: T2 (or T1 if export-only testable)  
- **Reqs**: NXSAV-08, NXSAV-09  
- **Commit**: `feat(nx): Export save shows MTP exports path`
- **Status**: ✅ complete

---

## Phase 3 — Docs + decision

### T4: Docs — install / transfer / development / launcher + `._*.sav` ✅
- **What**: Update `docs/switch-install.md`, `docs/switch-transfer.md`, `docs/switch-development.md`, `docs/launcher.md`; extend MTP AppleDouble tip to `._*.sav` (RES-10).
- **Done when**: Doc checklist: paths `imports/saves/`, `exports/`, Import save action, `._*.sav` mentioned.
- **Requires**: T3  
- **Reqs**: NXSAV-11  
- **Commit**: `docs(nx): save .sav inbox and exports paths`
- **Status**: ✅ complete

### T5: AD-012 in STATE.md + handoff ✅
- **What**: Record AD-012 (inbox path, rescan on Import save, export MTP hint, RES guards); update Handoff for this feature.
- **Done when**: STATE.md lists AD-012 active; Handoff points at this feature.
- **Requires**: T4  
- **Reqs**: NXSAV-12  
- **Commit**: `docs(specs): AD-012 NX save .sav inbox`
- **Status**: ✅ complete

---

## Phase 4 — Gate

### T6: Full gate + wire into test runner if needed
- **What**: Ensure new test is picked up by `scripts/test.sh` / `tests/run_tests.lua` the same way other `rom_importer_nx_*` tests are; run the new suite + a quick non-NX smoke if already wired.
- **Done when**: CI-equivalent local command runs the new file green; no desktop/Android intentional breakage.
- **Requires**: T1–T5  
- **Reqs**: all NXSAV-*  
- **Commit**: only if runner wiring needed; else verify-only (no empty commit)

---

## Requirement mapping

| Req | Tasks |
| --- | ----- |
| NXSAV-01 | T1 |
| NXSAV-02 | T1 |
| NXSAV-03 | T1 |
| NXSAV-04 | T1 |
| NXSAV-05 | T2 |
| NXSAV-06 | T1 |
| NXSAV-07 | T2 |
| NXSAV-08 | T3 |
| NXSAV-09 | T3 |
| NXSAV-10 | T1 |
| NXSAV-11 | T4 |
| NXSAV-12 | T5 |

**Unmapped:** none

---

## Execution order

T1 → T2 → T3 → T4 → T5 → T6 → **Verifier** (automatic)
