@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Launch-ArlImpactEmulatorTrace.ps1" ^
  -ProfilePath "C:\ARL\DOSBox-X-ARL\profiles\impact-format-equivalence-safe-loop.json" ^
  -InitialControlLabel "known-low-checksum-000" ^
  -InitialControlResponseAscii "#+20.00,+25.258,+030.52,+0035.40500,40.66,45.922,2.16,7.420,12.68,17.568,22.83,28.084,32.97,38.231,43.49 000\r"
if errorlevel 1 (
  echo.
  echo EMU LOWCHECK START failed. Leave this window open and send the text to Codex.
  pause
)
