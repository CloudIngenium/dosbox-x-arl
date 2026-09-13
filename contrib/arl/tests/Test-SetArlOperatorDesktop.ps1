<#
.SYNOPSIS
    Static + engine + mutation checks for Set-ArlOperatorDesktop.ps1 and its guide card.

.DESCRIPTION
    Set-ArlOperatorDesktop.ps1 is the tool that reshapes the ARL 3460 desktops so a floor
    technician can tell at a glance which launcher is theirs. The launcher a user opens decides
    the run-id prefix of the burn (normalization- / standardization- / sample-analysis-), so the
    icon set, the names, the move map, the manifest/undo contract and the ACLs all have to be
    exactly right. This test pins them at three depths:

      1. Static (any engine, no Windows APIs): the script is ASCII with no BOM, the operator-facing
         names carry none of the old cleanup jargon, the card is a valid offline Spanish page whose
         icon references match the icon set, and every filesystem/ACL mutation lives inside the one
         Invoke-ArlAction chokepoint. These run everywhere, including on the CI runner off Windows.

      2. Engine (Windows + elevated): the script's own -SelfTest is run under each available engine
         (powershell.exe = Windows PowerShell 5.1, pwsh = 7). It must exit 0, report autoprueba-ok,
         and print a PASS line for each of the 21 controls C01-C20 + C04b.

      3. Mutation (-Mutants, Windows + elevated): each of the 22 seeded mutants is applied to a
         private copy of the script and its self-test is run under Windows PowerShell 5.1; each must
         be caught (exit 1 with a FAIL line for the control that owns it).

    Run from anywhere:
      pwsh -NoProfile -File contrib/arl/tests/Test-SetArlOperatorDesktop.ps1
      pwsh -NoProfile -File contrib/arl/tests/Test-SetArlOperatorDesktop.ps1 -Mutants
    Exits non-zero on any failure. Off Windows the engine and mutant depths SKIP, and only turn into
    a failure when $env:CI is set (a CI runner that reached them on the wrong OS is a wiring bug).
#>
[CmdletBinding()]
param(
    # Directory holding Set-ArlOperatorDesktop.ps1. Defaults to contrib/arl next to this tests/ folder.
    [string]$ToolkitDir = '',
    # Also run the mutation suite (Windows + elevated only).
    [switch]$Mutants
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ToolkitDir)) { $ToolkitDir = Split-Path -Parent $PSScriptRoot }
$scriptPath = Join-Path $ToolkitDir 'Set-ArlOperatorDesktop.ps1'
$cardPath = Join-Path $ToolkitDir 'operator-desktop\cual-uso.html'

