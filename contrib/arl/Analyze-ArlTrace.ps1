param(
    [Parameter(Mandatory = $true)]
    [string]$TracePath,

    [string]$OutDir = "",

    [int]$IdleAfterTxMs = 5000,

    [int]$TransactionGapMs = 750
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

function ConvertTo-TraceByte($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
            $text = $text.Substring(2)
        }
        $text = ($text -replace '[^0-9A-Fa-f]', '')
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return [Convert]::ToInt32($text, 16) -band 0xff
    }
    return ([int]$Value) -band 0xff
}

function Get-EventByte($Event) {
    foreach ($name in @("byte_dec", "value_dec", "byte_hex", "value_hex")) {
        $value = Get-PropValue $Event $name
        if ($null -ne $value) {
            $byte = ConvertTo-TraceByte $value
            if ($null -ne $byte) { return $byte }
        }
    }
    return $null
}

function Get-PrintableByte([int]$Byte) {
    switch ($Byte) {
        9 { return "\t" }
        10 { return "\n" }
        13 { return "\r" }
        default {
            if ($Byte -ge 32 -and $Byte -le 126) {
                return [char]$Byte
            }
            return "."
        }
    }
}

function Format-HexBytes([System.Collections.IEnumerable]$Bytes) {
    $parts = foreach ($byte in $Bytes) { "{0:X2}" -f ([int]$byte -band 0xff) }
    return ($parts -join " ")
}

function Format-AsciiBytes([System.Collections.IEnumerable]$Bytes) {
    $parts = foreach ($byte in $Bytes) { Get-PrintableByte ([int]$byte) }
    return ($parts -join "")
}

function Get-CommandGuess([string]$Ascii, [string]$Hex) {
    if ($Ascii -match "TL") { return "tics-link-test" }
    if ($Ascii -match "VE") { return "tics-version" }
    if ($Ascii -match "SI") { return "status-si" }
    if ($Ascii -match "RS") { return "status-rs" }
    if (-not [string]::IsNullOrWhiteSpace($Ascii.Trim("."))) {
        $text = $Ascii
        if ($text.Length -gt 40) { $text = $text.Substring(0, 40) + "..." }
        return "ascii:$text"
    }
    if (-not [string]::IsNullOrWhiteSpace($Hex)) {
        return "hex:$Hex"
    }
    return "unknown"
}

function New-ProtocolCandidate($Index, $Items) {
    if ($Items.Count -eq 0) { return $null }

    $txBytes = New-Object System.Collections.Generic.List[int]
    $rxBytes = New-Object System.Collections.Generic.List[int]
    $marks = New-Object System.Collections.Generic.List[string]
    $hangCount = 0

    foreach ($item in $Items) {
        $eventName = Get-PropValue $item "event"
        if ($eventName -eq "tx" -or $eventName -eq "rx") {
            $byte = Get-EventByte $item
            if ($null -ne $byte) {
                if ($eventName -eq "tx") { $txBytes.Add($byte) }
                else { $rxBytes.Add($byte) }
            }
        } elseif ($eventName -eq "mark") {
            $message = Get-PropValue $item "message"
            if (-not [string]::IsNullOrWhiteSpace($message)) {
                $marks.Add($message)
            }
        } elseif ($eventName -eq "hang_snapshot") {
            $hangCount++
        }
    }

    $first = $Items[0]
    $last = $Items[$Items.Count - 1]
    $startMs = [int](Get-PropValue $first "elapsed_ms" 0)
    $endMs = [int](Get-PropValue $last "elapsed_ms" $startMs)
    $txHex = Format-HexBytes $txBytes
    $rxHex = Format-HexBytes $rxBytes
    $txAscii = Format-AsciiBytes $txBytes
    $rxAscii = Format-AsciiBytes $rxBytes

    return [pscustomobject]@{
        index = $Index
        start_line = Get-PropValue $first "line"
        end_line = Get-PropValue $last "line"
        start_elapsed_ms = $startMs
        end_elapsed_ms = $endMs
        duration_ms = ($endMs - $startMs)
        session = Get-PropValue $first "session"
        realport = Get-PropValue $first "realport"
        event_count = $Items.Count
        tx_count = $txBytes.Count
        rx_count = $rxBytes.Count
        mark_count = $marks.Count
        hang_snapshot_count = $hangCount
        tx_hex = $txHex
        tx_ascii = $txAscii
        rx_hex = $rxHex
        rx_ascii = $rxAscii
        marks = @($marks)
        command_guess = Get-CommandGuess $txAscii $txHex
        response_guess = if ($rxBytes.Count -gt 0) { Get-CommandGuess $rxAscii $rxHex } else { "none" }
    }
}

