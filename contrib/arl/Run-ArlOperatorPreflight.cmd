@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ARL\tools\Test-ArlPhysicalPreflight.ps1"
if errorlevel 1 (
  echo.
  echo PRECHECK NO APROBADO. El equipo todavia no esta listo para trabajar con el ARL.
  echo Deje esta ventana abierta y comparta este texto con soporte tecnico antes de continuar.
  pause
  exit /b 1
)
echo.
echo PRECHECK APROBADO. Puede cerrar esta ventana y abrir el acceso directo que corresponda:
echo   - 05 NORMALIZATION PASSIVE: normalizacion
echo   - 04 STANDARDIZATION PASSIVE: estandarizacion
echo   - ARL 3460 - Analizar: analisis de muestras
pause
