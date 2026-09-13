<#
.SYNOPSIS
    CI gate for the operator desktop suites: runs Test-SetArlOperatorDesktop.ps1 and fails unless every
    engine check (and, with -Depth Mutantes, every engine mutant) really ran and passed.

.DESCRIPTION
    The engine controls of Set-ArlOperatorDesktop.ps1 -SelfTest and the engine mutants only run on Windows
    in an elevated session. Anywhere else the test prints SKIP for them, and a green step would prove
    nothing. This gate turns that into a failure. It refuses to start off Windows or unelevated, streams
    the test output to the log, and then reads it back. It fails when
      - the test exits non-zero;
      - any line is a SKIP or a FAIL;
      - with -Depth Motor, a PASS line is missing for any self-test control under either engine
        (powershell = Windows PowerShell 5.1, pwsh = 7);
      - with -Depth Mutantes, a PASS line is missing for any engine mutant killed by its named control;
      - the final 'all passed' line is missing.
    -Depth Mutantes runs the test with -Mutants -SkipEngine: the workflow's step before it already ran the
    engine self-test under both engines through -Depth Motor, so the mutation step does not repeat it.
    The control list and the engine mutant list are read from the test file itself ($allControls and the
    M-mutant specs), so a new control or mutant there is required here with no second edit. A list shorter
    than the floors in Get-ArlCiGateProblems fails too, so an emptied list cannot pass by saying nothing.
    Test-SetArlOperatorDesktop.ps1 feeds this reader good and broken logs, and plants gate mutants G01-G10
    in a copy of this file; each must be caught by the log case named for it.

    Run by .github/workflows/arl-trace-win64.yml:
      pwsh -NoProfile -File contrib/arl/tests/Invoke-ArlOperatorDesktopCiGate.ps1 -Depth Motor
      pwsh -NoProfile -File contrib/arl/tests/Invoke-ArlOperatorDesktopCiGate.ps1 -Depth Mutantes
    Dot-sourcing it defines the functions and runs nothing; Test-SetArlOperatorDesktop.ps1 does that to
    check the log reader against good and broken logs on any OS.
#>
[CmdletBinding()]
param(
    [ValidateSet('Motor', 'Mutantes')] [string]$Depth = 'Motor',
    # Defaults to Test-SetArlOperatorDesktop.ps1 next to this file.
    [string]$TestPath = ''
)

# Returns one line per problem found in the test run (nothing when its exit code and log prove a full run at
# that depth). Each check is its own statement so a gate mutant can remove exactly one.
function Get-ArlCiGateProblems {
    param([string[]]$Lines, [string]$Depth, [string]$TestText, [int]$ExitCode = 0)
    $minControls = 22
    $minMutants = 24
    $engines = @('powershell', 'pwsh')
    $out = [System.Collections.Generic.List[string]]::new()

    if ($ExitCode -ne 0) { $out.Add('la prueba termino con codigo ' + $ExitCode) }
    $controls = @()
    $cm = [regex]::Match($TestText, '(?s)\$allControls\s*=\s*@\((.*?)\)')
    if ($cm.Success) { $controls = @([regex]::Matches($cm.Groups[1].Value, '''(C\d{2}b?)''') | ForEach-Object { $_.Groups[1].Value }) }
    if ($controls.Count -lt $minControls) { $out.Add('la prueba declara ' + $controls.Count + ' controles; se esperan al menos ' + $minControls) }
    $mutants = @([regex]::Matches($TestText, '@\{ Id = ''(M\d{2})''; Killer = ''(C\d{2}b?)''') | ForEach-Object { @{ Id = $_.Groups[1].Value; Killer = $_.Groups[2].Value } })
    if ($Depth -eq 'Mutantes' -and $mutants.Count -lt $minMutants) { $out.Add('la prueba declara ' + $mutants.Count + ' mutantes de motor; se esperan al menos ' + $minMutants) }

    foreach ($ln in @($Lines)) {
        if ($ln -match '^\s*SKIP\b') { $out.Add('SKIP: ' + $ln.Trim()) }
        if ($ln -match '^\s*FAIL\b') { $out.Add('FAIL: ' + $ln.Trim()) }
    }
    $text = (@($Lines) -join "`n")
    if ($Depth -eq 'Motor') {
        foreach ($engine in $engines) {
            $need = @('autoprueba exit 0', 'status autoprueba-ok') + @($controls | ForEach-Object { 'PASS ' + $_ })
            foreach ($n in $need) {
                $pattern = '(?m)^\s*PASS\s+motor ' + [regex]::Escape($engine) + ': ' + [regex]::Escape($n) + '\s*$'
                if ($text -notmatch $pattern) { $out.Add('falta PASS motor ' + $engine + ': ' + $n) }
            }
        }
    }
    if ($Depth -eq 'Mutantes') {
        foreach ($m in $mutants) {
            $pattern = '(?m)^\s*PASS\s+mutante ' + [regex]::Escape($m.Id) + ' muere por ' + [regex]::Escape($m.Killer) + '\s*$'
            if ($text -notmatch $pattern) { $out.Add('falta PASS mutante ' + $m.Id + ' muere por ' + $m.Killer) }
        }
    }
    if ($text -notmatch '(?m)^all passed\s*$') { $out.Add('falta la linea final all passed') }
    foreach ($p in $out) { $p }
}

function Test-ArlCiOnWindows {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function Write-ArlCiLine([string]$Text) { [Console]::Out.WriteLine($Text) }

# Runs the test at the requested depth and returns the step's exit code.
function Invoke-ArlCiGate([string]$Depth, [string]$TestPath) {
    if (-not $TestPath) { $TestPath = Join-Path $PSScriptRoot 'Test-SetArlOperatorDesktop.ps1' }
    if (-not (Test-ArlCiOnWindows)) {
        Write-ArlCiLine '::error::PUERTA CI: las pruebas de motor solo corren en Windows; este paso falla en vez de saltarlas.'
        return 1
    }
    $principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-ArlCiLine '::error::PUERTA CI: la sesion no esta elevada; las pruebas de motor no pueden correr y este paso falla en vez de saltarlas.'
        return 1
    }
    if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) {
        Write-ArlCiLine ('::error::PUERTA CI: no existe ' + $TestPath)
        return 1
    }
    $exe = Join-Path $PSHOME 'powershell.exe'
    if ($PSVersionTable.PSEdition -eq 'Core') { $exe = Join-Path $PSHOME 'pwsh.exe' }
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $TestPath)
    if ('Mutantes' -eq $Depth) { $argv += @('-Mutants', '-SkipEngine') }

    $lines = [System.Collections.Generic.List[string]]::new()
    & $exe @argv | ForEach-Object { $s = [string]$_; Write-ArlCiLine $s; [void]$lines.Add($s) }
    $code = $LASTEXITCODE
    $problems = @(Get-ArlCiGateProblems -Lines $lines.ToArray() -Depth $Depth -TestText ([System.IO.File]::ReadAllText($TestPath)) -ExitCode $code)
    if ($problems.Count -gt 0) {
        foreach ($p in $problems) { Write-ArlCiLine ('::error::PUERTA CI: ' + $p) }
        Write-ArlCiLine ('PUERTA CI: FALLA, ' + $problems.Count + ' problema(s) en ' + $Depth)
        if ($code -ne 0) { return $code }
        return 1
    }
    Write-ArlCiLine ('PUERTA CI: OK ' + $Depth + ', todas las pruebas de motor corrieron y pasaron')
    return 0
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-ArlCiGate -Depth $Depth -TestPath $TestPath) }
