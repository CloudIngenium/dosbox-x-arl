param(
    [Parameter(Mandatory = $true)]
    [string]$TracePath,

    [string]$OutDir = "",

    [int]$IdleAfterTxMs = 5000,

    [int]$TransactionGapMs = 750,

    [int]$TimelineMaxMb = 16,

    [switch]$NoTimeline
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $TracePath -PathType Leaf)) {
    throw "Trace file not found: $TracePath"
}
$traceItem = Get-Item -Path $TracePath

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

function Limit-DisplayText([string]$Text, [int]$MaxLength = 180) {
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    if ($Text.Length -le $MaxLength) { return $Text }
    return $Text.Substring(0, $MaxLength) + "...[truncated]"
}

function Get-NumberStats([System.Collections.IEnumerable]$Values) {
    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($numbers.Count -eq 0) {
        return [pscustomobject]@{
            count = 0
            avg = $null
            max = $null
            p95 = $null
        }
    }

    $sum = 0.0
    foreach ($number in $numbers) { $sum += $number }
    $p95Index = [Math]::Ceiling($numbers.Count * 0.95) - 1
    if ($p95Index -lt 0) { $p95Index = 0 }
    if ($p95Index -ge $numbers.Count) { $p95Index = $numbers.Count - 1 }

    return [pscustomobject]@{
        count = $numbers.Count
        avg = [Math]::Round($sum / $numbers.Count, 3)
        max = [Math]::Round($numbers[-1], 3)
        p95 = [Math]::Round($numbers[$p95Index], 3)
    }
}

function Get-ArlChecksum([string]$Payload) {
    if ($null -eq $Payload) { return $null }
    $body = $Payload
    if ($body.StartsWith("#")) {
        $body = $body.Substring(1)
    }
    $sum = 0
    foreach ($char in $body.ToCharArray()) {
        $sum = ($sum + [int][char]$char) -band 0xff
    }
    return $sum
}

function Get-ResultLineInfo([string]$Line) {
    $trimmed = ($Line -replace '\\r|\\n', '').Trim()
    if ($trimmed -notmatch '^#?-?\d+(\.\d+)?,.*\s+\d{1,3}$') { return $null }
    $match = [regex]::Match($trimmed, '^(.*?)(?:\s+(\d{1,3}))$')
    if (-not $match.Success) { return $null }

    $payload = "$($match.Groups[1].Value) "
    $checksum = [int]$match.Groups[2].Value
    $computed = Get-ArlChecksum $payload

    return [pscustomobject]@{
        raw = $trimmed
        payload = $payload
        checksum = $checksum
        computed_checksum = $computed
        checksum_valid = ($computed -eq $checksum)
        value_count = ([regex]::Matches(($trimmed -replace '^#', '' -replace '\s+\d{1,3}$', ''), ',').Count + 1)
    }
}

function Get-RunMetadata {
    $metadataPath = Join-Path $OutDir "run-metadata.json"
    if (-not (Test-Path -Path $metadataPath -PathType Leaf)) { return $null }
    try {
        return Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-RunArtifacts {
    $interfacArtifacts = @(
        Get-ChildItem -Path $OutDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'INTERFAC.DAT*' } |
            Sort-Object LastWriteTime
    )
    $lptArtifacts = @(
        Get-ChildItem -Path $OutDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'LPTCAP*' -or $_.Name -like '*.PRN' } |
            Sort-Object LastWriteTime
    )
    $printJobDir = Join-Path $OutDir "print-jobs"
    $printJobs = @()
    if (Test-Path -Path $printJobDir -PathType Container) {
        $printJobs = @(Get-ChildItem -Path $printJobDir -File -ErrorAction SilentlyContinue)
    }

    return [pscustomobject]@{
        interfac_artifact_count = $interfacArtifacts.Count
        interfac_latest = if ($interfacArtifacts.Count) { $interfacArtifacts[-1].FullName } else { $null }
        interfac_latest_bytes = if ($interfacArtifacts.Count) { $interfacArtifacts[-1].Length } else { 0 }
        interfac_latest_modified = if ($interfacArtifacts.Count) { $interfacArtifacts[-1].LastWriteTime.ToString("s") } else { $null }
        lpt_artifact_count = $lptArtifacts.Count
        lpt_latest = if ($lptArtifacts.Count) { $lptArtifacts[-1].FullName } else { $null }
        lpt_latest_bytes = if ($lptArtifacts.Count) { $lptArtifacts[-1].Length } else { 0 }
        lpt_latest_modified = if ($lptArtifacts.Count) { $lptArtifacts[-1].LastWriteTime.ToString("s") } else { $null }
        print_job_count = $printJobs.Count
    }
}

function Get-AuditFileEntry([string]$Path, [string]$Kind) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -Path $Path -PathType Leaf)) { return $null }
    $item = Get-Item -Path $Path
    $hash = $null
    $hashError = $null
    try {
        $hash = Get-FileHash -Path $Path -Algorithm SHA256
    } catch {
        $hashError = $_.Exception.Message
    }
    return [pscustomobject]@{
        name = $item.Name
        kind = $Kind
        path = $item.FullName
        size_bytes = $item.Length
        modified_at = $item.LastWriteTime.ToString("o")
        sha256 = if ($null -ne $hash) { $hash.Hash.ToLowerInvariant() } else { $null }
        hash_error = $hashError
    }
}

