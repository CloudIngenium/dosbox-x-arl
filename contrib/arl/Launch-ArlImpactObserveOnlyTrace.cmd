@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-ArlImpactPhysicalReference.ps1" -ObserveResults
if errorlevel 1 pause
