@echo off
REM Double-click to remove the Claude Code statusline (Windows).
REM Calls the PowerShell uninstaller sitting next to this file.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
pause
