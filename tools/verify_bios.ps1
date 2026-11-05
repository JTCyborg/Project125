$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$biosPath = Join-Path $root "bios\BIOS.BIN"
if (-not (Test-Path -LiteralPath $biosPath -PathType Leaf)) {
    Write-Error "BIOS image not found: $biosPath"
    exit 1
}
$length = (Get-Item -LiteralPath $biosPath).Length
if ($length -ne 8192) {
    Write-Error ("Unexpected BIOS size: {0}; expected exactly 8192 bytes" -f $length)
    exit 1
}
$sha = (Get-FileHash -LiteralPath $biosPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "BIOS image: 8192 bytes (8 KiB)"
Write-Host "Content validation: disabled; any byte sequence is accepted"
Write-Host ("SHA-256: {0}" -f $sha)
exit 0
