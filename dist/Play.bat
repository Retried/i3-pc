@echo off
rem inFAMOUS Second Son - starts the game. Saves and settings live in .\user
if not exist "%~dp0inFAMOUS Second Son.exe" (
  echo Program not found: %~dp0inFAMOUS Second Son.exe
  pause
  exit /b 1
)
cd /d "%~dp0"
start "" "%~dp0inFAMOUS Second Son.exe" %*
