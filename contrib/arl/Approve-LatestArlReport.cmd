@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\tools\Approve-LatestArlReport.ps1"
if errorlevel 1 (
  echo.
  echo REPORT APPROVAL DID NOT COMPLETE. Leave this window open and send the text to Codex.
  pause
  exit /b 1
)
echo.
echo REPORT PRINTED AND RECORDED.
pause
