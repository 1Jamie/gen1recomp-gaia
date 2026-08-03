# Install Gen1Recomp on Nintendo Switch

Every GitHub Release that includes Switch support ships a fused homebrew
binary: `gen1recomp-*-switch.nro`. Copy it to your microSD, launch with
**title override**, then import your own legal `.gb` ROM.

> You need a console that can run Switch homebrew (custom firmware / hbmenu).
> This project does not help you set that up. Tracks issue
> [#531](https://github.com/bryanthaboi/gen1recomp/issues/531).
> Hardware: **OLED** validated by the porter; **V1 / Erista** boot confirmed
> by the community. Lite and other setups welcome more reports.
> See [switch-development.md](switch-development.md) for limitations.

Prefer building from source? See [switch-build.md](switch-build.md).

Port by [andrewqsantos](https://github.com/andrewqsantos). Community testing
help from [booshankles](https://github.com/booshankles).

## 1. Download the NRO

1. Open
   [Releases](https://github.com/bryanthaboi/gen1recomp/releases).
2. Download `gen1recomp-*-switch.nro` for the version you want.
   (Optional: the matching `*.nro.sha256` sidecar if you want to verify the
   download.)

## 2. Copy it to the microSD

Put the file here on the SD card:

```text
sdmc:/switch/gen1recomp/gen1recomp.nro
```

(or keep the versioned name under `sdmc:/switch/gen1recomp/` — hbmenu will
list it either way).

Any method that lands the file on the SD is fine: **MTP** (DBI → Run MTP
responder + a client), **direct SD** (Hekate UMS or a card reader), or **FTP**.
Exit MTP / unmount / stop FTP cleanly before launching. Step-by-step for
macOS, Linux, and Windows: [switch-transfer.md](switch-transfer.md).

## 3. Launch with title override

**Applet Mode is not supported** for this game (not enough memory).

1. On the Switch HOME menu, highlight any installed title.
2. Hold **R** and launch that title — this opens hbmenu with full memory
   (title override).
3. From hbmenu, open `gen1recomp`.

Do **not** launch from the Album applet path for normal play.

## 4. Import your ROM

This project ships **no** game data. On first launch:

1. Put your own legally obtained Pokémon Red or Blue `.gb` into the ROM
   inbox under the game’s save directory (`imports/` — the launcher shows
   the live path).
2. Use **Scan again** on the Red/Blue tab if you add the
   file after the first open.

Saves live in the LÖVE save directory and **persist across NRO updates** —
you can replace only the `.nro` and keep your progress.

## Controls

### Gameplay

| Control | Action |
| ------- | ------ |
| D-pad / left stick | Move |
| **A** | Confirm |
| **B** | Cancel |
| **+** (Start) | Start |
| **−** (Select) | Select |
| **R** (no Select held) | Cycle game speed up |
| **L** (no Select held) | Cycle game speed down |

### Launcher

| Control | Action |
| ------- | ------ |
| D-pad / left stick | Move virtual cursor |
| **A** | Click at cursor |
| **L** / **R** | Previous / next tab |
| **Start** / **Select** | Play if a ROM is ready; otherwise Choose ROM |

### System

| Control | Action |
| ------- | ------ |
| Hold **R** on HOME, then open from hbmenu | Title override (full memory) |

## Community mods (VoxelMod)

Mods install from a zip inbox (same transfer methods as ROMs):

1. Copy a release `.zip` into the save-dir **`imports/mods/`** path the
   launcher shows (MTP / SD / FTP — [switch-transfer.md](switch-transfer.md)).
2. In the launcher, open **MODS** → **Scan again** → enable the mod →
   **Play**.

Remote **FIND MODS** / GitHub download stays **off** on Switch. Do not put
mod zips into git.

Example: [DramaticShape VoxelMod](https://github.com/DramaticShape/DramaticShapeVoxelMod/releases).

### Joy-Con shortcuts (Select + face)

Hold **Select** (−) and press a face/shoulder button. Without Select, A/B stay
normal gameplay confirm/cancel.

| Chord | Same as PC key | Typical effect (stock / VoxelMod) |
| ----- | -------------- | --------------------------------- |
| Select + **A** | `2` | COLORS |
| Select + **B** | `3` | TILT, or VoxelMod **VOXEL** pitch |
| Select + **Y** | `5` | GBC FX, or VoxelMod **V-GRID** |
| Select + **X** | `6` | VoxelMod **T-SHIFT** |
| Select + **L** | `7` | VoxelMod **V-CURVE** |

**3D-BTL** (`8`) and **WATER** (`9`) have no Joy-Con chord — use **OPTIONS**.

### VoxelMod: lighter settings on Switch

VoxelMod is visual-only but expensive. If the Switch stutters, open **OPTIONS**
and prefer:

1. **WATER** → `OFF` (or `SKY`; avoid `FULL`)
2. **3D-BTL** → `OFF`
3. **T-SHIFT** / **V-CURVE** / **V-GRID** → `OFF`
4. **DAYTIME** → `SYNC` (avoid `CYCLE`)
5. Engine **PERFORMANCE** → `LOW` or `BALANCED`

Full tables, chords vs Options rows, and contributor notes:
[switch-development.md](switch-development.md#joy-con-display-chords-select--face)
and
[switch-development.md](switch-development.md#voxelmod-on-switch-options--performance).

## Prefer building it yourself?

Building the fused (or loose) NRO from source is covered in
[switch-build.md](switch-build.md). Copying artifacts and inbox files
(MTP / SD / FTP on macOS, Linux, Windows): [switch-transfer.md](switch-transfer.md).
Status, limitations, and how we tested: [switch-development.md](switch-development.md).
