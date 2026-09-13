@echo off
title Ing. Serrano - NORMALIZACION - no cierre esta ventana
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-ArlPassiveWorkflowTrace.ps1" -Workflow normalization
if errorlevel 1 pause
