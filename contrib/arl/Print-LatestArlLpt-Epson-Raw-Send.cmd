@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Print-ArlLptCapture.ps1" -PrinterName "EPSON LX-350" -PrintMode Raw -AppendFormFeed -Send
echo.
pause
