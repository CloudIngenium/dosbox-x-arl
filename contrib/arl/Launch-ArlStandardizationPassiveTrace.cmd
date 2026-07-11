@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-ArlPassiveWorkflowTrace.ps1" -Workflow standardization
if errorlevel 1 pause
