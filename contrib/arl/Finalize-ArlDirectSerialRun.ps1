param(
    [Parameter(Mandatory = $true)][int]$ParentPid,
    [Parameter(Mandatory = $true)][datetime]$ParentStartTime,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][string]$ImplusPath,
    [string]$TraceFile = "serial.ndjson",
    [string]$DosBoxVersion = "dosbox-x-arl",
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
    @{ Path = "run-metadata.json"; Role = "other" },
    @{ Path = "dosbox.log"; Role = "other" }
)) {
    if (Test-Path -LiteralPath (Join-Path $RunDirectory $entry.Path) -PathType Leaf) {
        $artifacts.Add([ordered]@{ path = $entry.Path; name = $entry.Path; role = $entry.Role })
    }
}

$marker = [ordered]@{
    runId = Split-Path -Leaf $RunDirectory
    traceFile = $TraceFile
    source = "real_arl"
    finalizedAt = [datetimeoffset]::UtcNow.ToString("o")
    dosBoxVersion = $DosBoxVersion
    artifacts = @($artifacts.ToArray())
    metadata = [ordered]@{
        transport = "directserial"
        mutation = if ($correctionCount -gt 0) { "true" } else { "false" }
        correction_count = $correctionCount.ToString([Globalization.CultureInfo]::InvariantCulture)
        finalizer = "Finalize-ArlDirectSerialRun.ps1"
    }
}

$markerPath = Join-Path $RunDirectory "directserial-finalized.json"
$temporaryPath = "$markerPath.tmp-$([guid]::NewGuid().ToString('N'))"
$markerJson = $marker | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($temporaryPath, $markerJson, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $markerPath -Force
Write-Host "Finalized directserial evidence: $markerPath"
