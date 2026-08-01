param(
    [string]$Configuration = "Release",
    [string]$WindowsSdkVersion = "10.0"
)

$ErrorActionPreference = "Stop"

$portRoot = Split-Path -Parent $PSScriptRoot
$gameRoot = (Resolve-Path (Join-Path $portRoot "..\..")).Path
$sourceRoot = Join-Path $gameRoot "mobile\android\love\src\jni\SDL2"
$buildRoot = Join-Path $portRoot "build\sdl2"
$installRoot = Join-Path $portRoot "build\sdl2-install"

cmake -S $sourceRoot -B $buildRoot `
    -G "Visual Studio 17 2022" -A x64 `
    -DCMAKE_SYSTEM_NAME=WindowsStore `
    "-DCMAKE_SYSTEM_VERSION=$WindowsSdkVersion" `
    "-DCMAKE_INSTALL_PREFIX=$installRoot" `
    -DSDL_SHARED=ON -DSDL_STATIC=OFF `
    -DSDL_OPENGL=OFF -DSDL_OPENGLES=ON -DSDL_VULKAN=OFF
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --build $buildRoot --config $Configuration --target INSTALL --parallel
exit $LASTEXITCODE
