param(
    [string]$RunPath = "",

    [string]$TracePath = "",

    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TracePath)) {
    if ([string]::IsNullOrWhiteSpace($RunPath)) {
        throw "Provide -RunPath or -TracePath"
    }
    $TracePath = Join-Path $RunPath "serial.ndjson"
}

if (-not (Test-Path -Path $TracePath -PathType Leaf)) {
    throw "Trace file not found: $TracePath"
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Split-Path -Parent (Resolve-Path $TracePath)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$protocolPath = Join-Path $OutDir "protocol-candidates.json"
if (-not (Test-Path -Path $protocolPath -PathType Leaf)) {
    $analyzer = Join-Path $PSScriptRoot "Analyze-ArlTrace.ps1"
    & $analyzer -TracePath $TracePath -OutDir $OutDir
}

$protocol = Get-Content -Path $protocolPath -Raw | ConvertFrom-Json

function Limit-Text([string]$Text, [int]$Max = 220) {
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max) + "...[truncated]"
}

function Get-ResultLines([string]$Text) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split '\\r|\\n|\r?\n|\r')) {
        $normalized = $line.Trim()
        if ($normalized.StartsWith("#")) {
            $normalized = $normalized.Substring(1).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($normalized)) { continue }
        if ($normalized -notmatch ",") { continue }
        if (([regex]::Matches($normalized, ",").Count) -lt 5) { continue }
        $lines.Add($normalized)
    }
    return @($lines.ToArray())
}

function New-ResultSummary($Candidate) {
    $txAscii = [string]$Candidate.tx_ascii
    $rxAscii = [string]$Candidate.rx_ascii
    $resultLines = @(Get-ResultLines $rxAscii)
    $groups = @($resultLines | Group-Object | Sort-Object Count -Descending)
    $questionCount = [regex]::Matches($txAscii, "\?").Count
    $isLoop = $questionCount -ge 20 -and $groups.Count -gt 0 -and $groups[0].Count -ge 5

    [pscustomobject]@{
        index = [int]$Candidate.index
        start_elapsed_ms = [int]$Candidate.start_elapsed_ms
        end_elapsed_ms = [int]$Candidate.end_elapsed_ms
        duration_ms = [int]$Candidate.duration_ms
        tx_count = [int]$Candidate.tx_count
        rx_count = [int]$Candidate.rx_count
        question_count = $questionCount
        has_rd = $txAscii -match "#rd"
        has_em = $txAscii -match "#em"
        has_pa = $txAscii -match "(^|\\r)pa "
        has_we = $txAscii -match "(^|\\r)we "
        has_ns = $txAscii -match "(^|\\r)ns "
        result_line_count = $resultLines.Count
        unique_result_line_count = $groups.Count
        top_result_repeat_count = if ($groups.Count) { $groups[0].Count } else { 0 }
        top_result_sample = if ($groups.Count) { Limit-Text $groups[0].Name } else { "" }
        is_post_result_poll_loop = $isLoop
        tx_excerpt = Limit-Text $txAscii
        rx_excerpt = Limit-Text $rxAscii
    }
}

$resultCandidates = @(
    $protocol.candidates |
        Where-Object { ([string]$_.tx_ascii) -match "#rd" } |
        ForEach-Object { New-ResultSummary $_ }
)

$loops = @($resultCandidates | Where-Object { $_.is_post_result_poll_loop })
$good = @($resultCandidates | Where-Object { -not $_.is_post_result_poll_loop -and $_.result_line_count -gt 0 })
$lastGoodBeforeLoop = $null
$firstLoop = if ($loops.Count) { $loops[0] } else { $null }
if ($null -ne $firstLoop) {
    $lastGoodBeforeLoop = @($good | Where-Object { $_.index -lt $firstLoop.index } | Select-Object -Last 1)
    if ($lastGoodBeforeLoop.Count -gt 0) { $lastGoodBeforeLoop = $lastGoodBeforeLoop[0] }
}

$findings = New-Object System.Collections.Generic.List[string]
if ($loops.Count -gt 0) {
    $findings.Add("Detected post-result poll loop in candidate $($firstLoop.index): $($firstLoop.question_count) question-mark polls and repeated result count $($firstLoop.top_result_repeat_count).")
}
if ($null -ne $lastGoodBeforeLoop -and $null -ne $firstLoop) {
    if ($lastGoodBeforeLoop.has_em -and -not $firstLoop.has_em) {
        $findings.Add("Last good result candidate included #em but the loop candidate did not; investigate result-end/status transition after #rd.")
    }
    if ($lastGoodBeforeLoop.result_line_count -gt 0 -and $firstLoop.top_result_repeat_count -ge 5) {
        $findings.Add("The ARL kept sending parseable numeric result rows during the loop, so this is not a silent-instrument or Windows RX-loss failure.")
    }
}
if ($resultCandidates.Count -eq 0) {
    $findings.Add("No #rd result transactions were found in this trace.")
}
if ($findings.Count -eq 0) {
    $findings.Add("No post-result loop pattern was found.")
}

$comparison = [pscustomobject]@{
    trace_path = (Resolve-Path $TracePath).Path
    protocol_path = (Resolve-Path $protocolPath).Path
    result_candidate_count = $resultCandidates.Count
    good_result_candidate_count = $good.Count
    post_result_loop_count = $loops.Count
    last_good_before_first_loop = $lastGoodBeforeLoop
    first_post_result_loop = $firstLoop
    result_candidates = @($resultCandidates)
    findings = @($findings)
}

$jsonPath = Join-Path $OutDir "result-transaction-comparison.json"
$mdPath = Join-Path $OutDir "result-transaction-comparison.md"
$comparison | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# ARL Result Transaction Comparison")
$lines.Add("")
$lines.Add("Trace: $TracePath")
$lines.Add("")
$lines.Add("## Findings")
$lines.Add("")
foreach ($finding in $findings) {
    $lines.Add("- $finding")
}
$lines.Add("")
$lines.Add("## Result Transactions")
$lines.Add("")
$lines.Add("| # | ms | has #em | ? count | result rows | repeated top row | loop | TX excerpt | Top result |")
$lines.Add("|---:|---:|:---:|---:|---:|---:|:---:|---|---|")
foreach ($item in $resultCandidates) {
    $loopText = if ($item.is_post_result_poll_loop) { "yes" } else { "no" }
    $hasEm = if ($item.has_em) { "yes" } else { "no" }
    $tx = $item.tx_excerpt
    $top = $item.top_result_sample
    $lines.Add("| $($item.index) | $($item.start_elapsed_ms)-$($item.end_elapsed_ms) | $hasEm | $($item.question_count) | $($item.result_line_count) | $($item.top_result_repeat_count) | $loopText | ``$tx`` | ``$top`` |")
}
$lines | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote $mdPath"
Write-Host "Wrote $jsonPath"
