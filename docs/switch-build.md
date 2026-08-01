# Build the Nintendo Switch NRO — contributor guide

Want to play a release build instead? Download the fused NRO and copy it to
your console — see [switch-install.md](switch-install.md).

This guide is for contributors who build Gen1Recomp for Switch from source.
Hardware evidence, MTP operator loops, and deeper WIP notes live in
[switch-development.md](switch-development.md).

> **Experimental.** Releases may ship a fused `gen1recomp-*-switch.nro`, but
> the port is still WIP (issue
> [#531](https://github.com/bryanthaboi/gen1recomp/issues/531)). Hardware
> evidence so far is **Switch OLED only**.

---

## Prerequisites by OS

All packaging entrypoints are **bash**. On Windows, use Git Bash, MSYS2, or
WSL — not cmd.exe or PowerShell (AD-008).

### macOS / Linux

1. Install [devkitPro pacman](https://devkitpro.org/wiki/devkitPro_pacman).
2. Install Switch tools:

   ```sh
   sudo dkp-pacman -S switch-dev
   ```

3. Ensure `nacptool` and `elf2nro` are on `PATH` (or under
   `$DEVKITPRO/tools/bin` — the fused script prepends that when set).

**Optional:** Install [Docker](https://docs.docker.com/get-docker/) so fused
builds can fall back to the pinned image when native tools are missing.

### Windows (Git Bash / MSYS2 / WSL)

1. Use a bash environment:
   - **MSYS2** with the [devkitPro](https://devkitpro.org/wiki/devkitPro_pacman)
     packages (preferred for native `nacptool`/`elf2nro`), or
   - **WSL** (Ubuntu/etc.) with the Linux pacman flow above, or
   - **Git Bash** for `--fetch` / `--loose`; for `--fused` prefer MSYS2 or
     WSL if Docker bind-mounts from Git Bash paths misbehave.
2. Install `switch-dev` (or rely on Docker fallback — see below).
3. Do **not** expect `scripts/build_switch.sh` to run under cmd/PowerShell.

### What you must install yourself

| You install | Script does **not** install |
| ----------- | --------------------------- |
| bash, git, zip tooling the repo already expects | — |
| `dkp-pacman` + `switch-dev` (native fused) | `dkp-pacman -S …` |
| Docker (optional fused fallback) | Docker Engine |
| A legal `.gb` ROM (to play) | Any ROM or game data |

---

## Mode glossary

`scripts/build_switch.sh` supports three modes (combinable as noted):

| Mode | What it does |
| ---- | ------------ |
| `--fetch` | Downloads pinned **love.nro** + **love.elf** into `.bazinga/love-nx/11.5-nx1/` and verifies SHA-256 against `scripts/switch/love-nx-11.5-nx1.sha256`. |
| `--loose` | Packs `game.love`, copies pinned `love.nro` → `dist/switch/loose/` as `gen1recomp.nro` + `game.love` side by side. Needs the pin. |
| `--fused` | Builds a single `dist/switch/gen1recomp-<ver>-switch.nro` (game in romfs) via `nacptool` + `elf2nro`. Needs the pin + toolchain (native or Docker). |

Rules:

- `--fetch` alone is fine; combine as `--fetch --loose` or `--fetch --fused`.
- `--loose` and `--fused` are **XOR** — pick one packaging path per run.
- `--version X.Y.Z` sets the NACP / filename version (defaults to short git SHA).

### What `--fetch` downloads

Only the two pinned love-nx release assets (`love.nro`, `love.elf`). It does
**not** install:

- devkitPro / `dkp-pacman` / `switch-dev`
- Docker
- ROMs, saves, or mods

---

## Native tools, then Docker

Fused packaging (`scripts/switch/build_fused.sh`):

1. Prefer native `nacptool` + `elf2nro` on `PATH` (or `$DEVKITPRO/tools/bin`).
2. Else fall back to Docker using:
   - `GEN1_DKP_IMAGE` if set, otherwise
   - the image named in `scripts/switch/dkp-docker.image` (default
     `devkitpro/devkita64:latest`).

If neither native tools nor Docker work, the script exits non-zero with
macOS / Linux / Windows / Docker hints and a pointer to this doc.

---

## Example commands

From the repo root:

```sh
# Download pinned love-nx only
scripts/build_switch.sh --fetch

# Loose pair for iteration (fetch + assemble)
scripts/build_switch.sh --fetch --loose

# Single fused NRO for a release-like artifact
scripts/build_switch.sh --fetch --fused --version 0.2.0
```

Outputs land under `dist/switch/` (and `dist/switch/loose/` for loose mode).
The fused path also writes `gen1recomp-<ver>-switch.nro.sha256`.

Offline packaging smoke (no network, no nacptool required):

```sh
bash scripts/switch/selftest_build_switch.sh
bash scripts/switch/verify_payload.sh --self-test
```

---

## Release Mac runner

GitHub Releases build the Switch artifact on the same self-hosted Mac runner
as the other platforms (see `.github/workflows/release.yml`):

```sh
scripts/build_switch.sh --fetch --fused --version "<release version>"
```

The runner must have **native switch-tools** (`nacptool`/`elf2nro`) **and/or
Docker** available. CI does not silently run `dkp-pacman -S`; keep the runner
image/host provisioned per this guide.

---

## Limitations / non-goals

These scripts and this guide do **not**:

- Push files to the console (no MTP / OpenMTP / DBI automation)
- Bundle or download any Pokémon ROM
- Install `dkp-pacman` / `switch-dev` for you
- Provide `nxlink` / netloader deploy
- Validate **Applet Mode** — use title override (hold **R**) for full memory

Player install steps: [switch-install.md](switch-install.md).  
Hardware depth and evidence: [switch-development.md](switch-development.md),
[switch-hardware-evidence.md](switch-hardware-evidence.md).
