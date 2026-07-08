param(
    [Parameter(Mandatory = $true)]
    [string]$RunPath,

    [string]$Label = "arl-run",

    [string]$PreserveRoot = "C:\ARL\diagnostics\preserved"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $RunPath -PathType Container)) {
    throw "Run path not found: $RunPath"
}

$safeLabel = ($Label -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($safeLabel)) {
    $safeLabel = "arl-run"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dest = Join-Path $PreserveRoot "$stamp-$safeLabel"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$sourceBefore = Get-ChildItem -Path $RunPath -File -Recurse |
    Select-Object FullName, Length, LastWriteTime

$robocopyLog = Join-Path $dest "robocopy.log"
$robocopyArgs = @(
    $RunPath,
    $dest,
    "/E",
    "/R:1",
    "/W:1",
    "/COPY:DAT",
    "/DCOPY:DAT",
    "/NP",
    "/LOG:$robocopyLog"
)
$robocopy = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
if ($robocopy.ExitCode -ge 8) {
    throw "robocopy failed with exit code $($robocopy.ExitCode). See $robocopyLog"
}

$sourceAfter = Get-ChildItem -Path $RunPath -File -Recurse |
    Select-Object FullName, Length, LastWriteTime
$snapshotFiles = Get-ChildItem -Path $dest -File -Recurse |
    Select-Object FullName, Length, LastWriteTime

$hashes = foreach ($file in (Get-ChildItem -Path $dest -File -Recurse)) {
    try {
        $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256
        [pscustomobject]@{
            path = $file.FullName.Substring($dest.Length).TrimStart("\")
            length = $file.Length
            last_write_time = $file.LastWriteTime.ToString("o")
            sha256 = $hash.Hash
        }
    } catch {
        [pscustomobject]@{
            path = $file.FullName.Substring($dest.Length).TrimStart("\")
            length = $file.Length
            last_write_time = $file.LastWriteTime.ToString("o")
            sha256 = $null
            error = $_.Exception.Message
        }
    }
}

$shaPath = Join-Path $dest "SHA256SUMS.txt"
$hashes |
    Sort-Object path |
    ForEach-Object { "{0}  {1}" -f $_.sha256, $_.path } |
    Set-Content -Path $shaPath -Encoding ASCII

$processes = @(Get-Process dosbox* -ErrorAction SilentlyContinue |
    Select-Object Id, ProcessName, StartTime, Path)
$manifest = [pscustomobject]@{
    preserved_at = (Get-Date).ToString("o")
    source_run_path = $RunPath
    preserved_path = $dest
    label = $Label
    robocopy_exit_code = $robocopy.ExitCode
    source_before = $sourceBefore
    source_after = $sourceAfter
    snapshot_files = $snapshotFiles
    active_dosbox_processes = $processes
    hashes = @($hashes)
}

$manifestPath = Join-Path $dest "preservation-manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8

$readmePath = Join-Path $dest "README-preservation.md"
@(
    "# ARL Preserved Diagnostic Run",
    "",
    "- Preserved at: $($manifest.preserved_at)",
    "- Source run: $RunPath",
    "- Snapshot path: $dest",
    "- Label: $Label",
    "- Robocopy exit code: $($robocopy.ExitCode)",
    "",
    "## Included Evidence",
    "",
    "- serial.ndjson",
    "- summary.md / suspect.json when present",
    "- protocol-candidates.md / protocol-candidates.json when present",
    "- timeline.csv when present",
    "- dosbox.log and run-metadata.json when present",
    "- preservation-manifest.json",
    "- SHA256SUMS.txt",
    "",
    "Do not delete this folder during normal diagnostic cleanup."
) | Set-Content -Path $readmePath -Encoding UTF8

Write-Output $dest
