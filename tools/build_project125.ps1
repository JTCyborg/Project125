$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$assembler = Join-Path $root "tools/sjasmplus.exe"
$packer = Join-Path $root "tools/pack_neogs_project125.ps1"
$finalizer = Join-Path $root "tools/finalize_project125_trd.ps1"
$biosVerifier = Join-Path $root "tools/verify_bios.ps1"

Push-Location $root
try {
    New-Item -ItemType Directory -Force (Join-Path $root "build") | Out-Null

    & $biosVerifier
    if (-not $?) { throw "BIOS image size check failed." }

    & $assembler "neogs_sub/build_firmware.asm"
    if ($LASTEXITCODE -ne 0) { throw "NeoGS firmware assembly failed with exit code $LASTEXITCODE." }

    & $packer
    if ($LASTEXITCODE -ne 0) { throw "NeoGS firmware packaging failed with exit code $LASTEXITCODE." }

    & $assembler "zx_main/main.asm"
    if ($LASTEXITCODE -ne 0) { throw "ATM host/TR-DOS assembly failed with exit code $LASTEXITCODE." }

    & $finalizer
    if ($LASTEXITCODE -ne 0) { throw "TR-DOS directory finalization failed with exit code $LASTEXITCODE." }

    Write-Host "Project125 build completed: disk_A.trd"
}
finally {
    Pop-Location
}
