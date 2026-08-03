# STATE

## Decisions

### AD-001
- **Decision**: The Nintendo Switch port runs on pinned love-nx (initially tag `11.5-nx1` with SHA-256-pinned `love.nro`/`love.elf`), not a native libnx/NVK rewrite.
- **Reason**: Gen1Recomp already boots under love-nx; video/audio/input/FS are provided; keeps the patch small and upstreamable.
- **Trade-off**: Native defects may later require a love-nx fork; deferred until a minimal probe proves the bug is below Lua.
- **Scope**: All Switch packaging, runtime, and diagnostics work
- **Date**: 2026-08-01
- **Status**: active

### AD-002
- **Decision**: Platform differences are expressed as capability queries in `src/core/Platform.lua` (e.g. `romImportMode`, `canSpawnProcess`, `networkValidated`), never by overloading Android flags for NX.
- **Reason**: Reusing `self.android` would trigger mobile side effects such as deleting a user-copied ROM.
- **Trade-off**: Slightly more refactor in RomImporter than a one-line OS check.
- **Scope**: Import, updater, shell, conf, any `getOS` branching
- **Date**: 2026-08-01
- **Status**: active

### AD-003
- **Decision**: On NX, ROM import uses a writable inbox under `love.filesystem.getSaveDirectory()/imports/` with explicit rescan; no Horizon native file picker.
- **Reason**: love-nx/Gen1Recomp have no usable Switch picker; issue #531 fails before gameplay.
- **Trade-off**: Users must copy dumps via MTP into the shown path.
- **Scope**: RomImporter UI and scan logic on Switch
- **Date**: 2026-08-01
- **Status**: active

### AD-004
- **Decision**: All Mac↔Switch file transfer for NROs, `game.love`, ROMs, logs, and crash reports uses OpenMTP + DBI `Run MTP responder` on `1: SD Card` only (no SD removal, Finder mount, FTP, or `nxlink` artifact transport).
- **Reason**: Keeps the SD in-console and matches the operator’s established workflow; avoids false POSIX assumptions.
- **Trade-off**: Transfers are manual/UI-driven; scripts verify hashes locally, not via `/Volumes`.
- **Scope**: Development runbooks, release deploy, diagnostics collection
- **Date**: 2026-08-01
- **Status**: superseded by AD-009

### AD-005
- **Decision**: Release ships a single fused `gen1recomp.nro` (game.love in romfs); loose `nro`+`game.love` is development-only. Payload must never contain ROM, extracted cache, or saves; CI/release pins love-nx and fails on checksum/payload violations.
- **Reason**: Prevents version skew for players and preserves the project’s legal/technical model.
- **Trade-off**: Fused builds need devkitPro/container (`nacptool`/`elf2nro`).
- **Scope**: `scripts/build_switch.sh`, verify gates, release artifacts
- **Date**: 2026-08-01
- **Status**: active

### AD-006
- **Decision**: On NX, community mod `.zip` import uses a writable inbox at `love.filesystem.getSaveDirectory()/imports/mods/` with explicit rescan; separate from ROM `imports/`.
- **Reason**: Mirrors AD-003 without mixing ROM dumps and mod archives; no Horizon picker.
- **Trade-off**: Users must MTP zips into the shown path; FIND MODS remains off (`networkValidated`).
- **Scope**: RomImporter MODS tab, Switch docs, related NX tests
- **Date**: 2026-08-01
- **Status**: active

### AD-007
- **Decision**: Switch fused packaging uses host `nacptool`/`elf2nro` when available (including via `$DEVKITPRO/tools/bin`), then falls back to Docker using the image pin in `scripts/switch/dkp-docker.image` (override `GEN1_DKP_IMAGE`); CI never compiles love-nx from source.
- **Reason**: Matches contributor decision 2B and Mac self-hosted release (3A) while staying portable when only Docker exists.
- **Trade-off**: Two packaging paths to maintain; Docker bind-mount quirks on some Windows bash setups.
- **Scope**: `scripts/build_switch.sh`, `scripts/switch/build_fused.sh`, release Switch artifact, switch-build docs
- **Date**: 2026-08-01
- **Status**: active

### AD-008
- **Decision**: Switch packaging entrypoints remain bash scripts; supported Windows hosts are Git Bash, MSYS2 (devkitPro), or WSL — not cmd.exe or PowerShell-native rewrites.
- **Reason**: All existing pack/release scripts are bash; a parallel PowerShell stack would diverge.
- **Trade-off**: Windows contributors must use a bash environment (documented in switch-build.md).
- **Scope**: Switch build scripts and docs; any future NX packaging helpers
- **Date**: 2026-08-01
- **Status**: active

