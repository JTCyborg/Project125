$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build"
$outputDir = Join-Path $root "zx_main"

$bootstrapPath = Join-Path $build "neogs_bootstrap.bin"
$firmwarePath = Join-Path $build "neogs_code.bin"
$loaderOutput = Join-Path $outputDir "neoload.bin"
$firmwareOutput = Join-Path $outputDir "neofw.bin"
$includeOutput = Join-Path $outputDir "neogs_files.inc"

foreach ($path in @($bootstrapPath, $firmwarePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing NeoGS binary: $path"
    }
}

[byte[]]$loader = [System.IO.File]::ReadAllBytes($bootstrapPath)
[byte[]]$firmware = [System.IO.File]::ReadAllBytes($firmwarePath)

if ($loader.Length -lt 1 -or $loader.Length -gt 0x0800) {
    throw ("NEOLOAD.C size {0} is outside the supported 1..2048 byte range." -f $loader.Length)
}
if ($firmware.Length -lt 1 -or $firmware.Length -gt 0x4000) {
    throw ("NEOFW.C size {0} exceeds the current single-file 1..16384 byte limit." -f $firmware.Length)
}

[System.IO.File]::WriteAllBytes($loaderOutput, $loader)
[System.IO.File]::WriteAllBytes($firmwareOutput, $firmware)

$lines = @(
    ("NEOLOAD_FILE_SIZE EQU #{0:X4}" -f $loader.Length),
    ("NEOFW_FILE_SIZE EQU #{0:X4}" -f $firmware.Length)
)
[System.IO.File]::WriteAllLines($includeOutput, $lines, [System.Text.Encoding]::ASCII)

Write-Host ("NEOLOAD.C: {0} bytes (standalone bootstrap)" -f $loader.Length)
Write-Host ("NEOFW.C:   {0} bytes (standalone resident firmware)" -f $firmware.Length)
Write-Host "No combined package header or neoprog.C file is generated."
