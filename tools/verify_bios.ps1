$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$biosPath = Join-Path $root "bios\BIOS.BIN"
if (-not (Test-Path -LiteralPath $biosPath -PathType Leaf)) {
    Write-Error "BIOS image not found: $biosPath"
    exit 1
}
$length = (Get-Item -LiteralPath $biosPath).Length
if ($length -lt 1 -or $length -gt 8192) {
    Write-Error ("Unsupported BIOS size: {0}; allowed range is 1..8192 bytes" -f $length)
    exit 1
}
$sha = (Get-FileHash -LiteralPath $biosPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ("BIOS image accepted: {0} bytes (maximum 8192)" -f $length)
Write-Host "BIOS content/signature/reset-vector checks: disabled"
Write-Host ("SHA-256: {0}" -f $sha)
exit 0
