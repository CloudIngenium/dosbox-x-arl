param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
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
    RxDelay = 3000
    Core = "normal"
    CpuType = "486"
    WindowResolution = "original"
    VideoOutput = "default"
    Aspect = $false
    Scaler = "normal2x"
    ImpactIniSet = @("Use Bootup Status=OFF")
}
if ($NoLaunch) { $args.NoLaunch = $true }

& $stability @args
