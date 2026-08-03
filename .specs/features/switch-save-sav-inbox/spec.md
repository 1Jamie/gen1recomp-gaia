# Switch Save (.sav) Inbox — Specification

**Related:** `.specs/features/switch-port-love-nx/` (ROM inbox), `.specs/features/switch-mod-zip-inbox/` (mod zip inbox)  
**Context:** `.specs/features/switch-save-sav-inbox/context.md`  
**Tasks:** `.specs/features/switch-save-sav-inbox/tasks.md`  
**Status:** Execute nearly complete — T1–T5 done; pending T6 + Verifier

## Problem Statement

On Switch, **Import save** / **Export save** rely on a native file picker (desktop HostShell or Android SAF). love-nx has no usable explorer, so Import is a silent no-op and Export has no player-facing pull path. Players who want to continue a cart save on Switch (or take a slot off-console as `.sav`) need the same MTP inbox + rescan pattern already shipped for ROMs and mod zips — including the same resilience against Mac MTP junk, nested dirs, and silent failures that burned the ROM/mod paths.

## Goals

- [ ] Import a valid 32 KB Gen1 `.sav` from `imports/saves/` via MTP + **Import save** rescan on NX into a new active slot
- [ ] Export the active slot to `exports/` and surface an MTP-oriented path notice on NX (no `openURL` dependency)
- [ ] Document inbox + export destinations in Switch install / transfer / development docs and launcher.md
- [ ] Headless tests mirror `rom_importer_nx_mods_inbox_test.lua` resilience cases (AppleDouble, retain, nested ensure, no HostShell, isolation)

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Horizon native file picker | Unavailable; inbox only (AD-003/AD-006) |
| Changing desktop/Android Import/Export | Already works |
| Changing SaveConvert / slot format | Existing glue; NX only wires inbox |
| Deleting inbox `.sav` after import | Retain policy matches ROM/mod |
| Hardware OLED smoke as CI gate | Optional P2 evidence only |
| Reusing `self.android` for NX | Forbidden by AD-002 |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Save inbox path | `getSaveDirectory()/imports/saves/` | User chose 1A (separate from ROM + mods) | y |
| Import save button | Ensure dir + immediate rescan | User chose 2A (mirrors mod Import) | y |
| Retain `.sav` after import | Keep in inbox | Matches ROM dump / mod zip retain | y (assumption) |
| Export UX on NX | Notice + MTP hint to `exports/`; no openURL | Picker/`openURL` useless on NX | y (assumption) |
| Multi-file rescan | Import each real `*.sav`; overall notice like mod rescan | Mirrors `rescanModsAction` | y (assumption) |
| Transfer methods | MTP / SD / FTP to save-dir paths (AD-009) | Inherited | y |
| Platform branching | `isNX` / `Platform.isNX()` only — never `android` | AD-002 | y |

**Open questions:** none — all resolved or logged above.

---

## Resilience / Regression Guards (from ROM & mod scars)

These are **hard requirements**, not soft tips. They encode failures already hit on NX MTP:

| Guard ID | Scar (ROM/mod) | Required behavior for `.sav` inbox |
| -------- | -------------- | ---------------------------------- |
| RES-01 | Nested `createDirectory` fails without parent | `ensureSavesInboxDir` SHALL call `ensureImportsDir` before creating `imports/saves/` |
| RES-02 | Mac MTP AppleDouble `._*.gb` / `._*.zip` blocked scans | Scan SHALL skip names starting with `.` (including `._foo.sav`); AppleDouble-only inbox ≡ empty |
| RES-03 | AppleDouble sibling invented a “mixed failure” line | Skipping `._*` SHALL NOT count as an import failure in the notice |
| RES-04 | Silent no-op when picker missing | On NX, **Import save** SHALL always set `saveNotice` (empty hint, success, or failure) — never return with no feedback |
| RES-05 | Deleted user MTP drop after “success” | Success and failure SHALL retain inbox `.sav` bytes (no `remove` of user drops) |
| RES-06 | HostShell / desktop dialog on NX | `chooseSaveImport` on NX SHALL NOT call `chooseSav` / HostShell / Android `pickFile` |
| RES-07 | Wrong flag (`android`) triggered ROM delete side effects | NX path SHALL use `isNX` only (AD-002) |
| RES-08 | Cross-contamination of inboxes | Save scan: only `imports/saves/*.sav`. ROM `scanInbox` / mod `scanModsInbox` SHALL ignore `.sav`. Save scan SHALL ignore `.gb`/`.gbc`/`.zip` |
| RES-09 | Export “Open folder” / `openURL` useless or crashy on NX | NX export success SHALL set notice + MTP hint; SHALL NOT require or call `openURL` |
| RES-10 | Docs omitted `._*` MTP tip | Switch docs MTP tip SHALL mention `._*.sav` alongside ROM/mod sidecars |
| RES-11 | Default hint still said “system file picker” | On NX, SAVE FILES default hint SHALL mention `imports/saves/` / MTP (not desktop picker wording) |

