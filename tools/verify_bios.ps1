$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$biosPath = Join-Path $root "bios\BIOS.BIN"
if (-not (Test-Path -LiteralPath $biosPath -PathType Leaf)) {
    Write-Error "BIOS image not found: $biosPath"
    exit 1
}
[byte[]]$image = [System.IO.File]::ReadAllBytes($biosPath)
if ($image.Length -ne 8192) {
    Write-Error ("Unexpected BIOS size: {0}; expected 8192 bytes" -f $image.Length)
    exit 1
}
$expectedHeader = [System.Text.Encoding]::ASCII.GetBytes("BIOS V1.11.")
for ($i = 0; $i -lt $expectedHeader.Length; $i++) {
    if ($image[$i] -ne $expectedHeader[$i]) {
        Write-Error ("BIOS V1.11 marker mismatch at offset {0:X4}" -f $i)
        exit 1
    }
}
$resetOffset = 0x1FF0
[byte[]]$expectedVector = @(0xEA, 0x5B, 0xE0, 0x00, 0xF0)
for ($i = 0; $i -lt $expectedVector.Length; $i++) {
    if ($image[$resetOffset + $i] -ne $expectedVector[$i]) {
        Write-Error ("BIOS reset vector mismatch at image offset {0:X4}" -f ($resetOffset + $i))
        exit 1
    }
}
$sha = (Get-FileHash -LiteralPath $biosPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "BIOS image: 8192 bytes"
Write-Host "Identification: BIOS V1.11. Copyright 1986,87 Central Point Software, Inc."
Write-Host "Reset vector: FFFF0 = EA 5B E0 00 F0"
Write-Host "Reset target: F000:E05B -> FE05B"
Write-Host ("SHA-256: {0}" -f $sha)
exit 0
