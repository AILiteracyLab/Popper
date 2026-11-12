@echo off
setlocal

echo ========================================
echo Popper - Build Installer
echo ========================================

if "%AHK_ROOT%"=="" if exist "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_ROOT=C:\Program Files\AutoHotkey"
if "%AHK_ROOT%"=="" set "AHK_ROOT=%LOCALAPPDATA%\Programs\AutoHotkey"
set "AHK_COMPILER=%AHK_ROOT%\Compiler\Ahk2Exe.exe"
set "AHK_BASE=%AHK_ROOT%\v2\AutoHotkey64.exe"
set "PROJECT_ROOT=%~dp0.."
set "BUILD_DIR=%PROJECT_ROOT%\build"
set "ICON=%PROJECT_ROOT%\assets\icon.ico"

if not exist "%AHK_COMPILER%" (
    echo ERROR: AutoHotkey compiler not found at %AHK_COMPILER%
    exit /b 1
)
if not exist "%BUILD_DIR%\Popper.exe" (
    echo ERROR: build\Popper.exe not found. Run compile.bat first.
    exit /b 1
)

:: The uninstaller is packed inside Setup, so it is built first.
if exist "%BUILD_DIR%\Uninstall.exe" del "%BUILD_DIR%\Uninstall.exe"
echo Compiling the uninstaller...
"%AHK_COMPILER%" /in "%PROJECT_ROOT%\installer\Uninstall.ahk" /out "%BUILD_DIR%\Uninstall.exe" /icon "%ICON%" /base "%AHK_BASE%" /silent verbose
if not exist "%BUILD_DIR%\Uninstall.exe" (
    echo ERROR: Uninstaller build failed
    exit /b 1
)

if exist "%BUILD_DIR%\Popper-Setup.exe" del "%BUILD_DIR%\Popper-Setup.exe"
echo Compiling Setup...
"%AHK_COMPILER%" /in "%PROJECT_ROOT%\installer\Setup.ahk" /out "%BUILD_DIR%\Popper-Setup.exe" /icon "%ICON%" /base "%AHK_BASE%" /silent verbose
if not exist "%BUILD_DIR%\Popper-Setup.exe" (
    echo ERROR: Setup build failed
    exit /b 1
)

echo.
echo Installer built: %BUILD_DIR%\Popper-Setup.exe
exit /b 0
