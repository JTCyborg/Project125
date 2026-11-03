@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo.
echo ================================================================
echo PROJECT 125 - BIOS / NeoGS x86 runtime build
echo ================================================================
echo.
if not exist "tools\sjasmplus.exe" (
    echo ERROR: tools\sjasmplus.exe not found.
    echo Place sjasmplus.exe in the tools directory.
    exit /b 1
)
if not exist "bios\BIOS.BIN" (
    echo ERROR: bios\BIOS.BIN is missing.
    exit /b 1
)
if not exist "build" mkdir "build"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\verify_bios.ps1"
if errorlevel 1 exit /b 1
echo [BUILD] Assembling NeoGS resident firmware...
tools\sjasmplus.exe --msg=all neogs_sub\build_firmware.asm
if errorlevel 1 exit /b 1
if not exist "build\neogs_code.bin" (
    echo ERROR: build\neogs_code.bin was not produced.
    exit /b 1
)
if not exist "build\neogs_bootstrap.bin" (
    echo ERROR: build\neogs_bootstrap.bin was not produced.
    exit /b 1
)
echo.
echo BUILD COMPLETED.
dir "build\neogs_code.bin" "build\neogs_bootstrap.bin" "bios\BIOS.BIN"
exit /b 0
