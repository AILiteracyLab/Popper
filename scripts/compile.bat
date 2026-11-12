@echo off
setlocal

echo ========================================
echo Popper - Compilation Script
echo ========================================

:: Set AHK_ROOT if AutoHotkey is installed somewhere else. Otherwise the
:: machine-wide install is tried first, then the per-user one.
if "%AHK_ROOT%"=="" if exist "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_ROOT=C:\Program Files\AutoHotkey"
if "%AHK_ROOT%"=="" set "AHK_ROOT=%LOCALAPPDATA%\Programs\AutoHotkey"
set "AHK_COMPILER=%AHK_ROOT%\Compiler\Ahk2Exe.exe"
set "AHK_BASE=%AHK_ROOT%\v2\AutoHotkey64.exe"
set "PROJECT_ROOT=%~dp0.."
set "BUILD_DIR=%PROJECT_ROOT%\build"
set "MAIN_SCRIPT=%PROJECT_ROOT%\src\main.ahk"
set "ICON=%PROJECT_ROOT%\assets\icon.ico"

if not exist "%AHK_COMPILER%" (
    echo ERROR: AutoHotkey compiler not found at %AHK_COMPILER%
    exit /b 1
)
if not exist "%AHK_BASE%" (
    echo ERROR: AutoHotkey v2 base not found at %AHK_BASE%
    exit /b 1
)

if not exist "%BUILD_DIR%\assets" mkdir "%BUILD_DIR%\assets"
if exist "%BUILD_DIR%\Popper.exe" del "%BUILD_DIR%\Popper.exe"

echo Compiling %MAIN_SCRIPT%...
"%AHK_COMPILER%" /in "%MAIN_SCRIPT%" /out "%BUILD_DIR%\Popper.exe" /icon "%ICON%" /base "%AHK_BASE%" /silent verbose
if not exist "%BUILD_DIR%\Popper.exe" (
    echo ERROR: Compilation failed
    exit /b 1
)

copy /Y "%PROJECT_ROOT%\assets\icon.ico" "%BUILD_DIR%\assets\icon.ico" >nul
copy /Y "%PROJECT_ROOT%\assets\recording.ico" "%BUILD_DIR%\assets\recording.ico" >nul

echo.
echo Compilation successful: %BUILD_DIR%\Popper.exe
exit /b 0
