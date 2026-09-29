# Linux desktop (AppImage / Flatpak)

Releases ship raw AppImages (no zip wrapper) plus an optional Flatpak bundle:

- `gen1recomp-*-linux-x86_64.AppImage`
- `gen1recomp-*-linux-arm64.AppImage` (Raspberry Pi 4/5, Armbian, arm64 VMs)
- `gen1recomp-*-linux.flatpak` (see [linux-flatpak.md](../linux-flatpak.md))

```sh
chmod +x gen1recomp-*-linux-x86_64.AppImage
./gen1recomp-*-linux-x86_64.AppImage
```

```sh
chmod +x gen1recomp-*-linux-arm64.AppImage
./gen1recomp-*-linux-arm64.AppImage
```

Shared troubleshooting (FUSE, curl, portable mode):
[linux-appimage.md](../linux-appimage.md).

LÖVE publishes no aarch64 binary of any kind, so the arm64 artifact compiles
the engine, and SDL2, OpenAL and the codecs, from source inside a Debian
bullseye arm64 container. It needs only glibc 2.29+, libstdc++, freetype and
zlib on the host; OpenGL, X11, Wayland, KMSDRM, ALSA and PulseAudio are all
dlopened, so the same image runs on a full desktop, a Wayland-only session or
a KMSDRM handheld with no X server. Build instructions and the reasoning are
in [linux-arm64-build.md](../linux-arm64-build.md). Other ARM boards:
[linux-arm-sbc.md](../linux-arm-sbc.md).