function Get-AuditFileEntries([string]$Directory) {
    $entries = New-Object System.Collections.Generic.List[object]
    $preferred = @(
        @{ path = $TracePath; kind = "serial-trace" },
        @{ path = (Join-Path $Directory "run-metadata.json"); kind = "run-metadata" },
        @{ path = (Join-Path $Directory "dosbox.log"); kind = "dosbox-log" },
        @{ path = (Join-Path $Directory "INTERFAC.DAT"); kind = "interfac" },
        @{ path = (Join-Path $Directory "LPTCAP.PRN"); kind = "lpt-capture" }
    )

    foreach ($candidate in $preferred) {
        $entry = Get-AuditFileEntry $candidate.path $candidate.kind
        if ($null -ne $entry) { $entries.Add($entry) }
    }

    $known = @{}
    foreach ($entry in $entries) {
        $known[$entry.path.ToLowerInvariant()] = $true
    }

    foreach ($file in @(Get-ChildItem -Path $Directory -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($known.ContainsKey($file.FullName.ToLowerInvariant())) { continue }
        $kind = "artifact"
        $lower = $file.Name.ToLowerInvariant()
        if ($lower.EndsWith(".ndjson") -or $lower.Contains("serial")) { $kind = "serial-trace" }
        elseif ($lower.EndsWith(".log")) { $kind = "log" }
        elseif ($lower.Contains("interfac")) { $kind = "interfac" }
        elseif ($lower.Contains("lpt") -or $lower.EndsWith(".prn")) { $kind = "lpt-capture" }
        elseif ($lower.Contains("summary")) { $kind = "summary" }
        elseif ($lower.Contains("suspect")) { $kind = "analysis" }
        elseif ($lower.Contains("protocol")) { $kind = "protocol" }
        elseif ($lower.Contains("lab-next")) { $kind = "recommendation" }
        elseif ($lower.Contains("timeline")) { $kind = "timeline" }
        $entry = Get-AuditFileEntry $file.FullName $kind
        if ($null -ne $entry) { $entries.Add($entry) }
    }

    $printJobDir = Join-Path $Directory "print-jobs"
    if (Test-Path -Path $printJobDir -PathType Container) {
        foreach ($file in @(Get-ChildItem -Path $printJobDir -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $entry = Get-AuditFileEntry $file.FullName "print-job"
            if ($null -ne $entry) { $entries.Add($entry) }
        }
    }

    return @($entries.ToArray())
}

function Get-ResultReadMetrics {
    $serialEvents = @(
        $events |
            Where-Object {
                ((Get-PropValue $_ "event") -eq "tx" -or (Get-PropValue $_ "event") -eq "rx") -and
                $null -ne (Get-EventByte $_)
            } |
            Sort-Object { [int](Get-PropValue $_ "elapsed_ms" 0) }, { [int](Get-PropValue $_ "line" 0) }
    )

    $rdIndices = New-Object System.Collections.Generic.List[int]
    $txWindow = New-Object System.Collections.Generic.List[int]

    for ($i = 0; $i -lt $serialEvents.Count; $i++) {
        $evt = $serialEvents[$i]
        if ((Get-PropValue $evt "event") -ne "tx") { continue }
        $txWindow.Add((Get-EventByte $evt))
        while ($txWindow.Count -gt 20) {
            $txWindow.RemoveAt(0)
        }
        $windowText = Format-AsciiBytes $txWindow
        if ($windowText.EndsWith("#rd 246\r")) {
            $rdIndices.Add($i)
        }
    }

    $transactions = New-Object System.Collections.Generic.List[object]

    for ($n = 0; $n -lt $rdIndices.Count; $n++) {
        $rdIndex = $rdIndices[$n]
        $nextIndex = if ($n -lt ($rdIndices.Count - 1)) { $rdIndices[$n + 1] } else { $serialEvents.Count }
        $rdEvent = $serialEvents[$rdIndex]
        $rdMs = [int](Get-PropValue $rdEvent "elapsed_ms" 0)
        $window = @($serialEvents[($rdIndex + 1)..($nextIndex - 1)])
        $rxEvents = @($window | Where-Object { (Get-PropValue $_ "event") -eq "rx" })
        $txEvents = @($window | Where-Object { (Get-PropValue $_ "event") -eq "tx" })

        $rxLines = New-Object System.Collections.Generic.List[object]
        $lineEvents = New-Object System.Collections.Generic.List[object]
        $lineStartMs = $null
        foreach ($rxEvent in $rxEvents) {
            if ($null -eq $lineStartMs) {
                $lineStartMs = [int](Get-PropValue $rxEvent "elapsed_ms" 0)
            }
            $lineEvents.Add($rxEvent)
            if ((Get-EventByte $rxEvent) -eq 13) {
                $lineText = Format-AsciiBytes (@($lineEvents | ForEach-Object { Get-EventByte $_ }))
                $lineEndMs = [int](Get-PropValue $rxEvent "elapsed_ms" 0)
                $info = Get-ResultLineInfo $lineText
                if ($null -ne $info) {
                    $lineElapsed = @($lineEvents | ForEach-Object { [int](Get-PropValue $_ "elapsed_ms" 0) })
                    $lineGaps = New-Object System.Collections.Generic.List[int]
                    for ($gapIndex = 1; $gapIndex -lt $lineElapsed.Count; $gapIndex++) {
                        $lineGaps.Add($lineElapsed[$gapIndex] - $lineElapsed[$gapIndex - 1])
                    }
                    $gapStats = Get-NumberStats $lineGaps
                    $rxLines.Add([pscustomobject]@{
                        line = $info.raw
                        start_elapsed_ms = $lineStartMs
                        end_elapsed_ms = $lineEndMs
                        duration_ms = ($lineEndMs - $lineStartMs)
                        byte_count = $lineEvents.Count
                        interbyte_gap_count = $gapStats.count
                        interbyte_gap_avg_ms = $gapStats.avg
                        interbyte_gap_max_ms = $gapStats.max
                        interbyte_gap_p95_ms = $gapStats.p95
                        checksum = $info.checksum
                        computed_checksum = $info.computed_checksum
                        checksum_valid = $info.checksum_valid
                        value_count = $info.value_count
                    })
                }
                $lineEvents = New-Object System.Collections.Generic.List[object]
                $lineStartMs = $null
            }
        }

        $firstResult = if ($rxLines.Count) { $rxLines[0] } else { $null }
        $postTxEvents = @()
        if ($null -ne $firstResult) {
            $postTxEvents = @($txEvents | Where-Object { [int](Get-PropValue $_ "elapsed_ms" 0) -ge $firstResult.end_elapsed_ms })
        }
        $postText = Format-AsciiBytes (@($postTxEvents | Select-Object -First 24 | ForEach-Object { Get-EventByte $_ }))
        $outcome = "none"
        if ($postText.StartsWith("#em")) {
            $outcome = "accepted"
        } elseif ($postText.StartsWith("?")) {
            $outcome = "rejected"
        } elseif ($postText -match "#em") {
            $outcome = "accepted-later"
        } elseif ($postText -match "\?") {
            $outcome = "question-later"
        }

        $transactions.Add([pscustomobject]@{
            index = ($n + 1)
            rd_elapsed_ms = $rdMs
            first_rx_delay_ms = if ($rxEvents.Count) { [int](Get-PropValue $rxEvents[0] "elapsed_ms" 0) - $rdMs } else { $null }
            result_line_count = $rxLines.Count
            first_result = $firstResult
            first_result_start_delay_ms = if ($null -ne $firstResult) { $firstResult.start_elapsed_ms - $rdMs } else { $null }
            first_result_end_delay_ms = if ($null -ne $firstResult) { $firstResult.end_elapsed_ms - $rdMs } else { $null }
            first_result_duration_ms = if ($null -ne $firstResult) { $firstResult.duration_ms } else { $null }
            first_result_byte_count = if ($null -ne $firstResult) { $firstResult.byte_count } else { $null }
            first_result_interbyte_avg_ms = if ($null -ne $firstResult) { $firstResult.interbyte_gap_avg_ms } else { $null }
            first_result_interbyte_max_ms = if ($null -ne $firstResult) { $firstResult.interbyte_gap_max_ms } else { $null }
            first_result_interbyte_p95_ms = if ($null -ne $firstResult) { $firstResult.interbyte_gap_p95_ms } else { $null }
            first_result_checksum = if ($null -ne $firstResult) { $firstResult.checksum } else { $null }
            first_result_checksum_valid = if ($null -ne $firstResult) { $firstResult.checksum_valid } else { $null }
            post_result_tx_delay_ms = if ($null -ne $firstResult -and $postTxEvents.Count) { [int](Get-PropValue $postTxEvents[0] "elapsed_ms" 0) - $firstResult.end_elapsed_ms } else { $null }
            post_result_tx_excerpt = Limit-DisplayText $postText 80
            outcome = $outcome
        })
    }

    $accepted = @($transactions | Where-Object { ([string]$_.outcome).StartsWith("accepted") })
    $rejected = @($transactions | Where-Object { ([string]$_.outcome).StartsWith("rejected") })
    $firstReject = if ($rejected.Count) { $rejected[0] } else { $null }
    $acceptedBeforeReject = if ($null -ne $firstReject) {
        @($accepted | Where-Object { $_.index -lt $firstReject.index }).Count
    } else {
        $accepted.Count
    }

    return [pscustomobject]@{
        rd_transaction_count = $transactions.Count
        accepted_count = $accepted.Count
        rejected_count = $rejected.Count
        accepted_before_first_reject = $acceptedBeforeReject
        first_reject = $firstReject
        transactions = @($transactions.ToArray())
    }
}

function New-LabNextTestReport($Metadata, $Artifacts, $ResultMetrics, $PostResultPollLoop, [string[]]$Reasons) {
    $cycles = if ($null -ne $Metadata) { Get-PropValue $Metadata "cycles" } else { $null }
    $rxdelay = if ($null -ne $Metadata) { Get-PropValue $Metadata "rxdelay" } else { $null }
    $traceLevel = if ($null -ne $Metadata) { Get-PropValue $Metadata "trace_level" } else { $null }
    $acceptedBeforeReject = [int](Get-PropValue $ResultMetrics "accepted_before_first_reject" 0)
    $rejectedCount = [int](Get-PropValue $ResultMetrics "rejected_count" 0)
    $acceptedCount = [int](Get-PropValue $ResultMetrics "accepted_count" 0)

    $recommendation = "Revisar manualmente; la firma automatica no encontro una ruta preferida."
    $nextVariables = @()
    $interpretation = "Sin conclusion automatica fuerte."

    if ($null -ne $PostResultPollLoop) {
        $interpretation = "IMPACT rechazo una fila numerica repetida despues de #rd; no es una perdida RX silenciosa."
        if ($acceptedBeforeReject -ge 3) {
            $recommendation = "Preservar como referencia mixta, cerrar DOSBox, reinicializar ARL/ICS y volver a CYCLES6000 TRACE con rxdelay 3000; maximo cuatro quemas por sesion. Si falla de nuevo, capturar CYCLES6000 UARTDATA TRACE."
            $nextVariables = @("cycles=6000 rxdelay=3000 fresh session max4", "cycles=6000 rxdelay=3000 uartdata")
        } elseif ($null -ne $cycles -and [int]$cycles -ne 6000) {
            $recommendation = "Este setting rechazo de inmediato; volver a CYCLES6000 TRACE con rxdelay 3000 y sesion fresca."
            $nextVariables = @("cycles=6000 rxdelay=3000 fresh session")
        } else {
            $recommendation = "Reinicializar ARL/ICS y repetir una sola quema con el mismo setting antes de mover timing."
            $nextVariables = @("same cycles/rxdelay fresh session")
        }
    } elseif ([int](Get-PropValue $ResultMetrics "rd_transaction_count" 0) -eq 0 -and $null -ne $cycles -and [int]$cycles -ne 6000) {
        $interpretation = "La corrida no llego a #rd/result-read con este setting."
        $recommendation = "No seguir este setting; volver a CYCLES6000 TRACE con rxdelay 3000 despues de reinicializar ARL/ICS."
        $nextVariables = @("cycles=6000 rxdelay=3000 fresh session")
    } elseif ($acceptedCount -ge 5 -and $rejectedCount -eq 0) {
        $interpretation = "La corrida tiene al menos cinco resultados aceptados consecutivos."
        $recommendation = "Preservar como buena referencia y repetir el mismo setting en una sesion fresca."
        $nextVariables = @("same cycles/rxdelay fresh session")
    } elseif ($Reasons -contains "rx_received_but_guest_did_not_read") {
        $interpretation = "Windows/DOSBox recibio bytes que el invitado no consumio."
        $recommendation = "Probar menor carga o UARTDATA TRACE; revisar FIFO/timing antes de culpar a IMPACT."
        $nextVariables = @("cycles -1000 same rxdelay", "trace_level=uartdata")
    } elseif ($Reasons -contains "dirty_status_state") {
        $interpretation = "La sesion parece haber quedado en estado serial/status sucio."
        $recommendation = "Cerrar DOSBox, confirmar que no haya proceso vivo, reinicializar ARL/ICS y repetir una variable."
        $nextVariables = @("fresh session")
    }

    return [pscustomobject]@{
        generated_at = (Get-Date).ToString("o")
        trace_path = (Resolve-Path $TracePath).Path
        cycles = $cycles
        rxdelay = $rxdelay
        trace_level = $traceLevel
        accepted_count = $acceptedCount
        rejected_count = $rejectedCount
        accepted_before_first_reject = $acceptedBeforeReject
        rd_transaction_count = [int](Get-PropValue $ResultMetrics "rd_transaction_count" 0)
        post_result_poll_loop = $PostResultPollLoop
        interfac_artifact_count = $Artifacts.interfac_artifact_count
        lpt_artifact_count = $Artifacts.lpt_artifact_count
        print_job_count = $Artifacts.print_job_count
        interpretation = $interpretation
        recommendation = $recommendation
        next_variables = $nextVariables
    }
}

function Get-CommandGuess([string]$Ascii, [string]$Hex) {
    if ($Ascii -match "TL") { return "tics-link-test" }
    if ($Ascii -match "VE") { return "tics-version" }
    if ($Ascii -match "SI") { return "status-si" }
    if ($Ascii -match "RS") { return "status-rs" }
    if ($Ascii -match "#rd" -and ([regex]::Matches($Ascii, "\?").Count -ge 20)) { return "impact-result-read-poll-loop" }
    if ($Ascii -match "#rd") { return "impact-result-read" }
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
        $txHexText = Limit-DisplayText $candidate.tx_hex
        $txAsciiText = Limit-DisplayText $candidate.tx_ascii
        $rxHexText = Limit-DisplayText $candidate.rx_hex
        $rxAsciiText = Limit-DisplayText $candidate.rx_ascii
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
        candidates = $candidateArray
    }
}

function Get-PostResultPollLoop($Candidates) {
    foreach ($candidate in $Candidates) {
        $txAscii = [string]$candidate.tx_ascii
        $rxAscii = [string]$candidate.rx_ascii
        if ($txAscii -notmatch "#rd") { continue }

        $questionCount = [regex]::Matches($txAscii, "\?").Count
        if ($questionCount -lt 20) { continue }

        $lineCounts = @{}
        foreach ($line in ($rxAscii -split "\\r")) {
            $normalized = $line.Trim()
            if ($normalized.StartsWith("#")) {
                $normalized = $normalized.Substring(1).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($normalized)) { continue }
            if ($normalized -notmatch ",") { continue }
            if (([regex]::Matches($normalized, ",").Count) -lt 5) { continue }

            if (-not $lineCounts.ContainsKey($normalized)) {
                $lineCounts[$normalized] = 0
            }
            $lineCounts[$normalized]++
        }

        $bestLine = $null
        $bestCount = 0
        foreach ($key in $lineCounts.Keys) {
            if ($lineCounts[$key] -gt $bestCount) {
                $bestLine = $key
                $bestCount = $lineCounts[$key]
            }
        }

        if ($bestCount -ge 5) {
            return [pscustomobject]@{
                candidate_index = $candidate.index
                start_elapsed_ms = $candidate.start_elapsed_ms
                end_elapsed_ms = $candidate.end_elapsed_ms
                duration_ms = $candidate.duration_ms
                question_count = $questionCount
                repeated_result_count = $bestCount
                repeated_result_sample = Limit-DisplayText $bestLine 220
                tx_count = $candidate.tx_count
                rx_count = $candidate.rx_count
            }
        }
    }
    return $null
}

$timelinePath = Join-Path $OutDir "timeline.csv"
$traceMb = [math]::Round(($traceItem.Length / 1MB), 2)
$writeTimeline = (-not $NoTimeline) -and ($traceMb -le $TimelineMaxMb)
if ($writeTimeline) {
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
    $timeline | Export-Csv -Path $timelinePath -NoTypeInformation
} else {
    $timelineSkipPath = Join-Path $OutDir "timeline-skipped.txt"
    "Timeline CSV skipped. trace_mb=$traceMb timeline_max_mb=$TimelineMaxMb no_timeline=$([bool]$NoTimeline)" |
        Set-Content -Path $timelineSkipPath -Encoding UTF8
    $timelinePath = $timelineSkipPath
}
$protocolWorkbook = Write-ProtocolWorkbook
$postResultPollLoop = Get-PostResultPollLoop $protocolWorkbook.candidates
$runMetadata = Get-RunMetadata
$runArtifacts = Get-RunArtifacts
$resultReadMetrics = Get-ResultReadMetrics

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

$lineLowEvents = @($events | Where-Object {
    $eventName = Get-PropValue $_ "event"
    ($eventName -eq "modem" -or $eventName -eq "control") -and (
        (Get-PropValue $_ "cts" $true) -eq $false -or
        (Get-PropValue $_ "dsr" $true) -eq $false -or
        (Get-PropValue $_ "dcd" $true) -eq $false
    )
})

$blockingLineDrops = @($lineLowEvents | Where-Object {
    (Get-PropValue $_ "cts" $true) -eq $false -or
    (Get-PropValue $_ "dsr" $true) -eq $false
})

$dcdLowEvents = @($lineLowEvents | Where-Object {
    (Get-PropValue $_ "dcd" $true) -eq $false
})

$lastTx = Get-LastEvent { param($e) (Get-PropValue $e "event") -eq "tx" }
$lastRx = Get-LastEvent { param($e) (Get-PropValue $e "event") -eq "rx" }
$lastRhrRead = Get-LastEvent { param($e)
    (Get-PropValue $e "event") -eq "uart_read" -and (Get-PropValue $e "register") -eq "RHR"
}
$lastThrWrite = Get-LastEvent { param($e)
    (Get-PropValue $e "event") -eq "uart_write" -and (Get-PropValue $e "register") -eq "THR"
}
$lastUartEvent = Get-LastEvent { param($e)
    (Get-PropValue $e "event") -eq "uart_read" -or (Get-PropValue $e "event") -eq "uart_write"
}
$lastEvent = if ($events.Count -gt 0) { $events[$events.Count - 1] } else { $null }

$lastRxAfterLastRhrMs = $null
$lastRxAfterLastUartMs = $null

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
if ($null -ne $postResultPollLoop) {
    $reasons.Add("post_result_poll_loop")
}
$lastEventName = Get-PropValue $lastEvent "event"
if ($blockingLineDrops.Count -gt 0 -and ($txErrors.Count -gt 0 -or $lastEventName -eq "hang_snapshot")) {
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
    $lastUartMs = if ($null -ne $lastUartEvent) { [int](Get-PropValue $lastUartEvent "elapsed_ms" 0) } else { -1 }
    if ($lastReadMs -ge 0) {
        $lastRxAfterLastRhrMs = $lastRxMs - $lastReadMs
    }
    if ($lastUartMs -ge 0) {
        $lastRxAfterLastUartMs = $lastRxMs - $lastUartMs
    }
    if ($lastRxMs -gt $lastReadMs) {
        $reasons.Add("rx_received_but_guest_did_not_read")
    }
    if ($null -ne $lastRxAfterLastRhrMs -and $lastRxAfterLastRhrMs -ge $IdleAfterTxMs) {
        $reasons.Add("rx_continues_after_guest_rhr_reads_stop")
    }
}
if ($reasons.Count -eq 0 -and $hangs.Count -gt 0 -and $lastEventName -eq "hang_snapshot") {
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
    modem_line_low_observed_count = $lineLowEvents.Count
    blocking_modem_line_low_count = $blockingLineDrops.Count
    dcd_low_observed_count = $dcdLowEvents.Count
    protocol_candidate_count = $protocolWorkbook.count
    first_rejected_config = if ($configRejected.Count) { $configRejected[0] } else { $null }
    first_write_failure = if ($txErrors.Count) { $txErrors[0] } else { $null }
    first_fifo_or_uart_error = if ($overruns.Count) { $overruns[0] } else { $null }
    first_modem_line_drop = if ($blockingLineDrops.Count) { $blockingLineDrops[0] } else { $null }
    first_modem_line_low_observed = if ($lineLowEvents.Count) { $lineLowEvents[0] } else { $null }
    first_dcd_low_observed = if ($dcdLowEvents.Count) { $dcdLowEvents[0] } else { $null }
    post_result_poll_loop = $postResultPollLoop
    result_read_metrics = $resultReadMetrics
    run_metadata = $runMetadata
    run_artifacts = $runArtifacts
    last_tx = $lastTx
    last_rx = $lastRx
    last_uart_rhr_read = $lastRhrRead
    last_uart_thr_write = $lastThrWrite
    last_uart_event = $lastUartEvent
    last_rx_after_last_rhr_ms = $lastRxAfterLastRhrMs
    last_rx_after_last_uart_ms = $lastRxAfterLastUartMs
    last_event = $lastEvent
    classification = @($reasons)
}

$suspectPath = Join-Path $OutDir "suspect.json"
$suspect | ConvertTo-Json -Depth 12 | Set-Content -Path $suspectPath -Encoding UTF8
$labNextTest = New-LabNextTestReport $runMetadata $runArtifacts $resultReadMetrics $postResultPollLoop @($reasons)
$labNextTestJsonPath = Join-Path $OutDir "lab-next-test.json"
$labNextTestMdPath = Join-Path $OutDir "lab-next-test.md"
$labNextTest | ConvertTo-Json -Depth 10 | Set-Content -Path $labNextTestJsonPath -Encoding UTF8

$nextVariablesText = if ($labNextTest.next_variables.Count -gt 0) {
    ($labNextTest.next_variables | ForEach-Object { "- $_" }) -join "`n"
} else {
    "- none"
}
$labNextLines = @(
    "# ARL Lab Next Test",
    "",
    "Trace: $TracePath",
    "",
    "## Setting",
    "",
    "- Cycles: $($labNextTest.cycles)",
    "- RxDelay: $($labNextTest.rxdelay)",
    "- Trace level: $($labNextTest.trace_level)",
    "",
    "## Result Acceptance",
    "",
    "- Result-read transactions: $($labNextTest.rd_transaction_count)",
    "- Accepted results: $($labNextTest.accepted_count)",
    "- Rejected results: $($labNextTest.rejected_count)",
    "- Accepted before first reject: $($labNextTest.accepted_before_first_reject)",
    "- INTERFAC artifacts: $($labNextTest.interfac_artifact_count)",
    "- LPT artifacts: $($labNextTest.lpt_artifact_count)",
    "- Print jobs: $($labNextTest.print_job_count)",
    "",
    "## Interpretation",
    "",
    $labNextTest.interpretation,
    "",
    "## Recommendation",
    "",
    $labNextTest.recommendation,
    "",
    "## Next Variables",
    "",
    $nextVariablesText
)
$labNextLines | Set-Content -Path $labNextTestMdPath -Encoding UTF8

$resultTimingPath = Join-Path $OutDir "result-timing.csv"
$resultTimingMdPath = Join-Path $OutDir "result-timing.md"
$resultTimingRows = @(
    $resultReadMetrics.transactions | ForEach-Object {
        [pscustomobject]@{
            index = $_.index
            outcome = $_.outcome
            rd_elapsed_ms = $_.rd_elapsed_ms
            first_rx_delay_ms = $_.first_rx_delay_ms
            first_result_start_delay_ms = $_.first_result_start_delay_ms
            first_result_end_delay_ms = $_.first_result_end_delay_ms
            first_result_duration_ms = $_.first_result_duration_ms
            first_result_byte_count = $_.first_result_byte_count
            interbyte_avg_ms = $_.first_result_interbyte_avg_ms
            interbyte_p95_ms = $_.first_result_interbyte_p95_ms
            interbyte_max_ms = $_.first_result_interbyte_max_ms
            post_result_tx_delay_ms = $_.post_result_tx_delay_ms
            post_result_tx_excerpt = $_.post_result_tx_excerpt
            checksum = $_.first_result_checksum
            checksum_valid = $_.first_result_checksum_valid
            result_line_count = $_.result_line_count
            first_result = if ($null -ne $_.first_result) { $_.first_result.line } else { $null }
        }
    }
)
$resultTimingRows | Export-Csv -Path $resultTimingPath -NoTypeInformation -Encoding UTF8

$acceptedTiming = @($resultTimingRows | Where-Object { ([string]$_.outcome).StartsWith("accepted") })
$rejectedTiming = @($resultTimingRows | Where-Object { ([string]$_.outcome).StartsWith("rejected") })
function Format-TimingGroup([string]$Label, $Rows) {
    $rowsArray = @($Rows)
    if ($rowsArray.Count -eq 0) { return "- ${Label}: none" }
    $firstRxStats = Get-NumberStats (@($rowsArray | ForEach-Object { $_.first_rx_delay_ms }))
    $durationStats = Get-NumberStats (@($rowsArray | ForEach-Object { $_.first_result_duration_ms }))
    $postStats = Get-NumberStats (@($rowsArray | ForEach-Object { $_.post_result_tx_delay_ms }))
    return "- ${Label}: count $($rowsArray.Count), first RX avg/max $($firstRxStats.avg)/$($firstRxStats.max) ms, row duration avg/max $($durationStats.avg)/$($durationStats.max) ms, IMPACT response avg/max $($postStats.avg)/$($postStats.max) ms"
}

$resultTimingLines = @(
    "# ARL Result Timing",
    "",
    "Trace: $TracePath",
    "",
    "This report measures the result-read phase after each `#rd 246` command.",
    "",
    "## Summary",
    "",
    (Format-TimingGroup "accepted" $acceptedTiming),
    (Format-TimingGroup "rejected" $rejectedTiming),
    "",
    "## Transactions",
    "",
    "| # | outcome | #rd ms | first RX delay | row start delay | row end delay | row duration | bytes | gap avg/p95/max | IMPACT response delay | response | checksum |",
    "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|"
)
foreach ($row in $resultTimingRows) {
    $gapText = "$($row.interbyte_avg_ms)/$($row.interbyte_p95_ms)/$($row.interbyte_max_ms)"
    $checksumText = if ($null -ne $row.checksum) { "$($row.checksum) valid=$($row.checksum_valid)" } else { "" }
    $responseText = ([string]$row.post_result_tx_excerpt).Replace("|", "\|")
    $resultTimingLines += "| $($row.index) | $($row.outcome) | $($row.rd_elapsed_ms) | $($row.first_rx_delay_ms) | $($row.first_result_start_delay_ms) | $($row.first_result_end_delay_ms) | $($row.first_result_duration_ms) | $($row.first_result_byte_count) | $gapText | $($row.post_result_tx_delay_ms) | ``$responseText`` | $checksumText |"
}
$resultTimingLines | Set-Content -Path $resultTimingMdPath -Encoding UTF8

$summaryPath = Join-Path $OutDir "summary.md"
$auditManifestPath = Join-Path $OutDir "audit-manifest.json"
$auditManifestMdPath = Join-Path $OutDir "audit-manifest.md"
$classificationText = ($reasons | ForEach-Object { "- $_" }) -join "`n"
if ([string]::IsNullOrWhiteSpace($classificationText)) { $classificationText = "- none" }

$lastTxText = if ($lastTx) { "line $($lastTx.line), elapsed_ms $($lastTx.elapsed_ms), byte $($lastTx.byte_hex)" } else { "none" }
$lastRxText = if ($lastRx) { "line $($lastRx.line), elapsed_ms $($lastRx.elapsed_ms), byte $($lastRx.byte_hex), error $($lastRx.rx_error_bits)" } else { "none" }
$lastRhrText = if ($lastRhrRead) { "line $($lastRhrRead.line), elapsed_ms $($lastRhrRead.elapsed_ms), value $($lastRhrRead.value_hex)" } else { "none" }
$lastThrText = if ($lastThrWrite) { "line $($lastThrWrite.line), elapsed_ms $($lastThrWrite.elapsed_ms), value $($lastThrWrite.value_hex)" } else { "none" }
$lastEventText = if ($lastEvent) { "line $($lastEvent.line), elapsed_ms $($lastEvent.elapsed_ms), event $($lastEvent.event)" } else { "none" }
$rxVsRhrText = if ($null -ne $lastRxAfterLastRhrMs) { "$lastRxAfterLastRhrMs ms" } else { "n/a" }
$rxVsUartText = if ($null -ne $lastRxAfterLastUartMs) { "$lastRxAfterLastUartMs ms" } else { "n/a" }
$pollLoopText = if ($null -ne $postResultPollLoop) {
    "candidate $($postResultPollLoop.candidate_index), ? count $($postResultPollLoop.question_count), repeated result count $($postResultPollLoop.repeated_result_count), sample: $($postResultPollLoop.repeated_result_sample)"
} else {
    "none"
}
$resultReadText = "rd $($resultReadMetrics.rd_transaction_count), accepted $($resultReadMetrics.accepted_count), rejected $($resultReadMetrics.rejected_count), accepted before first reject $($resultReadMetrics.accepted_before_first_reject)"

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
    "- Modem/control line low observations: $($lineLowEvents.Count)",
    "- Blocking CTS/DSR low observations: $($blockingLineDrops.Count)",
    "- DCD low observations: $($dcdLowEvents.Count)",
    "- Protocol candidates: $($protocolWorkbook.count)",
    "- Post-result poll loop: $pollLoopText",
    "- Result-read metrics: $resultReadText",
    "",
    "## Classification",
    "",
    $classificationText,
    "",
    "## Last Events",
    "",
    "- Last TX: $lastTxText",
    "- Last RX: $lastRxText",
    "- Last guest RHR read: $lastRhrText",
    "- Last guest THR write: $lastThrText",
    "- Last RX after last RHR read: $rxVsRhrText",
    "- Last RX after last UART event: $rxVsUartText",
    "- Last event: $lastEventText",
    "",
    "## Outputs",
    "",
    "- Timeline CSV: $timelinePath",
    "- Protocol candidates MD: $($protocolWorkbook.markdown)",
    "- Protocol candidates JSON: $($protocolWorkbook.json)",
    "- Suspect JSON: $suspectPath",
    "- Lab next test MD: $labNextTestMdPath",
    "- Lab next test JSON: $labNextTestJsonPath",
    "- Result timing MD: $resultTimingMdPath",
    "- Result timing CSV: $resultTimingPath",
    "- Audit manifest MD: $auditManifestMdPath",
    "- Audit manifest JSON: $auditManifestPath"
)
$summaryLines | Set-Content -Path $summaryPath -Encoding UTF8

