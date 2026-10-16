@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build-windows.ps1" -Configuration Release -Lto %*
exit /b %errorlevel%