function Write-ProtocolWorkbook {
    $interestingNames = @("tx", "rx", "mark", "hang_snapshot")
    $interesting = @($events | Where-Object {
        $interestingNames -contains (Get-PropValue $_ "event") -and
        $null -ne (Get-PropValue $_ "elapsed_ms")
    } | Sort-Object { [int](Get-PropValue $_ "elapsed_ms" 0) }, { [int](Get-PropValue $_ "line" 0) })

    $candidates = New-Object System.Collections.Generic.List[object]
    $current = New-Object System.Collections.Generic.List[object]
    $lastMs = $null

    foreach ($item in $interesting) {
        $elapsed = [int](Get-PropValue $item "elapsed_ms" 0)
        if ($current.Count -gt 0 -and $null -ne $lastMs -and (($elapsed - $lastMs) -gt $TransactionGapMs)) {
            $candidate = New-ProtocolCandidate ($candidates.Count + 1) $current
            if ($null -ne $candidate) { $candidates.Add($candidate) }
            $current = New-Object System.Collections.Generic.List[object]
        }
        $current.Add($item)
        $lastMs = $elapsed
    }

    if ($current.Count -gt 0) {
        $candidate = New-ProtocolCandidate ($candidates.Count + 1) $current
        if ($null -ne $candidate) { $candidates.Add($candidate) }
    }

    $candidateArray = @($candidates.ToArray())
    $protocol = [pscustomobject]@{
        trace_path = (Resolve-Path $TracePath).Path
        transaction_gap_ms = $TransactionGapMs
        candidate_count = $candidates.Count
        candidates = $candidateArray
    }

    $protocolJsonPath = Join-Path $OutDir "protocol-candidates.json"
    $protocolMdPath = Join-Path $OutDir "protocol-candidates.md"
    $protocol | ConvertTo-Json -Depth 12 | Set-Content -Path $protocolJsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# ARL Protocol Candidates")
    $lines.Add("")
    $lines.Add("Trace: $TracePath")
    $lines.Add("")
    $lines.Add("Transaction gap: $TransactionGapMs ms")
    $lines.Add("")
    $lines.Add("| # | ms | TX hex | TX ascii | RX hex | RX ascii | Guess | Marks |")
    $lines.Add("|---|---:|---|---|---|---|---|---|")
    foreach ($candidate in $candidates) {
        $marks = ($candidate.marks -join "; ")
        $txHexText = $candidate.tx_hex
        $txAsciiText = $candidate.tx_ascii
        $rxHexText = $candidate.rx_hex
        $rxAsciiText = $candidate.rx_ascii
        $lines.Add("| $($candidate.index) | $($candidate.start_elapsed_ms)-$($candidate.end_elapsed_ms) | ``$txHexText`` | ``$txAsciiText`` | ``$rxHexText`` | ``$rxAsciiText`` | $($candidate.command_guess) / $($candidate.response_guess) | $marks |")
    }
    if ($candidates.Count -eq 0) {
        $lines.Add("| none | 0 |  |  |  |  | no serial TX/RX candidates |  |")
    }
    $lines.Add("")
    $lines.Add("Use these candidates to populate `contrib/arl/profiles/arl3460-baseline.json` only after confirming the bytes against a real lab run.")
    $lines | Set-Content -Path $protocolMdPath -Encoding UTF8

    return [pscustomobject]@{
        json = $protocolJsonPath
        markdown = $protocolMdPath
        count = $candidates.Count
    }
}

$timeline = foreach ($e in $events) {
    [pscustomobject]@{
        line = Get-PropValue $e "line"
        elapsed_ms = Get-PropValue $e "elapsed_ms"
        source = Get-PropValue $e "source"
        event = Get-PropValue $e "event"
        session = Get-PropValue $e "session"
        mode = Get-PropValue $e "mode"
        guest_com = Get-PropValue $e "guest_com"
        realport = Get-PropValue $e "realport"
        byte_hex = Get-PropValue $e "byte_hex"
        ascii = Get-PropValue $e "ascii"
        register = Get-PropValue $e "register"
        value_hex = Get-PropValue $e "value_hex"
        rule = Get-PropValue $e "rule"
        phase = Get-PropValue $e "phase"
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
$protocolWorkbook = Write-ProtocolWorkbook

$tx = @($events | Where-Object { (Get-PropValue $_ "event") -eq "tx" })
$rx = @($events | Where-Object { (Get-PropValue $_ "event") -eq "rx" })
$uartReads = @($events | Where-Object {
    (Get-PropValue $_ "event") -eq "uart_read" -and (Get-PropValue $_ "register") -eq "RHR"
})
$uartWrites = @($events | Where-Object {
    (Get-PropValue $_ "event") -eq "uart_write" -and (Get-PropValue $_ "register") -eq "THR"
})
$uartEvents = @($events | Where-Object {
    (Get-PropValue $_ "event") -eq "uart_read" -or (Get-PropValue $_ "event") -eq "uart_write"
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
if ($null -ne $lastRx -and $uartEvents.Count -gt 0) {
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
    protocol_candidate_count = $protocolWorkbook.count
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
    "- Protocol candidates: $($protocolWorkbook.count)",
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
    "- Protocol candidates MD: $($protocolWorkbook.markdown)",
    "- Protocol candidates JSON: $($protocolWorkbook.json)",
    "- Suspect JSON: $suspectPath"
)
$summaryLines | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "Wrote $summaryPath"
Write-Host "Wrote $timelinePath"
Write-Host "Wrote $($protocolWorkbook.markdown)"
Write-Host "Wrote $($protocolWorkbook.json)"
Write-Host "Wrote $suspectPath"
