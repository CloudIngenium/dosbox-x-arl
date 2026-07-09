@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactCycles6000Simple386NoInt33Trace.ps1" -NoAutoPrintLpt
if errorlevel 1 (
  echo.
  echo CYCLES6000 SIMPLE386 NOINT33 TRACE failed. Leave this window open and send the text to Codex.
  pause
)