$failures = 0
function Assert-True([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name $Detail"; $script:failures++ }
}

function Test-OnWindows {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}
function Test-Elevated {
    if (-not (Test-OnWindows)) { return $false }
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
$inCI = -not [string]::IsNullOrEmpty($env:CI)

# The 21 controls the self-test prints a PASS line for on a healthy tree (C04b is distinct from C04).
$allControls = @('C01', 'C02', 'C03', 'C04', 'C04b', 'C05', 'C06', 'C07', 'C08', 'C09',
    'C10', 'C11', 'C12', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'C19', 'C20')

# The seeded mutants. Find must occur exactly once in the script; Replace is spliced in with LF
# newlines; Killer is the control whose FAIL line must appear when the mutant's self-test runs.
$mutantSpecs = @(
    @{ Id = 'M01'; Killer = 'C05'; Find = '$missing.Count -gt 0'; Replace = '$false' }
    @{ Id = 'M02'; Killer = 'C08'; Find = 'function Resolve-ArlCollision([string]$Desired, [string]$Stamp) {'; Replace = ('function Resolve-ArlCollision([string]$Desired, [string]$Stamp) {' + "`n" + '    return $Desired') }
    @{ Id = 'M03'; Killer = 'C16'; Find = 'Write-ArlManifest -P $P -Manifest $manifest -Path $manifestPath -Initial'; Replace = '$null = $null' }
    @{ Id = 'M04'; Killer = 'C10'; Find = 'Reset-ArlChildAcl -P $P -Parent $dir -Leaf $leaf | Out-Null'; Replace = 'Reset-ArlChildAcl -P $P -Parent $dir -Leaf $leaf | Out-Null; Reset-ArlChildAcl -P $P -Parent $P.ArlRoot -Leaf ''Herramientas-Admin'' | Out-Null' }
    @{ Id = 'M05'; Killer = 'C09'; Find = '$inv = @{ Public = @(); Piso = @(); Others = @(); Pins = @(); Accesos = @() }'; Replace = ('$inv = @{ Public = @(); Piso = @(); Others = @(); Pins = @(); Accesos = @() }' + "`n" + '    Get-Process -Name dosbox-x-arl -ErrorAction SilentlyContinue | Out-Null') }
    @{ Id = 'M06'; Killer = 'C07'; Find = 'if ($P.LegacyDailyTargets -contains $Target) { return @{ Group = ''Accesos-anteriores''; Tag = '''' } }'; Replace = '' }
    @{ Id = 'M07'; Killer = 'C11'; Find = 'function Test-ArlReparseChain([string]$Path) {'; Replace = ('function Test-ArlReparseChain([string]$Path) {' + "`n" + '    return $false') }
    @{ Id = 'M08'; Killer = 'C12'; Find = 'if (-not (Test-ArlUnderAny -Path $candidate -Roots $trustRoots)) {'; Replace = 'if ($false) {' }
    @{ Id = 'M09'; Killer = 'C14'; Find = 'Name = ''Analizar colada'''; Replace = 'Name = ''ARL Analizar colada''' }
    @{ Id = 'M10'; Killer = 'C01'; Find = 'if (-not $PSCmdlet.ShouldProcess($Path, $Op)) { return $false }'; Replace = '' }
    @{ Id = 'M11'; Killer = 'C06'; Find = '(New-ArlClass ''desconocido'' '''' $note)'; Replace = '(New-ArlClass ''mover'' ''Diagnostico'' $note)' }
    @{ Id = 'M12'; Killer = 'C03'; Find = 'Test-ArlFieldsEqual -Actual $existing.Lnk -Expected $exp'; Replace = '$false' }
    @{ Id = 'M13'; Killer = 'C04'; Find = 'Restore-ArlSourceAcl -P $P -Path $a.source -OwnerSid $a.source_owner_sid -SourceSddl $a.source_sddl | Out-Null'; Replace = '' }
    @{ Id = 'M14'; Killer = 'C18'; Find = 'Invoke-ArlAction -P $P -Op ''move-file'' -Path $Path -Destination $Backup'; Replace = 'Invoke-ArlAction -P $P -Op ''delete-file'' -Path $Path' }
    @{ Id = 'M15'; Killer = 'C17'; Find = 'if (Test-Path -LiteralPath $P.OperatorDesktop -PathType Container) {'; Replace = 'if ($false) {' }
    @{ Id = 'M16'; Killer = 'C19'; Find = 'function Assert-ArlPathParameters([hashtable]$Bound) {'; Replace = ('function Assert-ArlPathParameters([hashtable]$Bound) {' + "`n" + '    return') }
    @{ Id = 'M17'; Killer = 'C12'; Find = 'if ((Get-ArlWriters $node).Count -gt 0) {'; Replace = 'if ($false) {' }
    @{ Id = 'M18'; Killer = 'C10'; Find = '(A;OICI;FA;;;BA)'''; Replace = '(A;OICI;FA;;;BU)''' }
    @{ Id = 'M19'; Killer = 'C04b'; Find = 'if (-not (Test-ArlLnkMatchesAction -Path $created -Action $a)) { Set-ArlUndoSkipped -Action $a -Reason ''modificado despues de aplicar''; return }'; Replace = '' }
    @{ Id = 'M20'; Killer = 'C15'; Find = 'Png = ''serrano.png''; Source = $P.ShellDll; Index = 314'; Replace = 'Png = ''ingeniero.png''; Source = $P.ShellDll; Index = 314' }
    @{ Id = 'M21'; Killer = 'C20'; Find = '$script:ArlReversibleStates = @(''applying'', ''applied'', ''failed-partial'', ''undoing'', ''undone-partial'')'; Replace = '$script:ArlReversibleStates = @(''applied'', ''failed-partial'', ''undone-partial'')' }
    @{ Id = 'M22'; Killer = 'C20'; Find = 'return (Test-ArlFieldsEqual -Actual (Read-ArlShortcut $Path) -Expected $want)'; Replace = 'return $false' }
)

# ---- depth 1: files exist + parse + one occurrence of every mutant find -------------------------
Assert-True 'el script Set-ArlOperatorDesktop.ps1 existe' (Test-Path -LiteralPath $scriptPath -PathType Leaf) "-- $scriptPath"
Assert-True 'la tarjeta operator-desktop\cual-uso.html existe' (Test-Path -LiteralPath $cardPath -PathType Leaf) "-- $cardPath"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { Write-Host "$failures failure(s)"; exit 1 }

$scriptText = [System.IO.File]::ReadAllText($scriptPath)
try {
    [void][scriptblock]::Create($scriptText)
    Assert-True 'el script compila (scriptblock)' $true
} catch {
    Assert-True 'el script compila (scriptblock)' $false ("-- " + $_.Exception.Message)
}

foreach ($m in $mutantSpecs) {
    $idx = $scriptText.IndexOf($m.Find, [System.StringComparison]::Ordinal)
    $last = $scriptText.LastIndexOf($m.Find, [System.StringComparison]::Ordinal)
    Assert-True "mutante $($m.Id): el patron aparece exactamente una vez" ($idx -ge 0 -and $idx -eq $last) "idx=$idx last=$last"
}

# ---- depth 1b: static controls via the script's own source-level checks -------------------------
. $scriptPath   # dot-source: defines the functions and (per the guard) runs nothing; sets StrictMode Latest here on
$script:ArlStResults = New-Object System.Collections.Generic.List[object]
Invoke-ArlStStatic
$staticIds = @('C13', 'C14', 'C15', 'C09')
foreach ($id in $staticIds) {
    $r = @($script:ArlStResults | Where-Object { $_.Id -eq $id })
    if ($r.Count -eq 0) { Assert-True "estatico $id" $false 'no se ejecuto'; continue }
    $bad = @($r | Where-Object { -not $_.Pass })
    $ok = $bad.Count -eq 0
    $detail = if ($ok) { '' } else { '-- ' + (($bad | ForEach-Object { $_.Detail }) -join ' | ') }
    Assert-True "estatico $id  $($r[0].Name)" $ok $detail
}

# ---- depth 1c: card mutants (any OS) ------------------------------------------------------------
# Each one plants a wording or layout defect in a private copy of the card; C15 must reject it. These
# need no Windows APIs, so they run on every engine and on the CI runner off Windows too.
$cardMutantSpecs = @(
    @{ Id = 'K01'; Find = 'repita la quema. Si vuelve'; Replace = 'no repita la quema. Si vuelve' }
    @{ Id = 'K02'; Find = 'Sali&oacute; la hoja <span class="marca">ARL 3460 - AVISO: SIN CHISPA</span>'; Replace = 'Hoja <span class="marca">SIN CHISPA</span>' }
    @{ Id = 'K03'; Find = 'arg&oacute;n y soporte.</li>'; Replace = 'arg&oacute;n y la mesa de chispa (stand).</li>' }
    @{ Id = 'K04'; Find = 'Los iconos <span class="nombre">Ing. Serrano</span> no son'; Replace = 'Los iconos <span class="nombre">Ing. Serrano - Normalizacion</span> no son' }
    @{ Id = 'K05'; Find = 'body { font-size: 14pt; }'; Replace = 'body { font-size: 12.5pt; }' }
    @{ Id = 'K06'; Find = 'No abra IMPACT de otra forma'; Replace = 'No abra IMPACT ni DOSBox-X de otra forma' }
    @{ Id = 'K07'; Find = '<section class="hoja pagina serrano">'; Replace = '<section class="hoja serrano">' }
    @{ Id = 'K08'; Find = 'No hubo chispa suficiente. Esa hoja'; Replace = 'Solo hubo ruido. Esa hoja' }
)
if (Test-Path -LiteralPath $cardPath -PathType Leaf) {
    $cardText = [System.IO.File]::ReadAllText($cardPath)
    $cardDir = Join-Path ([System.IO.Path]::GetTempPath()) ('arl-desktop-card-mutants-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $cardDir -Force | Out-Null
    try {
        foreach ($k in $cardMutantSpecs) {
            $idx = $cardText.IndexOf($k.Find, [System.StringComparison]::Ordinal)
            $last = $cardText.LastIndexOf($k.Find, [System.StringComparison]::Ordinal)
            if ($idx -lt 0 -or $idx -ne $last) { Assert-True "mutante de tarjeta $($k.Id): patron unico" $false "idx=$idx last=$last"; continue }
            $mutCard = Join-Path $cardDir ($k.Id + '.html')
            [System.IO.File]::WriteAllText($mutCard, ($cardText.Substring(0, $idx) + $k.Replace + $cardText.Substring($idx + $k.Find.Length)), (New-Object System.Text.UTF8Encoding($false)))
            $script:ArlStResults = New-Object System.Collections.Generic.List[object]
            $consoleOut = [Console]::Out
            [Console]::SetOut([System.IO.TextWriter]::Null)   # the expected FAIL line of the planted defect is noise here
            try { Invoke-ArlStCardStatic -CardPath $mutCard | Out-Null } finally { [Console]::SetOut($consoleOut) }
            $c15 = @($script:ArlStResults | Where-Object { $_.Id -eq 'C15' })
            Assert-True "mutante de tarjeta $($k.Id) muere por C15" (($c15.Count -eq 1) -and (-not $c15[0].Pass)) ($(if ($c15.Count -eq 1) { '-- ' + $c15[0].Detail } else { '-- C15 no se ejecuto' }))
        }
    } finally {
        Remove-Item -LiteralPath $cardDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- depth 2: run the script's own -SelfTest under each engine (Windows + elevated) -------------
if (-not (Test-OnWindows)) {
    Write-Host '  SKIP  autoprueba por motor (requiere Windows)'
    if ($inCI) { Assert-True 'CI no debe alcanzar la autoprueba por motor fuera de Windows' $false }
} elseif (-not (Test-Elevated)) {
    if ($inCI) { Assert-True 'la autoprueba por motor corre elevada en CI' $false '-- se requiere elevacion' }
    else { Write-Host '  SKIP  autoprueba por motor (requiere elevacion)' }
} else {
    $ErrorActionPreference = 'Continue'
    $engines = @()
    foreach ($name in @('powershell', 'pwsh')) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $engines += , @{ Name = $name; Path = $cmd.Source } }
    }
    if ($engines.Count -eq 0) { Assert-True 'hay al menos un motor de PowerShell' $false }
    foreach ($e in $engines) {
        $out = & $e.Path -NoProfile -ExecutionPolicy Bypass -File $scriptPath -SelfTest 2>&1
        $code = $LASTEXITCODE
        $outText = ($out | Out-String)
        Assert-True "motor $($e.Name): autoprueba exit 0" ($code -eq 0) "-- exit=$code"
        Assert-True "motor $($e.Name): status autoprueba-ok" ($outText -match 'autoprueba-ok')
        foreach ($id in $allControls) {
            $hit = $outText -match ('(?m)^\s*PASS\s+' + [regex]::Escape($id) + '\b')
            Assert-True "motor $($e.Name): PASS $id" $hit
        }
    }
    $ErrorActionPreference = 'Stop'
}

# ---- depth 3: mutation suite (-Mutants, Windows + elevated; each mutant dies under 5.1) ----------
if ($Mutants) {
    if (-not (Test-OnWindows)) {
        Write-Host '  SKIP  mutantes (requiere Windows)'
        if ($inCI) { Assert-True 'CI no debe alcanzar los mutantes fuera de Windows' $false }
    } elseif (-not (Test-Elevated)) {
        if ($inCI) { Assert-True 'los mutantes corren elevados en CI' $false '-- se requiere elevacion' }
        else { Write-Host '  SKIP  mutantes (requiere elevacion)' }
    } else {
        $ps51 = Get-Command 'powershell' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $ps51) { Assert-True 'powershell.exe (5.1) disponible para mutantes' $false }
        else {
            $ErrorActionPreference = 'Continue'
            foreach ($m in $mutantSpecs) {
                $idx = $scriptText.IndexOf($m.Find, [System.StringComparison]::Ordinal)
                $last = $scriptText.LastIndexOf($m.Find, [System.StringComparison]::Ordinal)
                if ($idx -lt 0 -or $idx -ne $last) { Assert-True "mutante $($m.Id): patron unico" $false "idx=$idx last=$last"; continue }
                $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('arl-desktop-mutant-' + $m.Id)
                if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $copy = Join-Path $dir 'Set-ArlOperatorDesktop.ps1'
                $mutText = $scriptText.Substring(0, $idx) + $m.Replace + $scriptText.Substring($idx + $m.Find.Length)
                [System.IO.File]::WriteAllText($copy, $mutText, (New-Object System.Text.UTF8Encoding($false)))
                Copy-Item -LiteralPath (Join-Path $ToolkitDir 'operator-desktop') -Destination (Join-Path $dir 'operator-desktop') -Recurse -Force
                $out = & $ps51.Source -NoProfile -ExecutionPolicy Bypass -File $copy -SelfTest 2>&1
                $code = $LASTEXITCODE
                $outText = ($out | Out-String)
                $killed = ($code -eq 1) -and ($outText -match ('(?m)^FAIL\s+' + [regex]::Escape($m.Killer) + '\b'))
                Assert-True "mutante $($m.Id) muere por $($m.Killer)" $killed "-- exit=$code"
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
            $ErrorActionPreference = 'Stop'
        }
    }
}

if ($failures -gt 0) { Write-Host "$failures failure(s)"; exit 1 }
Write-Host 'all passed'
