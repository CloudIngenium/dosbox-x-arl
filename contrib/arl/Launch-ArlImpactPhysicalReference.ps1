param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [string]$ArlRoot = "C:\ARL",
    [string]$ImplusPath = "C:\ARL\IMPLUS",
    [string]$RunRoot = "C:\ARL\diagnostics",
    [switch]$ObserveResults,
    [switch]$ReactiveRetryLow,
    [switch]$LegacyDebugPrintLpt,
    [switch]$NoAutoPrintLpt,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $root "Start-ArlTraceRun.ps1"
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    $launcher = Join-Path $root "contrib\arl\Start-ArlTraceRun.ps1"
}
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Start-ArlTraceRun.ps1 not found below $root"
}

$arguments = @{
    Session = "sample-analysis"
    DosboxExe = $DosboxExe
    ArlRoot = $ArlRoot
    ImplusPath = $ImplusPath
    RunRoot = $RunRoot
    ComPort = "COM5"
    Cycles = 12000
    RxDelay = 3000
    Core = "normal"
    CpuType = "486"
    TraceLevel = "basic"
    TraceMaxMb = 64
    HangMs = 30000
    WindowResolution = "1440x900"
    VideoOutput = "openglnb"
    Aspect = $false
    Scaler = "none"
    Wait = $true
}
if ($ObserveResults) { $arguments.ArlResultObserve = $true }
if ($ReactiveRetryLow) { $arguments.ArlResultRetryLow = $true }
if ($LegacyDebugPrintLpt -and $NoAutoPrintLpt) {
    throw "LegacyDebugPrintLpt and NoAutoPrintLpt cannot be combined."
}
if ($LegacyDebugPrintLpt) {
    $arguments.AutoPrintLpt = $true
    $arguments.PrinterName = "EPSON LX-350"
    # Diagnostic-only legacy output: IMPACT emits detailed stage blocks after
    # individual burns. Production reports are generated once per saved group
    # by Chispa.Agent and require manual approval during the gate.
    $arguments.PrintMode = "Text"
}
if ($NoLaunch) { $arguments.NoLaunch = $true }

$modeLabel = if ($ReactiveRetryLow) { "Mode: REACTIVE SAFE (retry only after IMPACT sends ?)" } elseif ($ObserveResults) { "Mode: OBSERVE ONLY (no byte mutation)" } else { "Mode: DIRECTSERIAL BYPASS" }
Write-Host $modeLabel
if ($LegacyDebugPrintLpt) {
    Write-Warning "Legacy detailed LPT printing is enabled for this diagnostic session."
} else {
    Write-Host "Printing: final saved-group report only (Chispa.Agent); LPT remains captured as evidence."
}
& $launcher @arguments
