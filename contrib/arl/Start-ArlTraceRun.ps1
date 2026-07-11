param(
    [ValidateSet("impact", "tics", "status-only", "sample-analysis", "impact-emulator", "tics-emulator")]
    [string]$Session = "impact",

    [string]$DosboxExe = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [string]$ArlRoot = "C:\ARL",
    [string]$ImplusPath = "C:\ARL\IMPLUS",
    [string]$ComPort = "COM5",
    [string]$EmulatorHost = "127.0.0.1",
    [int]$EmulatorPort = 3460,
    [ValidateSet("happy-path", "silent-after-spark", "delayed-result", "line-drop", "bad-response")]
    [string]$EmulatorMode = "happy-path",
    [string]$EmulatorProfilePath = (Join-Path $PSScriptRoot "profiles\arl3460-baseline.json"),
    [switch]$StartEmulator,
    [string]$EmulatorInitialControlLabel = "",
    [string]$EmulatorInitialControlResponseAscii = "",
    [string]$EmulatorInitialControlMatchAscii = "#rd 246`r",
    [int]$EmulatorInitialControlDelayMs = 0,
    [string]$WindowResolution = "1280x960",
    [ValidateSet("default", "surface", "opengl", "openglnb", "openglpp", "direct3d", "ttf")]
    [string]$VideoOutput = "openglnb",
    [bool]$Aspect = $true,
    [string]$Scaler = "none",
    [int]$RxDelay = 1000,
    [int]$Cycles = 12000,
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
    [switch]$ArlResultObserve,
    [ValidateSet("basic", "uartdata", "uart", "full")]
    [string]$TraceLevel = "basic",
    [int]$HangMs = 15000,
    [ValidateRange(0, 4096)]
    [int]$TraceMaxMb = 64,
    [string]$RunRoot = "C:\ARL\diagnostics",
    [switch]$AutoPrintLpt,
    [string]$PrinterName = "EPSON LX-350",
    [ValidateSet("Raw", "Text")]
    [string]$PrintMode = "Raw",
    [int]$LptIdleMs = 2500,
    [int]$LptPollMs = 500,
    [switch]$NoLptFormFeed,
    [bool]$CleanImpactTemp = $true,
    [string[]]$ImpactIniSet = @(),
    [switch]$Wait,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

function Join-ArlPath([string]$Base, [string]$Child) {
    if ($Base -match '^[A-Za-z]:') {
        return "$($Base.TrimEnd([char[]]'\/'))\$Child"
    }
    return Join-Path $Base $Child
}

function Quote-PowerShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertTo-ArlDosOption([object]$Value, [string]$Name, [string[]]$AllowedValues) {
    if ($Value -is [bool]) {
        $text = if ($Value) { "true" } else { "false" }
    } elseif ($null -eq $Value) {
        throw "$Name cannot be null"
    } else {
        $text = ([string]$Value).Trim().ToLowerInvariant()
        if ($text -eq "1") { $text = "true" }
        if ($text -eq "0") { $text = "false" }
    }

    if ($AllowedValues -notcontains $text) {
        throw "$Name must be one of: $($AllowedValues -join ', ')"
    }

    return $text
}

function Stop-StaleArlEmulatorProcesses([int]$Port) {
    $stalePids = New-Object System.Collections.Generic.HashSet[int]

    try {
        $connections = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
        foreach ($connection in $connections) {
            if ($connection.OwningProcess -gt 0) {
                [void]$stalePids.Add([int]$connection.OwningProcess)
            }
        }
    } catch {
        # Older Windows builds may not expose Get-NetTCPConnection in this context.
    }

    $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { ([string]$_.CommandLine) -match "Start-ArlEmulator\.ps1" })

    foreach ($process in $processes) {
        if ($stalePids.Count -eq 0 -or $stalePids.Contains([int]$process.ProcessId)) {
            Write-Host "Stopping stale ARL emulator PID $($process.ProcessId)"
            try {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
            } catch {
                Write-Warning "Could not stop stale ARL emulator PID $($process.ProcessId): $($_.Exception.Message)"
            }
        }
    }
}

