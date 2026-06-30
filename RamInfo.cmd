@echo off
REM Double-click launcher for the RAM Info window.
REM Uses Windows PowerShell (powershell.exe) because it runs STA by default,
REM which WinForms and the clipboard require. -ExecutionPolicy Bypass lets the
REM script run without changing any machine-wide setting.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Show-RamInfo.ps1"
