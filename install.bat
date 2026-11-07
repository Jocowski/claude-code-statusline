@echo off
REM Double-click to install the Claude Code statusline (Windows).
REM Calls the PowerShell installer sitting next to this file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
