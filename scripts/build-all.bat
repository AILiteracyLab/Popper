@echo off
setlocal

call "%~dp0compile.bat"
if errorlevel 1 exit /b 1
echo.
call "%~dp0build-installer.bat"
if errorlevel 1 exit /b 1

echo.
echo Outputs:
echo   build\Popper.exe
echo   build\Popper-Setup.exe  (this is the one to share)
exit /b 0
