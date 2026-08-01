param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$required = @('main.lua', 'conf.lua', 'tools/rom_manifest.json')
$allowedRoots = @('assets/', 'data/', 'mods/', 'src/', 'tools/rom_manifest')
$forbidden = '(?i)(^|/)(assets/generated|data/generated|build|dist|ports|mobile|tests?)(/|$)|\.(gb|gbc|sav|srm)$'

$tracked = & git -C $source ls-files
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed' }

$entries = $tracked |
    ForEach-Object { $_.Replace('\', '/') } |
    Where-Object {
        $path = $_
        (($required -contains $path) -or ($allowedRoots | Where-Object { $path.StartsWith($_) })) -and
        $path -notmatch $forbidden
    } |
    Sort-Object -Unique

foreach ($path in $required) {
    if ($entries -notcontains $path) { throw "Required game file is missing from archive input: $path" }
}

$parent = Split-Path -Parent $Output
New-Item -ItemType Directory -Force -Path $parent | Out-Null
if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($Output, 'Create')
try {
    foreach ($relative in $entries) {
        $full = Join-Path $source $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Tracked file is missing: $relative" }
        $entry = $archive.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]'2000-01-01T00:00:00Z'
        $input = [System.IO.File]::OpenRead($full)
        $outputStream = $entry.Open()
        try { $input.CopyTo($outputStream) } finally { $outputStream.Dispose(); $input.Dispose() }
    }
} finally {
    $archive.Dispose()
}

Write-Host "Created $Output with $($entries.Count) tracked, ROM-free entries."
