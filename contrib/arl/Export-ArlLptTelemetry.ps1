param(
    [string]$CapturePath = "",
    [string]$RunRoot = "C:\ARL\diagnostics",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

function Get-NextNonEmptyLine([string[]]$Lines, [ref]$Cursor) {
    while ($Cursor.Value -lt $Lines.Count) {
        $line = $Lines[$Cursor.Value].Trim()
        $Cursor.Value++
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            return $line
        }
    }
    return $null
}

function Get-Tokens([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return @() }
    return @($Line.Trim() -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-NumericToken([string]$Token) {
    return $Token -match '^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$'
}

function Get-SectionRows([string[]]$Lines, [string]$Title, [string]$Stage, [int]$StartAt = 0) {
    $rows = New-Object System.Collections.Generic.List[object]
    $occurrence = 0
    for ($i = $StartAt; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ne $Title) { continue }

        $cursor = $i + 1
        $header = @()
        while ($cursor -lt $Lines.Count -and $header.Count -lt 14) {
            $line = Get-NextNonEmptyLine $Lines ([ref]$cursor)
            if ($null -eq $line) { break }
            $tokens = Get-Tokens $line
            if ($tokens.Count -eq 0) { continue }
            if (($tokens | Where-Object { Test-NumericToken $_ }).Count -eq $tokens.Count) { break }
            $header += $tokens
        }
        if ($header.Count -ne 14) { continue }

        $values = @()
        while ($cursor -lt $Lines.Count -and $values.Count -lt 14) {
            $line = Get-NextNonEmptyLine $Lines ([ref]$cursor)
            if ($null -eq $line) { break }
            $tokens = Get-Tokens $line
            if (($tokens | Where-Object { Test-NumericToken $_ }).Count -ne $tokens.Count) { break }
            $values += $tokens
        }
        if ($values.Count -ne 14) { continue }

        $occurrence++
        for ($n = 0; $n -lt 14; $n++) {
            [void]$rows.Add([pscustomobject]@{
                stage = $Stage
                occurrence = $occurrence
                element = $header[$n]
                value = [decimal]::Parse($values[$n], [Globalization.CultureInfo]::InvariantCulture)
            })
        }
    }
    return $rows.ToArray()
}

function Get-FinalConcentrationRows([string[]]$Lines) {
    $rows = New-Object System.Collections.Generic.List[object]
    $occurrence = 0
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ne 'Final Concentration') { continue }
        $headerStart = -1
        for ($j = $i + 1; $j -lt [Math]::Min($i + 24, $Lines.Count); $j++) {
            $candidate = $Lines[$j].Trim()
            if ($candidate -match '\bMn\b' -and $candidate -match '\bNi\b' -and $candidate -match '\bFe1\b') {
                $headerStart = $j
                break
            }
        }
        if ($headerStart -lt 0) { continue }
        $cursor = $headerStart
        # The final report is printed as header/value pairs, unlike the
        # intermediate sections which print both header rows before values.
        $headerFirst = Get-Tokens (Get-NextNonEmptyLine $Lines ([ref]$cursor))
        $valuesFirst = Get-Tokens (Get-NextNonEmptyLine $Lines ([ref]$cursor))
        $headerSecond = Get-Tokens (Get-NextNonEmptyLine $Lines ([ref]$cursor))
        $valuesSecond = Get-Tokens (Get-NextNonEmptyLine $Lines ([ref]$cursor))
        $header = $headerFirst + $headerSecond
        $values = $valuesFirst + $valuesSecond
        if ($header.Count -ne 14 -or $values.Count -ne 14) { continue }
        if (($values | Where-Object { -not (Test-NumericToken $_) }).Count -gt 0) { continue }

        $occurrence++
        for ($n = 0; $n -lt 14; $n++) {
            [void]$rows.Add([pscustomobject]@{
                stage = 'final_concentration'
                occurrence = $occurrence
                element = $header[$n]
                value = [decimal]::Parse($values[$n], [Globalization.CultureInfo]::InvariantCulture)
            })
        }
    }
    return $rows.ToArray()
}

