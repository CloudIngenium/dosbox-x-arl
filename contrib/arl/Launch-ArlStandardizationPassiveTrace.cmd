@echo off
title Ing. Serrano - ESTANDARIZACION - no cierre esta ventana
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-ArlPassiveWorkflowTrace.ps1" -Workflow standardization
if errorlevel 1 pause
