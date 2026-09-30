@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Start-Validation.ps1" -Mode CornGun
if errorlevel 1 pause
