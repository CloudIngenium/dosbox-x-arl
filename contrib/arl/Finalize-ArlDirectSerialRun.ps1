param(
    [Parameter(Mandatory = $true)][int]$ParentPid,
    [Parameter(Mandatory = $true)][datetime]$ParentStartTime,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][string]$ImplusPath,
    [string]$ResultFilesBeforePath = "",
    [string]$TraceFile = "serial.ndjson",
    [string]$DosBoxVersion = "dosbox-x-arl",
    [string]$WorkflowKind = "",
    [string]$WorkflowSnapshotBeforePath = "",
    [string]$WorkflowSnapshotScriptPath = "",
    [int]$WaitTimeoutSeconds = 86400
)

$ErrorActionPreference = "Stop"

function Copy-RunArtifact([string]$Source, [string]$DestinationName) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $false }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $RunDirectory $DestinationName) -Force
    return $true
}

# Wait for DOSBox to exit, then collect the run's evidence.
#
# The wait must never be allowed to DESTROY the session. Operators routinely leave DOSBox open
# between turns ("waiting until it is needed again"), so the timeout is reached in normal
# operation, not only when something is wrong -- and until 2026-07-26 reaching it threw, which
# left the run permanently unfinalized and therefore never uploaded. Two real production
# sessions were lost that way (sample-analysis-20260725-154514, carrying colada 31550, and
# sample-analysis-20260724-075735 with 157 attempts); both had to be finalized by hand, and the
# only reason anyone noticed is that someone went looking for a specific colada.
#
# So on timeout we finalize ANYWAY and record that we did. Collecting a run while DOSBox is
# still open risks capturing a session the operator may yet add to; losing it entirely is worse
# and certain. The outcome is written to the marker (`finalize_wait_outcome`) so a bundle
# collected under the timeout is never mistaken for one collected after a clean exit.
$waitStartedUtc = [datetime]::UtcNow
$deadline = $waitStartedUtc.AddSeconds($WaitTimeoutSeconds)
$heartbeatInterval = [timespan]::FromMinutes(15)
$nextHeartbeat = $waitStartedUtc.Add($heartbeatInterval)
$waitOutcome = "parent_exited"

