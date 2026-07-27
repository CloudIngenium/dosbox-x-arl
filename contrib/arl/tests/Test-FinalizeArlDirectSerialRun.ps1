<#
.SYNOPSIS
    Behavioural tests for Finalize-ArlDirectSerialRun.ps1's wait-for-DOSBox contract.

.DESCRIPTION
    The finalizer's wait is the one place where a lab session can be lost outright, so the
    property under test is not "does it wait" but "does the run survive the wait, whatever
    DOSBox does". Until 2026-07-26 reaching the timeout threw, and two real production sessions
    were stranded that way -- unfinalized, therefore never uploaded, and discovered only because
    someone went looking for a specific colada.

    Run from anywhere:  pwsh -NoProfile -File contrib/arl/tests/Test-FinalizeArlDirectSerialRun.ps1
    Exits non-zero on the first failure.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$finalizer = Join-Path (Split-Path -Parent $PSScriptRoot) 'Finalize-ArlDirectSerialRun.ps1'
if (-not (Test-Path -LiteralPath $finalizer -PathType Leaf)) { throw "finalizer not found: $finalizer" }

$failures = 0
function Assert-Equal([string]$Name, $Expected, $Actual) {
    if ($Expected -eq $Actual) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name -- expected '$Expected', got '$Actual'"; $script:failures++ }
}

# A process we can hold open (or let exit) to stand in for DOSBox on any platform.
function Start-Placeholder([int]$Seconds) {
    if ($IsWindows) { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "timeout /t $Seconds /nobreak" -WindowStyle Hidden -PassThru }
    else { Start-Process -FilePath '/bin/sleep' -ArgumentList "$Seconds" -PassThru }
}

function New-RunDirectory([string]$Root, [string]$Name) {
    $run = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $run | Out-Null
    return $run
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("finalize-tests-" + [guid]::NewGuid().ToString('N'))
$implus = Join-Path $root 'IMPLUS'
New-Item -ItemType Directory -Force -Path $implus | Out-Null

try {
    Write-Host 'DOSBox still open at the deadline: the run is finalized anyway, and says so'
    $run = New-RunDirectory $root 'sample-analysis-timeout'
    $process = Start-Placeholder 120
    try {
        & $finalizer -ParentPid $process.Id -ParentStartTime $process.StartTime `
            -RunDirectory $run -ImplusPath $implus -WaitTimeoutSeconds 2 | Out-Null
    } catch {
        Write-Host "  FAIL  finalizer threw instead of finalizing: $($_.Exception.Message)"
        $failures++
    } finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $markerPath = Join-Path $run 'directserial-finalized.json'
    Assert-Equal 'marker written (the session survives)' $true (Test-Path -LiteralPath $markerPath)
    if (Test-Path -LiteralPath $markerPath) {
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        Assert-Equal 'outcome recorded as a timeout' 'timeout_parent_still_running' $marker.metadata.finalize_wait_outcome
    }

    Write-Host 'DOSBox exits normally: unchanged fast path, recorded as a clean exit'
    $run2 = New-RunDirectory $root 'sample-analysis-clean-exit'
    $shortLived = Start-Placeholder 1
    $startTime = $shortLived.StartTime
    Start-Sleep -Seconds 3
    & $finalizer -ParentPid $shortLived.Id -ParentStartTime $startTime `
        -RunDirectory $run2 -ImplusPath $implus -WaitTimeoutSeconds 30 | Out-Null
    $marker2 = Get-Content -LiteralPath (Join-Path $run2 'directserial-finalized.json') -Raw | ConvertFrom-Json
    Assert-Equal 'outcome recorded as a clean exit' 'parent_exited' $marker2.metadata.finalize_wait_outcome
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) { Write-Host "$failures failure(s)"; exit 1 }
Write-Host 'all passed'
