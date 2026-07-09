@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactEmulatorTrace.ps1" -ProfilePath "C:\ARL\DOSBox-X-ARL\profiles\impact-format-equivalence-safe-loop.json" -ImpactIniSet "Store Partial Results=ON"
if errorlevel 1 (
  echo.
  echo IMPACT EMULATOR STORE PARTIAL SAFE LOOP TRACE failed. Leave this window open and send the text to Codex.
  pause
)
