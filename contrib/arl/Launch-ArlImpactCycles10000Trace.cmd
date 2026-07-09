@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactCycles10000Trace.ps1"
if errorlevel 1 (
  echo.
  echo ARL IMPACT+ CYCLES10000 TRACE failed. Leave this window open and send the text to Codex.
  pause
)
