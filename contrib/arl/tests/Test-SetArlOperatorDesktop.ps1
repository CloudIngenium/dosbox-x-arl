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
         Invoke-ArlAction chokepoint. These need no Windows API, so they also run on a developer
         machine off Windows (CI itself runs only on windows-latest). So do the card mutants K01-K19
         (C15 must reject each; K09-K19 weaken Ing. Serrano's spark check, each caught by a named C15
         rule) and the planner checks: the planner's own functions, called on
         in-memory items and a temp folder, must give three distinct names to three same-name items,
         send a launcher planned twice in one run to duplicados once, route an Emulator/Bridge target
         (directly or through cmd.exe / powershell.exe) to Simuladores, leave a folder in place when it
         holds an item that stays, and send every shortcut Chispa's installers put back (00 DIRECTSERIAL
         BYPASS ... ARL 3460 - Analizar) to its admin group. Planner mutants P01-P06 plant the defects
         the reviewers found; each must fail its named check. The CI gate's log reader
         (Invoke-ArlOperatorDesktopCiGate.ps1) is checked here too, against good and broken runs, and
         gate mutants G01-G10 each remove one of its checks; the case named for each must fail.

      2. Engine (Windows + elevated): the script's own -SelfTest is run under each available engine
         (powershell.exe = Windows PowerShell 5.1, pwsh = 7). It must exit 0, report autoprueba-ok,
         and print a PASS line for each of the 22 controls C01-C21 + C04b.

      3. Mutation (-Mutants, Windows + elevated): each of the 25 seeded mutants is applied to a
         private copy of the script and its self-test is run under Windows PowerShell 5.1 with
         -Controls set to the control that owns it; each must be caught (exit 1 with a FAIL line for
         that control), so a mutant counts as killed only by the control named for it. M25 drops the
         owner Administradores from the folders the script creates: C10 catches it on an elevated
         runner too, because the self-test applies with a default owner that is not Administrators.

    Run from anywhere:
      pwsh -NoProfile -File contrib/arl/tests/Test-SetArlOperatorDesktop.ps1
      pwsh -NoProfile -File contrib/arl/tests/Test-SetArlOperatorDesktop.ps1 -Mutants
      pwsh -NoProfile -File contrib/arl/tests/Test-SetArlOperatorDesktop.ps1 -Mutants -SkipEngine
    -SkipEngine leaves out depth 2 (CI's mutation step, after the engine step already ran it).
    Exits non-zero on any failure. Off Windows, or unelevated, the engine and mutant depths print SKIP
    and do not fail on their own (a developer laptop); with $env:CI set they fail. CI does not rely on
    that: it runs this file through Invoke-ArlOperatorDesktopCiGate.ps1, which fails the step on any SKIP
    and on any engine control or mutant without its PASS line.
#>
[CmdletBinding()]
param(
    # Directory holding Set-ArlOperatorDesktop.ps1. Defaults to contrib/arl next to this tests/ folder.
    [string]$ToolkitDir = '',
    # Also run the mutation suite (Windows + elevated only).
    [switch]$Mutants,
    # Do not run the engine self-test (depth 2). CI's mutation step passes it: the step before already ran
    # the engine self-test under both engines, and every mutant still runs its own filtered self-test.
    [switch]$SkipEngine
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

# The 22 controls the self-test prints a PASS line for on a healthy tree (C04b is distinct from C04).
# Invoke-ArlOperatorDesktopCiGate.ps1 reads this list from this file, so keep it a single @(...) literal.
$allControls = @('C01', 'C02', 'C03', 'C04', 'C04b', 'C05', 'C06', 'C07', 'C08', 'C09',
    'C10', 'C11', 'C12', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'C19', 'C20', 'C21')

# The seeded mutants. Find must occur exactly once in the script; Replace is spliced in with LF
# newlines; Killer is the control whose FAIL line must appear when the mutant's self-test runs with
# -Controls <Killer>. The CI gate reads the Id/Killer pairs from these lines, so keep their shape.
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
    @{ Id = 'M17'; Killer = 'C12'; Find = 'if (@(Get-ArlWriters $node).Count -gt 0) {'; Replace = 'if ($false) {' }
    @{ Id = 'M18'; Killer = 'C10'; Find = '(A;OICI;FA;;;BA)'''; Replace = '(A;OICI;FA;;;BU)''' }
    @{ Id = 'M19'; Killer = 'C04b'; Find = 'if (-not (Test-ArlLnkMatchesAction -Path $created -Action $a)) { Set-ArlUndoSkipped -Action $a -Reason ''modificado despues de aplicar''; return }'; Replace = '' }
    @{ Id = 'M20'; Killer = 'C15'; Find = 'Png = ''serrano.png''; Source = $P.ShellDll; Index = 314'; Replace = 'Png = ''ingeniero.png''; Source = $P.ShellDll; Index = 314' }
    @{ Id = 'M21'; Killer = 'C20'; Find = '$script:ArlReversibleStates = @(''applying'', ''applied'', ''failed-partial'', ''undoing'', ''undone-partial'')'; Replace = '$script:ArlReversibleStates = @(''applied'', ''failed-partial'', ''undone-partial'')' }
    @{ Id = 'M22'; Killer = 'C20'; Find = 'return (Test-ArlFieldsEqual -Actual (Read-ArlShortcut $Path) -Expected $want)'; Replace = 'return $false' }
    @{ Id = 'M23'; Killer = 'C21'; Find = 'if (Test-ArlUnder -Path $Target -Root $P.ArlRoot) {'; Replace = 'if ($false) {' }
    @{ Id = 'M24'; Killer = 'C12'; Find = 'return @($out | Sort-Object -Property { [string]$_.Ts })'; Replace = 'return @($out | Sort-Object -Property { [string]$_.Ts } -Descending)' }
    @{ Id = 'M25'; Killer = 'C10'; Find = 'foreach ($od in $newDirs) {'; Replace = 'foreach ($od in @()) {' }
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
$script:ArlStResults = [System.Collections.Generic.List[object]]::new()
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
# need no Windows APIs, so they run on every engine, on Windows in CI and on a developer machine alike.
# K09-K19 target Ing. Serrano's spark check on page two. K09 puts back the old check (burn a sample in the
# daily icon, which prints a colada sheet that reaches the portal); K10 drops the stop before accepting
# factors; K11 drops the prohibition; K12 rewords it into a test burn in Analizar colada; K13 drops the stop
# on a SIN CHISPA sheet; K14 puts back the 1 kp floor (Chispa's is 10 kp); K15 limits the screen check to
# days with no colada; K16 appends a sentence that accepts anyway; K17 adds a test burn in Analizar colada
# outside the spark box; K18 puts a B row above the spark box; K19 adds a second, weaker spark box. Rule,
# when given, names the C15 flag that must read False for that mutant, so each rule is shown to catch a
# defect on its own.
$cardMutantSpecs = @(
    @{ Id = 'K01'; Find = 'repita la quema. Si vuelve'; Replace = 'no repita la quema. Si vuelve' }
    @{ Id = 'K02'; Find = 'Sali&oacute; la hoja <span class="marca">ARL 3460 - AVISO: SIN CHISPA</span>'; Replace = 'Hoja <span class="marca">SIN CHISPA</span>' }
    @{ Id = 'K03'; Find = 'arg&oacute;n y soporte.</li>'; Replace = 'arg&oacute;n y la mesa de chispa (stand).</li>' }
    @{ Id = 'K04'; Find = 'Los iconos <span class="nombre">Ing. Serrano</span> no son'; Replace = 'Los iconos <span class="nombre">Ing. Serrano - Normalizacion</span> no son' }
    @{ Id = 'K05'; Find = 'body { font-size: 14pt; }'; Replace = 'body { font-size: 12.5pt; }' }
    @{ Id = 'K06'; Find = 'No abra IMPACT de otra forma'; Replace = 'No abra IMPACT ni DOSBox-X de otra forma' }
    @{ Id = 'K07'; Find = '<section class="hoja pagina serrano">'; Replace = '<section class="hoja serrano">' }
    @{ Id = 'K08'; Find = 'No hubo chispa suficiente. Esa hoja'; Replace = 'Solo hubo ruido. Esa hoja' }
    @{ Id = 'K09'; Rule = 'sin-quema-de-prueba'; Find = '<h2>Antes de aceptar: revise que haya chispa</h2>'; Replace = ('<h2>Antes de aceptar: revise que haya chispa</h2>' + "`n" + '    <p>Queme una muestra en <img class="icono-linea" src="iconos/analizar-colada.png" alt=""> <span class="nombre">Analizar colada</span> y confirme que sali&oacute; <strong>ARL 3460 - REPORTE DE ANALISIS</strong> con n&uacute;meros. Luego cierre IMPACT.</p>') }
    @{ Id = 'K10'; Rule = 'revision-chispa'; Find = 'Si el canal m&aacute;s alto queda por debajo de 10 kp (el mismo l&iacute;mite que imprime la hoja SIN CHISPA) o no se puede leer: pare, no acepte los factores y siga el punto SIN CHISPA de abajo.'; Replace = 'Luego acepte en IMPACT como siempre.' }
    @{ Id = 'K11'; Rule = 'revision-chispa'; Find = '<p>No use <span class="nombre">Analizar colada</span> para probar la chispa: esa hoja se env&iacute;a al portal.</p>'; Replace = '' }
    @{ Id = 'K12'; Rule = 'hoja2-sin-prueba-diaria'; Find = '<p>No use <span class="nombre">Analizar colada</span> para probar la chispa: esa hoja se env&iacute;a al portal.</p>'; Replace = '<p>Haga una quema de prueba con el icono <span class="nombre">Analizar colada</span>.</p>' }
    @{ Id = 'K13'; Rule = 'revision-chispa'; Find = 'es <strong>AVISO: SIN CHISPA</strong>, no empiece y avise a Calidad. Si es '; Replace = 'es ' }
    @{ Id = 'K14'; Rule = 'revision-chispa'; Find = 'por debajo de 10 kp'; Replace = 'por debajo de 1 kp' }
    @{ Id = 'K15'; Rule = 'revision-chispa'; Find = 'Siempre, en su primera quema de B o C'; Replace = 'Si hoy no hubo coladas, en su primera quema de B o C' }
    @{ Id = 'K16'; Rule = 'revision-chispa'; Find = 'siga el punto SIN CHISPA de abajo.'; Replace = 'siga el punto SIN CHISPA de abajo. Si la siguiente quema sale bien, acepte los de la siguiente.' }
    @{ Id = 'K17'; Rule = 'hoja2-sin-prueba-diaria'; Find = '<li><strong>Con B o C sale REPORTE DE ANALISIS:</strong>'; Replace = ('<li>Si duda de la chispa, pruebe con una muestra en <span class="nombre">Analizar colada</span>.</li>' + "`n" + '      <li><strong>Con B o C sale REPORTE DE ANALISIS:</strong>') }
    @{ Id = 'K18'; Rule = 'revision-chispa'; Find = '<h1>Solo Ing. Serrano'; Replace = ('<div class="cab"><span class="letra">B</span> <span class="nombre">Ing. Serrano - Estandarizacion con muestras de ajuste</span></div>' + "`n" + '  <h1>Solo Ing. Serrano') }
    @{ Id = 'K19'; Rule = 'revision-chispa'; Find = '<span class="letra">B</span>'; Replace = ('<div class="caja alerta"><h2>Antes de aceptar: revise que haya chispa</h2><p>Si tiene prisa, acepte los factores.</p></div>' + "`n" + '      <span class="letra">B</span>') }
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
            $script:ArlStResults = [System.Collections.Generic.List[object]]::new()
            $consoleOut = [Console]::Out
            [Console]::SetOut([System.IO.TextWriter]::Null)   # the expected FAIL line of the planted defect is noise here
            try { Invoke-ArlStCardStatic -CardPath $mutCard | Out-Null } finally { [Console]::SetOut($consoleOut) }
            $c15 = @($script:ArlStResults | Where-Object { $_.Id -eq 'C15' })
            $killed = ($c15.Count -eq 1) -and (-not $c15[0].Pass)
            $label = "mutante de tarjeta $($k.Id) muere por C15"
            if ($k.ContainsKey('Rule')) {
                $killed = $killed -and ($c15[0].Detail -match ('(^|\s)' + [regex]::Escape($k.Rule) + '=False(\s|$)'))
                $label = $label + " ($($k.Rule))"
            }
            Assert-True $label $killed ($(if ($c15.Count -eq 1) { '-- ' + $c15[0].Detail } else { '-- C15 no se ejecuto' }))
        }
    } finally {
        Remove-Item -LiteralPath $cardDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- depth 1d: planner checks + planner mutants (any OS) -----------------------------------------
# The planner decides where each old shortcut goes before anything is touched. These checks call its
# functions directly on in-memory items and a private temp folder, with host-native paths, so they need
# no Windows APIs and no elevation: a triple name collision, a duplicate planned twice in one run, the
# Emulator/Bridge rule on the target name and on a cmd.exe / powershell.exe wrapper, a folder that
# holds an item that stays on the desktop, and the shortcuts Chispa's installers put back on every
# DOSBox-X-ARL deploy (the engine control C21 proves the same with real .lnk files, Windows only). Each
# planner mutant plants the defect a reviewer found in a
# private copy of the script, which is dot-sourced in place of the real one; its named check must fail.
$plannerMutantSpecs = @(
    @{ Id = 'P01'; Killer = 'carpeta-conserva'; Find = 'return @{ Cleared = (-not $unknown -and -not $kept); Unknown = $unknown; Kept = $kept; Moved = $moved }'; Replace = 'return @{ Cleared = (-not $unknown); Unknown = $unknown; Kept = $kept; Moved = $moved }' }
    @{ Id = 'P02'; Killer = 'colision-triple'; Find = 'if (-not ((Test-Path -LiteralPath $alt) -or $script:ArlPlannedPaths.Contains($alt))) { break }'; Replace = 'break' }
    @{ Id = 'P03'; Killer = 'duplicado-misma-corrida'; Find = 'if (-not $dup -and $script:ArlPlannedLaunchers.ContainsKey($dest)) {'; Replace = 'if ($false) {' }
    @{ Id = 'P04'; Killer = 'regla-destino-emulator'; Find = ' -or ($tleaf -match ''(?i)Emulator|Bridge'')'; Replace = '' }
    @{ Id = 'P05'; Killer = 'regla-cmd-bridge'; Find = 'if ($scriptArg) { $Target = $scriptArg }'; Replace = '' }
    @{ Id = 'P06'; Killer = 'generadores-chispa'; Find = 'if (Test-ArlUnder -Path $Target -Root $P.ArlRoot) {'; Replace = 'if ($false) {' }
)

function New-PlItem([string]$Dir, [string]$Leaf, [string]$Target, [string]$Arguments = '', [string]$Icon = '') {
    return @{ Path = (Join-Path $Dir $Leaf); Leaf = $Leaf; Rel = $Leaf; Depth = 1; Kind = 'file'
        Ext = [System.IO.Path]::GetExtension($Leaf).ToLowerInvariant(); Target = $Target; Sha256 = 'AA'; Sddl = ''; OwnerSid = ''
        Lnk = @{ Target = $Target; Arguments = $Arguments; WorkDir = ''; Icon = $Icon; Description = ''; WindowStyle = 1 }
        Reparse = $false; Children = @(); Unreadable = $false }
}

function Reset-PlState {
    $script:ArlPlannedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:ArlGroupNeeded = @{}
    $script:ArlPlannedLaunchers = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $report = @{}
    foreach ($b in @('Crear', 'Reemplazar', 'Mover', 'Archivar', 'Conserva', 'Desconocido', 'Informe', 'Pendiente', 'Aviso')) { $report[$b] = [System.Collections.Generic.List[string]]::new() }
    return @{ Report = $report; Counts = (New-ArlCounts); Moves = ([System.Collections.Generic.List[object]]::new()) }
}

# Returns one @{ Id; Name; Pass; Detail } per check. A check that throws counts as failed.
function Invoke-PlannerChecks([string]$Root) {
    $out = [System.Collections.Generic.List[object]]::new()
    $stamp = '20260101-000000'
    $arl = Join-Path $Root 'ARL'
    $away = Join-Path $Root 'fuera'
    $P = @{ ArlRoot = $arl; Bridge = (Join-Path $arl 'ChispaBridge'); LegacyDailyTargets = @(); VerificationTargets = @()
        VerificationLeaves = @(); FinalRows = @(); ArchiveDir = (Join-Path $Root 'archivo')
        GroupPaths = @{ 'Simuladores' = (Join-Path $Root 'Simuladores'); 'Diagnostico' = (Join-Path $Root 'Diagnostico')
            'Verificacion-y-aprobacion' = (Join-Path $Root 'Verificacion'); 'Accesos-anteriores' = (Join-Path $Root 'Accesos') } }
    $emuCmd = Join-Path $away 'Launch-ArlImpactEmulatorFormatSafeLoopTrace.cmd'
    $checks = @(
        @{ Id = 'colision-triple'; Name = 'colision: tres elementos con el mismo nombre reciben tres destinos distintos'; Body = {
            $null = Reset-PlState
            $want = Join-Path $Root 'Repetido.lnk'
            $got = @((Resolve-ArlCollision -Desired $want -Stamp $stamp), (Resolve-ArlCollision -Desired $want -Stamp $stamp), (Resolve-ArlCollision -Desired $want -Stamp $stamp))
            $exp = @($want, (Join-Path $Root ('Repetido (' + $stamp + ').lnk')), (Join-Path $Root ('Repetido (' + $stamp + '-2).lnk')))
            return @{ Pass = (($got -join '|') -eq ($exp -join '|')); Detail = ($got -join ' | ') } } }
        @{ Id = 'colision-disco'; Name = 'colision: un nombre alterno ocupado en disco se salta'; Body = {
            $null = Reset-PlState
            $dir = Join-Path $Root 'ocupado'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            foreach ($f in @('Ocupado.lnk', ('Ocupado (' + $stamp + ').lnk'))) { [System.IO.File]::WriteAllText((Join-Path $dir $f), 'x') }
            $got = Resolve-ArlCollision -Desired (Join-Path $dir 'Ocupado.lnk') -Stamp $stamp
            return @{ Pass = ($got -eq (Join-Path $dir ('Ocupado (' + $stamp + '-2).lnk'))); Detail = $got } } }
        @{ Id = 'duplicado-misma-corrida'; Name = 'duplicado: el mismo lanzador dos veces en una corrida va una vez a duplicados'; Body = {
            $st = Reset-PlState
            $a1 = New-PlItem -Dir (Join-Path $Root 'escritorio1') -Leaf 'Viejo.lnk' -Target $emuCmd
            $a2 = New-PlItem -Dir (Join-Path $Root 'escritorio2') -Leaf 'Viejo.lnk' -Target $emuCmd
            foreach ($it in @($a1, $a2)) { Add-ArlMove -P $P -Item $it -Group 'Simuladores' -Note '' -Stamp $stamp -Moves $st.Moves -Report $st.Report -Counts $st.Counts }
            $dest = @($st.Moves | Where-Object { $_.kind -eq 'move' } | ForEach-Object { [string]$_.destination })
            $ok = ($dest.Count -eq 2) -and ($dest[0] -eq (Join-Path $P.GroupPaths['Simuladores'] 'Viejo.lnk')) -and ($dest[1] -eq (Join-Path (Join-Path $P.ArchiveDir 'duplicados') 'Viejo.lnk')) -and ($st.Counts.mover -eq 1) -and ($st.Counts.archivar -eq 1)
            return @{ Pass = $ok; Detail = ($dest -join ' | ') } } }
        @{ Id = 'mismo-nombre-otro-lanzador'; Name = 'colision: tres lanzadores distintos con el mismo nombre en un grupo no chocan'; Body = {
            $st = Reset-PlState
            $i = 0
            foreach ($icon in @('a.ico', 'b.ico', 'c.ico')) {
                $i++
                $it = New-PlItem -Dir (Join-Path $Root ('escritorio' + $i)) -Leaf 'Viejo.lnk' -Target $emuCmd -Icon $icon
                Add-ArlMove -P $P -Item $it -Group 'Simuladores' -Note '' -Stamp $stamp -Moves $st.Moves -Report $st.Report -Counts $st.Counts
            }
            $g = $P.GroupPaths['Simuladores']
            $dest = @($st.Moves | Where-Object { $_.kind -eq 'move' } | ForEach-Object { [string]$_.destination })
            $exp = @((Join-Path $g 'Viejo.lnk'), (Join-Path $g ('Viejo (' + $stamp + ').lnk')), (Join-Path $g ('Viejo (' + $stamp + '-2).lnk')))
            return @{ Pass = ((($dest -join '|') -eq ($exp -join '|')) -and ($st.Counts.mover -eq 3)); Detail = ($dest -join ' | ') } } }
        @{ Id = 'regla-destino-emulator'; Name = 'regla: acceso con nombre neutro que abre un lanzador Emulator va a Simuladores'; Body = {
            $r = Get-ArlTargetRule -P $P -Target $emuCmd -Leaf 'Prueba IMPACT.lnk'
            return @{ Pass = ($null -ne $r -and $r.Group -eq 'Simuladores' -and $r.Tag -eq 'SIMULA VALORES'); Detail = $(if ($null -eq $r) { 'null' } else { $r.Group + ' / ' + $r.Tag }) } } }
        @{ Id = 'regla-cmd-bridge'; Name = 'regla: cmd.exe /c con un lanzador Bridge va a Simuladores'; Body = {
            $r = Get-ArlTargetRule -P $P -Target (Join-Path $away 'cmd.exe') -Leaf 'Puente.lnk' -Arguments ('/c "' + (Join-Path $away 'Launch-ArlBridgeSmoke.cmd') + '"')
            return @{ Pass = ($null -ne $r -and $r.Group -eq 'Simuladores'); Detail = $(if ($null -eq $r) { 'null' } else { $r.Group }) } } }
        @{ Id = 'regla-ps-emulator'; Name = 'regla: powershell.exe -File con un lanzador Emulator va a Simuladores'; Body = {
            $r = Get-ArlTargetRule -P $P -Target (Join-Path $away 'powershell.exe') -Leaf 'Prueba.lnk' -Arguments ('-NoProfile -File "' + (Join-Path $away 'Start-ArlEmulator.ps1') + '"')
            return @{ Pass = ($null -ne $r -and $r.Group -eq 'Simuladores'); Detail = $(if ($null -eq $r) { 'null' } else { $r.Group }) } } }
        @{ Id = 'regla-cmd-sin-script'; Name = 'regla: cmd.exe sin lanzador en los argumentos no se clasifica'; Body = {
            $r = Get-ArlTargetRule -P $P -Target (Join-Path $away 'cmd.exe') -Leaf 'Consola.lnk' -Arguments '/k echo hola'
            return @{ Pass = ($null -eq $r); Detail = $(if ($null -eq $r) { 'null' } else { $r.Group }) } } }
        @{ Id = 'carpeta-conserva'; Name = 'carpeta: con un elemento que se conserva no se archiva y el movible si se mueve'; Body = {
            $st = Reset-PlState
            $fdir = Join-Path $Root 'ARL Diagnostics'
            $folder = @{ Path = $fdir; Leaf = 'ARL Diagnostics'; Rel = 'ARL Diagnostics'; Depth = 0; Kind = 'dir'; Ext = ''; Lnk = $null; Target = ''
                Sha256 = ''; Sddl = ''; OwnerSid = ''; Reparse = $false; Unreadable = $false
                Children = @((New-PlItem -Dir $fdir -Leaf 'Microsoft Edge.lnk' -Target (Join-Path $away 'msedge.exe')), (New-PlItem -Dir $fdir -Leaf 'Prueba IMPACT.lnk' -Target $emuCmd)) }
            $res = Add-ArlFolderContents -P $P -Item $folder -Stamp $stamp -Moves $st.Moves -Report $st.Report -Counts $st.Counts
            $ok = ($res.Kept -eq $true) -and ($res.Cleared -eq $false) -and ($res.Moved -eq 1) -and ($st.Report['Conserva'].Count -eq 1)
            return @{ Pass = $ok; Detail = ('Kept=' + $res.Kept + ' Cleared=' + $res.Cleared + ' Moved=' + $res.Moved) } } }
        @{ Id = 'carpeta-movible'; Name = 'carpeta: solo con elementos movibles queda vacia'; Body = {
            $st = Reset-PlState
            $fdir = Join-Path $Root 'ARL Viejos'
            $folder = @{ Path = $fdir; Leaf = 'ARL Viejos'; Rel = 'ARL Viejos'; Depth = 0; Kind = 'dir'; Ext = ''; Lnk = $null; Target = ''
                Sha256 = ''; Sddl = ''; OwnerSid = ''; Reparse = $false; Unreadable = $false
                Children = @((New-PlItem -Dir $fdir -Leaf 'Prueba IMPACT.lnk' -Target $emuCmd)) }
            $res = Add-ArlFolderContents -P $P -Item $folder -Stamp $stamp -Moves $st.Moves -Report $st.Report -Counts $st.Counts
            return @{ Pass = (($res.Cleared -eq $true) -and ($res.Moved -eq 1)); Detail = ('Kept=' + $res.Kept + ' Cleared=' + $res.Cleared + ' Moved=' + $res.Moved) } } }
        @{ Id = 'generadores-chispa'; Name = 'regla: los accesos que ponen los instaladores de Chispa van a su grupo de administradores'; Body = {
            # Names and targets as Chispa's deploy scripts write them (Install-DosboxArlArtifact.ps1,
            # Install-ArlOperatorShortcuts.ps1, Reset-ArlDesktopShortcuts.ps1, Install-ArlOperatorExperience.ps1).
            # Targets are joined with a backslash under the fake ARL root, as the host records them. Off
            # Windows the backslash is an ordinary character, so the rule still sees them under that root;
            # only the group is asserted, because the tag reads the file name, which differs there.
            $kit = $arl + '\DOSBox-X-ARL'
            $PG = @{ ArlRoot = $arl; Bridge = ($arl + '\ChispaBridge'); LegacyDailyTargets = @($arl + '\ChispaOperator\Chispa.Operator.exe')
                VerificationTargets = @(); VerificationLeaves = @('Run-ArlOperatorPreflight.cmd', 'Approve-LatestArlReport.cmd'); FinalRows = @() }
            $legacy = @(
                @{ Leaf = '00 DIRECTSERIAL BYPASS.lnk'; Target = ($kit + '\Launch-ArlImpactDirectSerialBypass.cmd'); Group = 'Diagnostico' },
                @{ Leaf = '00 DIRECTSERIAL BYPASS.lnk'; Target = ($arl + '\tools\Launch-ImpactDirectSerialBypass.cmd'); Group = 'Diagnostico' },
                @{ Leaf = '01 OBSERVE ONLY.lnk'; Target = ($kit + '\Launch-ArlImpactObserveOnlyTrace.cmd'); Group = 'Diagnostico' },
                @{ Leaf = '02 REACTIVE SAFE.lnk'; Target = ($kit + '\Launch-ArlImpactReactiveSafeTrace.cmd'); Group = 'Diagnostico' },
                @{ Leaf = '90 EMULATOR.lnk'; Target = ($kit + '\contrib\arl\Launch-ArlImpactEmulatorFormatSafeLoopTrace.cmd'); Group = 'Simuladores' },
                @{ Leaf = 'Diagnosticos ARL.lnk'; Target = ($arl + '\diagnostics'); Group = 'Diagnostico' },
                @{ Leaf = 'Diagnostics - Serial Traces.lnk'; Target = ($arl + '\diagnostics'); Group = 'Diagnostico' },
                @{ Leaf = 'ARL 3460 - Analizar.lnk'; Target = ($arl + '\ChispaOperator\Chispa.Operator.exe'); Group = 'Accesos-anteriores' }
            )
            $bad = [System.Collections.Generic.List[string]]::new()
            foreach ($l in $legacy) {
                $it = New-PlItem -Dir (Join-Path $Root 'escritorio') -Leaf $l.Leaf -Target $l.Target
                $it.Depth = 0
                $cls = Get-ArlItemClass -P $PG -Item $it -Scope 'publico'
                if (($cls.Action -ne 'mover') -or ($cls.Group -ne $l.Group)) { $bad.Add($l.Leaf + ' -> ' + $cls.Action + '/' + $cls.Group) }
            }
            return @{ Pass = ($bad.Count -eq 0); Detail = ($bad -join ' | ') } } }
    )
    foreach ($c in $checks) {
        try { $r = & $c.Body; $out.Add(@{ Id = $c.Id; Name = $c.Name; Pass = [bool]$r.Pass; Detail = [string]$r.Detail }) }
        catch { $out.Add(@{ Id = $c.Id; Name = $c.Name; Pass = $false; Detail = ('excepcion: ' + $_.Exception.Message) }) }
    }
    return , $out
}

$plRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('arl-desktop-planner-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $plRoot -Force | Out-Null
try {
    foreach ($pc in (Invoke-PlannerChecks -Root $plRoot)) { Assert-True "planificador $($pc.Name)" $pc.Pass ('-- ' + $pc.Detail) }
    foreach ($pm in $plannerMutantSpecs) {
        $idx = $scriptText.IndexOf($pm.Find, [System.StringComparison]::Ordinal)
        $last = $scriptText.LastIndexOf($pm.Find, [System.StringComparison]::Ordinal)
        if ($idx -lt 0 -or $idx -ne $last) { Assert-True "mutante de planificador $($pm.Id): patron unico" $false "idx=$idx last=$last"; continue }
        $pmDir = Join-Path $plRoot ('mutante-' + $pm.Id)
        New-Item -ItemType Directory -Path $pmDir -Force | Out-Null
        $pmPath = Join-Path $pmDir 'Set-ArlOperatorDesktop.ps1'
        [System.IO.File]::WriteAllText($pmPath, ($scriptText.Substring(0, $idx) + $pm.Replace + $scriptText.Substring($idx + $pm.Find.Length)), (New-Object System.Text.UTF8Encoding($false)))
        $pmResults = @()
        try {
            . $pmPath   # the mutant's functions replace the real ones for this run only
            $pmResults = Invoke-PlannerChecks -Root $pmDir
        } catch {
            Write-Host "  (mutante de planificador $($pm.Id): $($_.Exception.Message))"
        } finally {
            . $scriptPath   # put the real functions back before anything else runs
        }
        $hit = @($pmResults | Where-Object { $_.Id -eq $pm.Killer })
        Assert-True "mutante de planificador $($pm.Id) muere por $($pm.Killer)" (($hit.Count -eq 1) -and (-not $hit[0].Pass)) ($(if ($hit.Count -eq 1) { '-- ' + $hit[0].Detail } else { '-- la prueba no se ejecuto' }))
    }
} finally {
    Remove-Item -LiteralPath $plRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- depth 1e: the CI gate's log reader + gate mutants (any OS) -------------------------------------
# CI runs this file through Invoke-ArlOperatorDesktopCiGate.ps1, which must fail the step whenever an
# engine control or engine mutant did not really run. Its reader is fed complete logs built from this
# file's own control and mutant lists, then runs with one planted gap each (a non-zero exit, a SKIP or FAIL
# line, a missing PASS, a mutant killed by another control, no 'all passed', a control list or mutant list
# too short); only the complete ones pass. Gate mutants G01-G10 each remove one of the reader's checks in a
# private copy of the gate, which is dot-sourced in place of the real one; the case named for it must fail.
$gatePath = Join-Path $PSScriptRoot 'Invoke-ArlOperatorDesktopCiGate.ps1'
$gateMutantSpecs = @(
    @{ Id = 'G01'; Killer = 'codigo de salida distinto de cero falla'; Find = 'if ($ExitCode -ne 0) { $out.Add(''la prueba termino con codigo '' + $ExitCode) }'; Replace = '' }
    @{ Id = 'G02'; Killer = 'un SKIP de motor falla'; Find = 'if ($ln -match ''^\s*SKIP\b'') { $out.Add(''SKIP: '' + $ln.Trim()) }'; Replace = '' }
    @{ Id = 'G03'; Killer = 'una linea FAIL falla'; Find = 'if ($ln -match ''^\s*FAIL\b'') { $out.Add(''FAIL: '' + $ln.Trim()) }'; Replace = '' }
    @{ Id = 'G04'; Killer = 'una lista de controles corta falla'; Find = 'if ($controls.Count -lt $minControls) {'; Replace = 'if ($false) {' }
    @{ Id = 'G05'; Killer = 'sin mutantes declarados falla (mutantes)'; Find = 'if ($Depth -eq ''Mutantes'' -and $mutants.Count -lt $minMutants) {'; Replace = 'if ($false) {' }
    @{ Id = 'G06'; Killer = 'un mutante muerto por otro control falla'; Find = ''' muere por '' + [regex]::Escape($m.Killer) + ''\s*$'''; Replace = ''' muere por ''' }
    @{ Id = 'G07'; Killer = 'sin all passed falla'; Find = 'if ($text -notmatch ''(?m)^all passed\s*$'') {'; Replace = 'if ($false) {' }
    @{ Id = 'G08'; Killer = 'sin PASS C21 en pwsh falla'; Find = 'if ($Depth -eq ''Motor'') {'; Replace = 'if ($false) {' }
    @{ Id = 'G09'; Killer = 'PASS C04b no cuenta como PASS C04'; Find = '[regex]::Escape($n) + ''\s*$'''; Replace = '[regex]::Escape($n)' }
    @{ Id = 'G10'; Killer = 'sin la linea de un mutante falla'; Find = 'if ($Depth -eq ''Mutantes'') {'; Replace = 'if ($false) {' }
)

# Returns one @{ Name; Pass; Detail } per log case, run against whichever Get-ArlCiGateProblems is loaded.
function Invoke-GateCases([string]$SelfText) {
    $goodLog = [System.Collections.Generic.List[string]]::new()
    foreach ($eng in @('powershell', 'pwsh')) {
        $goodLog.Add("  PASS  motor ${eng}: autoprueba exit 0")
        $goodLog.Add("  PASS  motor ${eng}: status autoprueba-ok")
        foreach ($id in $allControls) { $goodLog.Add("  PASS  motor ${eng}: PASS $id") }
    }
    $mutantLines = @($mutantSpecs | ForEach-Object { "  PASS  mutante $($_.Id) muere por $($_.Killer)" })
    foreach ($l in $mutantLines) { $goodLog.Add($l) }
    $goodLog.Add('all passed')
    $good = @($goodLog)
    $shortControls = (New-Object System.Text.RegularExpressions.Regex('(?s)\$allControls\s*=\s*@\(.*?\)')).Replace($SelfText, '$$allControls = @(''C01'')', 1)
    $noMutants = $SelfText.Replace('@{ Id = ''M', '@{ Id = ''N')
    $cases = @(
        @{ Name = 'un registro completo pasa (motor)'; Lines = $good; Depth = 'Motor'; WantOk = $true },
        @{ Name = 'un registro completo pasa (mutantes)'; Lines = $good; Depth = 'Mutantes'; WantOk = $true },
        @{ Name = 'mutantes con -SkipEngine sin lineas de motor pasa'; Lines = @($mutantLines + '  OMITIDO  autoprueba por motor (-SkipEngine)' + 'all passed'); Depth = 'Mutantes'; WantOk = $true },
        @{ Name = 'codigo de salida distinto de cero falla'; Lines = $good; Depth = 'Motor'; ExitCode = 1; WantOk = $false },
        @{ Name = 'un SKIP de motor falla'; Lines = ($good + '  SKIP  autoprueba por motor (requiere elevacion)'); Depth = 'Motor'; WantOk = $false },
        @{ Name = 'una linea FAIL falla'; Lines = ($good + '  FAIL  mutante de tarjeta K01 muere por C15'); Depth = 'Motor'; WantOk = $false },
        @{ Name = 'sin PASS C21 en pwsh falla'; Lines = @($good | Where-Object { $_ -ne '  PASS  motor pwsh: PASS C21' }); Depth = 'Motor'; WantOk = $false },
        @{ Name = 'PASS C04b no cuenta como PASS C04'; Lines = @($good | Where-Object { $_ -ne '  PASS  motor powershell: PASS C04' }); Depth = 'Motor'; WantOk = $false },
        @{ Name = 'sin la linea de un mutante falla'; Lines = @($good | Where-Object { $_ -notlike '*mutante M23 *' }); Depth = 'Mutantes'; WantOk = $false },
        @{ Name = 'un mutante muerto por otro control falla'; Lines = @($good | ForEach-Object { if ($_ -like '*mutante M23 muere por C21') { '  PASS  mutante M23 muere por C20' } else { $_ } }); Depth = 'Mutantes'; WantOk = $false },
        @{ Name = 'sin all passed falla'; Lines = @($good | Where-Object { $_ -ne 'all passed' }); Depth = 'Motor'; WantOk = $false },
        @{ Name = 'una lista de controles corta falla'; Lines = $good; Depth = 'Motor'; Text = $shortControls; WantOk = $false },
        @{ Name = 'sin mutantes declarados falla (mutantes)'; Lines = $good; Depth = 'Mutantes'; Text = $noMutants; WantOk = $false },
        @{ Name = 'un registro de laptop (estatico + SKIP) falla'; Lines = @('  PASS  estatico C15  tarjeta cual-uso.html valida', '  SKIP  autoprueba por motor (requiere Windows)', 'all passed'); Depth = 'Motor'; WantOk = $false }
    )
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($gc in $cases) {
        $text = if ($gc.ContainsKey('Text')) { $gc.Text } else { $SelfText }
        $code = if ($gc.ContainsKey('ExitCode')) { $gc.ExitCode } else { 0 }
        try {
            $probs = @(Get-ArlCiGateProblems -Lines $gc.Lines -Depth $gc.Depth -TestText $text -ExitCode $code)
            $out.Add(@{ Name = $gc.Name; Pass = (($probs.Count -eq 0) -eq $gc.WantOk); Detail = ('problemas=' + $probs.Count + ' ' + (@($probs | Select-Object -First 2) -join ' | ')) })
        } catch {
            $out.Add(@{ Name = $gc.Name; Pass = $false; Detail = ('excepcion: ' + $_.Exception.Message) })
        }
    }
    return , $out
}

if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) {
    Assert-True 'la puerta de CI Invoke-ArlOperatorDesktopCiGate.ps1 existe' $false "-- $gatePath"
} else {
    . $gatePath   # dot-source: defines Get-ArlCiGateProblems and runs nothing
    $selfText = [System.IO.File]::ReadAllText($PSCommandPath)
    foreach ($gc in (Invoke-GateCases -SelfText $selfText)) { Assert-True "puerta CI: $($gc.Name)" $gc.Pass ('-- ' + $gc.Detail) }
    $gateText = [System.IO.File]::ReadAllText($gatePath)
    $gmDir = Join-Path ([System.IO.Path]::GetTempPath()) ('arl-desktop-gate-mutants-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $gmDir -Force | Out-Null
    try {
        foreach ($gm in $gateMutantSpecs) {
            $idx = $gateText.IndexOf($gm.Find, [System.StringComparison]::Ordinal)
            $last = $gateText.LastIndexOf($gm.Find, [System.StringComparison]::Ordinal)
            if ($idx -lt 0 -or $idx -ne $last) { Assert-True "mutante de puerta $($gm.Id): patron unico" $false "idx=$idx last=$last"; continue }
            $gmPath = Join-Path $gmDir ($gm.Id + '.ps1')
            [System.IO.File]::WriteAllText($gmPath, ($gateText.Substring(0, $idx) + $gm.Replace + $gateText.Substring($idx + $gm.Find.Length)), (New-Object System.Text.UTF8Encoding($false)))
            $gmResults = @()
            try {
                . $gmPath   # the mutant's reader replaces the real one for this run only
                $gmResults = Invoke-GateCases -SelfText $selfText
            } catch {
                Write-Host "  (mutante de puerta $($gm.Id): $($_.Exception.Message))"
            } finally {
                . $gatePath   # put the real reader back
            }
            $hit = @($gmResults | Where-Object { $_.Name -eq $gm.Killer })
            Assert-True "mutante de puerta $($gm.Id) muere por '$($gm.Killer)'" (($hit.Count -eq 1) -and (-not $hit[0].Pass)) ($(if ($hit.Count -eq 1) { '-- ' + $hit[0].Detail } else { '-- el caso no se ejecuto' }))
        }
    } finally {
        Remove-Item -LiteralPath $gmDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- depth 2: run the script's own -SelfTest under each engine (Windows + elevated) -------------
if ($SkipEngine) {
    Write-Host '  OMITIDO  autoprueba por motor (-SkipEngine)'
} elseif (-not (Test-OnWindows)) {
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
        # The self-test's own lines, prefixed so the CI gate never reads them as this harness's PASS/FAIL/SKIP.
        foreach ($ln in @($out)) { Write-Host ('    motor ' + $e.Name + '> ' + [string]$ln) }
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
                # Only the owning control's group runs, so the mutant is killed by the control named for it.
                $out = & $ps51.Source -NoProfile -ExecutionPolicy Bypass -File $copy -SelfTest -Controls $m.Killer 2>&1
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
