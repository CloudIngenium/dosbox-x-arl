<#
.SYNOPSIS
    Static checks for Run-ArlOperatorPreflight.cmd, the '01 PRECHECK' desktop launcher.

.DESCRIPTION
    After the gate runs, this launcher's text is the operator's only instruction, so it is pinned
    here: Spanish, ASCII-only (cmd.exe prints the OEM codepage), no retired owner named, and a PASS
    text that names only shortcuts that exist. Until 2026-09-11 it told operators to run
    '02 REACTIVE SAFE' -- a shortcut Chispa's Install-ArlOperatorExperience.ps1 removes from the
    desktop -- and to send failures to Codex, whose ownership was retired on 2026-07-14.

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
$shortcutsPath = Join-Path $ToolkitDir 'Create-ArlHpShortcuts.ps1'
foreach ($path in @($cmdPath, $shortcutsPath)) {
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
Assert-True 'does not send operators to 02 REACTIVE SAFE' ($text -notmatch '(?i)02 REACTIVE')

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

Assert-True 'FAIL text is the Spanish one' ($failText.Contains('PRECHECK NO APROBADO'))
Assert-True 'FAIL branch keeps the window open and exits non-zero' ($failText -match '(?im)^\s*pause\s*$' -and $failText -match '(?im)^\s*exit /b 1\s*$')
Assert-True 'PASS text is the Spanish one' ($passText.Contains('PRECHECK APROBADO'))
foreach ($shortcut in @('05 NORMALIZATION PASSIVE', '04 STANDARDIZATION PASSIVE', 'ARL 3460 - Analizar')) {
    Assert-True "PASS text names '$shortcut'" ($passText.Contains($shortcut))
}

# The PASS text may name only shortcuts that exist. '04'/'05' are installed by
# Create-ArlHpShortcuts.ps1 in this repo; 'ARL 3460 - Analizar' is installed by Chispa's
# deploy/Install-ArlOperatorExperience.ps1 and cannot be cross-checked from here.
$shortcutNames = @([regex]::Matches([IO.File]::ReadAllText($shortcutsPath), 'Name\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
foreach ($shortcut in @('04 STANDARDIZATION PASSIVE', '05 NORMALIZATION PASSIVE')) {
    Assert-True "'$shortcut' is a shortcut Create-ArlHpShortcuts.ps1 installs" ($shortcutNames -contains $shortcut)
}

# cmd.exe ends a parenthesised block at the first ')' -- even inside an echo -- and treats & | < > ^ %
# as syntax, so either one in an echo silently truncates or rewrites the operator's instruction.
$badBlockEcho = @($failBlock | Where-Object { $_ -match '^\s*echo' -and $_ -match '[()]' })
Assert-True 'no echo inside the FAIL block carries a parenthesis' ($badBlockEcho.Count -eq 0) ("-- " + ($badBlockEcho -join ' | '))
$badEcho = @($lines | Where-Object { $_ -match '^\s*echo' -and $_ -match '[&|<>^%]' })
Assert-True 'no echo carries a cmd metacharacter' ($badEcho.Count -eq 0) ("-- " + ($badEcho -join ' | '))

if ($failures -gt 0) { Write-Host "$failures failure(s)"; exit 1 }
Write-Host 'all passed'
