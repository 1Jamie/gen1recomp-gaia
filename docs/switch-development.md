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