---

## Implicit-Requirement Dimensions Sweep (Medium)

| Dimension | Resolution |
| --------- | ---------- |
| Input validation & bounds | Only non-hidden `*.sav`; size/checksum via `SaveFileIO.importToSlot` / SaveConvert |
| Failure / partial-failure | Red notice; retain file; RES-04 forbids silent failure |
| Idempotency / retry | Rescan may re-import same file → new slot each success; acceptable |
| Auth / rate limits | N/A — local MTP only |
| Concurrency / ordering | Single-threaded; MTP with app closed when copying |
| Data lifecycle | Retain inbox `.sav`; export files user-managed under `exports/` |
| Observability | `saveNotice` always set on NX Import/Export outcomes |
| External-dependency failure | N/A — no network |
| State-transition integrity | Import requires ROM ready for panel version (existing guard) |

**Remaining dimensions N/A for this scope.**

---

## User Stories

### P1: NX `.sav` import inbox ⭐ MVP

**User Story**: As a Switch player, I want to copy a Gen1 `.sav` into a shown inbox folder and press Import save so it becomes a playable slot without a file picker.

**Why P1**: Without this, continuing a cart / PC save on Switch is blocked.

**Acceptance Criteria**:

1. WHEN the user activates **Import save** on NX THEN system SHALL ensure `imports/saves/` exists (**parent `imports/` first** — RES-01) and SHALL scan that folder for non-hidden `*.sav` files (RES-02)
2. WHEN the inbox is empty (including AppleDouble-only) THEN system SHALL show a notice with the save-dir path and an MTP-oriented hint for `imports/saves/` (RES-04) and SHALL NOT call HostShell/`chooseSav` (RES-06)
3. WHEN a valid `.sav` is present and the panel version’s ROM is ready THEN system SHALL import it via `SaveFileIO.importToSlot` into a new slot, refresh the SAVE SLOT list, show a success notice, and **retain** the inbox file (RES-05)
4. WHEN import fails (wrong size, bad checksum, ROM not ready, read error) THEN system SHALL show a clear red notice and SHALL NOT delete the user’s `.sav` from `imports/saves/` (RES-05)
5. WHEN NX is active THEN system SHALL branch on `isNX` only (RES-07) and SHALL NOT require a desktop or Android file picker (RES-06)
6. WHEN `._foo.sav` sits beside a real `foo.sav` THEN system SHALL import only the real file and SHALL NOT append a sibling “failed” line for the AppleDouble (RES-03)
7. WHEN the SAVE FILES card is shown on NX with no prior notice THEN the default hint SHALL mention the `imports/saves/` MTP path, not a system file picker (RES-11)

**Independent Test**: `tests/rom_importer_nx_saves_inbox_test.lua` (mirror mods suite) — see tasks.md Test Coverage Matrix.

---

### P1: NX export path notice ⭐ MVP

**User Story**: As a Switch player, I want Export save to write a `.sav` I can pull via MTP and to tell me where it landed.

**Why P1**: Export already writes via `love.filesystem`; without a path hint the file is invisible.

**Acceptance Criteria**:

1. WHEN the user activates **Export save** on NX with an existing active slot THEN system SHALL write `exports/gen1recomp-<version>-<slotId>.sav` (existing `SaveFileIO.exportActiveSlot` behavior)
2. WHEN export succeeds on NX THEN system SHALL show a success notice that includes the exports path and an MTP-oriented hint and SHALL NOT call `love.system.openURL` (RES-09)
3. WHEN export fails (no save) THEN system SHALL show the existing failure notice (RES-04 — not silent)

**Independent Test**: NX-flagged unit case in the same saves-inbox test file.

---

### P1: Inbox isolation ⭐ MVP

**User Story**: As a player, I want ROMs, mods, and saves in separate inboxes so one file type cannot break another’s scan.

**Why P1**: Cross-contamination was a class of MTP confusion; AD-006 already separated mods.

**Acceptance Criteria**:

