# UWP dependencies

The ANGLE UWP runtime is committed under `angle`. The package also uses:

- `LOVE_UWP_ROOT`: [caorthann-celt/love-xbox-uwp](https://github.com/caorthann-celt/love-xbox-uwp) on the `gen1recomp` branch.
- `UWP_SDL2_ANGLE_ROOT`: SDL2 built by `scripts/build-sdl2-angle.ps1`.
- `VCPKG_ROOT`: the UWP codec, font, compression, and audio runtimes used by LÖVE.

SDL headers, import library, and DLL must come from the same build. Runtime DLLs stay inside the installed package.
