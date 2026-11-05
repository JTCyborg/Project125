$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$trdPath = Join-Path $root "disk_A.trd"
$firmwarePath = Join-Path $root "zx_main/neofw.bin"

if (-not (Test-Path -LiteralPath $trdPath -PathType Leaf)) {
    throw "Missing TR-DOS image: $trdPath"
}
if (-not (Test-Path -LiteralPath $firmwarePath -PathType Leaf)) {
    throw "Missing packed firmware: $firmwarePath"
}

[byte[]]$disk = [System.IO.File]::ReadAllBytes($trdPath)
[byte[]]$firmware = [System.IO.File]::ReadAllBytes($firmwarePath)
$length = $firmware.Length
$sectors = [int][Math]::Ceiling($length / 256.0)

if ($length -lt 1 -or $length -gt 0xC010) {
    throw ("NEOFW.C length {0} is outside the supported 1..0xC010 range." -f $length)
}
if ($sectors -gt 255) {
    throw ("NEOFW.C requires {0} sectors; TR-DOS directory supports at most 255." -f $sectors)
}

# TR-DOS directory: 128 entries x 16 bytes at the start of the TRD image.
# For a CODE file, bytes 11..12 contain the exact byte length and byte 13
# contains the allocated sector count. SAVETRD '&' appends sectors and
# updates byte 13, but intentionally leaves the original byte length intact.
[byte[]]$name = [System.Text.Encoding]::ASCII.GetBytes("NEOFW   C")
$entryOffset = -1
for ($offset = 0; $offset -lt (128 * 16); $offset += 16) {
    $match = $true
    for ($i = 0; $i -lt $name.Length; $i++) {
        if ($disk[$offset + $i] -ne $name[$i]) {
            $match = $false
            break
        }
    }
    if ($match) {
        $entryOffset = $offset
        break
    }
}

if ($entryOffset -lt 0) {
    throw "NEOFW.C directory entry was not found in disk_A.trd."
}

$allocatedSectors = [int]$disk[$entryOffset + 13]
if ($allocatedSectors -ne $sectors) {
    throw ("NEOFW.C directory sector count mismatch: directory={0}, expected={1}." -f $allocatedSectors, $sectors)
}

$disk[$entryOffset + 11] = [byte]($length -band 0xFF)
$disk[$entryOffset + 12] = [byte](($length -shr 8) -band 0xFF)
[System.IO.File]::WriteAllBytes($trdPath, $disk)

Write-Host ("NEOFW.C directory length patched: {0} bytes, {1} sectors." -f $length, $sectors)
