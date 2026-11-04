$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build"
$outputDir = Join-Path $root "zx_main"

$bootstrapPath = Join-Path $build "neogs_bootstrap.bin"
$residentPath = Join-Path $build "neogs_resident.bin"
$overlay68Path = Join-Path $build "neogs_overlay68.bin"
$overlay69Path = Join-Path $build "neogs_overlay69.bin"
$loaderOutput = Join-Path $outputDir "neoload.bin"
$firmwareOutput = Join-Path $outputDir "neofw.bin"
$includeOutput = Join-Path $outputDir "neogs_files.inc"

foreach ($path in @($bootstrapPath, $residentPath, $overlay68Path, $overlay69Path)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing NeoGS binary section: $path"
    }
}

[byte[]]$loader = [System.IO.File]::ReadAllBytes($bootstrapPath)
[byte[]]$resident = [System.IO.File]::ReadAllBytes($residentPath)
[byte[]]$overlay68 = [System.IO.File]::ReadAllBytes($overlay68Path)
[byte[]]$overlay69 = [System.IO.File]::ReadAllBytes($overlay69Path)

if ($loader.Length -lt 1 -or $loader.Length -gt 0x0800) {
    throw ("NEOLOAD.C size {0} is outside the supported 1..2048 byte range." -f $loader.Length)
}
if ($resident.Length -lt 1 -or $resident.Length -gt 0x4000) {
    throw ("Resident firmware size {0} is outside the supported 1..16384 byte range." -f $resident.Length)
}
foreach ($section in @(
    @{ Name = "overlay page 68"; Bytes = $overlay68 },
    @{ Name = "overlay page 69"; Bytes = $overlay69 }
)) {
    if ($section.Bytes.Length -gt 0x4000) {
        throw ("{0} size {1} exceeds one 16-KiB physical page." -f $section.Name, $section.Bytes.Length)
    }
}

# P125 package: ASCII "P125", then three little-endian WORD lengths,
# followed by resident page 0, overlay page 68 and overlay page 69 payloads.
function Get-Crc16Ccitt([byte[]]$Bytes) {
    [UInt16]$crc = 0xFFFF
    foreach ($value in $Bytes) {
        $crc = [UInt16]($crc -bxor ([UInt16]$value -shl 8))
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 0x8000) -ne 0) {
                $crc = [UInt16]((($crc -shl 1) -bxor 0x1021) -band 0xFFFF)
            }
            else {
                $crc = [UInt16](($crc -shl 1) -band 0xFFFF)
            }
        }
    }
    return $crc
}

[byte[]]$crcTestVector = [System.Text.Encoding]::ASCII.GetBytes("123456789")
if ((Get-Crc16Ccitt $crcTestVector) -ne 0x29B1) {
    throw "CRC-16/CCITT implementation failed the 123456789 reference vector."
}

[UInt16]$residentCrc = Get-Crc16Ccitt $resident
[UInt16]$overlay68Crc = Get-Crc16Ccitt $overlay68
[UInt16]$overlay69Crc = Get-Crc16Ccitt $overlay69

$packageStream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($packageStream)
try {
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes("P125"))
    $writer.Write([UInt16]$resident.Length)
    $writer.Write([UInt16]$overlay68.Length)
    $writer.Write([UInt16]$overlay69.Length)
    $writer.Write($residentCrc)
    $writer.Write($overlay68Crc)
    $writer.Write($overlay69Crc)
    $writer.Write($resident)
    $writer.Write($overlay68)
    $writer.Write($overlay69)
    $writer.Flush()
    [byte[]]$package = $packageStream.ToArray()
}
finally {
    $writer.Dispose()
    $packageStream.Dispose()
}

if ($package.Length -gt 0xC010) {
    throw ("NEOFW.C package size {0} exceeds the 48-KiB payload plus 16-byte manifest limit (0xC010)." -f $package.Length)
}

[System.IO.File]::WriteAllBytes($loaderOutput, $loader)
[System.IO.File]::WriteAllBytes($firmwareOutput, $package)

$lines = @(
    ("NEOLOAD_FILE_SIZE EQU #{0:X4}" -f $loader.Length),
    ("NEOFW_FILE_SIZE EQU #{0:X4}" -f $package.Length),
    ("NEOFW_RESIDENT_SIZE EQU #{0:X4}" -f $resident.Length),
    ("NEOFW_BANK68_SIZE EQU #{0:X4}" -f $overlay68.Length),
    ("NEOFW_BANK69_SIZE EQU #{0:X4}" -f $overlay69.Length)
)
[System.IO.File]::WriteAllLines($includeOutput, $lines, [System.Text.Encoding]::ASCII)

Write-Host ("NEOLOAD.C:       {0} bytes (unchanged V1 bootstrap)" -f $loader.Length)
Write-Host ("Resident page 0: {0} / 16384 bytes" -f $resident.Length)
Write-Host ("Overlay page 68: {0} / 16384 bytes" -f $overlay68.Length)
Write-Host ("Overlay page 69: {0} / 16384 bytes" -f $overlay69.Length)
Write-Host ("NEOFW.C:         {0} bytes (P125 segmented package, CRC16 per bank)" -f $package.Length)