if ([string]::IsNullOrWhiteSpace($CapturePath)) {
    $latest = Get-ChildItem -Path $RunRoot -Directory | Sort-Object LastWriteTime -Descending |
        Where-Object { Test-Path (Join-Path $_.FullName 'LPTCAP.PRN') } | Select-Object -First 1
    if ($null -eq $latest) { throw "No LPTCAP.PRN found below $RunRoot" }
    $CapturePath = Join-Path $latest.FullName 'LPTCAP.PRN'
}
if (-not (Test-Path -LiteralPath $CapturePath -PathType Leaf)) { throw "LPT capture not found: $CapturePath" }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Split-Path -Parent $CapturePath }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$bytes = [IO.File]::ReadAllBytes($CapturePath)
$text = [Text.Encoding]::GetEncoding(437).GetString($bytes)
$lines = @($text -split "`r?`n")
$stages = @(
    @{ title = 'Absolute Intensities'; stage = 'absolute_intensity' },
    @{ title = 'Ratioed Intensities'; stage = 'ratioed_intensity' },
    @{ title = 'Drift Corrected Intensities'; stage = 'drift_corrected_intensity' },
    @{ title = 'Calibration Curve Evaluation'; stage = 'calibration_curve_evaluation' },
    @{ title = 'Interelement Interference Corrections'; stage = 'interelement_interference_correction' },
    @{ title = 'Type Standardization'; stage = 'type_standardization' },
    @{ title = '100% normalization'; stage = 'normalization_100_percent' }
)

$rows = New-Object System.Collections.Generic.List[object]
foreach ($definition in $stages) {
    foreach ($row in (Get-SectionRows $lines $definition.title $definition.stage)) { [void]$rows.Add($row) }
}
foreach ($row in (Get-FinalConcentrationRows $lines)) { [void]$rows.Add($row) }

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $CapturePath).Hash.ToLowerInvariant()
$exportRows = @($rows | ForEach-Object {
    [pscustomobject]@{
        capture = (Split-Path -Leaf $CapturePath)
        capture_sha256 = $hash
        stage = $_.stage
        occurrence = $_.occurrence
        element = $_.element
        value = $_.value
    }
})
$csvPath = Join-Path $OutputDirectory 'arl-telemetry.csv'
$jsonPath = Join-Path $OutputDirectory 'arl-telemetry.json'
$mdPath = Join-Path $OutputDirectory 'arl-telemetry-summary.md'
$exportRows | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $csvPath
$payload = [ordered]@{
    capture_path = $CapturePath
    capture_sha256 = $hash
    capture_bytes = $bytes.Length
    exported_at = (Get-Date).ToString('o')
    records = $exportRows
}
$payload | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $jsonPath

$summary = New-Object System.Collections.Generic.List[string]
[void]$summary.Add('# ARL LPT Telemetry')
[void]$summary.Add('')
[void]$summary.Add("- Capture: ``$CapturePath``")
[void]$summary.Add("- SHA-256: ``$hash``")
[void]$summary.Add("- Parsed values: $($exportRows.Count)")
[void]$summary.Add('')
[void]$summary.Add('| Stage | Reports | Values |')
[void]$summary.Add('|---|---:|---:|')
foreach ($group in ($exportRows | Group-Object stage | Sort-Object Name)) {
    [void]$summary.Add("| $($group.Name) | $(($group.Group | Select-Object -ExpandProperty occurrence -Unique).Count) | $($group.Count) |")
}
[void]$summary.Add('')
[void]$summary.Add('`final_concentration` is the reportable chemistry result. The intensity and correction stages are diagnostic/process telemetry; they must be labeled emulator-derived when the capture came from an emulator run.')
$summary | Set-Content -Encoding UTF8 -LiteralPath $mdPath

Write-Host "TELEMETRY_OK capture=$CapturePath records=$($exportRows.Count) csv=$csvPath json=$jsonPath summary=$mdPath"