$auditFiles = Get-AuditFileEntries $OutDir
$auditManifest = [pscustomobject]@{
    schema = "arl.diagnostics.audit.v1"
    generated_at = (Get-Date).ToString("o")
    run_dir = (Resolve-Path $OutDir).Path
    trace_path = (Resolve-Path $TracePath).Path
    trace_mb = $traceMb
    analyzer = @{
        script = $MyInvocation.MyCommand.Name
        timeline_written = [bool]$writeTimeline
        timeline_max_mb = $TimelineMaxMb
        no_timeline = [bool]$NoTimeline
        transaction_gap_ms = $TransactionGapMs
        idle_after_tx_ms = $IdleAfterTxMs
    }
    metadata = $runMetadata
    counts = @{
        events = $events.Count
        parse_errors = $badLines.Count
        tx_bytes = $tx.Count
        rx_bytes = $rx.Count
        guest_thr_writes = $uartWrites.Count
        guest_rhr_reads = $uartReads.Count
        hang_snapshots = $hangs.Count
        protocol_candidates = $protocolWorkbook.count
        result_read_transactions = $resultReadMetrics.rd_transaction_count
        accepted_results = $resultReadMetrics.accepted_count
        rejected_results = $resultReadMetrics.rejected_count
        accepted_before_first_reject = $resultReadMetrics.accepted_before_first_reject
        lpt_artifacts = $runArtifacts.lpt_artifact_count
        interfac_artifacts = $runArtifacts.interfac_artifact_count
        print_jobs = $runArtifacts.print_job_count
    }
    classification = @($reasons)
    recommendation = $labNextTest.recommendation
    next_variables = @($labNextTest.next_variables)
    post_result_poll_loop = $postResultPollLoop
    first_reject = $resultReadMetrics.first_reject
    files = $auditFiles
}
$auditManifest | ConvertTo-Json -Depth 14 | Set-Content -Path $auditManifestPath -Encoding UTF8

