@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactCycles6000Trace.ps1"
if errorlevel 1 (
  echo.
  echo BASELINE CYCLES6000 486 TRACE failed. Leave this window open and send the text to Codex.
  pause
)
