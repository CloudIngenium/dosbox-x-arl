param(
    [ValidateSet("happy-path", "silent-after-spark", "delayed-result", "line-drop", "bad-response")]
    [string]$Mode = "happy-path",

    [string]$ProfilePath = (Join-Path $PSScriptRoot "profiles\arl3460-baseline.json"),
    [string]$ListenAddress = "127.0.0.1",
    [int]$Port = 3460,
    [string]$Session = "impact-emulator",
    [string]$LogPath = "",
    [int]$MaxConnections = 0,
    [int]$ExitAfterIdleMs = 0,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function Get-PropValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Normalize-Hex([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    return (($Text -replace '[^0-9A-Fa-f]', '').ToUpperInvariant())
}

function ConvertFrom-HexBytes([string]$Hex) {
    $clean = Normalize-Hex $Hex
    if (($clean.Length % 2) -ne 0) {
        throw "Odd number of hex characters in response: $Hex"
    }
    $bytes = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $clean.Length; $i += 2) {
        $bytes.Add([Convert]::ToByte($clean.Substring($i, 2), 16))
    }
    return [byte[]]$bytes.ToArray()
}

function ConvertFrom-AsciiBytes([string]$Text) {
    if ($null -eq $Text) { return [byte[]]@() }
    return [System.Text.Encoding]::ASCII.GetBytes($Text)
}

function Format-HexBytes([byte[]]$Bytes) {
    $parts = foreach ($byte in $Bytes) { "{0:X2}" -f ([int]$byte -band 0xff) }
    return ($parts -join " ")
}

function Format-HexCompact([byte[]]$Bytes) {
    $parts = foreach ($byte in $Bytes) { "{0:X2}" -f ([int]$byte -band 0xff) }
    return ($parts -join "")
}

function Get-PrintableByte([byte]$Byte) {
    switch ([int]$Byte) {
        9 { return "\t" }
        10 { return "\n" }
        13 { return "\r" }
        default {
            if ($Byte -ge 32 -and $Byte -le 126) { return [char]$Byte }
            return "."
        }
    }
}

function Format-AsciiBytes([byte[]]$Bytes) {
    $parts = foreach ($byte in $Bytes) { Get-PrintableByte $byte }
    return ($parts -join "")
}

function Get-NowMs {
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function Get-ElapsedMs {
    return ((Get-NowMs) - $script:StartEpochMs)
}

function Write-EmulatorEvent([hashtable]$Fields) {
    $event = [ordered]@{
        epoch_ms = Get-NowMs
        elapsed_ms = Get-ElapsedMs
        source = "arlemu"
        session = $Session
        mode = $Mode
        realport = "nullmodem:$ListenAddress`:$Port"
        event = Get-PropValue ([pscustomobject]$Fields) "event" "message"
    }
    foreach ($key in $Fields.Keys) {
        if ($key -ne "event") {
            $event[$key] = $Fields[$key]
        }
    }
    $json = ([pscustomobject]$event | ConvertTo-Json -Depth 12 -Compress)
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -Path $LogPath -Value $json -Encoding UTF8
    }
}

function Write-ByteEvent([string]$Direction, [byte]$Byte, $Rule = $null) {
    $fields = @{
        event = $Direction
        byte_dec = [int]$Byte
        byte_hex = "{0:X2}" -f ([int]$Byte -band 0xff)
        ascii = Get-PrintableByte $Byte
    }
    if ($null -ne $Rule) {
        $fields["rule"] = Get-PropValue $Rule "label" "unknown"
        $fields["phase"] = Get-PropValue $Rule "phase" "unknown"
    }
    Write-EmulatorEvent $fields
}

function Get-ResponseBytes($Rule, [string]$CurrentMode) {
    if ($CurrentMode -eq "bad-response") {
        $badHex = Get-PropValue $Rule "bad_response_hex"
        $badAscii = Get-PropValue $Rule "bad_response_ascii"
        if (-not [string]::IsNullOrWhiteSpace($badHex)) { return ConvertFrom-HexBytes $badHex }
        if ($null -ne $badAscii) { return ConvertFrom-AsciiBytes $badAscii }
        return [byte[]]@(0x15)
    }

    $responseHex = Get-PropValue $Rule "response_hex"
    $responseAscii = Get-PropValue $Rule "response_ascii"
    if (-not [string]::IsNullOrWhiteSpace($responseHex)) { return ConvertFrom-HexBytes $responseHex }
    if ($null -ne $responseAscii) { return ConvertFrom-AsciiBytes $responseAscii }
    return [byte[]]@()
}

function Get-RuleDelayMs($Rule, [string]$CurrentMode) {
    $phase = Get-PropValue $Rule "phase" ""
    if ($CurrentMode -eq "delayed-result" -and $phase -eq "analysis-result") {
        $delay = [int](Get-PropValue $script:Profile "delayed_result_ms" 10000)
        return $delay
    }
    return [int](Get-PropValue $Rule "delay_ms" (Get-PropValue $script:Profile "default_response_delay_ms" 25))
}

function Find-MatchingRule([byte[]]$InputBytes) {
    $inputHex = Format-HexCompact $InputBytes
    $inputAscii = [System.Text.Encoding]::ASCII.GetString($InputBytes)

    foreach ($rule in @($script:Profile.responses)) {
        $matchType = Get-PropValue $rule "match" "exact_hex"
        switch ($matchType) {
            "any" { return $rule }
            "exact_hex" {
                if ($inputHex -eq (Normalize-Hex (Get-PropValue $rule "pattern_hex" ""))) { return $rule }
            }
            "prefix_hex" {
                $pattern = Normalize-Hex (Get-PropValue $rule "pattern_hex" "")
                if (-not [string]::IsNullOrWhiteSpace($pattern) -and $inputHex.StartsWith($pattern)) { return $rule }
            }
            "contains_hex" {
                $pattern = Normalize-Hex (Get-PropValue $rule "pattern_hex" "")
                if (-not [string]::IsNullOrWhiteSpace($pattern) -and $inputHex.Contains($pattern)) { return $rule }
            }
            "exact_ascii" {
                if ($inputAscii -eq (Get-PropValue $rule "pattern_ascii" "")) { return $rule }
            }
            "prefix_ascii" {
                $pattern = Get-PropValue $rule "pattern_ascii" ""
                if (-not [string]::IsNullOrWhiteSpace($pattern) -and $inputAscii.StartsWith($pattern)) { return $rule }
            }
            "ascii_contains" {
                $pattern = Get-PropValue $rule "pattern_ascii" ""
                if (-not [string]::IsNullOrWhiteSpace($pattern) -and $inputAscii.Contains($pattern)) { return $rule }
            }
            default {
                throw "Unknown emulator match type '$matchType' in rule '$((Get-PropValue $rule "label" "unknown"))'"
            }
        }
    }
    return $null
}

function Invoke-Transaction([System.Net.Sockets.NetworkStream]$Stream, [byte[]]$InputBytes) {
    $rule = Find-MatchingRule $InputBytes
    $inputHex = Format-HexBytes $InputBytes
    $inputAscii = Format-AsciiBytes $InputBytes

    if ($null -eq $rule) {
        Write-EmulatorEvent @{
            event = "no_match"
            input_hex = $inputHex
            input_ascii = $inputAscii
            message = "No profile rule matched this transaction"
        }
        return $false
    }

    $label = Get-PropValue $rule "label" "unknown"
    $phase = Get-PropValue $rule "phase" "unknown"

    Write-EmulatorEvent @{
        event = "rule_match"
        rule = $label
        phase = $phase
        input_hex = $inputHex
        input_ascii = $inputAscii
    }

    if ($Mode -eq "silent-after-spark" -and $phase -eq "analysis-result") {
        Write-EmulatorEvent @{
            event = "response_suppressed"
            rule = $label
            phase = $phase
            message = "Mode silent-after-spark suppresses this response"
        }
        return $false
    }

    if ($Mode -eq "line-drop" -and $phase -eq "analysis-result") {
        Write-EmulatorEvent @{
            event = "line_drop"
            rule = $label
            phase = $phase
            message = "Mode line-drop closes the TCP nullmodem connection"
        }
        return $true
    }

    $delayMs = Get-RuleDelayMs $rule $Mode
    if ($delayMs -gt 0) {
        Start-Sleep -Milliseconds $delayMs
    }

    $responseBytes = Get-ResponseBytes $rule $Mode
    if ($responseBytes.Count -eq 0) {
        Write-EmulatorEvent @{
            event = "matched_no_response"
            rule = $label
            phase = $phase
        }
        return $false
    }

    foreach ($byte in $responseBytes) {
        $one = [byte[]]@($byte)
        $Stream.Write($one, 0, 1)
        $Stream.Flush()
        Write-ByteEvent "rx" $byte $rule
    }
    return $false
}

function Test-Profile {
    if ($null -eq $script:Profile.responses -or @($script:Profile.responses).Count -eq 0) {
        throw "Profile has no responses: $ProfilePath"
    }
    foreach ($rule in @($script:Profile.responses)) {
        $label = Get-PropValue $rule "label"
        if ([string]::IsNullOrWhiteSpace($label)) { throw "Every response rule needs a label" }
        [void](Get-ResponseBytes $rule "happy-path")
        [void](Get-RuleDelayMs $rule "happy-path")
    }
    Write-Host "Profile OK: $ProfilePath"
    Write-Host "Rules: $(@($script:Profile.responses).Count)"
}

function Invoke-ClientSession([System.Net.Sockets.TcpClient]$Client) {
    $clientEndpoint = $Client.Client.RemoteEndPoint.ToString()
    Write-Host "Client connected: $clientEndpoint"
    Write-EmulatorEvent @{ event = "connect"; client = $clientEndpoint }

    $Client.NoDelay = $true
    $stream = $Client.GetStream()
    $buffer = New-Object System.Collections.Generic.List[byte]
    $transactionIdleMs = [int](Get-PropValue $script:Profile "transaction_idle_ms" 200)
    $lastInputTick = [Environment]::TickCount64
    $lastActivityTick = [Environment]::TickCount64

    try {
        while ($Client.Connected) {
            if ($stream.DataAvailable) {
                $value = $stream.ReadByte()
                if ($value -lt 0) { break }
                $byte = [byte]$value
                $buffer.Add($byte)
                Write-ByteEvent "tx" $byte
                $lastInputTick = [Environment]::TickCount64
                $lastActivityTick = $lastInputTick
                continue
            }

            $nowTick = [Environment]::TickCount64
            if ($buffer.Count -gt 0 -and (($nowTick - $lastInputTick) -ge $transactionIdleMs)) {
                $closeAfterTransaction = Invoke-Transaction $stream ([byte[]]$buffer.ToArray())
                $buffer.Clear()
                $lastActivityTick = [Environment]::TickCount64
                if ($closeAfterTransaction) { break }
            }

            if ($ExitAfterIdleMs -gt 0 -and $buffer.Count -eq 0 -and (($nowTick - $lastActivityTick) -ge $ExitAfterIdleMs)) {
                Write-EmulatorEvent @{ event = "idle_exit"; idle_ms = $ExitAfterIdleMs }
                break
            }

            Start-Sleep -Milliseconds 10
        }
    } finally {
        $stream.Close()
        $Client.Close()
        Write-EmulatorEvent @{ event = "disconnect"; client = $clientEndpoint }
        Write-Host "Client disconnected: $clientEndpoint"
    }
}

if (-not (Test-Path -Path $ProfilePath -PathType Leaf)) {
    throw "ARL emulator profile not found: $ProfilePath"
}

$script:Profile = Get-Content -Path $ProfilePath -Raw | ConvertFrom-Json
$script:StartEpochMs = Get-NowMs

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    $logDir = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    Write-EmulatorEvent @{
        event = "trace_open"
        profile = (Resolve-Path $ProfilePath).Path
        message = "ARL emulator trace enabled"
    }
}

