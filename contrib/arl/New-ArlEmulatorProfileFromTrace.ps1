param(
    [Parameter(Mandatory = $true)]
    [string]$RunPath,

    [string]$OutPath = "",

    [string]$Name = "",

    [ValidateSet("sequence", "rejected-first", "accepted-only")]
    [string]$Mode = "sequence",

    [ValidateSet("CR", "CRLF", "LF")]
    [string]$LineEnding = "CR",

    [int]$TransactionIdleMs = 80,

    [int]$DefaultResponseDelayMs = 15,

    [switch]$RunAnalyzer
)

$ErrorActionPreference = "Stop"

function Get-PropValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Convert-ToProfileName([string]$Text) {
    $slug = ($Text -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "arl-profile" }
    return $slug.ToLowerInvariant()
}

function Get-LineEndingText([string]$Value) {
    switch ($Value) {
        "CR" { return "`r" }
        "CRLF" { return "`r`n" }
        "LF" { return "`n" }
        default { throw "Unsupported line ending: $Value" }
    }
}

function Normalize-ResultLine([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return "" }
    $normalized = $Line.Trim()
    if (-not $normalized.StartsWith("#")) {
        $normalized = "#$normalized"
    }
    return $normalized
}

function Convert-ToNullableInt($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    return [int]$Value
}

function Convert-ToNullableBool($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    return [System.Convert]::ToBoolean($Value)
}

$resolvedRunPath = (Resolve-Path -Path $RunPath).Path
$tracePath = Join-Path $resolvedRunPath "serial.ndjson"
$timingPath = Join-Path $resolvedRunPath "result-timing.csv"
$metadataPath = Join-Path $resolvedRunPath "run-metadata.json"

if (-not (Test-Path -Path $tracePath -PathType Leaf)) {
    throw "Run path does not contain serial.ndjson: $resolvedRunPath"
}

if ($RunAnalyzer -or -not (Test-Path -Path $timingPath -PathType Leaf)) {
    $analyzer = Join-Path $PSScriptRoot "Analyze-ArlTrace.ps1"
    if (-not (Test-Path -Path $analyzer -PathType Leaf)) {
        throw "Analyzer not found: $analyzer"
    }
    & $analyzer -TracePath $tracePath -OutDir $resolvedRunPath
}

if (-not (Test-Path -Path $timingPath -PathType Leaf)) {
    throw "Analyzer did not produce result-timing.csv: $timingPath"
}

$rows = @(
    Import-Csv -Path $timingPath |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.first_result) -and
            ([string]$_.first_result).Contains(",")
        }
)

if ($rows.Count -eq 0) {
    throw "No result rows found in $timingPath"
}

$selectedRows = switch ($Mode) {
    "accepted-only" {
        @($rows | Where-Object { ([string]$_.outcome).StartsWith("accepted") })
    }
    "rejected-first" {
        $rejected = @($rows | Where-Object { ([string]$_.outcome).StartsWith("rejected") })
        if ($rejected.Count -eq 0) {
            throw "Mode rejected-first needs at least one rejected row in $timingPath"
        }
        @($rejected | Select-Object -First 1)
    }
    default {
        $rows
    }
}

if ($selectedRows.Count -eq 0) {
    throw "No rows selected for mode $Mode"
}
$selectedRows = @($selectedRows)

$sourceName = Split-Path -Leaf $resolvedRunPath
if ([string]::IsNullOrWhiteSpace($Name)) {
    $Name = Convert-ToProfileName "impact-$sourceName-$Mode"
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $profilesDir = Join-Path $PSScriptRoot "profiles"
    New-Item -ItemType Directory -Force -Path $profilesDir | Out-Null
    $OutPath = Join-Path $profilesDir "$Name.json"
}

$metadata = $null
if (Test-Path -Path $metadataPath -PathType Leaf) {
    $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
}

