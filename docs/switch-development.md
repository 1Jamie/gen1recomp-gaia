# Nintendo Switch development (love-nx)

Gen1Recomp on Nintendo Switch runs on a pinned [love-nx](https://github.com/retronx-team/love-nx) runtime. This document covers vendor layout, fetch instructions, and the Mac ↔ Switch transfer workflow.

## love-nx 11.5-nx1 (pinned)

**Tag:** [11.5-nx1](https://github.com/retronx-team/love-nx/releases/tag/11.5-nx1)

**Local layout (not committed):**

```text
.bazinga/love-nx/11.5-nx1/
├── love.nro    # homebrew launcher binary (loose mode: copied to gen1recomp.nro)
└── love.elf    # required for fused NRO builds (devkitPro nacptool/elf2nro)
```

**Manifest:** `scripts/switch/love-nx-11.5-nx1.sha256` lists expected artifact names and SHA-256 checksums. Checksums are filled when binaries are fetched (`TBD_*` placeholders until then).

### Fetch instructions

1. Open the [11.5-nx1 release](https://github.com/retronx-team/love-nx/releases/tag/11.5-nx1) and download `love.nro` and `love.elf`.
2. Create the directory: `mkdir -p .bazinga/love-nx/11.5-nx1`
3. Move both files into that directory.
4. Record checksums and update the manifest:

   ```bash
   shasum -a 256 .bazinga/love-nx/11.5-nx1/love.nro \
     .bazinga/love-nx/11.5-nx1/love.elf
   ```

5. Replace the `TBD_*` lines in `scripts/switch/love-nx-11.5-nx1.sha256` with the real hashes.

**Never commit** love-nx binaries, ROM dumps, or generated cache into git. The repo `.gitignore` excludes `.bazinga/` (vendor cache) and `/dist/` (build output).

## Loose-mode dist layout

Development builds place `gen1recomp.nro` and `game.love` side by side:

```text
dist/switch/loose/
├── gen1recomp.nro
└── game.love
```

Assemble with:

```bash
scripts/build_switch.sh --loose
```

(See `scripts/switch/assemble_loose.sh` for the underlying copy + checksum step.)

## Transfer policy (mandatory)

Mac ↔ Switch file movement uses **USB/MTP only**:

- **Switch:** DBI → `Run MTP responder`
- **Mac:** [OpenMTP](https://github.com/ganeshrvel/openmtp) (Apple Silicon build)
- **Destination root:** `1: SD Card/switch/gen1recomp/`

**Forbidden for this project** (do not use as workarounds):

- Removing the microSD card to mount it on the Mac (`/Volumes/…`, Finder copy)
- FTP / Sphaira / any network file share to the Switch
- `nxlink` / netloader deploy
- DBI `MicroSD install`, `NAND install`, or other virtual install folders (NSP/NSZ/XCI paths)

If MTP fails, diagnose cable, USB port, DBI state, and OpenMTP exclusivity — do not silently fall back to forbidden methods.

## OpenMTP + DBI transfer (loose build)

### On the Switch

1. Close Gen1Recomp if it is running.
2. Open **DBI** from hbmenu.
3. Select **`Run MTP responder`** (DBI documents `X` on the main screen).
4. Keep DBI on that screen for the entire transfer.
5. Connect the Switch to the Mac with a USB-C data cable.

### On the Mac

1. Close any other MTP clients.
2. Open **OpenMTP** and select the DBI device.
3. In the remote pane, open **`1: SD Card`**.
4. Navigate to **`switch/`** and create **`gen1recomp/`** if needed.
5. Enter **`1: SD Card/switch/gen1recomp/`**.
6. Drag from the local pane:

   ```text
   dist/switch/loose/gen1recomp.nro
   dist/switch/loose/game.love
   ```

7. Wait for the OpenMTP queue to finish completely.
8. Refresh the remote listing and confirm file sizes match the local files.
9. On the Switch, exit MTP responder normally in DBI before launching the app.

Expected layout on SD:

```text
1: SD Card/
└── switch/
    └── gen1recomp/
        ├── gen1recomp.nro
        └── game.love
```

## Round-trip SHA-256 verification

For the **first deploy** of each artifact type (loose pair, later fused NRO), verify MTP integrity:

1. **Before send** — record local hashes:

   ```bash
   shasum -a 256 dist/switch/loose/gen1recomp.nro \
     dist/switch/loose/game.love
   ```

2. **After send** — in OpenMTP, copy the same files from `1: SD Card/switch/gen1recomp/` back to an empty local folder, e.g. `dist/switch/mtp-roundtrip/`.

3. **Compare** round-trip hashes:

   ```bash
   shasum -a 256 dist/switch/mtp-roundtrip/gen1recomp.nro \
     dist/switch/mtp-roundtrip/game.love
   ```

4. Local pre-send and round-trip hashes **must match**. Record results in the test report template below.

Repeat whenever a cable glitch or interrupted transfer is suspected.

## Title override launch (full memory)

Applet Mode is **not** the primary validation path. Use **title override** so hbmenu runs with full memory:

1. Confirm the OpenMTP transfer queue finished.
2. Exit MTP responder in DBI; disconnect USB if desired.
3. Hold **`R`** while launching any legitimately installed title.
4. Keep holding until **hbmenu** appears.
5. Confirm hbmenu does **not** show **Applet Mode**.
6. Launch **`gen1recomp`** (or the probe NRO during Phase 0).

Album / applet launches are only useful to document applet-specific limitations; P0/P1 gates use title override.

## Phase 0 hardware checklist

Complete **in order** on OLED hardware. Operator fills evidence fields — leave blank until tested.

| Step | Action | Pass | Evidence / notes |
| ---- | ------ | ---- | ---------------- |
| P0-0a | Fetch love-nx 11.5-nx1; record manifest SHA-256 | yes | See `scripts/switch/love-nx-11.5-nx1.sha256` |
| P0-0b | Build `switch-probe.love` per `tools/switch-probe/README.md` | yes | |
| P0-0c | Assemble loose probe (`game.love` = probe) to `dist/switch/loose/` | yes | |
| P0-0d | MTP deploy to `1: SD Card/switch/gen1recomp/`; round-trip SHA-256 | yes | nro `8290ac15…5918f5`; love `9f198637…fa2e34f` |
| P0-0e | Title override → probe boots; `getOS()` shows `NX` | yes | `getOS()`=`NX`, `love._os`=`NX` |
| P0-0f | Probe lists 1280×720 (or documented dims), save path, gamepad/touch log | yes | save `sdmc:/switch/gen1recomp/switch-probe`; Joy-Con Y→#3 X→#4 |
| P0-1a | Replace `game.love` with unpatched Gen1Recomp build | yes | feat/switch-nx inbox build |
| P0-1b | MTP replace `game.love` only; round-trip SHA-256 | yes | |
| P0-1c | Title override → launcher reaches import screen | yes | |
| P0-1d | Joy-Con: can navigate launcher (no touch-only) | yes | Full report: `docs/switch-hardware-evidence.md` |

**Operator:** Andrew **Date:** 2026-08-01 **Console:** Switch OLED  
**love-nx tag:** 11.5-nx1 **gen1recomp commit:** `df7cea4`

## Phase 0 test report template

Copy this block into your hardware notes or PR evidence. **Do not commit ROM files or ROM hashes of private dumps.**

```markdown
## Switch Phase 0 — hardware report

- Operator:
- Date:
- Console model:
- Atmosphère / HOS version:
- gen1recomp commit:
- love-nx tag: 11.5-nx1
- love.nro SHA-256 (local):
- game.love SHA-256 (local, pre-send):
- MTP round-trip SHA-256 (gen1recomp.nro):
- MTP round-trip SHA-256 (game.love):
- Title override used: yes / no
- Applet Mode observed: yes / no (should be no for P0)
- Probe getOS():
- Probe dimensions:
- Probe save directory shown:
- Gamepad events logged: yes / no
- Touch events logged: yes / no
- Unpatched launcher boot: pass / fail
- Joy-Con launcher navigation: pass / fail / not tested
- Notes:
```

## Fast dev loop (loose mode)

While iterating on Lua/assets:

1. Edit on Mac; run `scripts/test.sh --quick`.
2. Rebuild `.bazinga/work/game.love` (`scripts/build.sh mac --no-notarize` or project pack step).
3. Close Gen1Recomp on Switch.
4. DBI → `Run MTP responder`.
5. OpenMTP → `1: SD Card/switch/gen1recomp/`.
6. Replace **only** `game.love`; wait for queue + refresh listing.
7. Exit MTP responder; launch via title override.
8. Keep `gen1recomp.nro` unchanged until the love-nx pin changes.

```bash
scripts/test.sh --quick
scripts/build.sh mac --no-notarize
scripts/build_switch.sh --loose
shasum -a 256 .bazinga/work/game.love
```

## Controller input mapping (NX)

Measured on Switch OLED (`feat/switch-nx`, love-nx `11.5-nx1`, 1280×720). Both `joystickpressed` and `gamepadpressed` fire for Joy-Con; prefer the gamepad path when `joystick:isGamepad()` is true.

| Path | Control | Mapping |
| ---- | ------- | ------- |
| `gamepadpressed` | D-pad / left stick | move |
| `gamepadpressed` | SDL `a` / `b` on **NX** | swapped via `NX_GAMEPAD_BINDINGS`: physical **A** (east) = GB A confirm, physical **B** (south) = GB B cancel |
| `gamepadpressed` | SDL `a` / `b` on desktop | identity (SDL south = GB A) |
| `gamepadpressed` | `start` / `back` | Start / Select |
| `joystickpressed` (raw) | only if **not** `isGamepad()` | face/menu fallback |
| `joystickpressed` (raw) | `#1` / `#2` on NX | Nintendo B / A → GB B / A |
| `joystickpressed` (raw) | `#9` / `#10` | Select / Start (− / +) |

**Nintendo UX on Switch:** physical A confirms, physical B cancels (explicit NX remap of SDL face labels).

**Dual-path rule:** love-nx emits both `gamepadpressed` and `joystickpressed` for Joy-Con. When `joystick:isGamepad()` is true, Input and RomImporter **ignore raw** face/menu so NamingScreen does not see A+B in one frame. `NamingScreen` also prefers A over B if both edges still fire.

Implementation: `src/core/GamepadMap.lua` (`NX_RAW_*`, `ignoreRawForJoystick`, `displayChordDigit`). Launcher and gameplay share the same converter.

## Mod zip inbox (NX)

Community mods install from a **separate** MTP inbox (not mixed into the ROM `imports/` scan):

| Item | Value |
| ---- | ----- |
| Save-relative path | `imports/mods/` |
| MTP destination | `1: SD Card/<save identity>/imports/mods/` (see launcher notice for the live `getSaveDirectory()` path) |
| Candidates | `*.zip` only |
| Rescan | MODS tab → **Procurar novamente** (installs each zip via `LauncherMods.installZip`; source zips are retained on success and failure) |
| FIND MODS | Remains network-gated / hidden on NX (`networkValidated == false`) |

Do **not** commit third-party mod zip bytes into git. Drop the zip over MTP, rescan, enable in MODS, then Play.

**MTP tip (Mac):** OpenMTP/Finder often creates AppleDouble sidecars named `._Something.zip` / `._cart.gb`. Those are not real archives or ROMs — the launcher ignores hidden `.*` names under both `imports/` and `imports/mods/`. If install still fails with “could not be opened” / “not a zip file”, delete any `._*` under the inbox and confirm the real zip starts with the `PK` magic (re-copy the release asset if unsure).

**Example zip source:** [DramaticShape VoxelMod releases](https://github.com/DramaticShape/DramaticShapeVoxelMod/releases) — download a release `.zip`, copy into `imports/mods/`, rescan, enable.

## Joy-Con display chords (Select + face)

PC digit hotkeys for COLORS / TILT / pipelines have Joy-Con equivalents. Hold **Select** (`back` / −) and press a face/shoulder button; the engine runs the same path as `Game:keypressed` for that digit (including `writeOptions` / Pipelines parity).

| Chord (Nintendo UX) | Engine key | Typical effect |
| ------------------- | ---------- | -------------- |
| Select + **A** | `2` | COLORS cycle |
| Select + **B** | `3` | TILT / perspective cycle |
| Select + **Y** | `5` | GBC FX / V-GRID (mod pipeline) |
| Select + **X** | `6` | T-SHIFT / mod pipeline |
| Select + **L** (left shoulder) | `7` | V-CURVE / mod pipeline |

Without Select held, face buttons keep normal GB A/B gameplay mapping (no accidental color/tilt cycles). The **Options** menu remains available for the same settings — chords are optional shortcuts, not the only path.

On NX, A/B chords resolve through the Nintendo UX face remap so physical **A** → key `2` and physical **B** → key `3` match this table.

**Opt-in diagnostics:** create an empty `switch-debug.txt` in the save directory; events flush to `switch.log` at ≤1 Hz with build identity (no ROM/save bytes).

**Hardware re-test:** T16 **pass** @ `2699c9a` (naming A=confirm / B=cancel). T19 **pass** (quit/reopen, suspend×10, reboot) — operator 2026-08-01.

**Suspend/resume audio:** after resume, chip music is stopped to avoid duplicate streams; confirm on hardware during P0-09/10 (T19).

## Lua error log (save directory)

On any uncaught Lua error, Gen1Recomp appends a redacted trace to `lua-error.log` in the LÖVE save directory (`love.filesystem.getSaveDirectory()`). The on-screen error overlay includes a hint pointing at that file. Logs rotate to `lua-error.log.1` when the active file exceeds 32 KiB. ROM/save bytes and non-printable data are stripped — never commit or share logs that might contain private paths without reviewing them first.

## Native crash triage (love-nx / Atmosphère)

love-nx native faults land under the console’s `crash_reports/` folder on SD (reachable via the same MTP workflow as game deploys).

1. **Collect** — DBI → `Run MTP responder`; copy `sdmc:/crash_reports/*.bin` (or the dated subfolder) to the Mac. Do **not** remove the microSD card.
2. **Redact** — delete any attached screenshots or notes that mention ROM filenames, save paths, or private hashes before sharing logs publicly.
3. **Symbolize** — use the **pinned** `love.elf` from `.bazinga/love-nx/11.5-nx1/` that matches `build-info.json` / `scripts/switch/love-nx-11.5-nx1.sha256`. Never use a “latest” download.

   ```bash
   # Example: aarch64-none-elf-addr2line from devkitPro
   aarch64-none-elf-addr2line -e .bazinga/love-nx/11.5-nx1/love.elf -f -C 0xADDRESS_FROM_CRASH_REPORT
   ```

4. **Correlate** — compare `gitCommit` / `loveNxTag` from embedded `build-info.json` with the operator’s hardware notes.

If `addr2line` cannot resolve an address, archive the crash `.bin` with the exact `love.elf` SHA-256 used for the build — addresses are only meaningful against that ELF.

## P0 / P1 hardware matrix (ADR §9)

Operator evidence lives in `docs/switch-hardware-evidence.md`. **Do not invent passes** for rows that require hardware not yet run.

| ID | Requirement | Status | Evidence |
| -- | ----------- | ------ | -------- |
| P0-0a–f | love-nx pin, probe, MTP, title override | **pass** | Phase 0 checklist above; T4 |
| P0-1a–d | Unpatched launcher boot + Joy-Con nav | **pass** | T4 / `docs/switch-hardware-evidence.md` |
| P0-02 | MTP inbox import path shown | **pass** | T12 |
| P0-03 | Rescan imports ROM | **pass** | T12 |
| P0-04 | Canonical hash routes version | **pass** | T12 |
| P0-05 | Source dump retained in inbox | **pass** | T12 |
| P0-06 | Play reaches game after import | **pass** | T12 |
| P0-07 | Joy-Con launcher navigation | **pass** | T16 @ `2699c9a` |
| P0-08 | Joy-Con gameplay (incl. naming A/B) | **pass** | T16 @ `2699c9a` |
| P0-09 | Save survives quit + reopen | **pass** | T19 |
| P0-10 | ≥10 suspend cycles, no stuck input/dup audio | **pass** | T19 (operator 2026-08-01) |
| P0-12 | Fused NRO boots without adjacent `game.love` | **pass** | T24 — `docs/switch-hardware-evidence.md` |
| P0-14 | Fused NRO MTP round-trip SHA-256 | **pass** | T24 — first artifact `b019e2e8…` @ `6fb5602` (redeploy after Blue fix) |
| P0-15 | Replace NRO only; saves persist | **pass** | T24 — operator NRO-only update keeps saves |
| P1-01 | Docked vs handheld spot-check | **deferred** | Not exercised on OLED dock yet |
| P1-02 | Applet Mode documented unsupported | **pass** | Title override required; Album path not validated |
| P1-03 | Long-play soak (≥30 min) | **deferred** | No soak session recorded |
| P1-04 | Reboot persistence | **pass** | T19 |
| P1-05 | Audio resume after suspend | **pass** | T19 (no dup audio reported) |

## Upstream contribution outline (ADR §11)

Split the eventual upstream PR into three reviewable slices. Each PR must declare: **no ROM/save bytes committed**, **love-nx pin with manifest checksums**, **hardware-tested rows listed**, **Applet Mode unsupported**, **network/updater disabled on NX**.

### PR 1 — Platform + import (`platform/import`)

- `src/core/Platform.lua`, `conf.lua` NX branch
- `src/import/RomImporter.lua` (NX flags, inbox, scan, shell/updater gates)
- Tests: `tests/platform_nx_*`, `tests/rom_importer_nx_*`
- Docs: inbox/MTP import sections only

### PR 2 — Input + lifecycle (`input/lifecycle`)

- `src/core/GamepadMap.lua`, `Input.lua`, `main.lua` focus/joystick hooks
- `src/debug/SwitchDiagnostics.lua` (opt-in probe + error log)
- Tests: input/diagnostics suites
- Docs: controller mapping, suspend/audio notes

### PR 3 — Build + docs (`build/docs`)

- `scripts/pack_love.sh`, `scripts/build_switch.sh`, `scripts/switch/*`
- `assets/switch/icon.jpg`, `docs/switch-development.md`, hardware evidence templates
- Gates: `pack_love.sh --dry-run`, `verify_payload.sh --self-test`, fused build script (devkitPro host)

**Pre-merge checklist (all PRs):**

- [ ] Manifest `scripts/switch/love-nx-11.5-nx1.sha256` filled; binaries not in git
- [ ] `verify_payload.sh` rejects generated cache / ROM / `.sav` / `.bak`
- [ ] P0 matrix rows marked pass only with linked hardware evidence
- [x] Fused NRO P0-12/14/15 pass with T24 evidence (`docs/switch-hardware-evidence.md`)
- [ ] Updater / remote mod download hidden on NX (`networkValidated == false`)

