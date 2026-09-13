@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\tools\Test-ArlPhysicalPreflight.ps1"
if errorlevel 1 (
  echo.
  echo EQUIPO NO LISTO. No abra ningun icono del ARL.
  echo Tome una foto de esta ventana y avise a Sistemas.
  pause
  exit /b 1
)
echo.
echo EQUIPO LISTO. Cierre esta ventana y abra el icono que corresponda:
echo   - Analizar colada
echo   - Ing. Serrano - Estandarizacion con muestras de ajuste
echo   - Ing. Serrano - Normalizacion
pause
