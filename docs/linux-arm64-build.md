# Linux arm64 (aarch64) AppImage

Releases ship `gen1recomp-<version>-linux-arm64.AppImage` alongside the
existing x86_64 `gen1recomp-<version>-linux.zip`. It targets 64-bit ARM
desktop Linux: Raspberry Pi 4/5 running Raspberry Pi OS, Armbian and other
SBC distros, arm64 VMs on Apple Silicon, Ampere/Graviton desktops, and the
aarch64 handhelds that run a full distro.

> The Anbernic RG34XXSP has its own PortMaster-style pack
> (`gen1recomp-*-rg34xxsp-stockos64-mod.zip`, see
> [anbernic-rg34xxsp.md](anbernic-rg34xxsp.md)). That one bundles PortMaster's
> LÖVE runtime and expects the device's own SDL; this AppImage is the generic
> desktop-Linux artifact and shares nothing with it but the `game.love`.

## For players

```sh
chmod +x gen1recomp-*-linux-arm64.AppImage
./gen1recomp-*-linux-arm64.AppImage
```

Then use **Import ROM** in the launcher to point it at your own legal Red /
Blue / Yellow cartridge dump, exactly as on every other platform.

If your system has no FUSE (`dlopen(): error loading libfuse.so.2`), either
install it (`sudo apt install libfuse2`) or run without it:

```sh
./gen1recomp-*-linux-arm64.AppImage --appimage-extract-and-run
```

### What the host has to provide

