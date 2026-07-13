@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\tools\Test-ArlPhysicalPreflight.ps1"
if errorlevel 1 (
  echo.
  echo PRECHECK FAILED. Leave this window open and send the text to Codex.
  pause
  exit /b 1
)
echo.
echo PRECHECK PASSED. You may close this window and run 02 REACTIVE SAFE.
pause