$auditLines = New-Object System.Collections.Generic.List[string]
$auditLines.Add("# ARL Run Audit Manifest")
$auditLines.Add("")
$auditLines.Add("Run directory: $OutDir")
$auditLines.Add("")
$auditLines.Add("## Outcome")
$auditLines.Add("")
$auditLines.Add("- Classification: $(@($reasons) -join ', ')")
$auditLines.Add("- Recommendation: $($labNextTest.recommendation)")
$auditLines.Add("- Result reads: $($resultReadMetrics.rd_transaction_count)")
$auditLines.Add("- Accepted results: $($resultReadMetrics.accepted_count)")
$auditLines.Add("- Rejected results: $($resultReadMetrics.rejected_count)")
$auditLines.Add("- Accepted before first reject: $($resultReadMetrics.accepted_before_first_reject)")
$auditLines.Add("")
$auditLines.Add("## Files")
$auditLines.Add("")
$auditLines.Add("| Kind | Name | Bytes | SHA-256 |")
$auditLines.Add("|---|---|---:|---|")
foreach ($file in $auditFiles) {
    $auditLines.Add("| $($file.kind) | ``$($file.name)`` | $($file.size_bytes) | ``$($file.sha256)`` |")
}
$auditLines | Set-Content -Path $auditManifestMdPath -Encoding UTF8

Write-Host "Wrote $summaryPath"
Write-Host "Wrote $timelinePath"
Write-Host "Wrote $($protocolWorkbook.markdown)"
Write-Host "Wrote $($protocolWorkbook.json)"
Write-Host "Wrote $suspectPath"
Write-Host "Wrote $labNextTestMdPath"
Write-Host "Wrote $labNextTestJsonPath"
Write-Host "Wrote $auditManifestMdPath"
Write-Host "Wrote $auditManifestPath"
