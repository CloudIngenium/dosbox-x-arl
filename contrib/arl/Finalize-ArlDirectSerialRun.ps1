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
    [int]$WaitTimeoutSeconds = 86400,
    # Slack on each side of the session window the .RES fallback uses (Select-ArlSessionResultFiles).
    # DOS file times have a 2-second resolution, so a file written in the first instant of the
    # session can carry a time just before it.
    [int]$ResultWindowToleranceSeconds = 2
)

$ErrorActionPreference = "Stop"

function Copy-RunArtifact([string]$Source, [string]$DestinationName) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $false }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $RunDirectory $DestinationName) -Force
    return $true
}

# Reads result-files-before.json (Start-ArlTraceRun writes it before DOSBox starts) into a
# name -> entry map. Throws rather than return a partial map.
#
# Why "assign, then enumerate": this used to be
#     foreach ($item in @(Get-Content -Raw $path | ConvertFrom-Json)) { $map[$item.name] = $item }
# Windows PowerShell 5.1 -- the engine Start-ArlTraceRun launches this finalizer with -- writes a
# JSON ARRAY from ConvertFrom-Json to the pipeline as ONE object (pwsh 7 enumerates it; its
# -NoEnumerate switch restores the 5.1 shape). So @() held a single element, the whole array; the
# loop ran once; $item.name member-enumerated to an array of every name; and that array became
# the only key of the map. Every per-file lookup returned $null, every .RES in IMPLUS looked new,
# and all of them were copied: 171 historic .RES files into each of the four 2026-09-09
# normalization bundles, which pushed them past the Agent's artifact cap into quarantine. CI never
# saw it because it ran this path under pwsh with a ONE-entry list, which ConvertTo-Json writes as
# an object, not an array.
function Read-ArlResultFilesBefore([string]$Path) {
    $map = @{}
    $raw = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $map }   # no .RES existed at launch
    $parsed = ConvertFrom-Json -InputObject $raw
    foreach ($item in @($parsed)) {
        # A nested array (the 5.1 shape above) is flattened, never taken as one entry.
        foreach ($entry in @($item)) {
            if ($null -eq $entry) { continue }
            $name = $entry.name
            if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) {
                throw "an entry has no scalar file name"
            }
            $map[$name] = $entry
        }
    }
    return $map
}

# The .RES fallback for a session in which the guest opened no .RES file (normalization and
# standardization normally open none). Captures only the .RES files that DIFFER from
# result-files-before.json AND whose last write falls inside the session window -- from the
# earlier of the before-list write and DOSBox's start, to now. A file that differs but was last
# written outside the window is not copied: it is LISTED as skipped, with its reason, so no
# evidence is dropped silently. Without a readable before list the window alone decides, and the
# returned basis says so.
function Select-ArlSessionResultFiles {
    $selection = [ordered]@{
        basis = "not_requested"
        before_list = ""
        before_list_entries = 0
        window_start_utc = ""
        window_end_utc = ""
        captured = @()
        skipped = @()
        vanished = @()
    }
    if ([string]::IsNullOrWhiteSpace($ResultFilesBeforePath)) { return $selection }

    $windowStart = $ParentStartTime.ToUniversalTime()
    $beforeByName = $null
    if (-not (Test-Path -LiteralPath $ResultFilesBeforePath -PathType Leaf)) {
        $selection.before_list = "missing"
    } else {
        $listWrittenUtc = (Get-Item -LiteralPath $ResultFilesBeforePath).LastWriteTimeUtc
        if ($listWrittenUtc -lt $windowStart) { $windowStart = $listWrittenUtc }
        try {
            $beforeByName = Read-ArlResultFilesBefore $ResultFilesBeforePath
            $selection.before_list = "ok"
            $selection.before_list_entries = $beforeByName.Count
        } catch {
            $beforeByName = $null
            $selection.before_list = "unreadable: " + $_.Exception.Message
        }
    }
    $windowStart = $windowStart.AddSeconds(-$ResultWindowToleranceSeconds)
    $windowEnd = [datetime]::UtcNow.AddSeconds($ResultWindowToleranceSeconds)
    $selection.window_start_utc = $windowStart.ToString("o")
    $selection.window_end_utc = $windowEnd.ToString("o")
    $selection.basis = if ($null -ne $beforeByName) { "before_list_and_session_window" } else { "session_window_only" }

    $captured = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[object]
    $present = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $ImplusPath -File -Filter "*.RES" -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $present[$file.Name] = $true
        $writeUtc = $file.LastWriteTimeUtc
        $inWindow = ($writeUtc -ge $windowStart) -and ($writeUtc -le $windowEnd)
        if ($null -eq $beforeByName) {
            # No before list: a write inside the window is the only evidence of change there is.
            if ($inWindow) { $captured.Add($file.Name) }
            continue
        }
        $before = $beforeByName[$file.Name]
        $reason = $null
        $beforeTicks = $null
        if ($null -eq $before) {
            $reason = "not_in_before_list"
        } else {
            $beforeTicks = if ($null -ne $before.last_write_utc_ticks) { [long]$before.last_write_utc_ticks } elseif ($null -ne $before.last_write_utc) { ([datetime]$before.last_write_utc).ToUniversalTime().Ticks } else { [long]0 }
            if ([long]$before.length -ne $file.Length) { $reason = "length_changed" }
            elseif ($beforeTicks -ne $writeUtc.Ticks) { $reason = "last_write_changed" }
        }
        if ($null -eq $reason) { continue }   # unchanged since launch: not this session's evidence
        if ($inWindow) {
            $captured.Add($file.Name)
        } else {
            $skipped.Add([ordered]@{
                name = $file.Name
                reason = $reason + "_outside_session_window"
                length = $file.Length
                last_write_utc = $writeUtc.ToString("o")
                before_length = if ($null -ne $before) { $before.length } else { $null }
                before_last_write_utc_ticks = $beforeTicks
            })
        }
    }
    if ($null -ne $beforeByName) {
        $selection.vanished = @($beforeByName.Keys | Where-Object { -not $present.ContainsKey($_) } | Sort-Object)
    }
    $selection.captured = @($captured.ToArray())
    $selection.skipped = @($skipped.ToArray())
    return $selection
}

