@echo off
if not exist "%~dp0install.ps1" (
    echo Extract the ZIP to a folder first, then run Install.cmd from there.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
