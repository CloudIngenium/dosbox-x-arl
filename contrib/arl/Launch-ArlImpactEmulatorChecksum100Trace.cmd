@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactEmulatorTrace.ps1" -ProfilePath "C:\ARL\DOSBox-X-ARL\profiles\impact-full-205041-rejectfirst-checksum100-control.json"
if errorlevel 1 (
  echo.
  echo IMPACT EMULATOR CHECKSUM100 TRACE failed. Leave this window open and send the text to Codex.
  pause
)
