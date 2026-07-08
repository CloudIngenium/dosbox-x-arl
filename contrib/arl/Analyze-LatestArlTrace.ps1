param(
    [string]$RunRoot = "C:\ARL\diagnostics",

    [string]$Session = "",

    [int]$IdleAfterTxMs = 5000,

    [int]$TransactionGapMs = 750
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $RunRoot -PathType Container)) {
    throw "Run root not found: $RunRoot"
}

$directories = Get-ChildItem -Path $RunRoot -Directory -ErrorAction Stop
if (-not [string]::IsNullOrWhiteSpace($Session)) {
    $prefix = "$Session-"
    $directories = @($directories | Where-Object { $_.Name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
}

$latest = $directories |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object {
        $trace = Join-Path $_.FullName "serial.ndjson"
        if (Test-Path -Path $trace -PathType Leaf) {
            [pscustomobject]@{
                Directory = $_.FullName
                Trace = $trace
                LastWriteTime = (Get-Item $trace).LastWriteTime
            }
        }
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $latest) {
    if ([string]::IsNullOrWhiteSpace($Session)) {
        throw "No serial.ndjson traces found under $RunRoot"
    }
    throw "No serial.ndjson traces found under $RunRoot for session '$Session'"
}

$analyzer = Join-Path $PSScriptRoot "Analyze-ArlTrace.ps1"
if (-not (Test-Path -Path $analyzer -PathType Leaf)) {
    throw "Analyzer not found: $analyzer"
}

Write-Host "Analyzing latest trace: $($latest.Trace)"
& $analyzer `
    -TracePath $latest.Trace `
    -OutDir $latest.Directory `
    -IdleAfterTxMs $IdleAfterTxMs `
    -TransactionGapMs $TransactionGapMs