function Invoke-ImpactTempCleanup([string]$ImpactPath, [string]$BackupRoot) {
    $tempNames = @(
        "tmh",
        "impact.dbf",
        "telex.sav",
        "temp.tmp",
        "result.tmp",
        "qafile.flg",
        "qanofile.flg",
        "spc.flg",
        "notdone.flg",
        "report.x",
        "telex.dat",
        "telex.def"
    )

    $backupDir = Join-ArlPath $BackupRoot "impact-temp-before-start"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    $manifest = New-Object System.Collections.Generic.List[object]
    foreach ($name in $tempNames) {
        $path = Join-ArlPath $ImpactPath $name
        if (-not (Test-Path -Path $path -PathType Leaf)) {
            continue
        }

        $backupPath = Join-ArlPath $backupDir $name
        Copy-Item -Path $path -Destination $backupPath -Force
        $item = Get-Item -Path $path
        [void]$manifest.Add([pscustomobject]@{
            name = $name
            path = $path
            backup_path = $backupPath
            length = $item.Length
            last_write_time = $item.LastWriteTime
        })
        Remove-Item -Path $path -Force
        Write-Host "Deleted stale IMPACT temp file: $path"
    }

    $manifestPath = Join-ArlPath $backupDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding UTF8
    return [pscustomobject]@{
        backup_dir = $backupDir
        manifest_path = $manifestPath
        deleted_count = $manifest.Count
        deleted_names = @($manifest | ForEach-Object { $_.name })
    }
}

function Set-ImpactIniValues([string]$ImpactPath, [string]$BackupRoot, [string[]]$Assignments) {
    if ($Assignments.Count -eq 0) {
        return $null
    }

    $iniPath = Join-ArlPath $ImpactPath "IMPACT.INI"
    if (-not (Test-Path -Path $iniPath -PathType Leaf)) {
        throw "IMPACT.INI not found: $iniPath"
    }

    $backupDir = Join-ArlPath $BackupRoot "impact-ini-before-start"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backupPath = Join-ArlPath $backupDir "IMPACT.INI"
    Copy-Item -Path $iniPath -Destination $backupPath -Force

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in [System.IO.File]::ReadAllLines($iniPath)) {
        [void]$lines.Add($line)
    }

    $applied = New-Object System.Collections.Generic.List[object]
    foreach ($assignment in $Assignments) {
        if ($assignment -notmatch '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
            throw "Invalid IMPACT.INI assignment '$assignment'. Use 'Key=Value'."
        }

        $key = $Matches[1].Trim()
        $value = $Matches[2].Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "Invalid IMPACT.INI assignment '$assignment'. Empty key."
        }

        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*([^;][^=]*?)\s*=') {
                $existingKey = $Matches[1].Trim()
                if ([string]::Equals($existingKey, $key, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $oldValue = $lines[$i]
                    $lines[$i] = "$existingKey = $value"
                    [void]$applied.Add([pscustomobject]@{
                        key = $existingKey
                        old_line = $oldValue
                        new_line = $lines[$i]
                    })
                    $found = $true
                    break
                }
            }
        }

        if (-not $found) {
            throw "IMPACT.INI key not found: $key"
        }
    }

    [System.IO.File]::WriteAllLines($iniPath, $lines, [System.Text.Encoding]::ASCII)
    $manifestPath = Join-ArlPath $backupDir "manifest.json"
    $manifest = [pscustomobject]@{
        ini_path = $iniPath
        backup_path = $backupPath
        assignments = @($Assignments)
        applied = @($applied.ToArray())
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

    return [pscustomobject]@{
        ini_path = $iniPath
        backup_path = $backupPath
        manifest_path = $manifestPath
        assignments = @($Assignments)
        applied = @($applied.ToArray())
    }
}

$xmsText = ConvertTo-ArlDosOption $Xms "Xms" @("true", "false")
$emsText = ConvertTo-ArlDosOption $Ems "Ems" @("true", "false", "emsboard", "emm386")
$umbText = ConvertTo-ArlDosOption $Umb "Umb" @("true", "false")
$int33Text = ConvertTo-ArlDosOption $Int33 "Int33" @("true", "false")
$biosPs2Text = ConvertTo-ArlDosOption $BiosPs2 "BiosPs2" @("true", "false")
$keyboardAuxText = ConvertTo-ArlDosOption $KeyboardAux "KeyboardAux" @("true", "false")

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-ArlPath $RunRoot "$Session-$stamp"
$runSuffix = 1
while (Test-Path -Path $runDir) {
    $runSuffix++
    $runDir = Join-ArlPath $RunRoot "$Session-$stamp-$runSuffix"
}
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$impactTempCleanup = $null
if ($CleanImpactTemp) {
    $impactTempCleanup = Invoke-ImpactTempCleanup -ImpactPath $ImplusPath -BackupRoot $runDir
}

