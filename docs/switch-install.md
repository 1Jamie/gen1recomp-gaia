# Install Gen1Recomp on Nintendo Switch

Every GitHub Release that includes Switch support ships a fused homebrew
binary: `gen1recomp-*-switch.nro`. Copy it to your microSD, launch with
**title override**, then import your own legal `.gb` ROM.

> **Experimental.** The Switch port is still WIP (issue
> [#531](https://github.com/bryanthaboi/gen1recomp/issues/531)). Hardware
> evidence so far is **Switch OLED only** — other models are untested.
> You need a console that can run Switch homebrew (custom firmware / hbmenu).
> This project does not help you set that up.

Prefer building from source? See [switch-build.md](switch-build.md).

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

Any method that lands the file on the SD is fine: **DBI → Run MTP responder**
plus an MTP client, Hekate UMS, a card reader, etc. Exit MTP / unmount cleanly
before launching.

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
2. Use **Procurar novamente** / rescan on the Red/Blue tab if you add the
   file after the first open.

Saves live in the LÖVE save directory and **persist across NRO updates** —
you can replace only the `.nro` and keep your progress.

## Prefer building it yourself?

Building the fused (or loose) NRO from source is covered in
[switch-build.md](switch-build.md). Hardware evidence and contributor MTP
loops: [switch-development.md](switch-development.md).