if ($SelfTest) {
    Test-Profile
    exit 0
}

$address = [System.Net.IPAddress]::Parse($ListenAddress)
$listener = [System.Net.Sockets.TcpListener]::new($address, $Port)
$listener.Start()
$connections = 0
$serverStartTick = [Environment]::TickCount64

Write-Host "ARL emulator listening on $ListenAddress`:$Port"
Write-Host "Mode: $Mode"
Write-Host "Profile: $ProfilePath"
Write-EmulatorEvent @{ event = "listen"; address = $ListenAddress; port = $Port }

try {
    while ($true) {
        if ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            $connections++
            Invoke-ClientSession $client
            if ($MaxConnections -gt 0 -and $connections -ge $MaxConnections) { break }
            continue
        }

        if ($ExitAfterIdleMs -gt 0 -and $connections -eq 0 -and (([Environment]::TickCount64 - $serverStartTick) -ge $ExitAfterIdleMs)) {
            Write-EmulatorEvent @{ event = "idle_exit"; idle_ms = $ExitAfterIdleMs; message = "No client connected before idle timeout" }
            break
        }

        Start-Sleep -Milliseconds 50
    }
} finally {
    $listener.Stop()
    Write-EmulatorEvent @{ event = "stop"; connections = $connections }
    Write-Host "ARL emulator stopped."
}