$impactIniOverride = Set-ImpactIniValues -ImpactPath $ImplusPath -BackupRoot $runDir -Assignments $ImpactIniSet

$tracePath = Join-ArlPath $runDir "serial.ndjson"
$emulatorTracePath = Join-ArlPath $runDir "emulator.ndjson"
$logPath = Join-ArlPath $runDir "dosbox.log"
$confPath = Join-ArlPath $runDir "dosbox-$Session.conf"
$lptPath = Join-ArlPath $runDir "LPTCAP.PRN"
$lptSpoolDir = Join-ArlPath $runDir "print-jobs"
$lptWatchLogPath = Join-ArlPath $runDir "lpt-watch.log"
$lptWatchErrPath = Join-ArlPath $runDir "lpt-watch.err.log"
$lptWatchLaunchPath = Join-ArlPath $runDir "lpt-watch-launch.ps1"
$interfacPath = Join-ArlPath $ImplusPath "INTERFAC.DAT"
$usesEmulator = $Session -eq "impact-emulator" -or $Session -eq "tics-emulator"
$usesTics = $Session -eq "tics" -or $Session -eq "tics-emulator"

if ($usesTics) {
    New-Item -ItemType Directory -Force -Path (Join-ArlPath $ImplusPath "TICS\PROC") | Out-Null

    foreach ($extension in @("DBI", "TXT", "HLP")) {
        $source = Join-ArlPath $ImplusPath "TICS\DBTICSOE.$extension"
        $target = Join-ArlPath $ImplusPath "TICS\DBTICS.$extension"
        if ((Test-Path -Path $source -PathType Leaf) -and -not (Test-Path -Path $target -PathType Leaf)) {
            Copy-Item -Path $source -Destination $target
        }
    }
}

switch ($Session) {
    { $_ -eq "tics" -or $_ -eq "tics-emulator" } {
        $autoexecCommand = @"
if exist TICS\TICS.EXE cd TICS
TICS
"@
    }
    "status-only" {
        $autoexecCommand = "ARLTRACE STATUS"
    }
    default {
        $autoexecCommand = "implus"
    }
}

if ($usesEmulator) {
    $serialLine = "serial1 = nullmodem server:$EmulatorHost port:$EmulatorPort transparent:1 rxdelay:$RxDelay"
    $serialComment = "# Emulator session: nullmodem over localhost. This never opens $ComPort."
} else {
    $traceLimitOption = if ($TraceMaxMb -gt 0) { " arltracemaxmb:$TraceMaxMb" } else { "" }
    $lineOptions = New-Object System.Collections.Generic.List[string]
    if ($ArlForceCts) { $lineOptions.Add("arlforcects:1") }
    if ($ArlForceDsr) { $lineOptions.Add("arlforcedsr:1") }
    if ($ArlForceDcd) { $lineOptions.Add("arlforcedcd:1") }
    if ($ArlHoldRts) { $lineOptions.Add("arlholdrts:1") }
    if ($ArlHoldDtr) { $lineOptions.Add("arlholddtr:1") }
    if ($ArlResultObserve) { $lineOptions.Add("arlresultobserve:1") }
    $lineOptionsText = if ($lineOptions.Count -gt 0) { " " + ($lineOptions -join " ") } else { "" }
    $serialLine = "serial1 = directserial realport:$ComPort rxdelay:$RxDelay arltracelevel:$TraceLevel arltracesession:$Session arltracehangms:$HangMs$traceLimitOption$lineOptionsText arltrace:$tracePath"
    $serialComment = "# Direct ARL session: opens the real Windows serial port."
}

