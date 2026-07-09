@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactCycles6000Simple386NoShareTrace.ps1"
if errorlevel 1 (
  echo.
  echo ARL IMPACT+ CYCLES6000 SIMPLE386 NOSHARE TRACE failed. Leave this window open and send the text to Codex.
  pause
)
