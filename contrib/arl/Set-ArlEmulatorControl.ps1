param(
    [string]$RunPath = "",
    [string]$RunRoot = "C:\ARL\diagnostics",
    [string]$ControlPath = "",

    [string[]]$Values = @(),
    [string]$ResponseAscii = "",
    [int]$TargetChecksum = -1,

    [string]$Label = "operator-next-result",
    [string]$MatchAscii = "#rd 246`r",
    [int]$DelayMs = 0,
    [switch]$AllowNumericAdjustment,
    [double]$MaxNumericDelta = 0.01,
    [switch]$Disable
)

$ErrorActionPreference = "Stop"

function Get-ArlChecksum([string]$Payload) {
    if ($Payload.StartsWith("#")) { $Payload = $Payload.Substring(1) }
    $sum = 0
    foreach ($char in $Payload.ToCharArray()) {
        $sum = ($sum + [int][char]$char) -band 0xff
    }
    return $sum
}

function Format-Checksum([int]$Checksum) {
    return "{0:D3}" -f ($Checksum -band 0xff)
}

function Get-ValueAlternatives([string]$Value) {
    $set = [ordered]@{}
    function Add([string]$Text) {
        if (-not [string]::IsNullOrWhiteSpace($Text) -and -not $set.Contains($Text)) {
            $set[$Text] = $true
        }
    }

    Add $Value

    $numeric = 0.0
    $isNumber = [double]::TryParse(
        $Value,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$numeric
    )
    if ($isNumber) {
        $abs = [math]::Abs($numeric)
        $positivePrefix = if ($numeric -ge 0) { @("", "+") } else { @("-") }
        foreach ($prefix in $positivePrefix) {
            for ($width = 0; $width -le 4; $width++) {
                for ($decimals = 0; $decimals -le 5; $decimals++) {
                    $format = if ($width -gt 0) { "{0:0$width.$(('0' * $decimals))}" } else { "{0:0.$(('0' * $decimals))}" }
                    if ($decimals -eq 0) {
                        $format = if ($width -gt 0) { "{0:0$width}" } else { "{0:0}" }
                    }
                    $candidate = $prefix + ($format -f $abs)
                    Add $candidate
                    if ($candidate -match '^\+?0\.(\d+)$') {
                        $sign = if ($candidate.StartsWith("+")) { "+" } else { "" }
                        Add "$sign.$($matches[1])"
                    }
                }
            }
        }

        if ($AllowNumericAdjustment -and $MaxNumericDelta -gt 0) {
            foreach ($decimals in 2..5) {
                $step = [math]::Pow(10, -$decimals)
                $limit = [int][math]::Floor($MaxNumericDelta / $step)
                if ($limit -le 0) { continue }
                for ($delta = -$limit; $delta -le $limit; $delta++) {
                    if ($delta -eq 0) { continue }
                    $adjusted = $numeric + ($delta * $step)
                    if ($adjusted -lt 0 -and $numeric -ge 0) { continue }
                    Add ($adjusted.ToString("F$decimals", [Globalization.CultureInfo]::InvariantCulture))
                    if ($adjusted -ge 0) {
                        Add ("+" + $adjusted.ToString("F$decimals", [Globalization.CultureInfo]::InvariantCulture))
                    }
                }
            }
        }
    }

    if ($Value -match '^\+?0\.(\d+)$') {
        $sign = if ($Value.StartsWith("+")) { "+" } else { "" }
        Add "$sign.$($matches[1])"
    }
    if ($Value -match '^([+-]?)\.(\d+)$') {
        Add "$($matches[1])0.$($matches[2])"
    }
    if ($Value -match '^([+-]?\d+)\.(\d+)$') {
        $integer = $matches[1]
        $fraction = $matches[2]
        $trimmed = $fraction.TrimEnd("0")
        if ($trimmed.Length -gt 0) {
            Add "$integer.$trimmed"
        }
        for ($i = 1; $i -le 4; $i++) {
            Add "$integer.$fraction$('0' * $i)"
        }
    }
    if ($Value -match '^[+-]?\d+$') {
        Add "$Value.0"
        Add "$Value.00"
    }

    return @($set.Keys)
}

