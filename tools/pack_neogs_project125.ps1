$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build"
$bootstrapPath = Join-Path $build "neogs_bootstrap.bin"
$firmwarePath = Join-Path $build "neogs_code.bin"

if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    throw "Missing NeoGS bootstrap: $bootstrapPath"
}
if (-not (Test-Path -LiteralPath $firmwarePath -PathType Leaf)) {
    throw "Missing NeoGS firmware: $firmwarePath"
}

[byte[]]$bootstrap = [System.IO.File]::ReadAllBytes($bootstrapPath)
[byte[]]$firmware = [System.IO.File]::ReadAllBytes($firmwarePath)

if ($bootstrap.Length -lt 1 -or $bootstrap.Length -gt 254) {
    throw ("Bootstrap length {0} is outside the supported 1..254 byte range." -f $bootstrap.Length)
}
if ($firmware.Length -lt 1) {
    throw "NeoGS firmware image is empty."
}

$totalLength = 2 + $bootstrap.Length + $firmware.Length
if ($totalLength -gt 0xFF00) {
    throw ("NeoGS package is too large for the current TR-DOS file profile: {0} bytes." -f $totalLength)
}

[byte[]]$package = New-Object byte[] $totalLength
$package[0] = [byte]($bootstrap.Length -band 0xFF)
$package[1] = [byte](($bootstrap.Length -shr 8) -band 0xFF)
[Array]::Copy($bootstrap, 0, $package, 2, $bootstrap.Length)
[Array]::Copy($firmware, 0, $package, 2 + $bootstrap.Length, $firmware.Length)

$chunkSize = 0x4000
$chunkCount = [int][Math]::Ceiling($package.Length / [double]$chunkSize)
if ($chunkCount -lt 1 -or $chunkCount -gt 4) {
    throw ("Package requires {0} chunks; current host exporter supports 1..4." -f $chunkCount)
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(("NEOGS_PACKAGE_CHUNK_COUNT EQU {0}" -f $chunkCount))
$lines.Add(("NEOGS_PACKAGE_TOTAL_SIZE EQU #{0:X4}" -f $package.Length))

for ($i = 0; $i -lt $chunkCount; $i++) {
    $offset = $i * $chunkSize
    $length = [Math]::Min($chunkSize, $package.Length - $offset)
    [byte[]]$chunk = New-Object byte[] $length
    [Array]::Copy($package, $offset, $chunk, 0, $length)
    $chunkPath = Join-Path $build ("neoprog_part{0}.bin" -f $i)
    [System.IO.File]::WriteAllBytes($chunkPath, $chunk)
    $lines.Add(("NEOGS_PACKAGE_CHUNK{0}_SIZE EQU #{1:X4}" -f $i, $length))
}

$includePath = Join-Path $build "neoprog_chunks.inc"
[System.IO.File]::WriteAllLines($includePath, $lines, [System.Text.Encoding]::ASCII)

Write-Host ("NeoGS package: {0} bytes ({1} bootstrap + {2} firmware + 2-byte header)" -f $totalLength, $bootstrap.Length, $firmware.Length)
Write-Host ("Package chunks: {0} x 16 KiB maximum" -f $chunkCount)
for ($i = 0; $i -lt $chunkCount; $i++) {
    $chunkPath = Join-Path $build ("neoprog_part{0}.bin" -f $i)
    Write-Host ("  part{0}: {1} bytes" -f $i, (Get-Item -LiteralPath $chunkPath).Length)
}
