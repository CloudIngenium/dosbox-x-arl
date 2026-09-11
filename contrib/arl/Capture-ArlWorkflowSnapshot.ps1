param(
    [Parameter(Mandatory = $true)]
    [string]$ImplusPath,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [ValidateSet("before", "after")]
    [string]$Phase
)

$ErrorActionPreference = "Stop"
# The snapshot set is every file a standardization or normalization can change on disk: the curves
# (.CAL/.REG), the four .DAT tables, every .GPX (AL.GPX carries the drift coefficients and the
# type-standardization values -- the 2026-07-23 KC-356HY type standardization changed it and no
# passive bundle captured it) and IMPACT.INI. Top level of IMPLUS only. Copy-Item copies bytes, so
# the CP437 content lands byte-exact; never read these files and write them back as text.
$snapshotExtensions = @(".CAL", ".REG", ".GPX")
$knownDataFiles = @("WORK.DAT", "QUA.DAT", "MAT.DAT", "MESS.DAT", "IMPACT.INI")
New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$files = @(
    Get-ChildItem -LiteralPath $ImplusPath -File -ErrorAction Stop |
        Where-Object { $_.Extension -in $snapshotExtensions -or $_.Name -in $knownDataFiles } |
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
