@echo off
rem Double-click to install (or update) Monitor Brightness for the current user. No admin rights needed.
title Monitor Brightness setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 (
    echo.
    echo Setup failed. See the message above.
    pause
    exit /b 1
)
echo.
echo You can close this window.
"%SystemRoot%\System32\timeout.exe" /t 10 >nul
