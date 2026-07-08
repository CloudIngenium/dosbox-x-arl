@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactSafeSerialTrace.ps1"
if errorlevel 1 (
  echo.
  echo ARL IMPACT+ SAFE SERIAL TRACE failed. Leave this window open and send the text to Codex.
  pause
)
