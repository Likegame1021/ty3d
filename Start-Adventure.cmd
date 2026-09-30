@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Start-Validation.ps1" -Mode Adventure %*
if errorlevel 1 pause