while ([datetime]::UtcNow -lt $deadline) {
    $process = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
    if ($null -eq $process) { break }
    if ([math]::Abs(($process.StartTime - $ParentStartTime).TotalSeconds) -gt 2) {
        # The pid was recycled by an unrelated process - our DOSBox is gone.
        $waitOutcome = "parent_replaced"
        break
    }
    # A heartbeat, because a silent 0-byte log for 24 hours is indistinguishable from a finalizer
    # that never started. This line is what makes a stuck wait visible while it is still stuck.
    if ([datetime]::UtcNow -ge $nextHeartbeat) {
        $waitedMinutes = [math]::Round(([datetime]::UtcNow - $waitStartedUtc).TotalMinutes)
        Write-Host ("[{0:o}] still waiting for DOSBox pid {1} to exit ({2} min elapsed, timeout at {3:o})" -f `
            [datetime]::UtcNow, $ParentPid, $waitedMinutes, $deadline)
        $nextHeartbeat = [datetime]::UtcNow.Add($heartbeatInterval)
    }
    Start-Sleep -Milliseconds 500
}

if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
    $waitOutcome = "timeout_parent_still_running"
    Write-Host ("[{0:o}] DOSBox pid {1} did not exit within {2}s - finalizing anyway rather than losing the run." -f `
        [datetime]::UtcNow, $ParentPid, $WaitTimeoutSeconds)
}
$waitedSeconds = [int][math]::Round(([datetime]::UtcNow - $waitStartedUtc).TotalSeconds)

$artifacts = New-Object System.Collections.Generic.List[object]
$calibrationAccessTrace = Join-Path $RunDirectory "calibration-access.ndjson"
$accessedCalibrationFiles = @()
if (Test-Path -LiteralPath $calibrationAccessTrace -PathType Leaf) {
    $accessedCalibrationFiles = @(Get-Content -LiteralPath $calibrationAccessTrace | ForEach-Object {
        try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    } | Where-Object {
        $null -ne $_ -and
        (($_.event -eq "guest_impact_file_open" -and $_.kind -eq "calibration") -or $_.event -eq "guest_calibration_open") -and
        $_.path -match '(?i)\.CAL$'
    } | ForEach-Object {
        [IO.Path]::GetFileName(($_.path -replace '/', '\'))
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    foreach ($calibrationName in $accessedCalibrationFiles) {
        $source = Join-Path $ImplusPath $calibrationName
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $destinationName = "accessed-$calibrationName"
            Copy-Item -LiteralPath $source -Destination (Join-Path $RunDirectory $destinationName) -Force
            $artifacts.Add([ordered]@{ path = $destinationName; name = $destinationName; role = "calibration" })
        }
    }
}
$accessedResultFiles = @()
if (Test-Path -LiteralPath $calibrationAccessTrace -PathType Leaf) {
    $accessedResultFiles = @(Get-Content -LiteralPath $calibrationAccessTrace | ForEach-Object {
        try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    } | Where-Object {
        $null -ne $_ -and $_.event -eq "guest_impact_file_open" -and $_.kind -eq "result" -and $_.path -match '(?i)\.RES$'
    } | ForEach-Object {
        [IO.Path]::GetFileName(($_.path -replace '/', '\'))
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

$changedResultFiles = @()
if (-not [string]::IsNullOrWhiteSpace($ResultFilesBeforePath) -and (Test-Path -LiteralPath $ResultFilesBeforePath -PathType Leaf)) {
    $beforeByName = @{}
    foreach ($item in @(Get-Content -Raw -LiteralPath $ResultFilesBeforePath | ConvertFrom-Json)) {
        $beforeByName[$item.name] = $item
    }
    $changedResultFiles = @(Get-ChildItem -LiteralPath $ImplusPath -File -Filter "*.RES" -ErrorAction SilentlyContinue | Where-Object {
        $before = $beforeByName[$_.Name]
        $beforeTicks = if ($null -ne $before -and $null -ne $before.last_write_utc_ticks) { [long]$before.last_write_utc_ticks } elseif ($null -ne $before) { ([datetime]$before.last_write_utc).ToUniversalTime().Ticks } else { 0 }
        $null -eq $before -or [long]$before.length -ne $_.Length -or $beforeTicks -ne $_.LastWriteTimeUtc.Ticks
    } | ForEach-Object Name | Sort-Object -Unique)
}
$resultFiles = if ($accessedResultFiles.Count -gt 0) {
    @($accessedResultFiles)
} else {
    @($changedResultFiles)
}
$workflowChanges = @()
if (-not [string]::IsNullOrWhiteSpace($WorkflowKind)) {
    if (-not (Test-Path -LiteralPath $WorkflowSnapshotBeforePath -PathType Container)) {
        throw "Workflow before-snapshot not found: $WorkflowSnapshotBeforePath"
    }
    if (-not (Test-Path -LiteralPath $WorkflowSnapshotScriptPath -PathType Leaf)) {
        throw "Workflow snapshot script not found: $WorkflowSnapshotScriptPath"
    }

    $afterTemp = Join-Path $RunDirectory "workflow-after-staging"
    & $WorkflowSnapshotScriptPath -ImplusPath $ImplusPath -Destination $afterTemp -Phase after | Out-Null
    $beforeManifest = Get-Content -Raw -LiteralPath (Join-Path $WorkflowSnapshotBeforePath "snapshot-manifest.json") | ConvertFrom-Json
    $afterManifest = Get-Content -Raw -LiteralPath (Join-Path $afterTemp "snapshot-manifest.json") | ConvertFrom-Json
    $beforeByName = @{}; foreach ($item in @($beforeManifest)) { $beforeByName[$item.name] = $item }
    $afterByName = @{}; foreach ($item in @($afterManifest)) { $afterByName[$item.name] = $item }
    $names = @($beforeByName.Keys + $afterByName.Keys | Sort-Object -Unique)
    $workflowChanges = @($names | ForEach-Object {
        $name = $_; $old = $beforeByName[$name]; $new = $afterByName[$name]
        $kind = if ($null -eq $old) { "created" } elseif ($null -eq $new) { "deleted" } elseif ($old.sha256 -ne $new.sha256) { "modified" } else { "unchanged" }
        [ordered]@{ name = $name; change = $kind; before_sha256 = $old.sha256; after_sha256 = $new.sha256 }
    })

    foreach ($snapshot in @(
        @{ Prefix = "workflow-before"; Path = $WorkflowSnapshotBeforePath },
        @{ Prefix = "workflow-after"; Path = $afterTemp }
    )) {
        foreach ($file in Get-ChildItem -LiteralPath $snapshot.Path -File | Where-Object Name -ne "snapshot-manifest.json") {
            $name = "$($snapshot.Prefix)-$($file.Name)"
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $RunDirectory $name) -Force
            $role = if ($file.Extension -in @(".CAL", ".REG")) { "calibration" } else { "other" }
            $artifacts.Add([ordered]@{ path = $name; name = $name; role = $role })
        }
    }
    $diffName = "workflow-file-diff.json"
    [IO.File]::WriteAllText((Join-Path $RunDirectory $diffName), ($workflowChanges | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $artifacts.Add([ordered]@{ path = $diffName; name = $diffName; role = "other" })
    Remove-Item -LiteralPath $afterTemp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Split-Path -Parent $WorkflowSnapshotBeforePath) -Recurse -Force -ErrorAction SilentlyContinue
}
if (Copy-RunArtifact (Join-Path $ImplusPath "INTERFAC.DAT") "INTERFAC.final.DAT") {
    $artifacts.Add([ordered]@{ path = "INTERFAC.final.DAT"; name = "INTERFAC.final.DAT"; role = "interfac" })
}

$tracePath = Join-Path $RunDirectory $TraceFile
$correctionCount = if (Test-Path -LiteralPath $tracePath -PathType Leaf) {
    @(Select-String -LiteralPath $tracePath -SimpleMatch '"event":"result_correction"' -ErrorAction Stop).Count
} else {
    0
}
foreach ($resultName in $resultFiles) {
    $source = Join-Path $ImplusPath $resultName
    $destinationName = "result-$resultName"
    if (Copy-RunArtifact $source $destinationName) {
        $artifacts.Add([ordered]@{ path = $destinationName; name = $destinationName; role = "legacy_result" })
    }
}
foreach ($entry in @(
    @{ Path = "LPTCAP.PRN"; Role = "lpt_raw" },
    @{ Path = "calibration-access.ndjson"; Role = "other" },
    @{ Path = "run-metadata.json"; Role = "other" },
    @{ Path = "dosbox.log"; Role = "other" }
)) {
    if (Test-Path -LiteralPath (Join-Path $RunDirectory $entry.Path) -PathType Leaf) {
        $artifacts.Add([ordered]@{ path = $entry.Path; name = $entry.Path; role = $entry.Role })
    }
}

$markerMetadata = [ordered]@{
    transport = "directserial"
    mutation = if ($correctionCount -gt 0) { "true" } else { "false" }
    correction_count = $correctionCount.ToString([Globalization.CultureInfo]::InvariantCulture)
    finalizer = "Finalize-ArlDirectSerialRun.ps1"
    # `timeout_parent_still_running` means DOSBox was STILL OPEN when this bundle was collected,
    # so the operator may have added burns to the session afterwards. Treat such a bundle as
    # complete-as-of-collection, not as a closed session.
    finalize_wait_outcome = $waitOutcome
    finalize_waited_seconds = $waitedSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
    calibration_candidates = ($accessedCalibrationFiles -join ",")
    curve_file = if (@($accessedCalibrationFiles).Count -eq 1) { $accessedCalibrationFiles[0] } else { "" }
    result_file_candidates = ($resultFiles -join ",")
    result_file = if (@($resultFiles).Count -eq 1) { @($resultFiles)[0] } else { "" }
}
if (-not [string]::IsNullOrWhiteSpace($WorkflowKind)) {
    $markerMetadata.workflow = $WorkflowKind
    $markerMetadata.workflow_changed_file_count = @($workflowChanges | Where-Object change -ne "unchanged").Count.ToString([Globalization.CultureInfo]::InvariantCulture)
}

$marker = [ordered]@{
    runId = Split-Path -Leaf $RunDirectory
    traceFile = $TraceFile
    source = "real_arl"
    finalizedAt = [datetimeoffset]::UtcNow.ToString("o")
    dosBoxVersion = $DosBoxVersion
    artifacts = @($artifacts.ToArray())
    metadata = $markerMetadata
}

$markerPath = Join-Path $RunDirectory "directserial-finalized.json"
$temporaryPath = "$markerPath.tmp-$([guid]::NewGuid().ToString('N'))"
$markerJson = $marker | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($temporaryPath, $markerJson, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $markerPath -Force
Write-Host "Finalized directserial evidence: $markerPath"
