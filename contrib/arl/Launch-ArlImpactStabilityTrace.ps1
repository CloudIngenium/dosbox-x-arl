param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl-96994b1.exe",
    [int]$Cycles = 8000,
    [int]$RxDelay = 3000
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

& $launcher `
    -Session sample-analysis `
    -DosboxExe $DosboxExe `
    -TraceLevel basic `
    -Cycles $Cycles `
    -RxDelay $RxDelay `
    -HangMs 30000
