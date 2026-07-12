param(
    [Parameter(Mandatory = $true)][string]$ReferencePath,
    [Parameter(Mandatory = $true)][string]$CandidatePath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$knownDataFiles = @("WORK.DAT", "QUA.DAT", "MAT.DAT", "MESS.DAT", "INTERFAC.DAT", "0.RES")
$temporaryRoots = New-Object System.Collections.Generic.List[string]

function Expand-SafeZip([string]$Path, [string]$Label) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $destination = Join-Path ([IO.Path]::GetTempPath()) ("arl-impact-{0}-{1}" -f $Label, [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    $destinationPrefix = [IO.Path]::GetFullPath($destination).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Path))
    try {
        foreach ($entry in $archive.Entries) {
            # Compress-Archive on Windows records backslashes. Normalize both separators so a
            # Windows-created backup extracts as directories on macOS/Linux too.
            $relative = $entry.FullName.Replace("\", [IO.Path]::DirectorySeparatorChar).Replace("/", [IO.Path]::DirectorySeparatorChar)
            $target = [IO.Path]::GetFullPath((Join-Path $destination $relative))
            if (-not $target.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "ZIP entry escapes extraction root: $($entry.FullName)"
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                continue
            }
            $parent = Split-Path -Parent $target
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
            $source = $entry.Open()
            $targetStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $source.CopyTo($targetStream) } finally { $targetStream.Dispose(); $source.Dispose() }
        }
    } finally {
        $archive.Dispose()
    }
    $temporaryRoots.Add($destination)
    return $destination
}

function Resolve-InputRoot([string]$Path, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (Test-Path -LiteralPath $resolved -PathType Container) { return $resolved }
    if ([IO.Path]::GetExtension($resolved) -ine ".zip") { throw "$Label must be a directory or ZIP file: $Path" }
    return Expand-SafeZip $resolved $Label
}

function Find-ImpactRoot([string]$Root) {
    $candidates = @((Get-Item -LiteralPath $Root)) + @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction Stop)
    $ranked = foreach ($directory in $candidates) {
        $names = @(Get-ChildItem -LiteralPath $directory.FullName -File -ErrorAction SilentlyContinue | ForEach-Object Name)
        $score = 0
        if ($names -contains "AL.CAL") { $score += 8 }
        if ($names -contains "WORK.DAT") { $score += 4 }
        foreach ($name in @("QUA.DAT", "MAT.DAT", "MESS.DAT")) { if ($names -contains $name) { $score++ } }
        if (@($names | Where-Object { $_ -match '^(IMPACT|IMPLUS).*\.EXE$' }).Count -gt 0) { $score += 4 }
        if ($score -gt 0) {
            [pscustomobject]@{ path = $directory.FullName; score = $score; depth = $directory.FullName.Split([IO.Path]::DirectorySeparatorChar).Count }
        }
    }
    $best = $ranked | Sort-Object @{ Expression = "score"; Descending = $true }, @{ Expression = "depth"; Descending = $false }, path | Select-Object -First 1
    if ($null -eq $best -or $best.score -lt 8) { throw "Could not identify an active IMPACT directory below $Root" }
    return $best.path
}

function Get-ImpactInventory([string]$Root) {
    $inventory = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -File | Where-Object { $_.Extension -in @(".CAL", ".REG") -or $_.Name -in $knownDataFiles }) {
        $inventory[$file.Name.ToUpperInvariant()] = [pscustomobject]@{
            name = $file.Name
            path = $file.FullName
            length = $file.Length
            last_write_time_utc = $file.LastWriteTimeUtc.ToString("o")
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $inventory
}

function Get-ByteDifference([string]$ReferenceFile, [string]$CandidateFile) {
    [byte[]]$left = [IO.File]::ReadAllBytes($ReferenceFile)
    [byte[]]$right = [IO.File]::ReadAllBytes($CandidateFile)
    $limit = [Math]::Min($left.Length, $right.Length)
    $first = $null
    $different = [Math]::Abs($left.Length - $right.Length)
    for ($index = 0; $index -lt $limit; $index++) {
        if ($left[$index] -ne $right[$index]) {
            if ($null -eq $first) { $first = $index }
            $different++
        }
    }
    if ($null -eq $first -and $left.Length -ne $right.Length) { $first = $limit }
    return [pscustomobject]@{ first_different_offset = $first; different_byte_count = $different }
}

try {
    $referenceInput = Resolve-InputRoot $ReferencePath "reference"
    $candidateInput = Resolve-InputRoot $CandidatePath "candidate"
    $referenceRoot = Find-ImpactRoot $referenceInput
    $candidateRoot = Find-ImpactRoot $candidateInput
    $reference = Get-ImpactInventory $referenceRoot
    $candidate = Get-ImpactInventory $candidateRoot
    $names = @($reference.Keys + $candidate.Keys | Sort-Object -Unique)
    $changes = foreach ($key in $names) {
        $old = $reference[$key]
        $new = $candidate[$key]
        $change = if ($null -eq $old) { "created" } elseif ($null -eq $new) { "deleted" } elseif ($old.sha256 -eq $new.sha256) { "unchanged" } else { "modified" }
        $difference = if ($change -eq "modified") { Get-ByteDifference $old.path $new.path } else { $null }
        [pscustomobject]@{
            name = if ($null -ne $new) { $new.name } else { $old.name }
            change = $change
            reference_length = $old.length
            candidate_length = $new.length
            reference_sha256 = $old.sha256
            candidate_sha256 = $new.sha256
            first_different_offset = $difference.first_different_offset
            different_byte_count = $difference.different_byte_count
        }
    }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $result = [ordered]@{
        compared_at_utc = [datetimeoffset]::UtcNow.ToString("o")
        reference_input = (Resolve-Path -LiteralPath $ReferencePath).Path
        candidate_input = (Resolve-Path -LiteralPath $CandidatePath).Path
        reference_impact_root = $referenceRoot
        candidate_impact_root = $candidateRoot
        summary = [ordered]@{
            created = @($changes | Where-Object change -eq "created").Count
            deleted = @($changes | Where-Object change -eq "deleted").Count
            modified = @($changes | Where-Object change -eq "modified").Count
            unchanged = @($changes | Where-Object change -eq "unchanged").Count
        }
        changes = @($changes)
    }
    $jsonPath = Join-Path $OutputDirectory "impact-backup-comparison.json"
    [IO.File]::WriteAllText($jsonPath, ($result | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))

    $lines = @(
        "# IMPACT backup comparison",
        "",
        "Reference root: ``$referenceRoot``",
        "Candidate root: ``$candidateRoot``",
        "",
        "Created: $($result.summary.created); deleted: $($result.summary.deleted); modified: $($result.summary.modified); unchanged: $($result.summary.unchanged)",
        "",
        "| File | Change | Reference SHA-256 | Candidate SHA-256 | First offset | Different bytes |",
        "|---|---:|---|---|---:|---:|"
    )
    foreach ($item in $changes | Where-Object change -ne "unchanged") {
        $lines += "| $($item.name) | $($item.change) | $($item.reference_sha256) | $($item.candidate_sha256) | $($item.first_different_offset) | $($item.different_byte_count) |"
    }
    $markdownPath = Join-Path $OutputDirectory "impact-backup-comparison.md"
    [IO.File]::WriteAllText($markdownPath, ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Comparison written to $jsonPath and $markdownPath"
    $result.summary | ConvertTo-Json -Compress
} finally {
    foreach ($temporary in $temporaryRoots) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
}