$emulatorScriptPath = Join-ArlPath $PSScriptRoot "Start-ArlEmulator.ps1"
$emulatorControlPath = Join-ArlPath $runDir "emulator-control.json"
$powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$emulatorCommand = "$powerShellExe -NoProfile -ExecutionPolicy Bypass -File `"$emulatorScriptPath`" -Mode $EmulatorMode -ProfilePath `"$EmulatorProfilePath`" -ListenAddress $EmulatorHost -Port $EmulatorPort -Session $Session -LogPath `"$emulatorTracePath`" -ControlPath `"$emulatorControlPath`" -MaxConnections 1"
$mouseCommand = if ($LoadMouse) { "DOS\MOUSE.COM" } else { "rem DOS\\MOUSE.COM disabled for memory-layout test" }

$conf = @"
# Generated by Start-ArlTraceRun.ps1
# Run directory: $runDir

[sdl]
fullscreen = false
windowresolution = $WindowResolution
output = $VideoOutput
autolock = false

[render]
aspect = $($Aspect.ToString().ToLowerInvariant())
scaler = $Scaler

[dosbox]
machine = svga_s3
captures = $runDir
memsize = $MemSize
logfile = $logPath

[cpu]
core = $Core
cputype = $CpuType
cycles = fixed $Cycles

[serial]
$serialComment
$serialLine
serial2 = disabled
serial3 = disabled
serial4 = disabled

[parallel]
parallel1 = file append:$lptPath timeout:2000
parallel2 = disabled

[keyboard]
aux = $keyboardAuxText
auxdevice = $AuxDevice

[dos]
xms = $xmsText
ems = $emsText
umb = $umbText
int33 = $int33Text
biosps2 = $biosPs2Text
zero memory on ems memory allocation = $($ZeroMemoryOnEmsAllocation.ToString().ToLowerInvariant())
zero memory on xms memory allocation = $($ZeroMemoryOnXmsAllocation.ToString().ToLowerInvariant())
mcb corruption becomes application free memory = $($McbCorruptionBecomesApplicationFreeMemory.ToString().ToLowerInvariant())
share = $($Share.ToString().ToLowerInvariant())
unmask timer on disk io = $($UnmaskTimerOnDiskIo.ToString().ToLowerInvariant())

[autoexec]
mount c "$ImplusPath"
c:
$mouseCommand
$autoexecCommand
"@

$conf | Set-Content -Path $confPath -Encoding ASCII

$metadata = [pscustomobject]@{
    session = $Session
    created = (Get-Date).ToString("o")
    run_dir = $runDir
    dosbox_exe = $DosboxExe
    config = $confPath
    window_resolution = $WindowResolution
    video_output = $VideoOutput
    aspect = $Aspect
    scaler = $Scaler
    trace = if ($usesEmulator) { $null } else { $tracePath }
    emulator_trace = if ($usesEmulator) { $emulatorTracePath } else { $null }
    emulator_control = if ($usesEmulator) { $emulatorControlPath } else { $null }
    log = $logPath
    interfac_dat = $interfacPath
    com_port = $ComPort
    serial_backend = if ($usesEmulator) { "nullmodem-emulator" } else { "directserial" }
    emulator_host = if ($usesEmulator) { $EmulatorHost } else { $null }
    emulator_port = if ($usesEmulator) { $EmulatorPort } else { $null }
    emulator_mode = if ($usesEmulator) { $EmulatorMode } else { $null }
    emulator_profile = if ($usesEmulator) { $EmulatorProfilePath } else { $null }
    emulator_command = if ($usesEmulator) { $emulatorCommand } else { $null }
    emulator_auto_started = if ($usesEmulator) { [bool]$StartEmulator } else { $null }
    emulator_initial_control_label = if ($usesEmulator -and -not [string]::IsNullOrWhiteSpace($EmulatorInitialControlResponseAscii)) { $EmulatorInitialControlLabel } else { $null }
    emulator_initial_control_match_ascii = if ($usesEmulator -and -not [string]::IsNullOrWhiteSpace($EmulatorInitialControlResponseAscii)) { $EmulatorInitialControlMatchAscii } else { $null }
    rxdelay = $RxDelay
    cycles = $Cycles
    core = $Core
    cputype = $CpuType
    memsize = $MemSize
    xms = $xmsText
    ems = $emsText
    umb = $umbText
    load_mouse = $LoadMouse
    int33 = $int33Text
    biosps2 = $biosPs2Text
    keyboard_aux = $keyboardAuxText
    auxdevice = $AuxDevice
    clean_impact_temp = $CleanImpactTemp
    impact_temp_cleanup = $impactTempCleanup
    impact_ini_override = $impactIniOverride
    zero_memory_on_ems_memory_allocation = $ZeroMemoryOnEmsAllocation
    zero_memory_on_xms_memory_allocation = $ZeroMemoryOnXmsAllocation
    mcb_corruption_becomes_application_free_memory = $McbCorruptionBecomesApplicationFreeMemory
    share = $Share
    unmask_timer_on_disk_io = $UnmaskTimerOnDiskIo
    arl_force_cts = [bool]$ArlForceCts
    arl_force_dsr = [bool]$ArlForceDsr
    arl_force_dcd = [bool]$ArlForceDcd
    arl_hold_rts = [bool]$ArlHoldRts
    arl_hold_dtr = [bool]$ArlHoldDtr
    arl_result_observe = [bool]$ArlResultObserve
    trace_level = if ($usesEmulator) { $null } else { $TraceLevel }
    hang_ms = $HangMs
    trace_max_mb = if ($usesEmulator) { $null } else { $TraceMaxMb }
    lpt_capture = $lptPath
    auto_print_lpt = [bool]$AutoPrintLpt
    printer_name = if ($AutoPrintLpt) { $PrinterName } else { $null }
    print_mode = if ($AutoPrintLpt) { $PrintMode } else { $null }
    lpt_idle_ms = if ($AutoPrintLpt) { $LptIdleMs } else { $null }
    lpt_spool_dir = if ($AutoPrintLpt) { $lptSpoolDir } else { $null }
    lpt_append_form_feed = if ($AutoPrintLpt) { -not [bool]$NoLptFormFeed } else { $null }
    lpt_watcher_launch = if ($AutoPrintLpt) { $lptWatchLaunchPath } else { $null }
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-ArlPath $runDir "run-metadata.json") -Encoding UTF8

Write-Host "Run directory: $runDir"
Write-Host "Config: $confPath"
if ($usesEmulator) {
    Write-Host "Emulator trace: $emulatorTracePath"
    Write-Host "Emulator control: $emulatorControlPath"
    if ($StartEmulator) {
        Write-Host "Emulator will be started automatically."
    } else {
        Write-Host "Start emulator first:"
        Write-Host $emulatorCommand
    }
} else {
    Write-Host "Trace: $tracePath"
}
Write-Host "Log: $logPath"

if ($NoLaunch) {
    if ($null -ne $impactIniOverride -and (Test-Path -Path $impactIniOverride.backup_path -PathType Leaf)) {
        Copy-Item -Path $impactIniOverride.backup_path -Destination $impactIniOverride.ini_path -Force
        Write-Host "NoLaunch set; restored IMPACT.INI from $($impactIniOverride.backup_path)"
    }
    Write-Host "NoLaunch set; DOSBox-X was not started."
    exit 0
}

if (-not (Test-Path -Path $DosboxExe -PathType Leaf)) {
    throw "DOSBox-X ARL executable not found: $DosboxExe"
}

$watcherScriptPath = $null
$printScriptPath = $null
if ($AutoPrintLpt -and -not $usesEmulator) {
    $watcherScriptPath = Join-ArlPath $PSScriptRoot "Watch-ArlLptCapture.ps1"
    $printScriptPath = Join-ArlPath $PSScriptRoot "Print-ArlLptCapture.ps1"
    if (-not (Test-Path -Path $watcherScriptPath -PathType Leaf)) {
        throw "LPT watcher script not found: $watcherScriptPath"
    }
    if (-not (Test-Path -Path $printScriptPath -PathType Leaf)) {
        throw "LPT print script not found: $printScriptPath"
    }
}

$emulatorProcess = $null
if ($usesEmulator -and $StartEmulator) {
    if (-not (Test-Path -Path $emulatorScriptPath -PathType Leaf)) {
        throw "ARL emulator script not found: $emulatorScriptPath"
    }
    if (-not (Test-Path -Path $EmulatorProfilePath -PathType Leaf)) {
        throw "ARL emulator profile not found: $EmulatorProfilePath"
    }
    Stop-StaleArlEmulatorProcesses -Port $EmulatorPort
    $initialControlEnabled = -not [string]::IsNullOrWhiteSpace($EmulatorInitialControlResponseAscii)
    $initialControlLabel = if ([string]::IsNullOrWhiteSpace($EmulatorInitialControlLabel)) { "initial-control-response" } else { $EmulatorInitialControlLabel }
    $initialControlRules = @()
    if ($initialControlEnabled) {
        $initialControlResponseAscii = $EmulatorInitialControlResponseAscii.Replace("\r", "`r").Replace("\n", "`n")
        $initialControlMatchAscii = $EmulatorInitialControlMatchAscii.Replace("\r", "`r").Replace("\n", "`n")
        $initialControlRules = @(
            [ordered]@{
                label = $initialControlLabel
                phase = "analysis-result"
                match = "exact_ascii"
                pattern_ascii = $initialControlMatchAscii
                response_ascii = $initialControlResponseAscii
                delay_ms = $EmulatorInitialControlDelayMs
            }
        )
    }
    $controlTemplate = [ordered]@{
        enabled = $initialControlEnabled
        note = if ($initialControlEnabled) {
            "Initial emulator control enabled by launcher. This avoids operator timing during checksum experiments."
        } else {
            "Hot control file. Set enabled=true and add rules to override emulator responses without restarting IMPACT."
        }
        examples = @(
            [ordered]@{
                label = "override-next-result-read"
                match = "exact_ascii"
                pattern_ascii = "#rd 246`r"
                response_ascii = "0.500,1.715,1.345,5.0958,5.64,0.239,0.995,0.382,0.2481,6.057,0.079,0.560,75.49,1.6636 000`r"
                delay_ms = 0
            }
        )
        rules = $initialControlRules
    }
    $controlTemplate | ConvertTo-Json -Depth 8 | Set-Content -Path $emulatorControlPath -Encoding UTF8
    $emulatorArgs = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $emulatorScriptPath,
        "-Mode",
        $EmulatorMode,
        "-ProfilePath",
        $EmulatorProfilePath,
        "-ListenAddress",
        $EmulatorHost,
        "-Port",
        [string]$EmulatorPort,
        "-Session",
        $Session,
        "-LogPath",
        $emulatorTracePath,
        "-ControlPath",
        $emulatorControlPath,
        "-MaxConnections",
        "1"
    )
    $emulatorProcess = Start-Process -FilePath $powerShellExe -ArgumentList $emulatorArgs -WindowStyle Minimized -PassThru
    Write-Host "Started ARL emulator PID $($emulatorProcess.Id)"
    Start-Sleep -Milliseconds 750
}