# Collect the run's evidence and write (or REWRITE) the finalized marker. Extracted into a
# function because finalization can now legitimately happen TWICE for one session: once at the
# wait timeout (so a run is never lost), and again when DOSBox actually exits (so the canonical
# bundle carries everything the operator burned AFTER the timeout). Every input is re-read from
# disk on each call; only the workflow snapshot diff (computed once, its inputs are consumed) is
# passed in.
function Invoke-ArlRunCollection([string]$WaitOutcome, [int]$WaitedSeconds, $WorkflowArtifactEntries, $WorkflowChanges) {
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

    # IMPACT's own .RES opens are the authoritative signal. Only a session in which the guest
    # opened no .RES at all (normalization/standardization) falls back to the session window.
    $resultSelection = $null
    $resultSource = "guest_open_event"
    $resultFiles = @($accessedResultFiles)
    if ($accessedResultFiles.Count -eq 0) {
        $resultSelection = Select-ArlSessionResultFiles
        $resultFiles = @($resultSelection.captured)
        $resultSource = if ($resultFiles.Count -gt 0) { "session_window_fallback" } else { "none" }
    }

    # NOT wrapped in @(): pwsh's array coercion of an EMPTY List[object] received as a parameter
    # fails with "Argument types do not match"; plain foreach enumerates (or skips $null) fine.
    if ($null -ne $WorkflowArtifactEntries) {
        foreach ($entry in $WorkflowArtifactEntries) {
            if ($null -ne $entry) { $artifacts.Add($entry) }
        }
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
    if ($null -ne $resultSelection -and $resultSelection.basis -ne "not_requested") {
        # The fallback's decision is evidence too: what it compared against, the window, what it
        # copied and what it deliberately did not. Rewritten on every collection.
        $selectionName = "finalizer-result-selection.json"
        [IO.File]::WriteAllText((Join-Path $RunDirectory $selectionName), ($resultSelection | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        $artifacts.Add([ordered]@{ path = $selectionName; name = $selectionName; role = "other" })
        Write-Host ("No guest .RES open in this session; result fallback basis={0}, before list={1}, window {2} .. {3}" -f `
            $resultSelection.basis, $resultSelection.before_list, $resultSelection.window_start_utc, $resultSelection.window_end_utc)
        Write-Host ("  captured {0} .RES: {1}" -f @($resultSelection.captured).Count, (@($resultSelection.captured) -join ","))
        foreach ($skippedFile in @($resultSelection.skipped)) {
            Write-Host ("  skipped (listed, not copied) {0}: {1}, last write {2}" -f $skippedFile.name, $skippedFile.reason, $skippedFile.last_write_utc)
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
        # `timeout_parent_still_running` means DOSBox was STILL OPEN when this bundle was
        # collected, so the operator may have added burns to the session afterwards. Treat such
        # a bundle as complete-as-of-collection, not as a closed session -- the finalizer keeps
        # waiting and REWRITES this marker (`parent_exited_after_timeout`) at the real exit.
        finalize_wait_outcome = $WaitOutcome
        finalize_waited_seconds = $WaitedSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
        calibration_candidates = ($accessedCalibrationFiles -join ",")
        curve_file = if (@($accessedCalibrationFiles).Count -eq 1) { $accessedCalibrationFiles[0] } else { "" }
        result_file_candidates = ($resultFiles -join ",")
        result_file = if (@($resultFiles).Count -eq 1) { @($resultFiles)[0] } else { "" }
        # Where result_file_candidates came from: guest_open_event | session_window_fallback | none.
        result_file_source = $resultSource
    }
    if ($null -ne $resultSelection) {
        $invariant = [Globalization.CultureInfo]::InvariantCulture
        $markerMetadata.result_fallback_basis = [string]$resultSelection.basis
        $markerMetadata.result_fallback_before_list = [string]$resultSelection.before_list
        $markerMetadata.result_fallback_window_start_utc = [string]$resultSelection.window_start_utc
        $markerMetadata.result_fallback_window_end_utc = [string]$resultSelection.window_end_utc
        $markerMetadata.result_fallback_captured_count = @($resultSelection.captured).Count.ToString($invariant)
        $markerMetadata.result_fallback_skipped = (@($resultSelection.skipped | ForEach-Object { $_.name }) -join ",")
        $markerMetadata.result_fallback_skipped_count = @($resultSelection.skipped).Count.ToString($invariant)
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkflowKind)) {
        $markerMetadata.workflow = $WorkflowKind
        $markerMetadata.workflow_changed_file_count = @($WorkflowChanges | Where-Object change -ne "unchanged").Count.ToString([Globalization.CultureInfo]::InvariantCulture)
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
#
# And since 2026-08-05 the timeout no longer ENDS the finalizer: it keeps waiting and finalizes
# AGAIN when DOSBox really exits. The timeout-collection alone left a hole measured in
# production (2026-08-01..05): the marker landed at +24 h, the session kept running for days,
# and everything burned after the marker existed only in the live directory -- the canonical
# bundle never saw it. The re-finalize rewrites the marker with the full evidence, so the
# finished-session bundle is always complete no matter how long DOSBox stayed open.
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

# Only a wait that ended by DEADLINE with our DOSBox still alive is a timeout; a recycled pid
# (`parent_replaced`) must keep its verdict even though Get-Process finds the impostor alive.
if ($waitOutcome -eq "parent_exited" -and (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) {
    $waitOutcome = "timeout_parent_still_running"
    Write-Host ("[{0:o}] DOSBox pid {1} did not exit within {2}s - finalizing anyway rather than losing the run." -f `
        [datetime]::UtcNow, $ParentPid, $WaitTimeoutSeconds)
}
$waitedSeconds = [int][math]::Round(([datetime]::UtcNow - $waitStartedUtc).TotalSeconds)

# The workflow snapshot diff runs ONCE: it consumes (and deletes) the before-snapshot staging
# directories, so a second collection cannot rebuild it. Its copied artifacts live in the run
# directory afterwards; both marker writes list them via $workflowArtifactEntries.
$workflowArtifactEntries = New-Object System.Collections.Generic.List[object]
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
            # .GPX and IMPACT.INI copies stay "other": the Agent's gpx_snapshot/instrument_config
            # roles mean "the program's file as captured at import", which a before/after copy is not.
            $role = if ($file.Extension -in @(".CAL", ".REG")) { "calibration" } else { "other" }
            $workflowArtifactEntries.Add([ordered]@{ path = $name; name = $name; role = $role })
        }
    }
    $diffName = "workflow-file-diff.json"
    [IO.File]::WriteAllText((Join-Path $RunDirectory $diffName), ($workflowChanges | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $workflowArtifactEntries.Add([ordered]@{ path = $diffName; name = $diffName; role = "other" })
    Remove-Item -LiteralPath $afterTemp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Split-Path -Parent $WorkflowSnapshotBeforePath) -Recurse -Force -ErrorAction SilentlyContinue
}

Invoke-ArlRunCollection -WaitOutcome $waitOutcome -WaitedSeconds $waitedSeconds `
    -WorkflowArtifactEntries $workflowArtifactEntries -WorkflowChanges $workflowChanges

if ($waitOutcome -eq "timeout_parent_still_running") {
    # Phase 2: the run is safe on disk; now wait HOWEVER LONG the session actually lasts and
    # collect again at the true exit. No deadline -- the whole point is that the lab leaves
    # DOSBox open for days and the 24 h guess was wrong. The heartbeat keeps the wait visible.
    Write-Host ("[{0:o}] timeout bundle collected; still waiting for DOSBox pid {1} to exit for the final collection." -f `
        [datetime]::UtcNow, $ParentPid)
    $secondOutcome = "parent_exited_after_timeout"
    $nextHeartbeat = [datetime]::UtcNow.Add($heartbeatInterval)
    while ($true) {
        $process = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
        if ($null -eq $process) { break }
        if ([math]::Abs(($process.StartTime - $ParentStartTime).TotalSeconds) -gt 2) {
            $secondOutcome = "parent_replaced_after_timeout"
            break
        }
        if ([datetime]::UtcNow -ge $nextHeartbeat) {
            $waitedHours = [math]::Round(([datetime]::UtcNow - $waitStartedUtc).TotalHours, 1)
            Write-Host ("[{0:o}] still waiting for DOSBox pid {1} to exit for the final collection ({2} h since launch)" -f `
                [datetime]::UtcNow, $ParentPid, $waitedHours)
            $nextHeartbeat = [datetime]::UtcNow.Add($heartbeatInterval)
        }
        Start-Sleep -Milliseconds 500
    }
    $totalWaitedSeconds = [int][math]::Round(([datetime]::UtcNow - $waitStartedUtc).TotalSeconds)
    Invoke-ArlRunCollection -WaitOutcome $secondOutcome -WaitedSeconds $totalWaitedSeconds `
        -WorkflowArtifactEntries $workflowArtifactEntries -WorkflowChanges $workflowChanges
}
