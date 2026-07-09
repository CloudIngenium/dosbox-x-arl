param(
    [string]$DiagnosticsRoot = "C:\ARL\diagnostics",
    [string]$RealRunPath = "C:\ARL\diagnostics\sample-analysis-20260708-232928",
    [int]$RealFromMs = 11000,
    [int]$RealToMs = 18000
)

$ErrorActionPreference = "Stop"

function Read-TraceEvents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TracePath,
        [int]$FromMs,
        [int]$ToMs
    )

    $line = 0
    Get-Content -Path $TracePath | ForEach-Object {
        $line++
        try {
            $event = $_ | ConvertFrom-Json
        } catch {
            return
        }

        $ms = -1
        if ($null -ne $event.elapsed_ms) {
            $ms = [int]$event.elapsed_ms
        }

        if ($ms -lt $FromMs -or $ms -gt $ToMs) {
            return
        }

        if ($event.event -notin @("tx", "rx", "rule_match", "no_match", "connect", "disconnect")) {
            return
        }

        [pscustomobject]@{
            line = $line
            ms = $ms
            event = $event.event
            hex = $event.byte_hex
            ascii = $event.ascii
            input_ascii = $event.input_ascii
            input_hex = $event.input_hex
            rule = $event.rule
        }
    }
}

if (-not (Test-Path -Path $DiagnosticsRoot -PathType Container)) {
    throw "Diagnostics root not found: $DiagnosticsRoot"
}

if (-not (Test-Path -Path $RealRunPath -PathType Container)) {
    $fallback = Get-ChildItem -Path $DiagnosticsRoot -Directory -Filter "sample-analysis-*" |
        Where-Object { Test-Path -Path (Join-Path $_.FullName "serial.ndjson") -PathType Leaf } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $fallback) {
        throw "No sample-analysis run with serial.ndjson found under $DiagnosticsRoot"
    }
    $RealRunPath = $fallback.FullName
}

$realTracePath = Join-Path $RealRunPath "serial.ndjson"
if (-not (Test-Path -Path $realTracePath -PathType Leaf)) {
    throw "Real run has no serial.ndjson: $RealRunPath"
}

$latestEmulator = Get-ChildItem -Path $DiagnosticsRoot -Directory -Filter "impact-emulator-*" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$emulatorEvents = @()
$emulatorLogTail = @()
if ($null -ne $latestEmulator) {
    $emulatorTracePath = Join-Path $latestEmulator.FullName "emulator.ndjson"
    if (Test-Path -Path $emulatorTracePath -PathType Leaf) {
        $emulatorEvents = @(Read-TraceEvents -TracePath $emulatorTracePath -FromMs 0 -ToMs 120000)
    }

    $dosboxLogPath = Join-Path $latestEmulator.FullName "dosbox.log"
    if (Test-Path -Path $dosboxLogPath -PathType Leaf) {
        $emulatorLogTail = @(Get-Content -Path $dosboxLogPath -Tail 80)
    }
}

$profileFiles = @()
$profileRoot = "C:\ARL\DOSBox-X-ARL\profiles"
if (Test-Path -Path $profileRoot -PathType Container) {
    $profileFiles = @(
        Get-ChildItem -Path $profileRoot -Filter "*.json" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10 Name, FullName, LastWriteTime
    )
}

[pscustomobject][ordered]@{
    latest_emulator = if ($null -ne $latestEmulator) { $latestEmulator.FullName } else { $null }
    real_run = $RealRunPath
    real_window = @{
        from_ms = $RealFromMs
        to_ms = $RealToMs
        events = @(Read-TraceEvents -TracePath $realTracePath -FromMs $RealFromMs -ToMs $RealToMs)
    }
    emulator_events = $emulatorEvents
    emulator_dosbox_log_tail = $emulatorLogTail
    emulator_profile_files = $profileFiles
} | ConvertTo-Json -Depth 8
