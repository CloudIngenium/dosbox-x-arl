param(
    [Parameter(Mandatory = $true)]
    [string]$CapturePath,

    [string]$PrinterName = "EPSON LX-350",

    [string]$SpoolDir = "",

    [string]$PrintScriptPath = "",

    [int]$ParentPid = 0,

    [int]$IdleMs = 2500,

    [int]$PollMs = 500,

    [int]$MinBytes = 1,

    [switch]$AppendFormFeed,

    [switch]$Send
)

$ErrorActionPreference = "Stop"

function Write-Log([string]$Message) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Write-Host "[$stamp] $Message"
}

function Read-FileRange([string]$Path, [long]$Offset, [long]$Count) {
    if ($Count -gt [int]::MaxValue) {
        throw "Requested LPT job is too large to buffer in one print job: $Count bytes"
    }

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        $stream.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $targetCount = [int]$Count
        $buffer = New-Object byte[] $targetCount
        $read = 0
        while ($read -lt $targetCount) {
            $chunk = $stream.Read($buffer, $read, $targetCount - $read)
            if ($chunk -le 0) { break }
            $read += $chunk
        }
        if ($read -eq $targetCount) { return ,$buffer }

        $actual = New-Object byte[] $read
        [Array]::Copy($buffer, $actual, $read)
        return ,$actual
    } finally {
        $stream.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($SpoolDir)) {
    $runDir = Split-Path -Parent $CapturePath
    $SpoolDir = Join-Path $runDir "print-jobs"
}
New-Item -ItemType Directory -Force -Path $SpoolDir | Out-Null

if ([string]::IsNullOrWhiteSpace($PrintScriptPath)) {
    $PrintScriptPath = Join-Path $PSScriptRoot "Print-ArlLptCapture.ps1"
}
if ($Send -and -not (Test-Path -Path $PrintScriptPath -PathType Leaf)) {
    throw "Print script not found: $PrintScriptPath"
}

Write-Log "Watching LPT capture: $CapturePath"
Write-Log "Spool directory: $SpoolDir"
Write-Log "Printer: $PrinterName"
Write-Log "Send enabled: $Send"
Write-Log "Append form feed: $AppendFormFeed"
if ($ParentPid -gt 0) {
    Write-Log "Parent DOSBox PID: $ParentPid"
}

$offset = 0L
$lastSize = -1L
$lastChange = Get-Date
$jobIndex = 0

while ($true) {
    $now = Get-Date
    $exists = Test-Path -Path $CapturePath -PathType Leaf
    $size = 0L

    if ($exists) {
        $item = Get-Item -Path $CapturePath
        $size = [long]$item.Length
    }

    if ($size -ne $lastSize) {
        Write-Log "LPT capture size changed: $lastSize -> $size"
        $lastSize = $size
        $lastChange = $now
    }

    if ($size -lt $offset) {
        Write-Log "LPT capture was truncated; resetting offset $offset -> 0"
        $offset = 0L
    }

    $idleFor = ($now - $lastChange).TotalMilliseconds
    if ($size -gt $offset -and $idleFor -ge $IdleMs) {
        $count = $size - $offset
        if ($count -ge $MinBytes) {
            $jobIndex++
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $jobBase = "{0}-{1:D3}-offset-{2}-len-{3}" -f $stamp, $jobIndex, $offset, $count
            $jobPath = Join-Path $SpoolDir "$jobBase.prn"
            $manifestPath = Join-Path $SpoolDir "$jobBase.json"
            $printLogPath = Join-Path $SpoolDir "$jobBase.print.log"

            Write-Log "Spooling LPT bytes offset=$offset length=$count to $jobPath"
            $bytes = Read-FileRange -Path $CapturePath -Offset $offset -Count $count
            [System.IO.File]::WriteAllBytes($jobPath, $bytes)

            $hash = Get-FileHash -Path $jobPath -Algorithm SHA256
            $manifest = [pscustomobject]@{
                created = (Get-Date).ToString("o")
                source_capture = $CapturePath
                job_path = $jobPath
                offset = $offset
                length = $count
                sha256 = $hash.Hash
                printer_name = $PrinterName
                send_enabled = [bool]$Send
                append_form_feed = [bool]$AppendFormFeed
                parent_pid = if ($ParentPid -gt 0) { $ParentPid } else { $null }
            }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

            if ($Send) {
                Write-Log "Sending $jobPath to $PrinterName"
                try {
                    $printArgs = @(
                        "-CapturePath", $jobPath,
                        "-PrinterName", $PrinterName,
                        "-Send"
                    )
                    if ($AppendFormFeed) {
                        $printArgs += "-AppendFormFeed"
                    }
                    & $PrintScriptPath @printArgs *>&1 |
                        Set-Content -Path $printLogPath -Encoding UTF8
                    Write-Log "Printed $jobPath"
                } catch {
                    $_ | Out-String | Set-Content -Path $printLogPath -Encoding UTF8
                    Write-Log "Print failed for ${jobPath}: $($_.Exception.Message)"
                }
            }

            $offset = $size
        }
    }

    $parentAlive = $true
    if ($ParentPid -gt 0) {
        $parentAlive = $null -ne (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)
    }

    if (-not $parentAlive -and $size -le $offset -and $idleFor -ge $IdleMs) {
        Write-Log "Parent exited and all LPT bytes were processed."
        break
    }

    Start-Sleep -Milliseconds $PollMs
}