function Find-EquivalentPayload([string[]]$Fields, [int]$Target) {
    $originalPayload = (($Fields -join ",") + " ")
    if ((Get-ArlChecksum $originalPayload) -eq $Target) {
        return $originalPayload
    }

    $statesByChecksum = @{ 0 = "" }
    for ($index = 0; $index -lt $Fields.Count; $index++) {
        $nextStatesByChecksum = @{}
        foreach ($state in $statesByChecksum.Values) {
            foreach ($alternative in (Get-ValueAlternatives $Fields[$index])) {
                $candidate = if ([string]::IsNullOrWhiteSpace($state)) { $alternative } else { "$state,$alternative" }
                $checksum = Get-ArlChecksum $candidate
                if (-not $nextStatesByChecksum.ContainsKey($checksum)) {
                    $nextStatesByChecksum[$checksum] = $candidate
                }
            }
        }
        $statesByChecksum = $nextStatesByChecksum
    }

    foreach ($state in $statesByChecksum.Values) {
        $payload = "$state "
        if ((Get-ArlChecksum $payload) -eq $Target) {
            return $payload
        }
    }

    throw "Could not find equivalent formatting for target checksum $(Format-Checksum $Target)."
}

if ([string]::IsNullOrWhiteSpace($ControlPath)) {
    if ([string]::IsNullOrWhiteSpace($RunPath)) {
        $candidate = Get-ChildItem -Path $RunRoot -Directory |
            Where-Object { Test-Path -Path (Join-Path $_.FullName "emulator-control.json") -PathType Leaf } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $candidate) {
            throw "No emulator-control.json found below $RunRoot"
        }
        $RunPath = $candidate.FullName
    }
    $ControlPath = Join-Path $RunPath "emulator-control.json"
}

if (-not (Test-Path -Path $ControlPath -PathType Leaf)) {
    throw "Control file not found: $ControlPath"
}

if ($Disable) {
    $control = Get-Content -Path $ControlPath -Raw | ConvertFrom-Json
    $control.enabled = $false
    $control.rules = @()
    $control.note = "Disabled by Set-ArlEmulatorControl.ps1 at $((Get-Date).ToString('o'))"
    $control | ConvertTo-Json -Depth 8 | Set-Content -Path $ControlPath -Encoding UTF8
    Write-Host "Disabled emulator control: $ControlPath"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ResponseAscii)) {
    if ($Values.Count -eq 0) {
        throw "Pass either -ResponseAscii or -Values."
    }
    if ($TargetChecksum -ge 0) {
        $payload = Find-EquivalentPayload $Values $TargetChecksum
        $checksum = $TargetChecksum
    } else {
        $payload = (($Values -join ",") + " ")
        $checksum = Get-ArlChecksum $payload
    }
    $ResponseAscii = "#$payload$(Format-Checksum $checksum)`r"
} else {
    $ResponseAscii = $ResponseAscii.Replace("\r", "`r").Replace("\n", "`n")
}

$body = $ResponseAscii.TrimEnd("`r", "`n")
if ($body -match '^#?(.*\s)(\d{1,3})$') {
    $payloadForChecksum = $matches[1]
    $claimed = [int]$matches[2]
    $computed = Get-ArlChecksum $payloadForChecksum
} else {
    $claimed = $null
    $computed = $null
}

$controlProfile = [ordered]@{
    enabled = $true
    note = "One-shot/operator override created at $((Get-Date).ToString('o')). Disable after the intended test."
    rules = @(
        [ordered]@{
            label = $Label
            phase = "analysis-result"
            match = "exact_ascii"
            pattern_ascii = $MatchAscii
            response_ascii = $ResponseAscii
            delay_ms = $DelayMs
        }
    )
}

$controlProfile | ConvertTo-Json -Depth 8 | Set-Content -Path $ControlPath -Encoding UTF8

Write-Host "Updated emulator control: $ControlPath"
Write-Host "Response: $($ResponseAscii.Replace("`r", '\r'))"
if ($null -ne $claimed) {
    Write-Host "Claimed checksum: $(Format-Checksum $claimed)"
    Write-Host "Computed checksum: $(Format-Checksum $computed)"
    Write-Host "Checksum valid: $($claimed -eq $computed)"
}
