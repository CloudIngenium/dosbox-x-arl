param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [int]$RxDelay = 3000,
    [string]$PrinterName = "EPSON LX-350",
    [switch]$NoAutoPrintLpt,
    [switch]$NoLptFormFeed,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stability = Join-Path $root "Launch-ArlImpactStabilityTrace.ps1"
if (-not (Test-Path -Path $stability -PathType Leaf)) {
    throw "Launch-ArlImpactStabilityTrace.ps1 not found below $root"
}

$args = @{
    DosboxExe = $DosboxExe
    Cycles = 6000
    RxDelay = $RxDelay
    Core = "simple"
    CpuType = "386"
    MemSize = 16
    Xms = $true
    Ems = "emsboard"
    Umb = $true
    LoadMouse = $true
    PrinterName = $PrinterName
}
if ($NoAutoPrintLpt) { $args.NoAutoPrintLpt = $true }
if ($NoLptFormFeed) { $args.NoLptFormFeed = $true }
if ($NoLaunch) { $args.NoLaunch = $true }

& $stability @args
