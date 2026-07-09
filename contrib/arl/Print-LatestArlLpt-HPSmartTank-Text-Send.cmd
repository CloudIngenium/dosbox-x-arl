@echo off
cd /d C:\ARL\DOSBox-X-ARL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\DOSBox-X-ARL\Print-ArlLptCapture.ps1" -PrinterName "HPAFDCEE.Corp.Tpu.mx (HP Smart Tank 750 series)" -PrintMode Text -Send
echo.
pause
