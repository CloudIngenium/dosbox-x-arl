param(
    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [int]$Cycles = 8000,
    [int]$RxDelay = 3000,
    [ValidateSet("normal", "simple", "dynamic", "auto")]
    [string]$Core = "normal",
    [string]$CpuType = "486",
    [ValidateRange(1, 63)]
    [int]$MemSize = 16,
    [bool]$Xms = $true,
    [object]$Ems = $true,
    [bool]$Umb = $true,
    [bool]$LoadMouse = $true,
    [bool]$Int33 = $true,
    [bool]$BiosPs2 = $true,
    [bool]$KeyboardAux = $true,
    [ValidateSet("intellimouse", "2button", "3button", "none")]
    [string]$AuxDevice = "intellimouse",
    [bool]$ZeroMemoryOnEmsAllocation = $false,
    [bool]$ZeroMemoryOnXmsAllocation = $false,
    [bool]$McbCorruptionBecomesApplicationFreeMemory = $false,
    [bool]$Share = $true,
    [bool]$UnmaskTimerOnDiskIo = $false,
    [switch]$ArlForceCts,
    [switch]$ArlForceDsr,
    [switch]$ArlForceDcd,
    [switch]$ArlHoldRts,
    [switch]$ArlHoldDtr,
    [string]$WindowResolution = "1280x960",
    [ValidateSet("default", "surface", "opengl", "openglnb", "openglpp", "direct3d", "ttf")]
    [string]$VideoOutput = "openglnb",
    [bool]$Aspect = $true,
    [string]$Scaler = "none",
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
    $candidate = Join-Path $root "dosbox-x-arl.exe"
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
    WindowResolution = $WindowResolution
    VideoOutput = $VideoOutput
    Aspect = $Aspect
    Scaler = $Scaler
    Cycles = $Cycles
    RxDelay = $RxDelay
    Core = $Core
    CpuType = $CpuType
    MemSize = $MemSize
    Xms = $Xms
    Ems = $Ems
    Umb = $Umb
    LoadMouse = $LoadMouse
    Int33 = $Int33
    BiosPs2 = $BiosPs2
    KeyboardAux = $KeyboardAux
    AuxDevice = $AuxDevice
    ZeroMemoryOnEmsAllocation = $ZeroMemoryOnEmsAllocation
    ZeroMemoryOnXmsAllocation = $ZeroMemoryOnXmsAllocation
    McbCorruptionBecomesApplicationFreeMemory = $McbCorruptionBecomesApplicationFreeMemory
    Share = $Share
    UnmaskTimerOnDiskIo = $UnmaskTimerOnDiskIo
    HangMs = 30000
}
if ($ArlForceCts) { $runArgs.ArlForceCts = $true }
if ($ArlForceDsr) { $runArgs.ArlForceDsr = $true }
if ($ArlForceDcd) { $runArgs.ArlForceDcd = $true }
if ($ArlHoldRts) { $runArgs.ArlHoldRts = $true }
if ($ArlHoldDtr) { $runArgs.ArlHoldDtr = $true }

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
