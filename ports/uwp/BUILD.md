# Gen1Recomp Xbox UWP build notes

This is the Xbox Dev Mode package for Gen1Recomp.

The rough shape is:

- `Gen1RecompUWP.exe` starts LÖVE through SDL's WinRT wrapper
- [love-xbox-uwp](https://github.com/caorthann-celt/love-xbox-uwp) provides the LÖVE 11.5 UWP backend and LuaJIT
- SDL2 is built from the copy already carried by Gen1Recomp
- ANGLE provides OpenGL ES over D3D11
- vcpkg provides the audio, font, video, and compression libraries

## What You Need

The tested toolchain is:

- Visual Studio 2022 17.14
- MSVC v143 x64/x86 build tools
- C++ Universal Windows Platform tools
- Windows 11 SDK `10.0.26100.0`
- CMake 3.24 or newer
- Git
- vcpkg with the `x64-uwp` triplet

Use Visual Studio Installer to add **Universal Windows Platform development**, the v143 C++ tools, CMake tools for Windows, and Windows SDK `10.0.26100.0`.

## Checkouts

Keep the game, LÖVE backend, and vcpkg in separate folders. From the parent of the existing Gen1Recomp checkout:

```powershell
git clone --branch gen1recomp --single-branch `
  https://github.com/caorthann-celt/love-xbox-uwp.git `
  love-xbox-uwp
git clone https://github.com/microsoft/vcpkg.git vcpkg
```

The LÖVE checkout must stay on the `gen1recomp` branch.

## vcpkg

Bootstrap vcpkg and install the UWP libraries used by LÖVE:

```powershell
Set-Location vcpkg
./bootstrap-vcpkg.bat
./vcpkg.exe install `
  freetype:x64-uwp `
  openal-soft:x64-uwp `
  libtheora:x64-uwp `
  libvorbis:x64-uwp `
  libogg:x64-uwp `
  zlib:x64-uwp
Set-Location ..
```

## Environment

Set the three build roots from the parent folder:

```powershell
$env:LOVE_UWP_ROOT = (Resolve-Path './love-xbox-uwp').Path
$env:VCPKG_ROOT = (Resolve-Path './vcpkg').Path
$gameRoot = (Resolve-Path './Gen1Recomp-UWP').Path
```

## Build SDL2

Start from a Visual Studio 2022 UWP developer prompt, or initialize `VsDevCmd.bat` for x64 UWP. Then build and install SDL2:

```powershell
Set-Location "$gameRoot\ports\uwp"
./scripts/build-sdl2-angle.ps1
$env:UWP_SDL2_ANGLE_ROOT = (Resolve-Path './build/sdl2-install').Path
```

## Build LÖVE

Configure the backend once, then build the Release libraries and DLLs:

```powershell
cmake -S $env:LOVE_UWP_ROOT -B "$env:LOVE_UWP_ROOT/build/uwp-x64-angle" `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_SYSTEM_NAME=WindowsStore -DCMAKE_SYSTEM_VERSION=10.0 `
  "-DCMAKE_TOOLCHAIN_FILE=$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-uwp `
  "-DLOVE_UWP_SDL_ROOT=$env:UWP_SDL2_ANGLE_ROOT" `
  -DLOVE_UWP_LUAJIT=ON -DLOVE_UWP_ANGLE=ON

cmake --build "$env:LOVE_UWP_ROOT/build/uwp-x64-angle" `
  --config Release --parallel
```

## Build the MSIX

Build the game package from `ports/uwp`:

```powershell
Set-Location "$gameRoot\ports\uwp"
cmake --preset uwp-release
cmake --build --preset uwp-release
```

The build creates `gen1recomp.love`, links the UWP host, and stages LÖVE, LuaJIT, SDL2, ANGLE, and the vcpkg runtime DLLs.

## Build Output

The Release package lands under:

```text
ports\uwp\build\release\AppPackages\Gen1RecompUWP
```
