param(
    [string]$LogPath = "",
    [string]$RunRoot = "C:\ARL\diagnostics",
    [string[]]$CaseLabelPrefix = @("format-equiv-", "format-control-", "grammar-", "sweep-case-"),
    [switch]$WriteFiles
)

$ErrorActionPreference = "Stop"

function Get-PropValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Test-CaseLabel([string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Label)) { return $false }
    foreach ($prefix in $CaseLabelPrefix) {
        if ($Label.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $latest = Get-ChildItem -Path $RunRoot -Directory -Filter "impact-emulator-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Where-Object { Test-Path -Path (Join-Path $_.FullName "emulator.ndjson") } |
        Select-Object -First 1
    if ($null -eq $latest) {
        throw "No emulator.ndjson found below $RunRoot"
    }
    $LogPath = Join-Path $latest.FullName "emulator.ndjson"
}

if (-not (Test-Path -Path $LogPath -PathType Leaf)) {
    throw "Emulator log not found: $LogPath"
}

$runDir = Split-Path -Parent $LogPath
$events = New-Object System.Collections.Generic.List[object]
Get-Content -Path $LogPath | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try {
        [void]$events.Add(($_ | ConvertFrom-Json))
    } catch {
        Write-Warning "Skipping invalid NDJSON line: $($_.Exception.Message)"
    }
}

$rules = @($events | Where-Object { $_.event -eq "rule_match" -or $_.event -eq "no_match" })
$caseRules = @($rules | Where-Object { $_.event -eq "rule_match" -and (Test-CaseLabel ([string]$_.rule)) })

$cases = New-Object System.Collections.Generic.List[object]
foreach ($case in $caseRules) {
    $start = [array]::IndexOf($rules, $case)
    $outcome = "unknown"
    $next = $null
    for ($i = $start + 1; $i -lt $rules.Count; $i++) {
        $candidate = $rules[$i]
        $input = [string](Get-PropValue $candidate "input_ascii" "")
        $rule = [string](Get-PropValue $candidate "rule" "")
        if ($input.StartsWith("#em")) {
            $outcome = "accepted"
            $next = $rule
            break
        }
        if ($input -eq "?") {
            $outcome = "rejected"
            $next = $rule
            break
        }
        if ($candidate.event -eq "no_match") {
            $outcome = "no_match"
            $next = $input
            break
        }
        if (Test-CaseLabel $rule) {
            break
        }
    }

    [void]$cases.Add([pscustomobject]@{
        index = $cases.Count + 1
        rule = $case.rule
        phase = $case.phase
        input_ascii = $case.input_ascii
        outcome = $outcome
        next = $next
    })
}

$noMatches = @($rules | Where-Object { $_.event -eq "no_match" })
$lastNoMatch = $noMatches | Select-Object -Last 1
$accepted = @($cases | Where-Object { $_.outcome -eq "accepted" })
$rejected = @($cases | Where-Object { $_.outcome -eq "rejected" })
$unknown = @($cases | Where-Object { $_.outcome -ne "accepted" -and $_.outcome -ne "rejected" })
$questionInputs = @($rules | Where-Object { [string](Get-PropValue $_ "input_ascii" "") -eq "?" })
$emInputs = @($rules | Where-Object { ([string](Get-PropValue $_ "input_ascii" "")).StartsWith("#em") })
$profileExhausted = $false
if ($null -ne $lastNoMatch) {
    $lastInput = [string](Get-PropValue $lastNoMatch "input_ascii" "")
    $profileExhausted = ($lastInput -eq "#rd 246`r" -or $lastInput -eq "#rd 246\r")
}

$lptPath = Join-Path $runDir "LPTCAP.PRN"
$metadataPath = Join-Path $runDir "run-metadata.json"
$metadata = $null
if (Test-Path -Path $metadataPath -PathType Leaf) {
    try { $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json } catch {}
}

$lastNoMatchText = $null
if ($null -ne $lastNoMatch) {
    $lastNoMatchText = Get-PropValue $lastNoMatch "input_ascii" ""
}
$lptCapture = $null
$lptBytes = 0
if (Test-Path -Path $lptPath -PathType Leaf) {
    $lptCapture = $lptPath
    $lptBytes = (Get-Item -Path $lptPath).Length
}
$classification = "inconclusive"
if ($rejected.Count -gt 0) {
    $classification = "impact_rejected_cases"
} elseif ($profileExhausted -and $accepted.Count -eq $cases.Count -and $cases.Count -gt 0) {
    $classification = "profile_exhausted_after_all_cases_accepted"
} elseif ($noMatches.Count -gt 0) {
    $classification = "profile_no_match"
} elseif ($accepted.Count -eq $cases.Count -and $cases.Count -gt 0) {
    $classification = "all_cases_accepted"
}

$summaryData = [ordered]@{}
$summaryData["run_dir"] = $runDir
$summaryData["log_path"] = $LogPath
$summaryData["profile"] = (Get-PropValue $metadata "emulator_profile" $null)
$summaryData["log_size"] = (Get-Item -Path $LogPath).Length
$summaryData["total_events"] = $events.Count
$summaryData["rule_events"] = $rules.Count
$summaryData["cases"] = $cases.Count
$summaryData["accepted"] = $accepted.Count
$summaryData["rejected"] = $rejected.Count
$summaryData["unknown"] = $unknown.Count
$summaryData["em_inputs"] = $emInputs.Count
$summaryData["question_inputs"] = $questionInputs.Count
$summaryData["no_match_events"] = $noMatches.Count
$summaryData["last_no_match"] = $lastNoMatchText
$summaryData["profile_exhausted_after_rd"] = $profileExhausted
$summaryData["lpt_capture"] = $lptCapture
$summaryData["lpt_bytes"] = $lptBytes
$summaryData["classification"] = $classification
$summaryData["case_results"] = @($cases.ToArray())
$summary = [pscustomobject]$summaryData

$summaryJson = $summary | ConvertTo-Json -Depth 8
Write-Output $summaryJson

if ($WriteFiles) {
    $jsonPath = Join-Path $runDir "emulator-summary.json"
    $mdPath = Join-Path $runDir "emulator-summary.md"
    $summaryJson | Set-Content -Path $jsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# ARL Emulator Summary")
    [void]$lines.Add("")
    [void]$lines.Add("- Run: ``$runDir``")
    [void]$lines.Add("- Classification: ``" + $summary.classification + "``")
    [void]$lines.Add("- Cases: $($summary.cases)")
    [void]$lines.Add("- Accepted: $($summary.accepted)")
    [void]$lines.Add("- Rejected: $($summary.rejected)")
    [void]$lines.Add("- Unknown: $($summary.unknown)")
    [void]$lines.Add("- No-match events: $($summary.no_match_events)")
    [void]$lines.Add("- Last no-match: ``" + $summary.last_no_match + "``")
    [void]$lines.Add("- LPT bytes: $($summary.lpt_bytes)")
    [void]$lines.Add("")
    [void]$lines.Add("| # | outcome | rule |")
    [void]$lines.Add("|---:|---|---|")
    foreach ($case in $cases) {
        [void]$lines.Add("| $($case.index) | $($case.outcome) | ``$($case.rule)`` |")
    }
    $lines | Set-Content -Path $mdPath -Encoding UTF8
}
