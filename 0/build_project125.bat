@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "BUILD_RESULT=0"
echo.
echo ================================================================
echo PROJECT 125 - BIOS / NeoGS x86 runtime build
echo ================================================================
echo.
set "SJASMPLUS=tools\sjasmplus.exe"
if not exist "%SJASMPLUS%" set "SJASMPLUS=sjasmplus"

if not exist "bios\BIOS.BIN" (
    echo ERROR: bios\BIOS.BIN is missing.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "build" mkdir "build"
if errorlevel 1 goto :failed

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\verify_bios.ps1"
if errorlevel 1 goto :failed

echo [BUILD] Assembling NeoGS resident firmware...
echo [DEBUG] Listing: build\NEOGS.lst
echo [DEBUG] Symbol map: build\NEOGS.map
%SJASMPLUS% --msg=all --lst=build\NEOGS.lst --lstlab=sort --sym=build\NEOGS.map neogs_sub\build_firmware.asm
if errorlevel 1 goto :failed
if not exist "build\NEOGS.lst" (
    echo ERROR: build\NEOGS.lst was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "build\NEOGS.map" (
    echo ERROR: build\NEOGS.map was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "build\neogs_code.bin" (
    echo ERROR: build\neogs_code.bin was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "build\neogs_bootstrap.bin" (
    echo ERROR: build\neogs_bootstrap.bin was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)

echo [BUILD] Creating separate NEOLOAD.C and NEOFW.C TR-DOS files...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "tools\pack_neogs_project125.ps1"
if errorlevel 1 goto :failed

if exist "disk_A.trd" del /Q "disk_A.trd"
echo [BUILD] Assembling ATM host and exporting TR-DOS disk...
echo [DEBUG] Listing: build\ATM.lst
echo [DEBUG] Symbol map: build\ATM.map
%SJASMPLUS% --msg=all --lst=build\ATM.lst --lstlab=sort --sym=build\ATM.map zx_main\main.asm
if errorlevel 1 (
    echo ERROR: ATM host assembly / TR-DOS export failed.
    goto :failed
)
if not exist "build\ATM.lst" (
    echo ERROR: build\ATM.lst was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "build\ATM.map" (
    echo ERROR: build\ATM.map was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
if not exist "disk_A.trd" (
    echo ERROR: disk_A.trd was not produced.
    set "BUILD_RESULT=1"
    goto :finish
)
copy /Y "disk_A.trd" "build\disk_A.trd" >nul
if errorlevel 1 goto :failed

echo.
echo BUILD COMPLETED.
dir "build\ATM.lst" "build\ATM.map" "build\NEOGS.lst" "build\NEOGS.map" "build\neogs_code.bin" "build\neogs_bootstrap.bin" "build\disk_A.trd" "bios\BIOS.BIN"
goto :finish

:failed
set "BUILD_RESULT=%ERRORLEVEL%"
if "%BUILD_RESULT%"=="0" set "BUILD_RESULT=1"
echo.
echo BUILD FAILED. Exit code: %BUILD_RESULT%

:finish
echo.
echo ================================================================
echo BUILD SCRIPT FINISHED. Exit code: %BUILD_RESULT%
echo The window will remain open. Press any key to close it.
echo ================================================================
pause >nul
exit /b %BUILD_RESULT%
