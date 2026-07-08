@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactStabilityTrace.ps1" -RxDelay 4000
if errorlevel 1 (
  echo.
  echo ARL IMPACT+ RX4000 TRACE failed. Leave this window open and send the text to Codex.
  pause
)
