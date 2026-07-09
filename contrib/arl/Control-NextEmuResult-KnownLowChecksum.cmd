@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Set-ArlEmulatorControl.ps1" ^
  -ResponseAscii "#+20.00,+25.258,+030.52,+0035.40500,40.66,45.922,2.16,7.420,12.68,17.568,22.83,28.084,32.97,38.231,43.49 000\r" ^
  -Label "known-low-checksum-000"
echo.
pause