1. WHEN scanning the save inbox THEN system SHALL ignore `.gb` / `.gbc` / `.zip` under `imports/saves/` (RES-08)
2. WHEN ROM `scanInbox` or mod `scanModsInbox` runs THEN they SHALL NOT treat `imports/saves/*.sav` as ROM/mod candidates (RES-08)

**Independent Test**: Isolation cases in the NX saves inbox test file.

---

### P1: Docs — save inbox + export destinations ⭐ MVP

**User Story**: As a Switch operator/player, I want documented paths so I can move `.sav` files the same way as ROMs and mods.

**Why P1**: Missing docs blocks adoption of the inbox.

**Acceptance Criteria**:

1. WHEN reading `docs/switch-install.md` THEN it SHALL document copying a `.sav` into `imports/saves/` and using **Import save**, plus pulling exports from `exports/`
2. WHEN reading `docs/switch-transfer.md` THEN the destinations table SHALL list the save inbox and exports folder
3. WHEN reading `docs/switch-development.md` THEN it SHALL note the NX save inbox alongside ROM/mod inboxes
4. WHEN reading `docs/launcher.md` Import/Export section THEN it SHALL mention the NX inbox path (not only desktop/Android pickers)
5. WHEN reading Switch MTP tips THEN they SHALL mention ignoring / deleting `._*.sav` AppleDouble sidecars (RES-10)

**Independent Test**: Doc review checklist in tasks.

---

### P2: Project decision AD-012

**User Story**: As a maintainer, I want the NX save inbox recorded in `.specs/STATE.md` like AD-003/AD-006.

**Why P2**: Keeps platform decisions discoverable for future import work.

**Acceptance Criteria**:

1. WHEN the feature ships THEN STATE.md SHALL include an active decision: NX raw `.sav` import uses `imports/saves/` + Import-save rescan; export surfaces `exports/` via MTP hint; resilience guards RES-01..11 apply

**Independent Test**: STATE.md review.

---

## Edge Cases

- WHEN `imports/saves/` contains only `._foo.sav` / hidden names THEN system SHALL treat as empty and show MTP notice (RES-02, RES-04)
- WHEN ROM is not imported for the panel version THEN system SHALL refuse with the existing “Import the … ROM before importing a save” notice (no silent no-op)
- WHEN multiple valid `.sav` files exist THEN system SHALL attempt each; success wins overall when any ok; real failures still surface (mod-rescan pattern); AppleDouble never counts as failure (RES-03)
- WHEN not on NX THEN Import save / Export save SHALL keep existing desktop/Android behavior
- WHEN `workState == "working"` THEN Import/Export SHALL no-op without clearing an existing useful notice (same as other launcher actions)

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| NXSAV-01 | P1: Import ensure + scan (RES-01/02) | Tasks | Pending |
| NXSAV-02 | P1: Empty / AppleDouble-only MTP notice (RES-04/06) | Tasks | Pending |
| NXSAV-03 | P1: Valid `.sav` → slot + retain (RES-05) | Tasks | Pending |
| NXSAV-04 | P1: Failure notice + retain (RES-05) | Tasks | Pending |
| NXSAV-05 | P1: No HostShell; `isNX` only (RES-06/07) | Tasks | Pending |
| NXSAV-06 | P1: AppleDouble sibling no false failure (RES-03) | Tasks | Pending |
| NXSAV-07 | P1: Default NX SAVE FILES hint (RES-11) | Tasks | Pending |
| NXSAV-08 | P1: Export writes `exports/` | Tasks | Pending |
| NXSAV-09 | P1: Export NX MTP notice; no openURL (RES-09) | Tasks | Pending |
| NXSAV-10 | P1: Inbox isolation (RES-08) | Tasks | Pending |
| NXSAV-11 | P1: Docs + `._*.sav` MTP tip (RES-10) | Tasks | Pending |
| NXSAV-12 | P2: AD-012 in STATE.md | Tasks | Pending |

**Coverage:** 12 total — see `tasks.md` for mapping.

---

## Success Criteria

- [ ] On NX, Import save never silently no-ops; empty/AppleDouble-only → path hint; valid file → new slot; junk skipped without fake failures
- [ ] Nested `imports/saves/` creates reliably; user `.sav` never auto-deleted
- [ ] On NX, Export save success notice points at `exports/` for MTP pull without `openURL`
- [ ] Switch + launcher docs mention `imports/saves/`, `exports/`, and `._*.sav`
- [ ] `rom_importer_nx_saves_inbox_test.lua` passes with the resilience matrix in tasks.md
