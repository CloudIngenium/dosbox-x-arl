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
        Name = "00 DIRECTSERIAL BYPASS"
        Target = "Launch-ArlImpactDirectSerialBypass.cmd"
        BuildRequired = $false
    },
    @{
        Name = "01 OBSERVE ONLY"
        Target = "Launch-ArlImpactObserveOnlyTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "02 REACTIVE SAFE"
        Target = "Launch-ArlImpactReactiveSafeTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "03 STANDARDIZATION PASSIVE"
        Target = "Launch-ArlStandardizationPassiveTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "04 NORMALIZATION PASSIVE"
        Target = "Launch-ArlNormalizationPassiveTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "80 EMU NORMAL LOOP"
        Target = "Launch-ArlImpactEmulatorFormatSafeLoopTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "81 EMU LOWCHECK START"
        Target = "Launch-ArlImpactEmulatorLowChecksumStartTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "84 INSPECT CURRENT RUN"
        Target = "Inspect-ArlCurrentRun.cmd"
        BuildRequired = $false
    },
    @{
        Name = "86 PRINT EPSON RAW DRYRUN"
        Target = "Print-LatestArlLpt-Epson-Raw-DryRun.cmd"
        BuildRequired = $false
    },
    @{
        Name = "87 PRINT HP TEXT DRYRUN"
        Target = "Print-LatestArlLpt-HPSmartTank-Text-DryRun.cmd"
        BuildRequired = $false
    },
    @{
        Name = "88 PRINT EPSON RAW SEND"
        Target = "Print-LatestArlLpt-Epson-Raw-Send.cmd"
        BuildRequired = $false
    },
    @{
        Name = "89 PRINT HP TEXT SEND"
        Target = "Print-LatestArlLpt-HPSmartTank-Text-Send.cmd"
        BuildRequired = $false
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
            ($_.BaseName -match "ARL|IMPACT|CYCLES|SIMPLE|TRACE|TICS|UARTDATA|FORCELINES|HOLDRTS|RX4000|SAFE SERIAL|STABILITY|NOINT33|NO MOUSE|EMU|PRINT|INSPECT") -and
            -not $desiredNames.ContainsKey($name)
        } |
        Remove-Item -Force

    Get-ChildItem -Path $DesktopPath -File |
        Where-Object {
            $_.Extension -ne ".lnk" -and
            $_.BaseName -match "ARL|IMPACT|CYCLES|SIMPLE|TRACE|TICS|UARTDATA|FORCELINES|HOLDRTS|RX4000|SAFE SERIAL|STABILITY|EMU|PRINT|INSPECT"
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
