@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactEmulatorTrace.ps1" -ProfilePath "C:\ARL\DOSBox-X-ARL\profiles\impact-full-205041-rejectfirst-checksum099.json"
if errorlevel 1 (
  echo.
  echo IMPACT EMULATOR CHECKSUM099 TRACE failed. Leave this window open and send the text to Codex.
  pause
)
