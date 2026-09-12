param(
    [string]$ToolkitRoot = "C:\ARL\DOSBox-X-ARL",
    [string]$DesktopPath = "C:\Users\Public\Desktop",
    [string]$IconPath = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [string]$DiagnosticsPath = "C:\ARL\diagnostics",
    [switch]$NoCleanup,
    [switch]$IncludeBuildRequired
)

$ErrorActionPreference = "Stop"

# Retired 2026-09. This script created the old jargon-named desktop (00 DIRECTSERIAL BYPASS,
# 01 PRECHECK, 04 STANDARDIZATION PASSIVE, ...) that the ARL floor could not tell apart. The
# operator desktop is now built and undone by Set-ArlOperatorDesktop.ps1, which lays down the
# three Spanish launchers, the guide card and the diagnostics groups under one manifest. The
# parameters above are kept so any caller that still splats them fails with this message instead
# of a missing-command error.
throw 'Retirado 2026-09: el escritorio del ARL lo administra C:\ARL\DOSBox-X-ARL\contrib\arl\Set-ArlOperatorDesktop.ps1 (Aplicar/-Undo/-SelfTest). Este script ya no crea accesos directos.'
