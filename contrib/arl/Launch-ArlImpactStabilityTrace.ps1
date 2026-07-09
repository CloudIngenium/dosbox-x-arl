param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl-96994b1.exe",
    [int]$Cycles = 8000,
    [int]$RxDelay = 3000,
    [ValidateSet("normal", "simple", "dynamic", "auto")]
    [string]$Core = "normal",
    [string]$CpuType = "486",
    [ValidateRange(1, 63)]
    [int]$MemSize = 16,
    [bool]$Xms = $true,
    [bool]$Ems = $true,
    [bool]$Umb = $true,
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
    $candidate = Join-Path $root "dosbox-x-arl-96994b1.exe"
    if (Test-Path -Path $candidate -PathType Leaf) {
        $DosboxExe = $candidate
    } else {
        $DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe"
    }
}

$runArgs = @{
    Session = "sample-analysis"
    DosboxExe = $DosboxExe
    TraceLevel = "basic"
    Cycles = $Cycles
    RxDelay = $RxDelay
    Core = $Core
    CpuType = $CpuType
    MemSize = $MemSize
    Xms = $Xms
    Ems = $Ems
    Umb = $Umb
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
