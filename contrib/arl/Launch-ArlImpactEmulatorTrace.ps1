param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",

    [string]$ProfilePath = "C:\ARL\DOSBox-X-ARL\profiles\impact-full-205041-sequence.json",

    [ValidateSet("happy-path", "silent-after-spark", "delayed-result", "line-drop", "bad-response")]
    [string]$Mode = "happy-path",

    [int]$Port = 3460,

    [int]$RxDelay = 1000,

    [int]$Cycles = 6000,

    [ValidateSet("normal", "simple", "dynamic", "auto")]
    [string]$Core = "normal",

    [string]$CpuType = "486",

    [string[]]$ImpactIniSet = @(),

    [string]$InitialControlLabel = "",

    [string]$InitialControlResponseAscii = "",

    [string]$InitialControlMatchAscii = "#rd 246`r",

    [int]$InitialControlDelayMs = 0,

    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $root "Start-ArlTraceRun.ps1"
if (-not (Test-Path -Path $launcher -PathType Leaf)) {
    throw "Start-ArlTraceRun.ps1 not found below $root"
}

if (-not (Test-Path -Path $DosboxExe -PathType Leaf)) {
    $candidate = Join-Path $root "dosbox-x-arl.exe"
    if (Test-Path -Path $candidate -PathType Leaf) {
        $DosboxExe = $candidate
    }
}

if (-not (Test-Path -Path $ProfilePath -PathType Leaf)) {
    throw "ARL emulator profile not found: $ProfilePath"
}

& $launcher `
    -Session impact-emulator `
    -DosboxExe $DosboxExe `
    -EmulatorProfilePath $ProfilePath `
    -EmulatorMode $Mode `
    -EmulatorPort $Port `
    -StartEmulator `
    -RxDelay $RxDelay `
    -Cycles $Cycles `
    -Core $Core `
    -CpuType $CpuType `
    -WindowResolution "original" `
    -VideoOutput "default" `
    -Aspect $false `
    -Scaler "normal2x" `
    -EmulatorInitialControlLabel $InitialControlLabel `
    -EmulatorInitialControlResponseAscii $InitialControlResponseAscii `
    -EmulatorInitialControlMatchAscii $InitialControlMatchAscii `
    -EmulatorInitialControlDelayMs $InitialControlDelayMs `
    -ImpactIniSet $ImpactIniSet `
    -HangMs 30000 `
    -NoLaunch:$NoLaunch
