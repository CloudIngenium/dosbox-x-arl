param(
    [string]$ToolkitRoot = "C:\ARL\DOSBox-X-ARL",
    [string]$DesktopPath = "C:\Users\Public\Desktop",
    [string]$IconPath = "C:\ARL\DOSBox-X-ARL\dosbox-x-arl.exe",
    [switch]$IncludeBuildRequired
)

$ErrorActionPreference = "Stop"

$shortcuts = @(
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 NOMOUSE TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386NoMouseTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 NOUMB TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386NoUmbTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 NOAUTOPRINT TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386NoAutoPrintTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 EMSBOARD TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386EmsBoardTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 EMM386 TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386Emm386Trace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 ZEROEMS TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386ZeroEmsTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 ZEROXMS TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386ZeroXmsTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 MCBCOMPAT TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386McbCompatTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 NOSHARE TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386NoShareTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 UNMASKDISKIO TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386UnmaskTimerDiskIoTrace.cmd"
        BuildRequired = $false
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 FORCELINES TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386ForceLinesTrace.cmd"
        BuildRequired = $true
    },
    @{
        Name = "ARL IMPACT+ CYCLES6000 SIMPLE386 HOLDRTS-DTR TRACE"
        Target = "Launch-ArlImpactCycles6000Simple386HoldRtsDtrTrace.cmd"
        BuildRequired = $true
    }
)

New-Item -ItemType Directory -Force -Path $DesktopPath | Out-Null
$wsh = New-Object -ComObject WScript.Shell

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

$created | Format-Table -AutoSize