$process = Start-Process -FilePath $DosboxExe -ArgumentList @("-conf", $confPath) -PassThru
Write-Host "Started DOSBox-X ARL PID $($process.Id)"

$directSerialFinalizerProcess = $null
if (-not $usesEmulator) {
    $finalizerScriptPath = Join-ArlPath $PSScriptRoot "Finalize-ArlDirectSerialRun.ps1"
    $finalizerLogPath = Join-ArlPath $runDir "directserial-finalizer.log"
    $finalizerErrorPath = Join-ArlPath $runDir "directserial-finalizer.err.log"
    if (-not (Test-Path -LiteralPath $finalizerScriptPath -PathType Leaf)) {
        throw "Directserial finalizer script not found: $finalizerScriptPath"
    }
    $directSerialFinalizerProcess = Start-Process -FilePath $powerShellExe `
        -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $finalizerScriptPath,
            "-ParentPid", [string]$process.Id,
            "-ParentStartTime", $process.StartTime.ToString("o"),
            "-RunDirectory", $runDir,
            "-ImplusPath", $ImplusPath
        ) `
        -RedirectStandardOutput $finalizerLogPath `
        -RedirectStandardError $finalizerErrorPath `
        -WindowStyle Hidden `
        -PassThru
    Write-Host "Started directserial bundle finalizer PID $($directSerialFinalizerProcess.Id)"
}

$iniRestoreProcess = $null
if ($null -ne $impactIniOverride) {
    $restoreScriptPath = Join-ArlPath $runDir "restore-impact-ini-after-dosbox.ps1"
    $restoreLogPath = Join-ArlPath $runDir "restore-impact-ini.log"
    $restoreErrPath = Join-ArlPath $runDir "restore-impact-ini.err.log"
    $restoreScript = @(
        '$ErrorActionPreference = "Stop"',
        "`$pidToWait = $($process.Id)",
        "`$iniPath = $(Quote-PowerShellLiteral $impactIniOverride.ini_path)",
        "`$backupPath = $(Quote-PowerShellLiteral $impactIniOverride.backup_path)",
        "`$impactPath = $(Quote-PowerShellLiteral $ImplusPath)",
        "`$runDir = $(Quote-PowerShellLiteral $runDir)",
        'try {',
        '    $p = Get-Process -Id $pidToWait -ErrorAction SilentlyContinue',
        '    if ($null -ne $p) { $p.WaitForExit() }',
        '    $postDir = Join-Path $runDir "impact-post-run-files"',
        '    New-Item -ItemType Directory -Force -Path $postDir | Out-Null',
        '    foreach ($name in @("INTERFAC.DAT","TELEX.DAT","TELEX.DEF","TELEX.SAV","TEMP.TMP","RESULT.TMP","IMPACT.DBF","SENTFILE.DAT","NOTDONE.FLG","REPORT.X")) {',
        '        $source = Join-Path $impactPath $name',
        '        if (Test-Path -Path $source -PathType Leaf) {',
        '            Copy-Item -Path $source -Destination (Join-Path $postDir $name) -Force',
        '        }',
        '    }',
        '    if (Test-Path -Path $backupPath -PathType Leaf) {',
        '        Copy-Item -Path $backupPath -Destination $iniPath -Force',
        '        Write-Host "Restored IMPACT.INI from $backupPath"',
        '    } else {',
        '        Write-Warning "Backup IMPACT.INI not found: $backupPath"',
        '    }',
        '} catch {',
        '    Write-Error $_',
        '    exit 1',
        '}'
    )
    $restoreScript | Set-Content -Path $restoreScriptPath -Encoding UTF8
    $iniRestoreProcess = Start-Process -FilePath $powerShellExe `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $restoreScriptPath) `
        -RedirectStandardOutput $restoreLogPath `
        -RedirectStandardError $restoreErrPath `
        -WindowStyle Hidden `
        -PassThru
    Write-Host "IMPACT.INI overrides active for this run only: $($ImpactIniSet -join '; ')"
    Write-Host "Started IMPACT.INI restore watcher PID $($iniRestoreProcess.Id)"
}

$watcherProcess = $null
if ($AutoPrintLpt -and -not $usesEmulator) {
    $watcherArgs = [ordered]@{
        CapturePath = $lptPath
        PrinterName = $PrinterName
        PrintMode = $PrintMode
        SpoolDir = $lptSpoolDir
        PrintScriptPath = $printScriptPath
        ParentPid = $process.Id
        ParentStartTime = $process.StartTime.ToString("o")
        IdleMs = $LptIdleMs
        PollMs = $LptPollMs
        Send = $true
    }
    if (-not $NoLptFormFeed) {
        $watcherArgs.AppendFormFeed = $true
    }

    $watcherLaunch = @(
        '$ErrorActionPreference = "Stop"',
        '$watcherArgs = @{'
    )
    foreach ($entry in $watcherArgs.GetEnumerator()) {
        $value = $entry.Value
        if ($value -is [bool]) {
            $renderedValue = if ($value) { '$true' } else { '$false' }
        } elseif ($value -is [int]) {
            $renderedValue = [string]$value
        } else {
            $renderedValue = Quote-PowerShellLiteral ([string]$value)
        }
        $watcherLaunch += "    $($entry.Key) = $renderedValue"
    }
    $watcherLaunch += @(
        '}',
        "& $(Quote-PowerShellLiteral $watcherScriptPath) @watcherArgs"
    )
    $watcherLaunch | Set-Content -Path $lptWatchLaunchPath -Encoding UTF8

    $watcherProcess = Start-Process -FilePath $powerShellExe `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $lptWatchLaunchPath) `
        -RedirectStandardOutput $lptWatchLogPath `
        -RedirectStandardError $lptWatchErrPath `
        -WindowStyle Hidden `
        -PassThru
    Write-Host "Started LPT watcher PID $($watcherProcess.Id)"
    Write-Host "LPT capture: $lptPath"
    Write-Host "LPT print jobs: $lptSpoolDir"
    Write-Host "LPT watcher log: $lptWatchLogPath"
}

if ($Wait) {
    $process.WaitForExit()
    if ($null -ne $watcherProcess) {
        $watcherProcess.WaitForExit(10000) | Out-Null
    }
    if ($null -ne $emulatorProcess) {
        $emulatorProcess.WaitForExit(10000) | Out-Null
    }
    if ($null -ne $iniRestoreProcess) {
        $iniRestoreProcess.WaitForExit(10000) | Out-Null
    }
    if ($null -ne $directSerialFinalizerProcess) {
        $directSerialFinalizerProcess.WaitForExit(10000) | Out-Null
    }
    if (Test-Path -Path $interfacPath -PathType Leaf) {
        Copy-Item -Path $interfacPath -Destination (Join-ArlPath $runDir "INTERFAC.DAT.after") -Force
    }
    Write-Host "DOSBox-X exited with code $($process.ExitCode)"
}
