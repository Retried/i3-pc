@echo off
rem Opens the key binding menu.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Keys.ps1" %*
pause
