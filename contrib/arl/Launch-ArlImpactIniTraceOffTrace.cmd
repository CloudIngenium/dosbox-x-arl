@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactIniTraceOffTrace.ps1"
if errorlevel 1 (
  echo.
  echo INI TRACE OFF TRACE failed. Leave this window open and send the text to Codex.
  pause
)
