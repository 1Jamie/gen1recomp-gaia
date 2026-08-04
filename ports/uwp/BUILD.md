# Gen1Recomp Xbox UWP build notes

This is the Xbox Dev Mode package for Gen1Recomp.

The rough shape is:

- `Gen1RecompUWP.exe` starts LÖVE through SDL's WinRT wrapper
- the bundled LÖVE 11.5 UWP backend provides LuaJIT and the Xbox file picker
- the bundled SDL2 runtime contains the Xbox controller mapping
- ANGLE provides OpenGL ES over D3D11
- the bundled runtime contains the audio, font, video, and compression libraries

## What You Need

The tested toolchain is:

- Visual Studio 2022 17.14
- MSVC v143 x64/x86 build tools
- C++ Universal Windows Platform tools
- Windows 11 SDK `10.0.26100.0`
- CMake 3.24 or newer
- Git

Use Visual Studio Installer to add **Universal Windows Platform development**, the v143 C++ tools, CMake tools for Windows, and Windows SDK `10.0.26100.0`.

The x64 UWP dependencies are committed under `third_party`. Their versions,
source revisions, licences, and hashes are recorded in `third_party/manifest.json`.
No additional checkout or environment variable is required for a normal game
build.

## Rebuild the Dependencies

Run the dependency rebuild from `ports/uwp`:

```powershell
.\scripts\rebuild-dependencies.ps1
```

The script clones the pinned SDL2, LÖVE, LuaJIT, vcpkg, depot_tools, and ANGLE
sources when they are missing. It applies the Xbox SDL2 patch, builds the x64
UWP Release libraries, stages the required DLLs, import libraries, headers, and
licences under `third_party`, updates every SHA-256 entry in the manifest, then
builds the Release MSIX.

The generated source checkouts are ignored by Git. A fresh ANGLE sync is about
10 GB, so allow at least 20 GB of free disk space for all sources and build
outputs. Use `-SkipAngle` to retain the existing pinned ANGLE runtime while
rebuilding SDL2, LÖVE, LuaJIT, and the vcpkg libraries. Use `-SkipPackage` when
only the dependency bundle needs to be refreshed.

## Build the MSIX

Build the game package from `ports/uwp`:

```powershell
Set-Location "ports\uwp"
cmake --preset uwp-release
cmake --build --preset uwp-release
```

The build creates `gen1recomp.love`, links the UWP host, and stages LÖVE, LuaJIT, SDL2, ANGLE, and the vcpkg runtime DLLs.

## Build Output

The Release package lands under:

```text
ports\uwp\build\release\AppPackages\Gen1RecompUWP
```
