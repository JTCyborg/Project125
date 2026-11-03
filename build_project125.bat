@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo.
echo ================================================================
echo PROJECT 125 - BIOS / NeoGS x86 runtime build
echo ================================================================
echo.
set "SJASMPLUS=tools\sjasmplus.exe"
if not exist "%SJASMPLUS%" set "SJASMPLUS=sjasmplus"

if not exist "bios\BIOS.BIN" (
    echo ERROR: bios\BIOS.BIN is missing.
    exit /b 1
)
if not exist "build" mkdir "build"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\verify_bios.ps1"
if errorlevel 1 exit /b 1
echo [BUILD] Assembling NeoGS resident firmware...
%SJASMPLUS% --msg=all neogs_sub\build_firmware.asm
if errorlevel 1 exit /b 1
if not exist "build\neogs_code.bin" (
    echo ERROR: build\neogs_code.bin was not produced.
    exit /b 1
)
if not exist "build\neogs_bootstrap.bin" (
    echo ERROR: build\neogs_bootstrap.bin was not produced.
    exit /b 1
)
echo [BUILD] Packing NeoGS bootstrap + firmware into 16 KiB TR-DOS chunks...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\pack_neogs_project125.ps1"
if errorlevel 1 exit /b 1

if exist "disk_A.trd" del /Q "disk_A.trd"
echo [BUILD] Assembling ATM host and exporting TR-DOS disk...
%SJASMPLUS% --msg=all zx_main\main.asm
if errorlevel 1 (
    echo ERROR: ATM host assembly / TR-DOS export failed.
    exit /b 1
)
if not exist "disk_A.trd" (
    echo ERROR: disk_A.trd was not produced.
    exit /b 1
)
copy /Y "disk_A.trd" "build\disk_A.trd" >nul
if errorlevel 1 exit /b 1

echo.
echo BUILD COMPLETED.
dir "build\neogs_code.bin" "build\neogs_bootstrap.bin" "build\disk_A.trd" "bios\BIOS.BIN"
exit /b 0
