param(
    [Parameter(Mandatory = $true)][int]$ParentPid,
    [Parameter(Mandatory = $true)][datetime]$ParentStartTime,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][string]$ImplusPath,
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

$deadline = [datetime]::UtcNow.AddSeconds($WaitTimeoutSeconds)
while ([datetime]::UtcNow -lt $deadline) {
    $process = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
    if ($null -eq $process) { break }
    if ([math]::Abs(($process.StartTime - $ParentStartTime).TotalSeconds) -gt 2) { break }
    Start-Sleep -Milliseconds 500
}

if (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
    throw "DOSBox process $ParentPid did not exit before the finalizer timeout."
}

$artifacts = New-Object System.Collections.Generic.List[object]
$calibrationAccessTrace = Join-Path $RunDirectory "calibration-access.ndjson"
$accessedCalibrationFiles = @()
if (Test-Path -LiteralPath $calibrationAccessTrace -PathType Leaf) {
    $accessedCalibrationFiles = @(Get-Content -LiteralPath $calibrationAccessTrace | ForEach-Object {
        try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    } | Where-Object {
        $null -ne $_ -and $_.event -eq "guest_calibration_open" -and $_.path -match '(?i)\.CAL$'
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
if (Copy-RunArtifact (Join-Path $ImplusPath "0.RES") "0.final.RES") {
    $artifacts.Add([ordered]@{ path = "0.final.RES"; name = "0.final.RES"; role = "legacy_result" })
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
    calibration_candidates = @($accessedCalibrationFiles)
    curve_file = if (@($accessedCalibrationFiles).Count -eq 1) { $accessedCalibrationFiles[0] } else { $null }
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