$lineEndingText = Get-LineEndingText $LineEnding
$responses = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $selectedRows.Count; $i++) {
    $row = $selectedRows[$i]
    $result = Normalize-ResultLine ([string]$row.first_result)
    $outcome = [string]$row.outcome
    $accepted = $outcome.StartsWith("accepted")
    $labelOutcome = if ($accepted) { "accepted" } else { "rejected" }
    $checksum = Convert-ToNullableInt $row.checksum
    $checksumValid = Convert-ToNullableBool $row.checksum_valid
    $sourceTransactionIndex = Convert-ToNullableInt $row.index
    $firstRxDelayMs = Convert-ToNullableInt $row.first_rx_delay_ms
    $resultDurationMs = Convert-ToNullableInt $row.first_result_duration_ms
    $impactResponseDelayMs = Convert-ToNullableInt $row.post_result_tx_delay_ms
    $rule = [ordered]@{
        label = "impact-result-row-$($i + 1)-$labelOutcome"
        phase = "analysis-result"
        match = "ascii_contains"
        pattern_ascii = "#rd"
        response_ascii = "$result$lineEndingText"
        repeat_policy = "sequence"
        sequence_key = "impact-result-row"
        sequence_index = $i
        sequence_next = $i + 1
        checksum = $checksum
        checksum_valid = $checksumValid
        accepted_by_impact = $accepted
        source_transaction_index = $sourceTransactionIndex
        first_rx_delay_ms = $firstRxDelayMs
        result_duration_ms = $resultDurationMs
        impact_response_delay_ms = $impactResponseDelayMs
    }
    if (-not $accepted) {
        $rule.failure_mode = "impact-sent-question-mark"
    }
    $responses.Add([pscustomobject]$rule)
}

$firstRejected = @($selectedRows | Where-Object { ([string]$_.outcome).StartsWith("rejected") } | Select-Object -First 1)
if ($firstRejected.Count -gt 0) {
    $rejectResult = Normalize-ResultLine ([string]$firstRejected[0].first_result)
    $rejectChecksum = Convert-ToNullableInt $firstRejected[0].checksum
    $rejectChecksumValid = Convert-ToNullableBool $firstRejected[0].checksum_valid
    $responses.Add([pscustomobject][ordered]@{
        label = "impact-reject-loop-repeat-first-rejected-row"
        phase = "reject-loop"
        match = "ascii_contains"
        pattern_ascii = "?"
        response_ascii = "$rejectResult$lineEndingText"
        checksum = $rejectChecksum
        checksum_valid = $rejectChecksumValid
        note = "When IMPACT sends '?', repeat the valid row it rejected in the source trace."
    })
}

$responses.Add([pscustomobject][ordered]@{
    label = "impact-accepted-end-marker"
    phase = "accepted"
    match = "ascii_contains"
    pattern_ascii = "#em"
    response_ascii = ""
    note = "Observed IMPACT transition after accepted rows."
})

$acceptedCount = @($rows | Where-Object { ([string]$_.outcome).StartsWith("accepted") }).Count
$rejectedCount = @($rows | Where-Object { ([string]$_.outcome).StartsWith("rejected") }).Count
$sourceCore = Get-PropValue $metadata "core"
$sourceCpuType = Get-PropValue $metadata "cputype"
$sourceCycles = Get-PropValue $metadata "cycles"
$sourceRxDelay = Get-PropValue $metadata "rxdelay"
$sourceTraceLevel = Get-PropValue $metadata "trace_level"

$profile = [pscustomobject]@{
    name = $Name
    description = "Trace-derived IMPACT emulator profile from $resolvedRunPath."
    source_run = $sourceName
    source_trace = $tracePath
    profile_mode = $Mode
    source_counts = @{
        accepted = $acceptedCount
        rejected = $rejectedCount
        selected = $selectedRows.Count
    }
    source_settings = @{
        core = $sourceCore
        cputype = $sourceCpuType
        cycles = $sourceCycles
        rxdelay = $sourceRxDelay
        trace_level = $sourceTraceLevel
    }
    safety = @{
        transport = "dosbox-x nullmodem TCP"
        listen_address = "127.0.0.1"
        opens_real_com_port = $false
        touches_arl_hardware = $false
    }
    transaction_idle_ms = $TransactionIdleMs
    default_response_delay_ms = $DefaultResponseDelayMs
    delayed_result_ms = 10000
    response_line_ending = $LineEnding
    notes = @(
        "Generated from result-timing.csv; no command in this profile opens COM5.",
        "Rows include the leading # and the selected line ending.",
        "Use with serial1=nullmodem, never directserial."
    )
    responses = @($responses.ToArray())
}

$outDir = Split-Path -Parent $OutPath
if (-not [string]::IsNullOrWhiteSpace($outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$profile | ConvertTo-Json -Depth 12 | Set-Content -Path $OutPath -Encoding UTF8
Write-Host "Wrote emulator profile: $OutPath"
Write-Host "Selected rows: $($selectedRows.Count); accepted in source: $acceptedCount; rejected in source: $rejectedCount"
