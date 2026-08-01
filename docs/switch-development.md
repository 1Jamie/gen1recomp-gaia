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
| P0-0a | Fetch love-nx 11.5-nx1; record manifest SHA-256 | | |
| P0-0b | Build `switch-probe.love` per `tools/switch-probe/README.md` | | |
| P0-0c | Assemble loose probe (`game.love` = probe) to `dist/switch/loose/` | | |
| P0-0d | MTP deploy to `1: SD Card/switch/gen1recomp/`; round-trip SHA-256 | | |
| P0-0e | Title override → probe boots; `getOS()` shows `NX` | | |
| P0-0f | Probe lists 1280×720 (or documented dims), save path, gamepad/touch log | | |
| P0-1a | Replace `game.love` with unpatched Gen1Recomp build | | |
| P0-1b | MTP replace `game.love` only; round-trip SHA-256 | | |
| P0-1c | Title override → launcher reaches import screen | | |
| P0-1d | Joy-Con: can navigate launcher (no touch-only) | | |

**Operator:** ___________________ **Date:** __________ **Console:** Switch OLED  
**love-nx tag:** 11.5-nx1 **gen1recomp commit:** ___________________

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

