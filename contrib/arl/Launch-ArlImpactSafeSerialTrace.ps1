param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [int]$Cycles = 8000,
    [int]$RxDelay = 10000,
    [string]$PrinterName = "EPSON LX-350",
    [switch]$NoAutoPrintLpt,
    [switch]$NoLptFormFeed,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $root "Start-ArlTraceRun.ps1"
if (-not (Test-Path -Path $launcher -PathType Leaf)) {
    $launcher = Join-Path $root "contrib\arl\Start-ArlTraceRun.ps1"
}
if (-not (Test-Path -Path $launcher -PathType Leaf)) {
    throw "Start-ArlTraceRun.ps1 not found below $root"
}

if (-not (Test-Path -Path $DosboxExe -PathType Leaf)) {
    $fallback = Join-Path $root "dosbox-x-arl.exe"
    if (Test-Path -Path $fallback -PathType Leaf) {
        $DosboxExe = $fallback
    }
}

$runArgs = @{
    Session = "sample-analysis"
    DosboxExe = $DosboxExe
    TraceLevel = "basic"
    Cycles = $Cycles
    RxDelay = $RxDelay
    HangMs = 30000
}

if (-not $NoAutoPrintLpt) {
    $runArgs.AutoPrintLpt = $true
    $runArgs.PrinterName = $PrinterName
    $runArgs.LptIdleMs = 2500
    if ($NoLptFormFeed) {
        $runArgs.NoLptFormFeed = $true
    }
}

if ($NoLaunch) {
    $runArgs.NoLaunch = $true
}

& $launcher @runArgs
