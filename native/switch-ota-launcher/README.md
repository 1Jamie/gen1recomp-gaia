# Native Switch OTA launcher

In-console updates for Gen1Recomp on Nintendo Switch. This NRO is the **hbmenu
entry** (`gen1recomp.nro`). It checks GitHub Releases quietly (no UI when you
are already up to date or offline). Only if a newer release exists does it show
a **launcher-style screen** (black + RGB rail + project logo + flat A/B
buttons), download the same `gen1recomp-*-switch.zip` used for install, verify
SHA-256 from `sha256sums.txt`, replace **both** `gen1recomp-game.nro` and
`gen1recomp.nro` (matching NACP version for hbmenu/Sphaira), then hand off
with `envSetNextLoad`.

The LÖVE self-updater (`src/update/Check.lua`) stays **disabled** on NX.
Protocol contract (also in Lua): `src/update/SwitchOta.lua`.
NACP icon: `assets/switch/icon.jpg`.

## Layout on microSD

```text
sdmc:/switch/gen1recomp/gen1recomp.nro        ← this launcher
sdmc:/switch/gen1recomp/gen1recomp-game.nro   ← fused LÖVE game
sdmc:/switch/gen1recomp/version.txt          ← installed X.Y.Z
sdmc:/switch/gen1recomp/pokemon-love2d/      ← saves (never touched by OTA)
```

## Host tests (no DEVKITPRO)

```bash
cd native/switch-ota-launcher
make host-test
```

## Switch build (DEVKITPRO)

Needs `DEVKITPRO` with packages roughly:

```bash
(dkp-)pacman -S --needed switch-curl switch-mbedtls switch-zlib switch-zziplib
# or: bash scripts/switch/install_devkitpro_deps.sh
```

```bash
export DEVKITPRO=/opt/devkitpro   # typical
cd native/switch-ota-launcher
make
# → gen1recomp.nro
```

Or from repo root:

```bash
scripts/switch/build_ota_launcher.sh
```

Docker fallback uses the same pin as fused builds (`scripts/switch/dkp-docker.image`).

## Packaging

`scripts/switch/pack_sd_zip.sh GAME_NRO VERSION OUT_ZIP LAUNCHER_NRO` writes both
NROs into the SD zip. That zip is also the OTA download asset (unified).
Manifest: `scripts/switch/ota_launcher.manifest`.

## Status / known gaps

- Zip extraction uses `switch-zziplib` (`ota_unzip.c`) on device.
- OTA replaces launcher + game from the unified zip (NACP versions stay aligned).
- Sphaira HOME forwarders cache metadata until reinstalled (see docs/switch-install.md).
- Install toolchain deps once: `bash scripts/switch/install_devkitpro_deps.sh`