The AppImage bundles LÖVE, SDL2, OpenAL and the audio/video decoders. It
deliberately does **not** bundle the graphics drivers, the audio server
client libraries, or the font stack — those have to come from your system,
because bundled copies would either bypass your GPU driver or disagree with
libraries your desktop already has loaded (see
[Why the font stack is not bundled](#why-the-font-stack-is-not-bundled)).

In practice any arm64 system with a working desktop already satisfies this.
The requirements are glibc 2.29 or newer, plus Mesa/GL, X11 or Wayland,
ALSA or PulseAudio, and freetype/fontconfig — i.e. `libgl1`, `libfreetype6`,
`libfontconfig1`, `libpng16-16`, `libx11-6`.

## For builders

```sh
scripts/build_linux_arm64.sh --version 0.1.0
```

Output:

```
dist/linux-arm64/gen1recomp-<version>-linux-arm64.AppImage
dist/linux-arm64/gen1recomp-<version>-linux-arm64.AppImage.sha256
```

Useful flags: `--game-love PATH` reuses an already-packed payload (CI does
this so every platform ships identical bytes), `--rebuild-image` forces the
builder container to rebuild, `--clean-cache` throws away the pinned
downloads and the compiled LÖVE prefix.

### Requirements

An **aarch64 host** with **docker or podman**. A Raspberry Pi 5 is the
reference machine (a full build takes about 3.5 minutes on one; rebuilds
reuse the cached LÖVE prefix and take seconds). Apple Silicon with Docker
Desktop and GitHub's `ubuntu-24.04-arm` runner both work too.

The script refuses to run on x86_64 rather than falling back to qemu-user
emulation: that path takes hours and has produced miscompiled LuaJIT.

### Why this is not just another `scripts/build.sh` target

`scripts/build.sh linux` downloads LÖVE's official `love-11.5-x86_64.AppImage`,
unpacks its squashfs, drops `game.love` in, and glues it back together. That
trick is not available here — **LÖVE publishes no aarch64 binary at all.** The
11.5 release has win32, win64, macOS, Android, iOS and one x86_64 AppImage,
and that is the entire list.

So this build compiles LÖVE 11.5 from the official `linux-src` tarball and
assembles the AppImage from scratch. Both pinned inputs (the LÖVE source
tarball and the AppImage type-2 runtime) are SHA-256 verified on the host
before the container ever sees them, and the container itself runs with no
network access.

### Why the build happens in a Debian bullseye container

glibc is backward compatible but not forward compatible: a binary linked
against glibc 2.41 will not start on a system with 2.31, and there is no way
to fix that after the fact. Compiling on the oldest base we support is
therefore the only thing that makes one artifact work everywhere.

Bullseye (glibc 2.31) is that base. The resulting binaries actually come out
needing only **glibc 2.29** and **GLIBCXX_3.4.21**, so the AppImage covers
everything from Ubuntu 20.04 and Raspberry Pi OS bullseye through current
trixie.

This is a statement about the *compile environment*, not about where the
artifact runs — building on your own newer distro would silently raise that
floor and strand every user on an older one, with no symptom until they
download it. CI enforces the floor: `linux-arm64-build` fails if the highest
required glibc symbol version climbs above 2.31.

### Why the font stack is not bundled

The dependency walker copies in what LÖVE needs and leaves everything else to
the host. Three categories are excluded, and the third one is subtle enough
to be worth writing down, because it is a real crash that shipped in an early
version of this build:

1. **Driver and session coupled** — GL/EGL/gbm/drm, X11/xcb/Wayland, D-Bus,
   PulseAudio, ALSA, systemd/udev. A bundled `libGL` would bypass Mesa's V3D
   driver on the Pi; a bundled `libpulse` would fight the running sound server.
2. **Loader coupled** — glibc's own pieces cannot be mixed with the host's
   `ld.so`, and `libstdc++`/`libgcc_s` must be at least as new as the compiler
   that built us (bullseye's gcc 10 is older than any supported host's, so the
   host copy always satisfies us).
3. **Shared with the host font stack** — freetype, fontconfig, libpng, brotli,
   zlib.

That third one exists because Debian's `libtheoradec.so.1` is, oddly, linked
against `libcairo.so.2`. LÖVE needs theora for `love.video`, so the host's
cairo gets pulled into our process. The dynamic loader resolves one SONAME
exactly once per process, so a host cairo then binds to whatever
`libfreetype.so.6` *we* bundled:

```
love -> liblove -> libtheoradec -> libcairo (host, new)
                                      `-> FT_Get_Transform -> libfreetype (ours, bullseye 2.10.4)
```

`FT_Get_Transform` arrived in FreeType 2.11, so cairo 1.18 on a trixie host
fails to relocate and the game dies at startup with a symbol lookup error.
Bundling a *newer* freetype only moves the arms race one release along.
Excluding the whole font/compression stack instead makes the process
self-consistent: cairo, fontconfig and freetype all come from one host and
agree with each other, while `liblove` — compiled against 2.10.4 — only ever
asks for symbols every supported host already has.

### CI

Three jobs, path-gated on `scripts/build_linux_arm64.sh`,
`scripts/linux-arm64/`, `scripts/pack_love.sh` and this document:

- **`linux-arm64-selftest`** (`ubuntu-latest`, x86_64) — offline gate. Checks
  the pins are real digests on a dated tag rather than the moving
  `continuous` one, that the Dockerfile still builds on bullseye, that the
  exclude list still classifies known sonames correctly, that AppRun still
  launches `game.love` with `--fused`, and that the host-arch guard actually
  fires. Needs no container and no arm64 machine.
- **`linux-arm64-build`** (`ubuntu-24.04-arm`) — the real build, then extracts
  the artifact and asserts the layout, that every bundled object resolves
  under AppRun's `LD_LIBRARY_PATH`, and that the glibc floor is still ≤ 2.31.
  Uploads the AppImage for 7 days.
- **release** — `linux-arm64` runs on `ubuntu-24.04-arm`, reuses the shared
  `game.love` from the `love-payload` job, and the AppImage is staged and
  published like every other release asset.

Unlike the Switch job, none of this needs secrets or self-hosted hardware, so
it runs on fork PRs too.

### Updating the pins

Both pins live in `scripts/linux-arm64/common.sh`:

- `LOVE_VERSION` / `LOVE_SRC_SHA256` — bumping the LÖVE version invalidates
  the cached prefix automatically (it is keyed by version). Check that
  bullseye still has `-dev` packages new enough for the new release;
  `build_appimage.sh` asserts every optional module actually linked, because
  LÖVE's `configure` exits 0 and silently drops a module when one is missing.
- `APPIMAGE_RUNTIME_TAG` / `APPIMAGE_RUNTIME_SHA256` — always a dated tag
  from [AppImage/type2-runtime](https://github.com/AppImage/type2-runtime/releases).
  The selftest fails the build if this ever points at `continuous`.