### AD-009
- **Decision**: Canonical Switch file transfer for NROs, loose `game.love`, ROM inbox, mod zips, logs, and crash pulls is any method that lands bytes at the documented SD / save-dir paths: **MTP** (e.g. DBI `Run MTP responder` + an MTP client), **direct SD** (Hekate UMS and/or physical microSD reader), or **FTP** (any Switch-side FTP homebrew that exposes the SD). macOS + OpenMTP is one documented example, not the product contract. **`nxlink` / hbmenu netloader remains deferred** — not a supported path yet (future contributor fast-loop only).
- **Reason**: Contributors on Linux/Windows (and Mac users who prefer UMS/FTP) must not be blocked by an OpenMTP-only narrative; destinations matter, not the host tool.
- **Trade-off**: More transfer recipes to maintain; FTP/SD details stay destination-first with example apps only. No automated push scripts in this decision.
- **Scope**: Switch transfer/install/development docs, contributor runbooks, future deploy tooling decisions
- **Date**: 2026-08-01
- **Status**: active

### AD-010
- **Decision**: Switch CI mirrors the iOS safety net: path-gated offline selftest on `ubuntu-latest` for all repos (forks included); fused `--fetch --fused` + artifact `gen1recomp-switch-nro` only on the canonical repo (`bryanthaboi/gen1recomp`) self-hosted Mac runner; PR artifact comment mirrors iOS (`switch-build-result`); release Switch remains a hard-fail gate (no `continue-on-error`).
- **Reason**: Catch packaging regressions before merge without requiring Switch toolchain on hosted runners for forks; keep ship integrity on `main` while giving maintainers a downloadable fused NRO on path-gated PRs.
- **Trade-off**: Extra self-hosted Mac CI when Switch paths change on the canonical repo; forks never get a fused CI artifact.
- **Scope**: `.github/workflows/ci.yml`, `switch-artifact-comment.yml`, `release.yml` Switch step, Switch CI docs
- **Date**: 2026-08-02
- **Status**: active (amended by AD-011 for fork→canonical PRs)

### AD-011
- **Decision**: Switch fused CI (`switch-build`) runs on the canonical self-hosted Mac only when the workflow head is the canonical repo: same-repo push/PR. Fork→canonical pull requests skip Switch fused (ubuntu selftest still runs). iOS `ios-build` eligibility is unchanged by this decision.
- **Reason**: Avoid executing untrusted fork head packaging scripts on the self-hosted Mac while keeping offline Switch verification for external PRs.
- **Trade-off**: Reviewers do not get a Switch NRO artifact on fork PRs; they still get selftest + (when iOS paths change) iOS artifacts as before.
- **Scope**: `.github/workflows/ci.yml` `switch-build` `if:`, Switch CI docs
- **Date**: 2026-08-02
- **Status**: active

### AD-012
- **Decision**: On NX, raw Gen1 `.sav` import uses per-game inboxes at `love.filesystem.getSaveDirectory()/imports/saves/{red,blue,yellow}/` with **Import save** scanning only the active tab’s folder; export writes `exports/{red,blue,yellow}/gen1recomp-<game>-<slot>.sav` and surfaces an MTP path notice (no `openURL`). After success the live `.sav` is retired to `*.sav.imported` and hashed in that folder’s `.imported-sha1`. Resilience guards RES-01..11 still apply.
- **Reason**: love-nx has no usable Horizon file picker (AD-003/AD-006); per-game folders make MTP destinations obvious and prevent Red/Blue/Yellow inbox mix-ups. Hash retire blocks slot clones on re-press.
- **Trade-off**: Users must drop `.sav` into the matching game folder; flat `imports/saves/*.sav` is no longer scanned; retired `.imported` files may accumulate until deleted.
- **Scope**: RomImporter SAVE FILES, SaveFileIO export paths, Switch/launcher docs, `tests/rom_importer_nx_saves_inbox_test.lua`
- **Date**: 2026-08-03
- **Status**: active (amended 2026-08-03 — per-game folders + retire/hash)

## Handoff

- **Feature**: switch-save-sav-inbox / `.specs/features/switch-save-sav-inbox`
- **Phase / Task**: Execute **COMPLETE** — Verifier PASS ✅
- **Completed**: T1–T6 + fix `fe4491a`; commits `3c62814` `5d1e7ff` `74f6b68` `4afb54c` `7e0c64c` `8120f11` `fe4491a` `62ef647`
- **In-progress**: none
- **Next step**: Push / include in Switch PR when ready; HW smoke optional (P2)
- **Blockers**: none
- **Branch**: `feat/switch-nx`
- **Report**: `.specs/features/switch-save-sav-inbox/validation.md`
