# Nintendo Switch development (love-nx)

> Fused NRO support for issue [#531](https://github.com/bryanthaboi/gen1recomp/issues/531).
> Releases ship `gen1recomp-*-switch.zip` (SD-ready tree). Console copy is
> extract/merge at microSD root; title override required. See
> [Known limitations](#known-limitations-read-before-reviewing).

**Canonical install / build / transfer docs** (start here unless you need hardware depth):

- Players → [switch-install.md](switch-install.md)
- Builders → [switch-build.md](switch-build.md) (`scripts/build_switch.sh --fetch` downloads the pinned love-nx pair)
- Transfer (MTP / SD / FTP on macOS, Linux, Windows) → [switch-transfer.md](switch-transfer.md)

This document covers what landed, known limitations, how hardware was tested,
vendor layout, build/deploy, and the contributor transfer loop (detail lives in
the transfer runbook).

## Acknowledgments

- **Port / love-nx packaging:** [andrewqsantos](https://github.com/andrewqsantos)
- **Community hardware testing** (Switch V1 / Erista boot): [booshankles](https://github.com/booshankles)
- **Method guidance:** [Dusklight Switch port](https://github.com/HayatoG/dusklight/tree/main/platforms/switch) / love-nx
- **Upstream project:** [bryanthaboi](https://github.com/bryanthaboi) / Gen1Recomp

## Status

| Area | State |
| ---- | ----- |
| Feature | **Available** — playable fused NRO path (issue #531) |
| Runtime | Pinned love-nx **`11.5-nx1`** |
| Product artifact | Releases: SD-ready `gen1recomp-*-switch.zip`; local/PR: fused `.nro`; loose `nro`+`game.love` for iteration |
| Hardware | **OLED** validated (author, title override); **V1 / Erista** boot confirmed (community). Lite, docked soak, and Pro Controller matrices welcome |
| Deploy / install | Releases publish SD-ready zip; **extract/merge at microSD root** (MTP / SD / FTP — [switch-transfer.md](switch-transfer.md)); no `nxlink` path yet |
| Contributor transfer | Documented for **macOS, Linux, and Windows**; OpenMTP on Mac is one example, not the only contract |
| Network features on NX | Self-update / remote mod download **disabled** (`networkValidated == false`) |
| Community help | Welcome — especially HOS / love-nx packaging and broader hardware coverage |

### What landed

- Detect `NX` via `src/core/Platform.lua` without reusing Android flags
- Writable ROM inbox under `getSaveDirectory()/imports/` + “Scan again”
- Joy-Con / gamepad mapping shared by launcher and gameplay (Nintendo A/B UX on NX)
- Launcher L/R tab switch; gameplay L/R game-speed cycle; Select+face display chords
- Focus loss / joystick reconnect recovery; opt-in `switch-debug.txt` diagnostics
- Loose assemble + fused NRO build scripts (`scripts/build_switch.sh`, `scripts/switch/*`)
- Payload gates so ROM / generated cache / saves never enter `game.love`
- Community mod zip inbox at `imports/mods/` (rescan installs; FIND MODS stays network-gated)
- Raw `.sav` inbox at `imports/saves/{red,blue,yellow}/` (**Import save** rescan) + export pull path `exports/{red,blue,yellow}/` (MTP hint; no openURL)
- VoxelMod OPTIONS + Switch performance tips documented (WATER / 3D-BTL / extras)
- Hardware evidence for Phase 0 probe, ROM import, naming A/B, save/suspend, fused NRO — see `docs/switch-hardware-evidence.md`
- Path-gated CI selftest + canonical fused PR artifact; release Switch hard-fail
- Save editor pad/touch input (virtual cursor, A click, B close) — see `tools/save-editor/README.md`

### Known gaps / welcome contributions

- Docked vs handheld soak, long-play soak (≥30 min)
- Switch Lite and fuller Pro Controller / third-party pad matrices
- Applet Mode remains unsupported by design (title override required)
- `nxlink` / netloader contrib fast-loop (deferred — see [switch-transfer.md](switch-transfer.md))

Transfer runbooks for Linux/Windows (and SD/FTP alternatives) are in
[switch-transfer.md](switch-transfer.md). VoxelMod OLED smoke is **pass** —
see NXMOD-12 in [switch-hardware-evidence.md](switch-hardware-evidence.md).

## Design references (Dusklight)

This work borrowed method — not the native stack — from the [Dusklight Switch port](https://github.com/HayatoG/dusklight/tree/main/platforms/switch), especially [`LESSONS_AND_REUSE.md`](https://github.com/HayatoG/dusklight/blob/main/platforms/switch/LESSONS_AND_REUSE.md):

| Dusklight lesson | How Gen1Recomp applied it |
| ---------------- | ------------------------- |
| Emulators hide Tegra failures | Gate milestones on **real OLED hardware**, not Ryujinx/Yuzu alone |
| Prove the lower layer first | `tools/switch-probe` before full launcher |
| Know which binary ran | Embedded `build-info.json` (commit / love-nx tag) |
| Cap continuous logs | Opt-in diagnostics, ≤1 Hz flush; Lua error log rotation |
| Crash symbolization needs the exact ELF | Keep pinned `love.elf` with the NRO under test |
| Full memory matters | Title override; Applet Mode is not the validation path |
| Do not treat SD FS like desktop POSIX | Lua stays on `love.filesystem`; inbox + MTP for user files |
| Isolate platform code | Capability module instead of Android flag overload |
| NVK / WSI / `audren` stacks | **Not** copied — love-nx already supplies video/audio/input/FS |

The packaging goal matches Dusklight’s **single self-contained `.nro`**; contributor transfer stays multi-host (not Mac-only).

## Known limitations (read before reviewing)

1. **Transfer is manual and multi-method.** Runtime only needs files under the LÖVE save directory / NRO install folder. Use MTP, direct SD, or FTP per [switch-transfer.md](switch-transfer.md). macOS + OpenMTP is a documented example for OLED evidence — not “Switch requires a Mac.”
2. **Deploy is manual.** There is no automated push to the console and no `nxlink` path yet. Operators build locally, transfer files, then title-override launch.
3. **Hardware coverage.** Author P0/P1 pass rows were recorded on one Switch OLED; Switch V1 boot was confirmed independently. Treat Lite, docked soak, and other hosts as unknown until someone re-runs the checklist.
4. **No ROM/save/mod zip bytes in git.** Legal dumps and third-party mods stay on the console (or local untracked folders).
5. **AppleDouble sidecars** (`._*`) from some MTP clients can break zip/ROM/`.sav` scans — the launcher skips hidden `.*` names (including `._*.sav`); still prefer clean copies.

## How we tested

| Layer | What | Where |
| ----- | ---- | ----- |
| Unit / headless | Platform NX flags, RomImporter inbox, dual-path input, mod zip inbox, save `.sav` inbox, display chords, payload/self-tests | `tests/*`, `scripts/test.sh` |
| Switch CI / packaging | Path-gated offline selftest (`selftest_build_switch.sh`, `verify_payload.sh --self-test`, `switch_ci_workflows_test.lua`); canonical fused PR artifact | `.github/workflows/ci.yml`, [switch-build.md](switch-build.md) § CI and release |
| Probe on hardware | `getOS()==NX`, 1280×720, save path, Joy-Con events | `tools/switch-probe` → OLED |
| Integration on hardware | MTP inbox ROM import, Play Red/Blue, naming A/B, quit/reopen save, suspend×10, reboot, fused NRO alone + NRO-only update | `docs/switch-hardware-evidence.md` |
| Community hardware | Switch V1 / Erista boot with prebuilt NRO | [booshankles](https://github.com/booshankles) — see evidence log |
| Known gaps | Docked soak, ≥30 min long-play, Lite, automated/`nxlink` deploy | Matrix deferred / absent rows |

Operator evidence must stay in `docs/switch-hardware-evidence.md`. **Do not invent passes** for hardware not run.

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

Preferred (automated checksum verify):

```bash
scripts/build_switch.sh --fetch
```

That downloads pinned `love.nro` + `love.elf` into `.bazinga/love-nx/11.5-nx1/`
and checks them against `scripts/switch/love-nx-11.5-nx1.sha256`. See
[switch-build.md](switch-build.md) for the full mode glossary.

Manual fallback:

1. Open the [11.5-nx1 release](https://github.com/retronx-team/love-nx/releases/tag/11.5-nx1) and download `love.nro` and `love.elf`.
2. Create the directory: `mkdir -p .bazinga/love-nx/11.5-nx1`
3. Move both files into that directory.
4. Confirm checksums match the manifest:

   ```bash
   shasum -a 256 .bazinga/love-nx/11.5-nx1/love.nro \
     .bazinga/love-nx/11.5-nx1/love.elf
   ```

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

## Transfer & deploy (current contributor loop)

Detail for **macOS / Linux / Windows** and **MTP / SD / FTP** lives in
[switch-transfer.md](switch-transfer.md). Summary:

| Layer | Intent |
| ----- | ------ |
| **Runtime / players** | Extract the release zip at microSD root (`switch/gen1recomp/`) and land ROMs/mods under the save-dir inboxes. The game does not hard-depend on OpenMTP or macOS. |
| **Contributor loop** | Manual copy via MTP (DBI responder), direct SD (Hekate UMS / reader), or FTP. Fully manual — no CI deploy, no `nxlink` yet. |

The Mac + OpenMTP steps that remain below are the **OLED evidence reproduction** path; prefer the transfer runbook for day-to-day contrib on other hosts.

**Still avoided for routine evidence** (keeps SD handling honest):

- Treating `nxlink` / netloader as the release deploy story (deferred)
- DBI `MicroSD install` / `NAND install` / NSP-style virtual folders for the `.love`/`.nro` pair

If MTP fails: check cable, USB port, DBI state, and that only one MTP client holds the device — then retry or switch to SD/FTP. Do not silently rewrite evidence using an untested path and claim parity with recorded SHA-256 round-trips.

### Manual deploy checklist (today)

1. Build on the contributor host (`scripts/build_switch.sh --loose` or fused).
2. Close Gen1Recomp on the Switch; open DBI → `Run MTP responder`.
3. Copy artifacts with your MTP client into `1: SD Card/switch/gen1recomp/` (and ROMs/mods into the save-dir inboxes when needed).
4. Wait for the transfer queue; refresh; optionally round-trip SHA-256 on first artifacts of a type.
5. Exit MTP; launch via **title override** (hold **R** on a title → hbmenu, not Applet Mode).

## OpenMTP + DBI transfer (loose build, Mac evidence example)

Full multi-OS / multi-method steps: [switch-transfer.md](switch-transfer.md).
The numbered Mac loop below reproduces the OLED evidence path.

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

**Operator:** Andrew **Date:** 2026-08-01 **Console:** Switch OLED only  
**Deploy:** manual Mac + OpenMTP + DBI MTP (not automated)  
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
| `gamepadpressed` | `start` / `back` | Start / Select (+ / −) |
| `gamepadpressed` | Right / left shoulder (no Select) | Cycle game speed up / down (same as PC hotkey `1` / speed-down path) |
| `joystickpressed` (raw) | only if **not** `isGamepad()` | face/menu fallback |
| `joystickpressed` (raw) | `#1` / `#2` on NX | Nintendo B / A → GB B / A |
| `joystickpressed` (raw) | `#9` / `#10` | Select / Start (− / +) |

**Nintendo UX on Switch:** physical A confirms, physical B cancels (explicit NX remap of SDL face labels).

**Launcher extras** (`RomImporter`): physical **A** clicks at the virtual cursor; **L** / **R** switch tabs; **Start** / **Select** start Play when a ROM is ready (else open Choose ROM). D-pad / left stick move the virtual cursor.

**Dual-path rule:** love-nx emits both `gamepadpressed` and `joystickpressed` for Joy-Con. When `joystick:isGamepad()` is true, Input and RomImporter **ignore raw** face/menu so NamingScreen does not see A+B in one frame. `NamingScreen` also prefers A over B if both edges still fire.

Implementation: `src/core/GamepadMap.lua` (`NX_RAW_*`, `ignoreRawForJoystick`, `displayChordDigit`), `src/core/Game.lua` (shoulder speed), `src/import/RomImporter.lua` (launcher tabs). Launcher and gameplay share the same converter.

## Mod zip inbox (NX)

Community mods install from a **separate** MTP inbox (not mixed into the ROM `imports/` scan):

| Item | Value |
| ---- | ----- |
| Save-relative path | `imports/mods/` |
| MTP destination | `1: SD Card/<save identity>/imports/mods/` (see launcher notice for the live `getSaveDirectory()` path) |
| Candidates | `*.zip` only |
| Rescan | MODS tab → **Scan again** (installs each zip via `LauncherMods.installZip`; source zips are retained on success and failure) |
| FIND MODS | Remains network-gated / hidden on NX (`networkValidated == false`) |

Do **not** commit third-party mod zip bytes into git. Drop the zip over MTP, rescan, enable in MODS, then Play.

**MTP tip (esp. macOS clients):** OpenMTP/Finder often creates AppleDouble sidecars named `._Something.zip` / `._cart.gb` / `._foo.sav`. Those are not real archives, ROMs, or saves — the launcher ignores hidden `.*` names under `imports/`, `imports/mods/`, and `imports/saves/<game>/`. If install still fails with “could not be opened” / “not a zip file”, delete any `._*` under the inbox and confirm the real zip starts with the `PK` magic (re-copy the release asset if unsure). This is a host-side annoyance of the current manual MTP loop, not something players should need forever.

**Example zip source:** [DramaticShape VoxelMod releases](https://github.com/DramaticShape/DramaticShapeVoxelMod/releases) — download a release `.zip`, copy into `imports/mods/`, rescan, enable. Player-facing install + performance tips: [switch-install.md](switch-install.md#community-mods-voxelmod).

## Save `.sav` inbox (NX)

Raw Gen1 battery images use a **separate** MTP inbox (not mixed into ROM `imports/` or mod `imports/mods/`):

| Item | Value |
| ---- | ----- |
| Save-relative path | `imports/saves/red/`, `imports/saves/blue/`, `imports/saves/yellow/` |
| MTP destination | `1: SD Card/<save identity>/imports/saves/<game>/` (see launcher notice for the live `getSaveDirectory()` path) |
| Candidates | non-hidden `*.sav` only in **that game’s** folder |
| Rescan | SAVE FILES → **Import save** on the matching game tab (scans only that folder) |
| After success | Retire to `*.sav.imported` + append content hash to `imports/saves/<game>/.imported-sha1` |
| Exports | **Export save** writes under `exports/<game>/gen1recomp-<game>-<slot>.sav`; NX shows an MTP path notice (no `openURL`) |

Do **not** commit `.sav` bytes into git. Drop the file into the matching game folder over MTP, press **Import save** on that tab, then play. Pull exports from `exports/<game>/`.

**MTP tip:** the same AppleDouble `._*.sav` rule applies — see the mod inbox tip above.

## Joy-Con display chords (Select + face)

PC digit hotkeys for COLORS / TILT / pipelines have Joy-Con equivalents. Hold **Select** (`back` / −) and press a face/shoulder button; the engine runs the same path as `Game:keypressed` for that digit (including `writeOptions` / Pipelines parity).

| Chord (Nintendo UX) | Engine key | Stock engine | With DramaticShape VoxelMod |
| ------------------- | ---------- | ------------ | --------------------------- |
| Select + **A** | `2` | COLORS cycle | COLORS cycle (unchanged) |
| Select + **B** | `3` | TILT / perspective | **VOXEL** pitch (OFF → 15 → 35 → 50 → 75 → OFF); mod hides stock TILT |
| Select + **Y** | `5` | GBC FX | **V-GRID** ON/OFF (mod hides stock GBC FX) |
| Select + **X** | `6` | (pipeline) | **T-SHIFT** OFF → 1 → 2 → 3 → OFF (tilt-shift blur) |
| Select + **L** (left shoulder) | `7` | (pipeline) | **V-CURVE** OFF → 1 → 2 → 3 (horizon bend) |

There is **no** Joy-Con chord for VoxelMod **`8` (3D-BTL)** or **`9` (WATER)** — change those in **OPTIONS** (see below).

Without Select held, face buttons keep normal GB A/B gameplay mapping (no accidental color/tilt cycles). The **Options** menu remains available for the same settings — chords are optional shortcuts, not the only path.

On NX, A/B chords resolve through the Nintendo UX face remap so physical **A** → key `2` and physical **B** → key `3` match this table.

## VoxelMod on Switch (options + performance)

[DramaticShape VoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod) is a heavy presentational mod (3D overworld, optional water shader, 3D battles). It runs on Switch OLED smoke (NXMOD-12), but weaker handheld budgets benefit from dialing options down. Everything below is **purely visual** — no gameplay rules change.

### VoxelMod OPTIONS rows

| OPTIONS row | PC key | Values | Notes |
| ----------- | ------ | ------ | ----- |
| **VOXEL** | `3` / Select+B | OFF → 15 → 35 → 50 → 75 → OFF | Camera pitch over the diorama |
| **V-GRID** | `5` / Select+Y | OFF / ON | One-pixel wireframe on every voxel |
| **T-SHIFT** | `6` / Select+X | OFF → 1 → 2 → 3 → OFF | Miniature tilt-shift blur |
| **V-CURVE** | `7` / Select+L | OFF → 1 → 2 → 3 | Bend the world over the horizon |
| **3D-BTL** | `8` (Options only) | ON / OFF | Fight on the map instead of a white field; **ON by default**, independent of VOXEL pitch |
| **WATER** | `9` (Options only) | FULL / SKY / OFF | Waves + reflections. **FULL** = screen-space ray march (heaviest); **SKY** = sky/sun/moon/cast only; **OFF** = disable water shader |
| **BACK SPRITES** | Options only | OFF / ON | Own Pokémon as classic back sprite on the battle menu; only shown while **3D-BTL** is on |
| **DAYTIME** | Options only | SYNC / DAY / NIGHT / DUSK / DAWN / CYCLE | Outdoor lighting; held at SYNC (and off the menu) while VOXEL is FULL |

While VoxelMod is installed it **hides and forces off** the engine’s **TILT** and **GBC FX** rows (those conflict with the diorama). Uninstall restores them to their last saved values.

Upstream control table: [DramaticShape README](https://github.com/DramaticShape/DramaticShapeVoxelMod/blob/master/README.md).

### Suggested Switch profile (smoother handheld)

Priority order if the game feels heavy with VoxelMod enabled:

1. **WATER** → **`OFF`** (or at most **`SKY`**; avoid **`FULL`** on Switch)
2. **3D-BTL** → **`OFF`** (biggest win after water; battles go back to the stock field)
3. **T-SHIFT** → **`OFF`**
4. **V-CURVE** → **`OFF`**
5. **V-GRID** → **`OFF`**
6. **BACK SPRITES** → **`OFF`** if 3D-BTL is still on
7. **DAYTIME** → prefer **`SYNC`** (or a fixed time); avoid **`CYCLE`**

Keep **VOXEL** at a modest pitch (e.g. **35** or **50**) if you want the 3D look without stacking every extra pass.

### Engine PERFORMANCE tier

Separately from the mod, **OPTIONS → PERFORMANCE** clamps the port’s own extras (TILT / GBC FX / survey ZOOM) and can cap FPS. On Switch with VoxelMod, set **PERFORMANCE → LOW** (or **BALANCED**) if the handheld still stutters after the VoxelMod rows above are dialed down. Details: [new-features.md — Performance tier](new-features.md#performance-tier-low-end-devices).

VoxelMod smoke evidence (install + overworld chords): NXMOD-12 in [switch-hardware-evidence.md](switch-hardware-evidence.md). Full soak of every VoxelMod option on OLED is still deferred.

**Opt-in diagnostics:** create an empty `switch-debug.txt` in the save directory; events flush to `switch.log` at ≤1 Hz with build identity (no ROM/save bytes).

**Hardware re-test:** T16 **pass** @ `2699c9a` (naming A=confirm / B=cancel). T19 **pass** (quit/reopen, suspend×10, reboot) — operator 2026-08-01.

**Suspend/resume audio:** after resume, chip music is stopped to avoid duplicate streams; confirm on hardware during P0-09/10 (T19).

## Lua error log (save directory)

On any uncaught Lua error, Gen1Recomp appends a redacted trace to `lua-error.log` in the LÖVE save directory (`love.filesystem.getSaveDirectory()`). The on-screen error overlay includes a hint pointing at that file. Logs rotate to `lua-error.log.1` when the active file exceeds 32 KiB. ROM/save bytes and non-printable data are stripped — never commit or share logs that might contain private paths without reviewing them first.

## Native crash triage (love-nx / Atmosphère)

love-nx native faults land under the console’s `crash_reports/` folder on SD (reachable via the same manual MTP workflow used for game deploys).

1. **Collect** — DBI → `Run MTP responder`; copy `sdmc:/crash_reports/*.bin` (or the dated subfolder) to the contributor host. Prefer keeping the microSD in-console for routine pulls.
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
| — | Switch V1 / Erista boot | **pass** (boot) | Community — [booshankles](https://github.com/booshankles); see evidence log |
| — | Switch Lite / docked soak | **untested** / **deferred** | Welcome contributions |
| — | Automated / `nxlink` deploy | **absent** | Manual MTP / SD / FTP only (AD-009) |
| — | Multi-OS transfer runbooks | **pass** | [switch-transfer.md](switch-transfer.md) |
| — | VoxelMod OLED smoke (NXMOD-12) | **pass** | `docs/switch-hardware-evidence.md` |

## Review guidance

Maintainers may review as one PR or split later. Suggested slices (optional):

Each slice should declare: **no ROM/save bytes committed**, **love-nx pin with manifest checksums**, **hardware-tested rows listed with linked evidence**, **Applet Mode unsupported**, **network/updater disabled on NX**, **deploy still manual** (MTP / SD / FTP; no nxlink yet), **OpenMTP is one example not the sole contract**.

### Slice 1 — Platform + import (`platform/import`)

- `src/core/Platform.lua`, `conf.lua` NX branch
- `src/import/RomImporter.lua` (NX flags, inbox, scan, shell/updater gates)
- Tests: `tests/engine/platform_nx_*`, `tests/engine/rom_importer_nx_*` (ROM-free T2)
- Docs: inbox/MTP import sections only

### Slice 2 — Input + lifecycle (`input/lifecycle`)

- `src/core/GamepadMap.lua`, `Input.lua`, `main.lua` focus/joystick hooks
- `src/debug/SwitchDiagnostics.lua` (opt-in probe + error log)
- Tests: input/diagnostics suites
- Docs: controller mapping, suspend/audio notes

### Slice 3 — Build + docs (`build/docs`)

- `scripts/pack_love.sh`, `scripts/build_switch.sh`, `scripts/switch/*`
- `assets/switch/icon.jpg`, `docs/switch-development.md`, hardware evidence templates
- Gates: `pack_love.sh --dry-run`, `verify_payload.sh --self-test`, fused build script (devkitPro host)

**Pre-merge checklist:**

- [ ] Manifest `scripts/switch/love-nx-11.5-nx1.sha256` filled; binaries not in git
- [ ] `verify_payload.sh` rejects generated cache / ROM / `.sav` / `.bak`
- [ ] P0 matrix rows marked pass only with linked hardware evidence
- [x] Fused NRO P0-12/14/15 pass with T24 evidence (`docs/switch-hardware-evidence.md`)
- [ ] Updater / remote mod download hidden on NX (`networkValidated == false`)

