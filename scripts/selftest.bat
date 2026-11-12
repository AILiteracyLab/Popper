@echo off
:: Usage: scripts\selftest.bat [server-url] [model]
if "%AHK_ROOT%"=="" set "AHK_ROOT=C:\Program Files\AutoHotkey"
"%AHK_ROOT%\v2\AutoHotkey64.exe" /ErrorStdOut "%~dp0..\tests\selftest.ahk" %*
