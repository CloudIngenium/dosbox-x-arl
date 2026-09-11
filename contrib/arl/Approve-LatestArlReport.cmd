@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\tools\Approve-LatestArlReport.ps1"
if errorlevel 1 (
  echo.
  echo LA APROBACION DEL REPORTE NO SE COMPLETO. Deje esta ventana abierta y comparta este texto con soporte tecnico.
  pause
  exit /b 1
)
echo.
echo REPORTE IMPRESO Y REGISTRADO.
pause
