<#
.SYNOPSIS
    Static checks for Run-ArlOperatorPreflight.cmd, the preflight launcher the operator desktop
    lays down.

.DESCRIPTION
    After the gate runs, this launcher's text is the operator's only instruction, so it is pinned
    here: Spanish, plain words with no English jargon (PRECHECK/PASSIVE), ASCII-only (cmd.exe prints
    the OEM codepage), and a PASS text that names only launchers the operator desktop actually
    creates. The three names it points to are cross-checked against Set-ArlOperatorDesktop.ps1's
    final rows, so renaming a launcher without fixing this text fails here.

    Until 2026-09 the launcher spoke jargon (PRECHECK NO APROBADO / APROBADO) and pointed at the old
    '04 STANDARDIZATION PASSIVE' / '05 NORMALIZATION PASSIVE' shortcut names. Both are retired.

    Run from anywhere:  pwsh -NoProfile -File contrib/arl/tests/Test-ArlOperatorPreflightCmd.ps1
    Exits non-zero on any failure.
#>
[CmdletBinding()]
param(
    # Directory holding the launcher. Defaults to contrib/arl next to this tests/ folder;
    # pointing it at a mutated copy is how mutants are run.
    [string]$ToolkitDir = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ToolkitDir)) { $ToolkitDir = Split-Path -Parent $PSScriptRoot }
$cmdPath = Join-Path $ToolkitDir 'Run-ArlOperatorPreflight.cmd'
$desktopScript = Join-Path $ToolkitDir 'Set-ArlOperatorDesktop.ps1'
foreach ($path in @($cmdPath, $desktopScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "not found: $path" }
}

$failures = 0
function Assert-True([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name $Detail"; $script:failures++ }
}

$bytes = [IO.File]::ReadAllBytes($cmdPath)
$nonAscii = @($bytes | Where-Object { $_ -gt 0x7F }).Count
Assert-True 'launcher is ASCII-only (cmd.exe prints the OEM codepage)' ($nonAscii -eq 0) "-- $nonAscii non-ASCII byte(s)"
$text = [Text.Encoding]::ASCII.GetString($bytes)
$lines = @($text -split "`r?`n")

Assert-True 'still runs the deployed gate script' ($text.Contains('-File "C:\ARL\tools\Test-ArlPhysicalPreflight.ps1"'))
Assert-True 'names no retired owner (Codex)' ($text -notmatch '(?i)codex')
Assert-True 'speaks no English jargon (PRECHECK/PASSIVE)' ($text -notmatch '(?i)(precheck|passive)')

# The three launcher names the PASS text points to. They must match the operator desktop's final
# rows exactly, so this is the single source of truth for what the operator is told to open.
$expectedNames = @(
    'Analizar colada',
    'Ing. Serrano - Estandarizacion con muestras de ajuste',
    'Ing. Serrano - Normalizacion'
)

# Split the launcher into the FAIL block (inside `if errorlevel 1 ( ... )`) and the PASS tail.
$ifIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq 'if errorlevel 1 (') { $ifIndex = $i; break } }
$closeIndex = -1
if ($ifIndex -ge 0) {
    for ($i = $ifIndex + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq ')') { $closeIndex = $i; break } }
}
Assert-True 'branches on the gate exit code with one FAIL block' ($ifIndex -ge 0 -and $closeIndex -gt $ifIndex)
$failBlock = if ($closeIndex -gt $ifIndex -and $ifIndex -ge 0) { @($lines[($ifIndex + 1)..($closeIndex - 1)]) } else { @() }
$passBlock = if ($closeIndex -ge 0 -and $closeIndex + 1 -lt $lines.Count) { @($lines[($closeIndex + 1)..($lines.Count - 1)]) } else { @() }
$failText = $failBlock -join "`n"
$passText = $passBlock -join "`n"

Assert-True 'FAIL text is the Spanish one' ($failText.Contains('EQUIPO NO LISTO'))
Assert-True 'FAIL branch keeps the window open and exits non-zero' ($failText -match '(?im)^\s*pause\s*$' -and $failText -match '(?im)^\s*exit /b 1\s*$')
Assert-True 'PASS text is the Spanish one' ($passText.Contains('EQUIPO LISTO'))
foreach ($name in $expectedNames) {
    Assert-True "PASS text names '$name'" ($passText.Contains($name))
}

# The PASS text may name only launchers the operator desktop actually creates. All three are final
# rows in Set-ArlOperatorDesktop.ps1 (Name = '...'), so a rename there without fixing this text fails.
$rowNames = @([regex]::Matches([IO.File]::ReadAllText($desktopScript), "Name\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
foreach ($name in $expectedNames) {
    Assert-True "'$name' is a launcher Set-ArlOperatorDesktop.ps1 creates" ($rowNames -contains $name)
}

# cmd.exe ends a parenthesised block at the first ')' -- even inside an echo -- and treats & | < > ^ %
# as syntax, so either one in an echo silently truncates or rewrites the operator's instruction.
$badBlockEcho = @($failBlock | Where-Object { $_ -match '^\s*echo' -and $_ -match '[()]' })
Assert-True 'no echo inside the FAIL block carries a parenthesis' ($badBlockEcho.Count -eq 0) ("-- " + ($badBlockEcho -join ' | '))
$badEcho = @($lines | Where-Object { $_ -match '^\s*echo' -and $_ -match '[&|<>^%]' })
Assert-True 'no echo carries a cmd metacharacter' ($badEcho.Count -eq 0) ("-- " + ($badEcho -join ' | '))

if ($failures -gt 0) { Write-Host "$failures failure(s)"; exit 1 }
Write-Host 'all passed'
