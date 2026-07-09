param(
    [string]$ToolkitRoot = "C:\ARL\DOSBox-X-ARL",
    [string]$DesktopPath = "C:\Users\Public\Desktop",
    [string]$IconPath = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [string]$DiagnosticsPath = "C:\ARL\diagnostics",
    [switch]$NoCleanup,
    [switch]$IncludeBuildRequired
)

$ErrorActionPreference = "Stop"

$shortcuts = @(
    @{
        Name = "00 BASELINE - 6000 486"
        Target = "Launch-ArlImpactCycles6000Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "01 NOAUTOPRINT - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386NoAutoPrintTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "02 NO MOUSE.COM - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386NoMouseTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "03 NOUMB - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386NoUmbTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "04 EMSBOARD - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386EmsBoardTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "05 EMM386 - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386Emm386Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "06 ZEROEMS - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386ZeroEmsTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "07 ZEROXMS - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386ZeroXmsTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "08 MCBCOMPAT - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386McbCompatTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "09 NOSHARE - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386NoShareTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "10 UNMASKDISKIO - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386UnmaskTimerDiskIoTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "11 NOINT33 - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386NoInt33Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "20 INI ICSDELAY200 - 6000"
        Target = "Launch-ArlImpactIniIcsDelay200Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "21 INI ICSDELAY300 - 6000"
        Target = "Launch-ArlImpactIniIcsDelay300Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "22 INI BOOTSTATUS OFF - 6000"
        Target = "Launch-ArlImpactIniBootStatusOffTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "23 INI TRACE OFF - 6000"
        Target = "Launch-ArlImpactIniTraceOffTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "80 EMU SAFE LOOP"
        Target = "Launch-ArlImpactEmulatorFormatSafeLoopTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "81 EMU COMPAC ON SAFE LOOP"
        Target = "Launch-ArlImpactEmulatorCompacOnSafeLoopTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "82 EMU COMPAC AUTO SAFE LOOP"
        Target = "Launch-ArlImpactEmulatorCompacAutoSafeLoopTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "83 EMU STORE PARTIAL SAFE LOOP"
        Target = "Launch-ArlImpactEmulatorStorePartialSafeLoopTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "90 EMU GOOD-THEN-REJECT"
        Target = "Launch-ArlImpactEmulatorTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "91 EMU REJECT-FIRST"
        Target = "Launch-ArlImpactEmulatorRejectFirstTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "92 EMU CLAMP SUSPECTS"
        Target = "Launch-ArlImpactEmulatorClampedSuspectsTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "93 EMU CHECKSUM099"
        Target = "Launch-ArlImpactEmulatorChecksum099Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "94 EMU CHECKSUM100"
        Target = "Launch-ArlImpactEmulatorChecksum100Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "95 EMU CHECKSUM SWEEP"
        Target = "Launch-ArlImpactEmulatorChecksumSweepTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "96 EMU FORMAT EQUIV"
        Target = "Launch-ArlImpactEmulatorFormatEquivalenceTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "97 EMU CHECKSUM GRAMMAR"
        Target = "Launch-ArlImpactEmulatorChecksumGrammarTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "98 EMU FORMAT SAFE"
        Target = "Launch-ArlImpactEmulatorFormatSafeTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "99 FORCELINES - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386ForceLinesTrace.cmd"
        BuildRequired = $true
    },
    @{
        Name = "99 HOLDRTS-DTR - 6000 SIMPLE386"
        Target = "Launch-ArlImpactCycles6000Simple386HoldRtsDtrTrace.cmd"
        BuildRequired = $true
    }
)

New-Item -ItemType Directory -Force -Path $DesktopPath | Out-Null
$wsh = New-Object -ComObject WScript.Shell

$desiredNames = @{}
foreach ($item in $shortcuts) {
    if ($item.BuildRequired -and -not $IncludeBuildRequired) { continue }
    $desiredNames["$($item.Name).lnk".ToLowerInvariant()] = $true
}
$desiredNames["Diagnostics - Serial Traces.lnk".ToLowerInvariant()] = $true

if (-not $NoCleanup) {
    Get-ChildItem -Path $DesktopPath -Filter "*.lnk" -File |
        Where-Object {
            $name = $_.Name.ToLowerInvariant()
            ($_.BaseName -match "ARL|IMPACT|CYCLES|SIMPLE|TRACE|TICS|UARTDATA|FORCELINES|HOLDRTS|RX4000|SAFE SERIAL|STABILITY|NOINT33|NO MOUSE|EMU") -and
            -not $desiredNames.ContainsKey($name)
        } |
        Remove-Item -Force

    Get-ChildItem -Path $DesktopPath -File |
        Where-Object {
            $_.Extension -ne ".lnk" -and
            $_.BaseName -match "ARL|IMPACT|CYCLES|SIMPLE|TRACE|TICS|UARTDATA|FORCELINES|HOLDRTS|RX4000|SAFE SERIAL|STABILITY|EMU"
        } |
        Remove-Item -Force
}

$created = foreach ($item in $shortcuts) {
    if ($item.BuildRequired -and -not $IncludeBuildRequired) {
        continue
    }

    $targetPath = Join-Path $ToolkitRoot $item.Target
    if (-not (Test-Path -Path $targetPath -PathType Leaf)) {
        throw "Shortcut target does not exist: $targetPath"
    }

    $shortcutPath = Join-Path $DesktopPath "$($item.Name).lnk"
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.WorkingDirectory = $ToolkitRoot
    if (Test-Path -Path $IconPath -PathType Leaf) {
        $shortcut.IconLocation = "$IconPath,0"
    }
    $shortcut.Save()

    [pscustomobject]@{
        Name = $item.Name
        Path = $shortcutPath
        Target = $targetPath
        BuildRequired = [bool]$item.BuildRequired
        Exists = Test-Path -Path $targetPath -PathType Leaf
    }
}

if (Test-Path -Path $DiagnosticsPath -PathType Container) {
    $diagnosticsShortcut = Join-Path $DesktopPath "Diagnostics - Serial Traces.lnk"
    $shortcut = $wsh.CreateShortcut($diagnosticsShortcut)
    $shortcut.TargetPath = $DiagnosticsPath
    $shortcut.WorkingDirectory = $DiagnosticsPath
    if (Test-Path -Path $IconPath -PathType Leaf) {
        $shortcut.IconLocation = "$IconPath,0"
    }
    $shortcut.Save()
}

$created | Format-Table -AutoSize
