param(
    [string]$Manifest = (Join-Path $PSScriptRoot "..\third_party\manifest.json")
)

$ErrorActionPreference = "Stop"

$manifestPath = (Resolve-Path $Manifest).Path
$thirdPartyRoot = Split-Path -Parent $manifestPath
$metadata = Get-Content -Raw $manifestPath | ConvertFrom-Json

foreach ($file in $metadata.files) {
    $path = Join-Path $thirdPartyRoot $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing UWP dependency: $($file.path)"
    }

    $stream = [System.IO.File]::OpenRead($path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha256.ComputeHash($stream)
            $actual = [System.BitConverter]::ToString($hash).Replace("-", "")
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
    if ($actual -ne $file.sha256) {
        throw "UWP dependency hash mismatch: $($file.path)"
    }
}

Write-Host "Verified $($metadata.files.Count) UWP dependency files."
