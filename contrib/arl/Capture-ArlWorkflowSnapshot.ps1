param(
    [Parameter(Mandatory = $true)]
    [string]$ImplusPath,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [ValidateSet("before", "after")]
    [string]$Phase
)

$ErrorActionPreference = "Stop"
$knownDataFiles = @("WORK.DAT", "QUA.DAT", "MAT.DAT", "MESS.DAT")
New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$files = @(
    Get-ChildItem -LiteralPath $ImplusPath -File -ErrorAction Stop |
        Where-Object { $_.Extension -in @(".CAL", ".REG") -or $_.Name -in $knownDataFiles } |
        Sort-Object Name
)

$manifest = foreach ($file in $files) {
    $target = Join-Path $Destination $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    [pscustomobject]@{
        phase = $Phase
        name = $file.Name
        length = $file.Length
        last_write_time_utc = $file.LastWriteTimeUtc.ToString("o")
        sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$encoding = New-Object System.Text.UTF8Encoding($false)
$json = $manifest | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $Destination "snapshot-manifest.json"), $json, $encoding)
$manifest
