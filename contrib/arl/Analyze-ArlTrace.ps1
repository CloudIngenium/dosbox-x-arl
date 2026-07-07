param(
    [Parameter(Mandatory = $true)]
    [string]$TracePath,

    [string]$OutDir = "",

    [int]$IdleAfterTxMs = 5000
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $TracePath -PathType Leaf)) {
    throw "Trace file not found: $TracePath"
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Split-Path -Parent (Resolve-Path $TracePath)
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$events = New-Object System.Collections.Generic.List[object]
$badLines = New-Object System.Collections.Generic.List[object]
$lineNo = 0

Get-Content -Path $TracePath | ForEach-Object {
	$lineNo++
	$rawLine = $_
	if ([string]::IsNullOrWhiteSpace($rawLine)) { return }
	try {
		$evt = $rawLine | ConvertFrom-Json
		$evt | Add-Member -NotePropertyName line -NotePropertyValue $lineNo -Force
		$events.Add($evt)
	} catch {
		$badLines.Add([pscustomobject]@{
			line = $lineNo
			text = $rawLine
			error = $_.Exception.Message
		})
	}
}

function Get-PropValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Get-LastEvent([scriptblock]$Predicate) {
    for ($i = $events.Count - 1; $i -ge 0; $i--) {
        if (& $Predicate $events[$i]) { return $events[$i] }
    }
    return $null
}

$timeline = foreach ($e in $events) {
    [pscustomobject]@{
        line = Get-PropValue $e "line"
        elapsed_ms = Get-PropValue $e "elapsed_ms"
        event = Get-PropValue $e "event"
        session = Get-PropValue $e "session"
        guest_com = Get-PropValue $e "guest_com"
        realport = Get-PropValue $e "realport"
        byte_hex = Get-PropValue $e "byte_hex"
        ascii = Get-PropValue $e "ascii"
        register = Get-PropValue $e "register"
        value_hex = Get-PropValue $e "value_hex"
        rx_error_bits = Get-PropValue $e "rx_error_bits"
        rts = Get-PropValue $e "rts"
        dtr = Get-PropValue $e "dtr"
        cts = Get-PropValue $e "cts"
        dsr = Get-PropValue $e "dsr"
        dcd = Get-PropValue $e "dcd"
        ri = Get-PropValue $e "ri"
        rx_fifo_usage = Get-PropValue $e "rx_fifo_usage"
        tx_fifo_usage = Get-PropValue $e "tx_fifo_usage"
        rx_state = Get-PropValue $e "rx_state"
        rx_retry = Get-PropValue $e "rx_retry"
        message = Get-PropValue $e "message"
    }
}

$timelinePath = Join-Path $OutDir "timeline.csv"
$timeline | Export-Csv -Path $timelinePath -NoTypeInformation

$tx = @($events | Where-Object { (Get-PropValue $_ "event") -eq "tx" })
$rx = @($events | Where-Object { (Get-PropValue $_ "event") -eq "rx" })
$uartReads = @($events | Where-Object {
    (Get-PropValue $_ "event") -eq "uart_read" -and (Get-PropValue $_ "register") -eq "RHR"
})
$uartWrites = @($events | Where-Object {
    (Get-PropValue $_ "event") -eq "uart_write" -and (Get-PropValue $_ "register") -eq "THR"
})
$hangs = @($events | Where-Object { (Get-PropValue $_ "event") -eq "hang_snapshot" })
$txErrors = @($events | Where-Object { (Get-PropValue $_ "event") -eq "tx_error" })
$configRejected = @($events | Where-Object {
    (Get-PropValue $_ "event") -eq "config" -and (Get-PropValue $_ "accepted") -eq $false
})

$overruns = @($events | Where-Object {
    [int](Get-PropValue $_ "rx_error_bits" 0) -ne 0 -or
    [int](Get-PropValue $_ "overrun_errors" 0) -ne 0 -or
    [int](Get-PropValue $_ "tx_overrun_errors" 0) -ne 0 -or
    [int](Get-PropValue $_ "errors_in_fifo" 0) -ne 0
})

$lineDrops = @($events | Where-Object {
    $eventName = Get-PropValue $_ "event"
    ($eventName -eq "modem" -or $eventName -eq "control") -and (
        (Get-PropValue $_ "cts" $true) -eq $false -or
        (Get-PropValue $_ "dsr" $true) -eq $false -or
        (Get-PropValue $_ "dcd" $true) -eq $false
    )
})

$lastTx = Get-LastEvent { param($e) (Get-PropValue $e "event") -eq "tx" }
$lastRx = Get-LastEvent { param($e) (Get-PropValue $e "event") -eq "rx" }
$lastRhrRead = Get-LastEvent { param($e)
    (Get-PropValue $e "event") -eq "uart_read" -and (Get-PropValue $e "register") -eq "RHR"
}
$lastEvent = if ($events.Count -gt 0) { $events[$events.Count - 1] } else { $null }

$reasons = New-Object System.Collections.Generic.List[string]

if ($badLines.Count -gt 0) {
    $reasons.Add("trace_parse_errors")
}
if ($txErrors.Count -gt 0) {
    $reasons.Add("write_failed")
}
if ($configRejected.Count -gt 0) {
    $reasons.Add("baud_or_parity_rejected")
}
if ($overruns.Count -gt 0) {
    $reasons.Add("fifo_or_uart_error")
}
if ($lineDrops.Count -gt 0) {
    $reasons.Add("modem_line_drop_or_low")
}
if ($hangs.Count -gt 0 -and $null -ne $lastTx) {
    $lastTxMs = [int](Get-PropValue $lastTx "elapsed_ms" 0)
    $lastRxMs = if ($null -ne $lastRx) { [int](Get-PropValue $lastRx "elapsed_ms" 0) } else { -1 }
    if ($lastTxMs -gt $lastRxMs -and (($lastTxMs - $lastRxMs) -ge 0)) {
        $reasons.Add("arl_silent_after_tx")
    }
}
if ($null -ne $lastRx) {
    $lastRxMs = [int](Get-PropValue $lastRx "elapsed_ms" 0)
    $lastReadMs = if ($null -ne $lastRhrRead) { [int](Get-PropValue $lastRhrRead "elapsed_ms" 0) } else { -1 }
    if ($lastRxMs -gt $lastReadMs) {
        $reasons.Add("rx_received_but_guest_did_not_read")
    }
}
if ($reasons.Count -eq 0 -and $hangs.Count -gt 0) {
    $reasons.Add("hang_without_clear_serial_fault")
}
if ($reasons.Count -eq 0) {
    $reasons.Add("no_obvious_serial_fault")
}

$suspect = [pscustomobject]@{
    trace_path = (Resolve-Path $TracePath).Path
    event_count = $events.Count
    parse_error_count = $badLines.Count
    tx_count = $tx.Count
    rx_count = $rx.Count
    uart_thr_write_count = $uartWrites.Count
    uart_rhr_read_count = $uartReads.Count
    hang_snapshot_count = $hangs.Count
    first_rejected_config = if ($configRejected.Count) { $configRejected[0] } else { $null }
    first_write_failure = if ($txErrors.Count) { $txErrors[0] } else { $null }
    first_fifo_or_uart_error = if ($overruns.Count) { $overruns[0] } else { $null }
    first_modem_line_drop = if ($lineDrops.Count) { $lineDrops[0] } else { $null }
    last_tx = $lastTx
    last_rx = $lastRx
    last_uart_rhr_read = $lastRhrRead
    last_event = $lastEvent
    classification = @($reasons)
}

$suspectPath = Join-Path $OutDir "suspect.json"
$suspect | ConvertTo-Json -Depth 12 | Set-Content -Path $suspectPath -Encoding UTF8

$summaryPath = Join-Path $OutDir "summary.md"
$classificationText = ($reasons | ForEach-Object { "- $_" }) -join "`n"
if ([string]::IsNullOrWhiteSpace($classificationText)) { $classificationText = "- none" }

$lastTxText = if ($lastTx) { "line $($lastTx.line), elapsed_ms $($lastTx.elapsed_ms), byte $($lastTx.byte_hex)" } else { "none" }
$lastRxText = if ($lastRx) { "line $($lastRx.line), elapsed_ms $($lastRx.elapsed_ms), byte $($lastRx.byte_hex), error $($lastRx.rx_error_bits)" } else { "none" }
$lastEventText = if ($lastEvent) { "line $($lastEvent.line), elapsed_ms $($lastEvent.elapsed_ms), event $($lastEvent.event)" } else { "none" }

$summaryLines = @(
    "# ARL Trace Summary",
    "",
    "Trace: $TracePath",
    "",
    "## Counts",
    "",
    "- Events: $($events.Count)",
    "- Parse errors: $($badLines.Count)",
    "- TX bytes: $($tx.Count)",
    "- RX bytes: $($rx.Count)",
    "- Guest THR writes: $($uartWrites.Count)",
    "- Guest RHR reads: $($uartReads.Count)",
    "- Hang snapshots: $($hangs.Count)",
    "",
    "## Classification",
    "",
    $classificationText,
    "",
    "## Last Events",
    "",
    "- Last TX: $lastTxText",
    "- Last RX: $lastRxText",
    "- Last event: $lastEventText",
    "",
    "## Outputs",
    "",
    "- Timeline CSV: $timelinePath",
    "- Suspect JSON: $suspectPath"
)
$summaryLines | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "Wrote $summaryPath"
Write-Host "Wrote $timelinePath"
Write-Host "Wrote $suspectPath"
