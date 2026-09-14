<#
.SYNOPSIS
    Leaves the ARL 3460 public desktop with the four icons people use and moves every other ARL
    launcher to an administrators-only tools folder. Read-only unless -Apply or -Undo is given.

.DESCRIPTION
    The launcher an operator clicks decides the run-id prefix (sample-analysis-, standardization-,
    normalization-), and the emulator and bridge launchers simulate values. A floor technician
    choosing between fifteen icons named PASSIVE, TRACE and PRECHECK is the failure this fixes.

    Final desktop (C:\Users\Public\Desktop), besides the Epson/Edge items that are kept:
      Analizar colada                            daily work (Chispa.Operator.exe)
      Ayuda - Que icono uso                      the printable card (C:\ARL\Guia-Operador\cual-uso.html)
      Ing. Serrano - Estandarizacion con muestras de ajuste
      Ing. Serrano - Normalizacion
    Everything else that launches ARL tooling goes to C:\ARL\Herramientas-Admin\<grupo> (SY/BA only).
    Nothing is deleted: replaced and emptied items go to C:\ARL\_staging\desktop-archive\<ts>, next to a
    crash-safe manifest that -Undo reverses (last applied first). -Undo also recovers a run that was cut
    off (manifest left at applying or undoing), retries what an earlier -Undo skipped, and moves what apply
    put down into <ts>\deshecho instead of deleting it; only empty folders apply created are removed.

    Modes
      (no switch)                     revisar: validate, inventory, print the plan. Writes nothing.
      -Apply -WhatIf                  the revisar checks plus elevation (R1), the same plan; stops at the
                                      first write with cambios-pendientes. Rehearses no move.
      -Apply                          aplicar (elevated).
      -Undo [-Manifest <path>]        deshacer (elevated). Prefer fixing forward: an exact undo puts the
                                      simulator icons back on the public desktop.
      -SelfTest [-Controls C02,C10]   autoprueba (elevated): builds a fake tree under %TEMP% and runs the
                                      contract controls C01-C21 against child runs of this same file.

    Exit codes: 0 sin-cambios|cambios-pendientes|aplicado|deshecho|autoprueba-ok, 1 error|autoprueba-fallo,
    2 rechazado (nothing written), 3 deshecho-parcial. The last stdout line is always
    ARL-DESKTOP-RESULT {json}.

    Encoding: this file is ASCII-only on purpose. Windows PowerShell 5.1 reads a BOM-less script as ANSI,
    so no accented literal may appear here; operator text with accents lives in
    operator-desktop\cual-uso.html as HTML entities. The self-test (C13) and the CI test pin this.
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Revisar')]
param(
    [Parameter(ParameterSetName = 'Aplicar', Mandatory = $true)] [switch]$Apply,
    [Parameter(ParameterSetName = 'Deshacer', Mandatory = $true)] [switch]$Undo,
    [Parameter(ParameterSetName = 'Deshacer')] [string]$Manifest = '',
    [Parameter(ParameterSetName = 'Autoprueba', Mandatory = $true)] [switch]$SelfTest,
    [Parameter(ParameterSetName = 'Autoprueba')] [string[]]$Controls = @(),
    [string]$PublicDesktop = '',
    [string]$OperatorDesktop = '',
    [string]$UsersRoot = '',
    [string]$ArlRoot = '',
    [string]$EdgePath = '',
    [string]$SystemRoot = '',
    [string]$CardSource = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region conjunto-final
# The four icons that stay on the public desktop. {ARL} is -ArlRoot, {SYS} is -SystemRoot\System32 and
# {EDGE} is the resolved Edge path. Names and tooltips are ASCII (cmd.exe and the self-test C13), carry
# none of the words the old generators' cleanup regexes match (C14), and sort together:
# Analizar, Ayuda, Epson..., Ing. Serrano - Estandarizacion, Ing. Serrano - Normalizacion, Manual, Microsoft.
function Get-ArlFinalRows {
    @(
        @{ Name = 'Analizar colada'; Target = '{ARL}\ChispaOperator\Chispa.Operator.exe'; Arguments = ''; WorkDir = '{ARL}\ChispaOperator'; Icon = '{ARL}\DOSBox-X-ARL\dosbox-x-arl.exe,0'; Description = 'Trabajo diario: analisis de coladas. La hoja sale sola en la impresora HP.' }
        @{ Name = 'Ayuda - Que icono uso'; Target = '{EDGE}'; Arguments = '"{ARL}\Guia-Operador\cual-uso.html"'; WorkDir = '{ARL}\Guia-Operador'; Icon = '{SYS}\shell32.dll,23'; Description = 'Hoja de ayuda: que icono usar para cada trabajo.' }
        @{ Name = 'Ing. Serrano - Estandarizacion con muestras de ajuste'; Target = '{ARL}\DOSBox-X-ARL\contrib\arl\Launch-ArlStandardizationPassiveTrace.cmd'; Arguments = ''; WorkDir = '{ARL}\DOSBox-X-ARL'; Icon = '{SYS}\shell32.dll,314'; Description = 'Solo Ing. Serrano. Tecnicos: no lo abran; usen Analizar colada.' }
        @{ Name = 'Ing. Serrano - Normalizacion'; Target = '{ARL}\DOSBox-X-ARL\contrib\arl\Launch-ArlNormalizationPassiveTrace.cmd'; Arguments = ''; WorkDir = '{ARL}\DOSBox-X-ARL'; Icon = '{SYS}\shell32.dll,314'; Description = 'Solo Ing. Serrano. Tecnicos: no lo abran; usen Analizar colada.' }
    )
}

# Items on the public desktop that are not ARL tooling and stay exactly as they are.
$script:ArlKeptNames = @('Epson Photo+ Tool.lnk', 'Epson Photo+.lnk', 'Manual Epson L6270.url', 'Microsoft Edge.lnk', 'desktop.ini')
#endregion conjunto-final

#region implementacion
# Security descriptors. SIDs are used as aliases, never as names (the host is in Spanish).
# SY = SYSTEM, BA = BUILTIN\Administrators, BU = BUILTIN\Users.
$script:SddlAdminOnly = 'O:BAG:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
$script:SddlGuide = $script:SddlAdminOnly + '(A;OICI;0x1200a9;;;BU)'
$script:SidSY = 'S-1-5-18'
$script:SidBA = 'S-1-5-32-544'
$script:ArlGroups = @('Simuladores', 'Diagnostico', 'Verificacion-y-aprobacion', 'Accesos-anteriores')

# Union of the words the old desktop generators match on (spec 1.2). Used for SOSPECHA and rule 4.
$script:ArlTokenUnion = 'ARL|IMPACT|TRACE|TICS|EMU|PRINT|INSPECT|DIAGN|PRECHECK|APPROVE|STANDARDIZATION|NORMALIZATION|BYPASS|OBSERVE|REACTIVE|DIRECTSERIAL|CYCLES|SIMPLE|STABILITY|UARTDATA|FORCELINES|HOLDRTS|RX4000|SAFE SERIAL|NOINT33|NO MOUSE|^\d{2} |^ARL '

# Rights that let a SID change a file or folder (manifest trust checks and the G5 warning).
$script:ArlWriteMask = 0x500D0156

function Test-ArlWindows { return ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) }

function New-ArlRefusal([string]$Id, [string]$Message) {
    return (New-Object System.Exception ('ARL-RECHAZO|' + $Id + '|' + $Message))
}

function ConvertTo-ArlHex([byte[]]$Bytes) {
    $sb = New-Object System.Text.StringBuilder ($Bytes.Length * 2)
    foreach ($b in $Bytes) { [void]$sb.Append($b.ToString('x2')) }
    return $sb.ToString()
}

function Get-ArlBytesSha256([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (ConvertTo-ArlHex $sha.ComputeHash($Bytes)) } finally { $sha.Dispose() }
}

function Get-ArlFileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-ArlJsonString([string]$Text) {
    if ($null -eq $Text) { return 'null' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $c = [int]$ch
        if ($c -eq 34) { [void]$sb.Append('\"') }
        elseif ($c -eq 92) { [void]$sb.Append('\\') }
        elseif ($c -lt 0x20 -or $c -gt 0x7E) { [void]$sb.Append(('\u{0:x4}' -f $c)) }
        else { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Own serializer: ConvertTo-Json differs between 5.1 and 7 and does not escape non-ASCII.
function ConvertTo-ArlJson($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-ArlJsonString $Value) }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $Value.Keys) { $parts.Add((ConvertTo-ArlJsonString ([string]$k)) + ':' + (ConvertTo-ArlJson $Value[$k])) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($p in $Value.PSObject.Properties) { $parts.Add((ConvertTo-ArlJsonString $p.Name) + ':' + (ConvertTo-ArlJson $p.Value)) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($v in $Value) { $parts.Add((ConvertTo-ArlJson $v)) }
        return '[' + ($parts -join ',') + ']'
    }
    return (ConvertTo-ArlJsonString ([string]$Value))
}

# P/Invoke through Add-Type -MemberDefinition (no -TypeDefinition, no modules). Loaded once, only when needed.
function Import-ArlNative {
    if ('ArlDesktop.Native' -as [type]) { return }
    $members = @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern uint GetLongPathNameW(string lpszShortPath, System.Text.StringBuilder lpszLongPath, uint cchBuffer);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int SHDefExtractIconW(string pszIconFile, int iIndex, uint uFlags, out IntPtr phiconLarge, out IntPtr phiconSmall, uint nIconSize);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern uint ExtractIconExW(string lpszFile, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, uint nIcons);
[DllImport("user32.dll", SetLastError = true)]
public static extern bool DestroyIcon(IntPtr hIcon);
'@
    Add-Type -Namespace ArlDesktop -Name Native -MemberDefinition $members
}

# Full path with 8.3 components expanded (the runner TEMP is often C:\Users\RUNNER~1\...). Works for paths
# that do not exist yet by expanding the longest existing ancestor.
function Get-ArlLongPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    if (-not (Test-ArlWindows) -or $full.IndexOf('~') -lt 0) { return $full }
    Import-ArlNative
    $existing = $full
    $rest = ''
    while ($existing -and -not (Test-Path -LiteralPath $existing)) {
        $leaf = [System.IO.Path]::GetFileName($existing)
        $rest = if ($rest) { $leaf + '\' + $rest } else { $leaf }
        $existing = [System.IO.Path]::GetDirectoryName($existing)
    }
    if (-not $existing) { return $full }
    $sb = New-Object System.Text.StringBuilder 1024
    $n = [ArlDesktop.Native]::GetLongPathNameW($existing, $sb, 1024)
    if ($n -gt 0 -and $n -lt 1024) { $existing = $sb.ToString() }
    if ($rest) { return ([System.IO.Path]::Combine($existing, $rest)).TrimEnd('\') }
    return $existing.TrimEnd('\')
}

function Test-ArlUnder([string]$Path, [string]$Root, [switch]$AllowEqual) {
    if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($Root)) { return $false }
    # A path 5.1 cannot parse (invalid characters, an alternate-stream colon) is never under anything.
    try {
        $p = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        $r = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    } catch { return $false }
    if ($AllowEqual -and [string]::Equals($p, $r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $p.StartsWith($r + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

# Roots: array of @{ Path = ...; AllowEqual = $bool }.
function Test-ArlUnderAny([string]$Path, [object[]]$Roots) {
    foreach ($r in $Roots) {
        if (Test-ArlUnder -Path $Path -Root $r.Path -AllowEqual:([bool]$r.AllowEqual)) { return $true }
    }
    return $false
}

function Test-ArlDotDot([string]$Path) { return ($Path -match '(^|[\\/])\.\.([\\/]|$)') }

function Resolve-ArlTargetPath([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $x = [Environment]::ExpandEnvironmentVariables($Raw.Trim().Trim('"'))
    try { if ([System.IO.Path]::IsPathRooted($x)) { return [System.IO.Path]::GetFullPath($x).TrimEnd('\') } } catch { return $x }
    return $x
}

# SDDL comparison key. Only what decides access counts: the owner, whether the DACL is protected, and the
# set of ACEs in any order. The primary group is not security relevant and cannot be set without extra
# privileges, Windows adds the AR/AI auto-inherit flags on its own, and an ACL reset rebuilds inherited ACEs
# in its own order (on Laboratorio-ARL the public desktop hands down IU,SY,BA while its older .lnk files
# hold BA,IU,SY), so an order-sensitive string compare would call a correct restore a failure.
# The key is built from the parsed descriptor (SIDs as S-1-..., rights as numbers), so FA and 0x1f01ff or BA
# and S-1-5-32-544 compare equal; the text parser below is only the fallback where Windows cannot parse it.
function ConvertTo-ArlSddlKey([string]$Sddl) {
    if ([string]::IsNullOrEmpty($Sddl)) { return '' }
    try {
        $rsd = New-Object System.Security.AccessControl.RawSecurityDescriptor $Sddl
        $rowner = ''
        if ($null -ne $rsd.Owner) { $rowner = $rsd.Owner.Value }
        $rprot = ''
        if (($rsd.ControlFlags -band [System.Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0) { $rprot = 'P' }
        $rlist = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $rsd.DiscretionaryAcl) {
            foreach ($ace in $rsd.DiscretionaryAcl) {
                [void]$rlist.Add('(' + [int]$ace.AceType + ';' + [int]$ace.AceFlags + ';' + [string]$ace.AccessMask + ';' + $ace.SecurityIdentifier.Value + ')')
            }
        }
        [string[]]$races = $rlist.ToArray()
        [Array]::Sort($races, [System.StringComparer]::Ordinal)
        return ('O:' + $rowner + 'D:' + $rprot + ($races -join ''))
    } catch { }
    $owner = ''
    $m = [regex]::Match($Sddl, '^O:(S-1-[0-9-]+|[A-Z]{2})')
    if ($m.Success) { $owner = $m.Groups[1].Value }
    $prot = ''
    $d = [regex]::Match($Sddl, 'D:(P?)')
    if ($d.Success) { $prot = $d.Groups[1].Value }
    [string[]]$aces = @(Get-ArlSddlAces $Sddl | ForEach-Object { [string]$_.Raw })
    [Array]::Sort($aces, [System.StringComparer]::Ordinal)
    return ('O:' + $owner + 'D:' + $prot + ($aces -join ''))
}

function Get-ArlSddlAces([string]$Sddl) {
    $out = [System.Collections.Generic.List[object]]::new()
    $idx = $Sddl.IndexOf('D:')
    if ($idx -lt 0) { return $out }
    $dacl = $Sddl.Substring($idx + 2)
    $s = $dacl.IndexOf('S:')
    if ($s -ge 0) { $dacl = $dacl.Substring(0, $s) }
    foreach ($m in [regex]::Matches($dacl, '\(([^)]*)\)')) {
        $f = $m.Groups[1].Value.Split(';')
        if ($f.Count -ge 6) { $out.Add(@{ Raw = $m.Value; Type = $f[0]; Flags = $f[1]; Rights = $f[2]; Sid = $f[5] }) }
    }
    return $out
}

# A child under a protected root: owner BA, only inherited ACEs, SIDs within the allowed set.
function Test-ArlChildSddl([string]$Sddl, [string]$Scope) {
    if ($Sddl -notmatch '^O:BA') { return $false }
    foreach ($ace in (Get-ArlSddlAces $Sddl)) {
        if ($ace.Flags -notmatch 'ID') { return $false }
        if ($Scope -eq 'escritorio') { continue }
        if ($ace.Type -ne 'A') { return $false }
        if ($ace.Sid -eq 'SY' -or $ace.Sid -eq 'BA') { continue }
        if ($Scope -eq 'guia' -and $ace.Sid -eq 'BU' -and @('0x1200a9', 'FRFX', 'FXFR') -contains $ace.Rights) { continue }
        return $false
    }
    return $true
}

function Get-ArlOwnerSid([string]$Path) {
    return (Get-Acl -LiteralPath $Path).GetOwner([System.Security.Principal.SecurityIdentifier]).Value
}

# SIDs (other than SY, BA and TrustedInstaller) holding an allow ACE with a write-class right on the object.
function Get-ArlWriters([string]$Path) {
    $acl = Get-Acl -LiteralPath $Path
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        if (($r.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) { continue }
        $sid = $r.IdentityReference.Value
        if (@($script:SidSY, $script:SidBA, 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464') -contains $sid) { continue }
        if (([int]$r.FileSystemRights -band $script:ArlWriteMask) -ne 0) { $out.Add($sid) }
    }
    return $out
}

# PNG names are defined here once; the card, the plan and the self-test all read them from this table.
function Get-ArlIconSet($P) {
    @(
        @{ Png = 'analizar-colada.png'; Source = $P.DosboxExe; Index = 0 }
        @{ Png = 'guia.png'; Source = $P.ShellDll; Index = 23 }
        @{ Png = 'serrano.png'; Source = $P.ShellDll; Index = 314 }
    )
}

function Write-ArlLine([string]$Text) { [Console]::Out.WriteLine($Text) }

function New-ArlCounts {
    return [ordered]@{ crear = 0; reemplazar = 0; mover = 0; archivar = 0; desconocidos = 0; sospechosos = 0; pendientes_manuales = 0; avisos = 0 }
}

function Get-ArlExitCode([string]$Status) {
    if (@('sin-cambios', 'cambios-pendientes', 'aplicado', 'deshecho', 'autoprueba-ok') -contains $Status) { return 0 }
    if ($Status -eq 'rechazado') { return 2 }
    if ($Status -eq 'deshecho-parcial') { return 3 }
    return 1
}

function Write-ArlResult([string]$Mode, [string]$Status, $Colada, $ManifestPath, $Counts, $Failed) {
    if ($null -eq $Counts) { $Counts = New-ArlCounts }
    $list = @()
    if ($null -ne $Failed) { $list = @($Failed) }
    $o = [ordered]@{
        schema = 'arl-desktop-result-v1'; mode = $Mode; status = $Status; colada_shortcut = $Colada
        manifest = $ManifestPath; counts = $Counts; failed_controls = $list
    }
    Write-ArlLine ('ARL-DESKTOP-RESULT ' + (ConvertTo-ArlJson $o))
}

function Get-ArlDefaultEdge {
    try {
        $v = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -Name '(default)' -ErrorAction Stop
        if ($v) { return ([string]$v).Trim('"') }
    } catch { }
    return (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
}

# Every path the script touches or reads is derived here from the seven path parameters.
function Resolve-ArlPaths([hashtable]$Values) {
    $v = @{}
    foreach ($k in @('PublicDesktop', 'OperatorDesktop', 'UsersRoot', 'ArlRoot', 'EdgePath', 'SystemRoot', 'CardSource')) { $v[$k] = [string]$Values[$k] }
    if (-not $v.PublicDesktop) { $v.PublicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory') }
    if (-not $v.UsersRoot) { if ($env:PUBLIC) { $v.UsersRoot = Split-Path -Parent $env:PUBLIC } else { $v.UsersRoot = 'C:\Users' } }
    if (-not $v.OperatorDesktop) { $v.OperatorDesktop = Join-Path $v.UsersRoot 'Piso\Desktop' }
    if (-not $v.ArlRoot) { $v.ArlRoot = 'C:\ARL' }
    if (-not $v.EdgePath) { $v.EdgePath = Get-ArlDefaultEdge }
    if (-not $v.SystemRoot) { $v.SystemRoot = $env:SystemRoot }
    if (-not $v.CardSource) { $v.CardSource = Join-Path $PSScriptRoot 'operator-desktop\cual-uso.html' }
    $P = @{}
    foreach ($k in $v.Keys) { $P[$k] = [System.IO.Path]::GetFullPath($v[$k]).TrimEnd('\') }
    $P.Tools = Join-Path $P.ArlRoot 'Herramientas-Admin'
    $P.Guide = Join-Path $P.ArlRoot 'Guia-Operador'
    $P.Icons = Join-Path $P.Guide 'iconos'
    $P.Card = Join-Path $P.Guide 'cual-uso.html'
    $P.Staging = Join-Path $P.ArlRoot '_staging'
    $P.ArchiveRoot = Join-Path $P.Staging 'desktop-archive'
    $P.Toolkit = Join-Path $P.ArlRoot 'DOSBox-X-ARL'
    $P.OperatorDir = Join-Path $P.ArlRoot 'ChispaOperator'
    $P.Bridge = Join-Path $P.ArlRoot 'ChispaBridge'
    $P.DosboxExe = Join-Path $P.Toolkit 'dosbox-x-arl.exe'
    $P.ShellDll = Join-Path $P.SystemRoot 'System32\shell32.dll'
    $P.ChispaExe = Join-Path $P.OperatorDir 'Chispa.Operator.exe'
    $P.OperatorSettings = Join-Path $P.OperatorDir 'operator-settings.json'
    $P.PassiveStd = Join-Path $P.Toolkit 'contrib\arl\Launch-ArlStandardizationPassiveTrace.cmd'
    $P.PassiveNorm = Join-Path $P.Toolkit 'contrib\arl\Launch-ArlNormalizationPassiveTrace.cmd'
    $P.PassiveWorkflow = Join-Path $P.Toolkit 'contrib\arl\Launch-ArlPassiveWorkflowTrace.ps1'
    $P.LegacyDailyTargets = @($P.ChispaExe, $P.PassiveStd, $P.PassiveNorm)
    $P.VerificationTargets = @((Join-Path $P.ArlRoot 'tools\Test-ArlPhysicalPreflight.ps1'), (Join-Path $P.ArlRoot 'tools\Approve-LatestArlReport.ps1'))
    $P.VerificationLeaves = @('Run-ArlOperatorPreflight.cmd', 'Approve-LatestArlReport.cmd')
    $P.PisoPins = Join-Path $P.UsersRoot 'Piso\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    $P.Accesos = Join-Path $P.ArlRoot 'Administradores\Accesos'
    $P.GroupPaths = @{}
    foreach ($g in $script:ArlGroups) { $P.GroupPaths[$g] = Join-Path $P.Tools $g }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($r in (Get-ArlFinalRows)) {
        $e = @{}
        foreach ($k in $r.Keys) {
            $e[$k] = $r[$k].Replace('{ARL}', $P.ArlRoot).Replace('{SYS}', (Join-Path $P.SystemRoot 'System32')).Replace('{EDGE}', $P.EdgePath)
        }
        $e.Name = $r.Name
        $rows.Add($e)
    }
    $P.FinalRows = $rows
    $P.ColadaPath = Join-Path $P.PublicDesktop ($rows[0].Name + '.lnk')
    # Mutations are confined to these roots (Invoke-ArlAction). The desktops never as a whole.
    $P.WriteRoots = @(
        @{ Path = $P.PublicDesktop; AllowEqual = $false }, @{ Path = $P.OperatorDesktop; AllowEqual = $false },
        @{ Path = $P.Tools; AllowEqual = $true }, @{ Path = $P.Guide; AllowEqual = $true }, @{ Path = $P.ArchiveRoot; AllowEqual = $true }
    )
    $P.NeverRoots = @($P.Toolkit, $P.OperatorDir, $P.Bridge, (Join-Path $P.ArlRoot 'IMPLUS'), (Join-Path $P.ArlRoot 'diagnostics'), (Join-Path $P.ArlRoot 'state'), (Join-Path $P.ArlRoot 'tools'))
    return $P
}

function Assert-ArlEnvironment([hashtable]$Bound) {
    if (-not (Test-ArlWindows)) { throw (New-ArlRefusal 'R9' 'este script solo funciona en Windows') }
    if (-not [Environment]::Is64BitProcess) { throw (New-ArlRefusal 'R9' 'use PowerShell de 64 bits (C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe)') }
}

function Test-ArlReparseChain([string]$Path) {
    $cur = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    while ($cur) {
        try {
            if (Test-Path -LiteralPath $cur) {
                $it = Get-Item -LiteralPath $cur -Force
                if (($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
            }
        } catch { }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }
    return $false
}

# The chain from the drive root, plus every descendant (never following a reparse point).
function Test-ArlReparseTree([string]$Path) {
    if (Test-ArlReparseChain $Path) { return $true }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($c in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        if (($c.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        if ($c.PSIsContainer -and (Test-ArlReparseTree $c.FullName)) { return $true }
    }
    return $false
}

function Assert-ArlPathParameters([hashtable]$Bound) {
    $names = @('PublicDesktop', 'OperatorDesktop', 'UsersRoot', 'ArlRoot', 'EdgePath', 'SystemRoot', 'CardSource')
    $given = @($names | Where-Object { $Bound.ContainsKey($_) -and -not [string]::IsNullOrEmpty([string]$Bound[$_]) })
    if ($Bound.ContainsKey('SelfTest')) {
        if ($given.Count -gt 0 -or $Bound.ContainsKey('WhatIf')) {
            throw (New-ArlRefusal 'R2' 'la autoprueba no acepta rutas ni -WhatIf; crea su propio arbol en la carpeta temporal')
        }
        return
    }
    if ($given.Count -eq 0) { return }
    $defaults = Resolve-ArlPaths @{}
    $temp = Get-ArlLongPath ([System.IO.Path]::GetTempPath())
    $underTemp = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $given) {
        try { $value = [System.IO.Path]::GetFullPath([string]$Bound[$n]).TrimEnd('\') }
        catch { throw (New-ArlRefusal 'R2' ('ruta no valida: -' + $n + ' ' + [string]$Bound[$n])) }
        if ([string]::Equals($value, $defaults[$n], [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $long = Get-ArlLongPath $value
        if (-not (Test-ArlUnder -Path $long -Root $temp)) {
            throw (New-ArlRefusal 'R2' ('ruta fuera de la carpeta temporal: -' + $n + ' ' + $value + '. En el equipo real use los valores de fabrica.'))
        }
        if (Test-ArlReparseChain $long) { throw (New-ArlRefusal 'R2' ('ruta con enlace (junction): -' + $n + ' ' + $value)) }
        $underTemp.Add($n)
    }
    # All or nothing: a test -ArlRoot next to the real desktops would plan against the real desktops.
    if ($underTemp.Count -gt 0) {
        $rest = @($names | Where-Object { -not $underTemp.Contains($_) })
        if ($rest.Count -gt 0) {
            throw (New-ArlRefusal 'R2' ('rutas de prueba mezcladas con las del equipo real; pase tambien bajo la carpeta temporal: -' + ($rest -join ', -')))
        }
    }
}

function Assert-ArlElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([System.Security.Principal.SecurityIdentifier]$script:SidBA)) {
        throw (New-ArlRefusal 'R1' 'abra PowerShell como administrador (clic derecho, Ejecutar como administrador)')
    }
}

function Assert-ArlTargetsPresent($P) {
    $missing = [System.Collections.Generic.List[string]]::new()
    # EdgePath too: the Ayuda shortcut targets it, and a missing Edge would leave a dead help icon.
    foreach ($f in @($P.ChispaExe, $P.OperatorSettings, $P.PassiveStd, $P.PassiveNorm, $P.PassiveWorkflow, $P.DosboxExe, $P.ShellDll, $P.CardSource, $P.EdgePath)) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { $missing.Add($f) }
    }
    if (Test-Path -LiteralPath $P.OperatorSettings -PathType Leaf) {
        $launcher = ''
        try {
            $j = [System.IO.File]::ReadAllText($P.OperatorSettings) | ConvertFrom-Json
            $prop = $j.PSObject.Properties['launcherPath']
            if ($null -ne $prop) { $launcher = [string]$prop.Value }
        } catch { $launcher = '' }
        if (-not $launcher) { $missing.Add($P.OperatorSettings + ' (launcherPath)') }
        else {
            $lp = Resolve-ArlTargetPath $launcher
            if (-not (Test-ArlUnder -Path $lp -Root $P.ArlRoot) -or -not (Test-Path -LiteralPath $lp -PathType Leaf)) { $missing.Add($launcher + ' (launcherPath)') }
        }
    }
    if ($missing.Count -gt 0) {
        throw (New-ArlRefusal 'R3' ('faltan archivos; no se cambia nada: ' + ($missing -join '; ')))
    }
}

function Assert-ArlIconsExtract($P) {
    $bad = [System.Collections.Generic.List[string]]::new()
    foreach ($i in (Get-ArlIconSet $P)) {
        $bmp = Get-ArlIconBitmap -File $i.Source -Index $i.Index
        if ($null -eq $bmp) { $bad.Add($i.Source + ',' + $i.Index) } else { $bmp.Dispose() }
    }
    if ($bad.Count -gt 0) { throw (New-ArlRefusal 'R4' ('no se pudo leer el icono: ' + ($bad -join '; '))) }
}

function Assert-ArlCardValid($P) {
    $bytes = [System.IO.File]::ReadAllBytes($P.CardSource)
    foreach ($b in $bytes) {
        if (-not ($b -eq 9 -or $b -eq 10 -or $b -eq 13 -or ($b -ge 32 -and $b -le 126))) {
            throw (New-ArlRefusal 'R5' 'la hoja de ayuda tiene caracteres que no son ASCII (use entidades HTML)')
        }
    }
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    foreach ($r in $P.FinalRows) {
        if ($text.IndexOf($r.Name, [System.StringComparison]::Ordinal) -lt 0) { throw (New-ArlRefusal 'R5' ('la hoja de ayuda no nombra el icono: ' + $r.Name)) }
    }
    foreach ($i in (Get-ArlIconSet $P)) {
        if ($text.IndexOf('iconos/' + $i.Png, [System.StringComparison]::Ordinal) -lt 0) { throw (New-ArlRefusal 'R5' ('la hoja de ayuda no usa iconos/' + $i.Png)) }
    }
    if ($text -match '(?i)https?:|<script') { throw (New-ArlRefusal 'R5' 'la hoja de ayuda no puede tener enlaces externos ni scripts') }
}

function Assert-ArlFolderOwnership($P, [string]$ArchiveDir) {
    foreach ($f in @($P.Tools, $P.Guide, $P.ArchiveRoot)) {
        if (Test-Path -LiteralPath $f -PathType Container) {
            $owner = Get-ArlOwnerSid $f
            if (@($script:SidBA, $script:SidSY) -notcontains $owner) {
                throw (New-ArlRefusal 'R7' ('carpeta existente con dueno no administrador: ' + $f + '; revisela y quitela a mano'))
            }
            # An admin-owned folder that still lets users write is not the protected folder the plan assumes.
            $w = @(Get-ArlWriters $f)
            if ($w.Count -gt 0) {
                throw (New-ArlRefusal 'R7' ('carpeta existente que otros usuarios pueden modificar: ' + $f + ' (' + ($w -join ', ') + '); revisela y quitela a mano'))
            }
        }
    }
    if ($ArchiveDir -and (Test-Path -LiteralPath $ArchiveDir)) { throw (New-ArlRefusal 'R7' ('ya existe ' + $ArchiveDir + '; espere un segundo y repita')) }
}

function Assert-ArlNoReparse($P) {
    # _staging holds other tools' data (its own links are not ours to judge): only its chain counts.
    if (Test-ArlReparseChain $P.Staging) { throw (New-ArlRefusal 'R6' ('enlace (junction o symlink) en ' + $P.Staging)) }
    foreach ($f in @($P.ArchiveRoot, $P.Tools, $P.Guide)) {
        if (Test-ArlReparseTree $f) { throw (New-ArlRefusal 'R6' ('enlace (junction o symlink) en ' + $f)) }
    }
    foreach ($f in @($P.PublicDesktop, $P.OperatorDesktop)) {
        if (Test-ArlReparseTree $f) { throw (New-ArlRefusal 'R6' ('enlace (junction o symlink) en ' + $f)) }
    }
}

function Assert-ArlPathTypes($P) {
    $dirs = @($P.Staging, $P.ArchiveRoot, $P.Tools, $P.Guide, $P.Icons) + @($P.GroupPaths.Values)
    foreach ($d in $dirs) {
        if (Test-Path -LiteralPath $d -PathType Leaf) { throw (New-ArlRefusal 'R8' ('se esperaba una carpeta y hay un archivo: ' + $d)) }
    }
    $files = @($P.Card) + @($P.FinalRows | ForEach-Object { Join-Path $P.PublicDesktop ($_.Name + '.lnk') })
    foreach ($i in (Get-ArlIconSet $P)) { $files += (Join-Path $P.Icons $i.Png) }
    foreach ($f in $files) {
        if (Test-Path -LiteralPath $f -PathType Container) { throw (New-ArlRefusal 'R8' ('se esperaba un archivo y hay una carpeta: ' + $f)) }
    }
}

function Read-ArlShortcut([string]$Path) {
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq '.url') {
        $target = ''
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            if ($line -match '^\s*URL\s*=\s*(.+)$') {
                $u = $Matches[1].Trim()
                if ($u -match '^(?i)file:') { try { $target = ([Uri]$u).LocalPath } catch { $target = '' } }
                else { $target = '' }
            }
        }
        return @{ Target = $target; Arguments = ''; WorkDir = ''; Icon = ''; Description = ''; WindowStyle = 1 }
    }
    if ($ext -ne '.lnk') { return $null }
    $shell = New-Object -ComObject WScript.Shell
    try {
        # CreateShortcut on an existing file only reads it; the shortcut is never saved back (contract 4.8).
        $sc = $shell.CreateShortcut($Path)
        $icon = [string]$sc.IconLocation
        $iconNorm = $icon
        $comma = $icon.LastIndexOf(',')
        if ($comma -ge 0) {
            $ipath = $icon.Substring(0, $comma)
            $idx = $icon.Substring($comma + 1)
            $iconNorm = (Resolve-ArlTargetPath $ipath) + ',' + $idx
        } elseif ($icon) {
            $iconNorm = Resolve-ArlTargetPath $icon
        }
        return @{
            Target = Resolve-ArlTargetPath ([string]$sc.TargetPath)
            Arguments = ([string]$sc.Arguments).Trim()
            WorkDir = Resolve-ArlTargetPath ([string]$sc.WorkingDirectory)
            Icon = $iconNorm
            Description = ([string]$sc.Description)
            WindowStyle = [int]$sc.WindowStyle
        }
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

# The stored final row, resolved into absolute comparison values.
function Resolve-ArlRowFields($P, $Row) {
    $icon = $Row.Icon
    $comma = $icon.LastIndexOf(',')
    if ($comma -ge 0) { $icon = (Resolve-ArlTargetPath $icon.Substring(0, $comma)) + ',' + $icon.Substring($comma + 1) }
    return @{
        Target = Resolve-ArlTargetPath $Row.Target
        Arguments = ([string]$Row.Arguments).Trim()
        WorkDir = Resolve-ArlTargetPath $Row.WorkDir
        Icon = $icon
        Description = [string]$Row.Description
        WindowStyle = 1
    }
}

function Test-ArlFieldsEqual($Actual, $Expected) {
    if ($null -eq $Actual) { return $false }
    foreach ($k in @('Target', 'Arguments', 'WorkDir', 'Icon', 'Description')) {
        if (-not [string]::Equals([string]$Actual[$k], [string]$Expected[$k], [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return ([int]$Actual.WindowStyle -eq [int]$Expected.WindowStyle)
}

# Two on-disk shortcuts are the same launcher when their meaningful fields match (duplicate detection).
function Test-ArlSameLauncher($A, $B) {
    if ($null -eq $A -or $null -eq $B) { return $false }
    foreach ($k in @('Target', 'Arguments', 'WorkDir', 'Icon')) {
        if (-not [string]::Equals([string]$A[$k], [string]$B[$k], [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

function Read-ArlItem($P, [string]$Path, [string]$Rel, [int]$Depth, [switch]$NoChildren) {
    $item = @{ Path = $Path; Leaf = [System.IO.Path]::GetFileName($Path); Rel = $Rel; Depth = $Depth
        Kind = 'file'; Ext = ''; Lnk = $null; Target = ''; Sha256 = ''; Sddl = ''; OwnerSid = ''
        Reparse = $false; Children = @(); Unreadable = $false }
    try {
        $gi = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($gi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $item.Reparse = $true }
        if ($gi.PSIsContainer) { $item.Kind = 'dir' }
        $item.Sddl = (Get-Acl -LiteralPath $Path).Sddl
        $item.OwnerSid = Get-ArlOwnerSid $Path
    } catch { $item.Unreadable = $true; return $item }
    if ($item.Kind -eq 'file') {
        $item.Ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
        try { $item.Sha256 = Get-ArlFileSha256 $Path } catch { $item.Sha256 = '' }
        if (@('.lnk', '.url') -contains $item.Ext) {
            try { $item.Lnk = Read-ArlShortcut $Path } catch { $item.Lnk = $null }
            if ($null -ne $item.Lnk) { $item.Target = $item.Lnk.Target }
        }
    } elseif (-not $NoChildren -and -not $item.Reparse) {
        $kids = [System.Collections.Generic.List[object]]::new()
        foreach ($c in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
            $kids.Add((Read-ArlItem -P $P -Path $c.FullName -Rel ($Rel + '\' + $c.Name) -Depth ($Depth + 1)))
        }
        $item.Children = $kids.ToArray()
    }
    return $item
}

function Get-ArlTopItems($P, [string]$Root, [switch]$FilesOnly) {
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $out }
    foreach ($c in @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)) {
        if ($FilesOnly -and $c.PSIsContainer) {
            $out.Add((Read-ArlItem -P $P -Path $c.FullName -Rel $c.Name -Depth 0 -NoChildren))
        } else {
            $out.Add((Read-ArlItem -P $P -Path $c.FullName -Rel $c.Name -Depth 0))
        }
    }
    return $out
}

function Get-ArlDesktopInventory($P) {
    $inv = @{ Public = @(); Piso = @(); Others = @(); Pins = @(); Accesos = @() }
    $inv.Public = @(Get-ArlTopItems -P $P -Root $P.PublicDesktop)
    if (Test-Path -LiteralPath $P.OperatorDesktop -PathType Container) {
        $inv.Piso = @(Get-ArlTopItems -P $P -Root $P.OperatorDesktop -FilesOnly)
    }
    $skip = @('Public', 'Piso', 'Default', 'Default User', 'All Users')
    if (Test-Path -LiteralPath $P.UsersRoot -PathType Container) {
        foreach ($u in @(Get-ChildItem -LiteralPath $P.UsersRoot -Force -Directory -ErrorAction SilentlyContinue)) {
            if ($skip -contains $u.Name) { continue }
            $d = Join-Path $u.FullName 'Desktop'
            if (Test-Path -LiteralPath $d -PathType Container) {
                $items = @(Get-ArlTopItems -P $P -Root $d -FilesOnly)
                if ($items.Count -gt 0) { $inv.Others += , @{ Desktop = $d; User = $u.Name; Items = $items } }
            }
        }
    }
    if (Test-Path -LiteralPath $P.PisoPins -PathType Container) { $inv.Pins = @(Get-ArlTopItems -P $P -Root $P.PisoPins -FilesOnly) }
    if (Test-Path -LiteralPath $P.Accesos -PathType Container) { $inv.Accesos = @(Get-ArlTopItems -P $P -Root $P.Accesos -FilesOnly) }
    return $inv
}

function New-ArlClass([string]$Action, [string]$Group, [string]$Note) { return @{ Action = $Action; Group = $Group; Note = $Note } }

function Get-ArlSafeLeaf([string]$Path) {
    try { return [System.IO.Path]::GetFileName($Path) } catch { return '' }
}

# A shortcut that runs a script host (cmd.exe /c x.cmd, powershell.exe -File x.ps1) is routed by the
# first .cmd/.bat/.ps1 path in its arguments; '' when there is none.
function Get-ArlScriptFromArguments([string]$Arguments) {
    if ([string]::IsNullOrWhiteSpace($Arguments)) { return '' }
    $m = [regex]::Match($Arguments, '(?i)"([^"]+\.(?:cmd|bat|ps1))"|((?:[A-Za-z]:|%[A-Za-z_]+%)[^\s"]*\.(?:cmd|bat|ps1))(?=\s|$)')
    if (-not $m.Success) { return '' }
    if ($m.Groups[1].Success) { return (Resolve-ArlTargetPath $m.Groups[1].Value) }
    return (Resolve-ArlTargetPath $m.Groups[2].Value)
}

# Target-based routing for .lnk / file:.url items (rules 3a-3e). Returns @{ Group; Tag }.
function Get-ArlTargetRule($P, [string]$Target, [string]$Leaf, [string]$Arguments = '') {
    if (@('cmd.exe', 'powershell.exe', 'pwsh.exe') -contains (Get-ArlSafeLeaf $Target)) {
        $scriptArg = Get-ArlScriptFromArguments $Arguments
        if ($scriptArg) { $Target = $scriptArg }
    }
    $tleaf = Get-ArlSafeLeaf $Target
    # Emulator in either name, or anything named or placed like the bridge, simulates values.
    if ((Test-ArlUnder -Path $Target -Root $P.Bridge) -or ($Leaf -match '(?i)Emulator') -or ($tleaf -match '(?i)Emulator|Bridge')) { return @{ Group = 'Simuladores'; Tag = 'SIMULA VALORES' } }
    if ($P.LegacyDailyTargets -contains $Target) { return @{ Group = 'Accesos-anteriores'; Tag = '' } }
    if (($P.VerificationTargets -contains $Target) -or ($P.VerificationLeaves -contains $tleaf)) { return @{ Group = 'Verificacion-y-aprobacion'; Tag = '' } }
    if (@('dosbox-x-arl.exe', 'dosbox-x.exe', 'IMPACT.EXE') -contains $tleaf) { return @{ Group = 'Diagnostico'; Tag = 'IMPACT SIN REGISTRO DE CHISPA' } }
    if (Test-ArlUnder -Path $Target -Root $P.ArlRoot) {
        $tag = ''
        if (-not (Test-Path -LiteralPath $Target)) { $tag = 'ROTO' }
        if ($tleaf -match '(?i)^Launch-ArlImpact') { $tag = ($tag + ' PUERTO SERIE SIN REVISION').Trim() }
        return @{ Group = 'Diagnostico'; Tag = $tag }
    }
    return $null
}

function Get-ArlItemClass($P, $Item, [string]$Scope) {
    $leaf = $Item.Leaf
    $isFinal = $false
    foreach ($r in $P.FinalRows) { if ([string]::Equals($leaf, ($r.Name + '.lnk'), [System.StringComparison]::OrdinalIgnoreCase)) { $isFinal = $true; $finalRow = $r } }
    if ($Scope -eq 'publico' -and $Item.Depth -eq 0 -and $isFinal) {
        $row = Resolve-ArlRowFields $P $finalRow
        if (Test-ArlFieldsEqual -Actual $Item.Lnk -Expected $row) { return (New-ArlClass 'nada' '' 'final') }
        return (New-ArlClass 'reemplazar' '' 'final drift')
    }
    if ($script:ArlKeptNames -contains $leaf) { return (New-ArlClass 'conserva' '' '') }
    if ([string]::Equals($leaf, 'desktop.ini', [System.StringComparison]::OrdinalIgnoreCase)) { return (New-ArlClass 'conserva' '' '') }
    $note = ''
    $suspect = ($leaf -match ('(?i)(' + $script:ArlTokenUnion + ')')) -or ($Item.Target -match '(?i)dosbox|IMPACT|Chispa')
    if ($Item.Kind -eq 'dir') {
        if ($Scope -eq 'piso') { $pnote = ''; if ($suspect) { $pnote = 'SOSPECHA' }; return (New-ArlClass 'desconocido' '' $pnote) }
        return (New-ArlClass 'carpeta' '' '')
    }
    if (@('.lnk', '.url') -contains $Item.Ext -and $Item.Target) {
        $rule = Get-ArlTargetRule -P $P -Target $Item.Target -Leaf $leaf -Arguments ([string]$Item.Lnk.Arguments)
        if ($null -ne $rule) { return (New-ArlClass 'mover' $rule.Group $rule.Tag) }
    }
    if ($Item.Depth -eq 0 -and (@('.cmd', '.bat', '.ps1') -contains $Item.Ext)) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
        if ($base -match ('(?i)(' + $script:ArlTokenUnion + ')')) { return (New-ArlClass 'mover' 'Diagnostico' 'PUERTO SERIE SIN REVISION') }
    }
    if ($suspect) { $note = 'SOSPECHA' }
    return (New-ArlClass 'desconocido' '' $note)
}
$script:ArlActionFields = @('seq', 'kind', 'path', 'source', 'destination', 'temp_path', 'backup',
    'sha256', 'sha256_old', 'sha256_new', 'target', 'arguments', 'fields', 'group', 'note',
    'source_owner_sid', 'source_sddl', 'existed', 'sddl_before', 'sddl_after', 'status', 'undo_reason')

function New-ArlAction([string]$Kind) {
    $a = [ordered]@{}
    foreach ($f in $script:ArlActionFields) { $a[$f] = $null }
    $a.kind = $Kind
    $a.status = 'planned'
    return $a
}

# Returns a free destination path, claiming it in a plan-scoped set so two moves never collide.
function Resolve-ArlCollision([string]$Desired, [string]$Stamp) {
    if (-not ((Test-Path -LiteralPath $Desired) -or $script:ArlPlannedPaths.Contains($Desired))) {
        [void]$script:ArlPlannedPaths.Add($Desired); return $Desired
    }
    $dir = Split-Path -Parent $Desired
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Desired)
    $ext = [System.IO.Path]::GetExtension($Desired)
    # ' (stamp)', then ' (stamp-2)', ' (stamp-3)' ... until the name is free on disk and in the plan.
    $n = 1
    while ($true) {
        $suffix = $Stamp
        if ($n -gt 1) { $suffix = $Stamp + '-' + $n }
        $alt = Join-Path $dir ($base + ' (' + $suffix + ')' + $ext)
        if (-not ((Test-Path -LiteralPath $alt) -or $script:ArlPlannedPaths.Contains($alt))) { break }
        $n++
    }
    [void]$script:ArlPlannedPaths.Add($alt)
    return $alt
}

function Add-ArlReport($Report, [string]$Bucket, [string]$Line) { [void]$Report[$Bucket].Add($Line) }

# Plans one movable shortcut (rules 3a-3e already resolved into Group/Note). Duplicates go to the archive.
function Add-ArlMove($P, $Item, [string]$Group, [string]$Note, [string]$Stamp, $Moves, $Report, $Counts) {
    $groupDir = $P.GroupPaths[$Group]
    $dest = Join-Path $groupDir $Item.Leaf
    $dup = $false
    if ($null -ne $Item.Lnk) {
        # Same launcher already in the group folder, or already planned into it earlier in this run.
        if (Test-Path -LiteralPath $dest -PathType Leaf) {
            $existing = Read-ArlShortcut $dest
            if (Test-ArlSameLauncher $existing $Item.Lnk) { $dup = $true }
        }
        if (-not $dup -and $script:ArlPlannedLaunchers.ContainsKey($dest)) {
            foreach ($planned in $script:ArlPlannedLaunchers[$dest]) { if (Test-ArlSameLauncher $planned $Item.Lnk) { $dup = $true } }
        }
        if (-not $dup) {
            if (-not $script:ArlPlannedLaunchers.ContainsKey($dest)) { $script:ArlPlannedLaunchers[$dest] = [System.Collections.Generic.List[object]]::new() }
            [void]$script:ArlPlannedLaunchers[$dest].Add($Item.Lnk)
        }
    }
    if ($dup) {
        $dest = Resolve-ArlCollision -Desired (Join-Path (Join-Path $P.ArchiveDir 'duplicados') $Item.Leaf) -Stamp $Stamp
        $a = New-ArlAction 'move'; $a.source = $Item.Path; $a.destination = $dest; $a.target = $Item.Target
        $a.group = $Group; $a.note = 'duplicado'; $a.source_owner_sid = $Item.OwnerSid; $a.source_sddl = $Item.Sddl; $a.sha256 = $Item.Sha256
        [void]$Moves.Add($a)
        # The archive is admin-only too: the moved duplicate must not keep its desktop ACL.
        $r = New-ArlAction 'acl-reset'; $r.path = $dest; [void]$Moves.Add($r)
        $Counts.archivar++
        Add-ArlReport $Report 'Archivar' ($Item.Rel + ' -> duplicados\ (' + $Note + ')')
    } else {
        $dest = Resolve-ArlCollision -Desired $dest -Stamp $Stamp
        $script:ArlGroupNeeded[$Group] = $true
        $a = New-ArlAction 'move'; $a.source = $Item.Path; $a.destination = $dest; $a.target = $Item.Target
        $a.group = $Group; $a.note = $Note; $a.source_owner_sid = $Item.OwnerSid; $a.source_sddl = $Item.Sddl; $a.sha256 = $Item.Sha256
        [void]$Moves.Add($a)
        $r = New-ArlAction 'acl-reset'; $r.path = $dest; [void]$Moves.Add($r)
        $Counts.mover++
        Add-ArlReport $Report 'Mover' ($Item.Rel + ' -> ' + $Group + '\  ' + $Note)
    }
    if ($Item.Target -and (Test-Path -LiteralPath $Item.Target) -and @(Get-ArlWriters $Item.Target).Count -gt 0) {
        $Counts.avisos++
        Add-ArlReport $Report 'Aviso' ('destino modificable por usuarios no administradores: ' + $Item.Target)
    }
}

# Recurses a desktop folder's movable descendants. Returns @{ Cleared; Unknown; Kept; Moved }.
# A folder holding a kept item is never archived, so SE CONSERVA stays true.
function Add-ArlFolderContents($P, $Item, [string]$Stamp, $Moves, $Report, $Counts) {
    $unknown = $false; $kept = $false; $moved = 0
    foreach ($c in $Item.Children) {
        if ([string]::Equals($c.Leaf, 'desktop.ini', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($c.Kind -eq 'dir') {
            $sub = Add-ArlFolderContents -P $P -Item $c -Stamp $Stamp -Moves $Moves -Report $Report -Counts $Counts
            if ($sub.Kept) { $kept = $true }
            if ($sub.Unknown) { $unknown = $true } else { $moved += $sub.Moved }
            continue
        }
        $cls = Get-ArlItemClass -P $P -Item $c -Scope 'publico'
        if ($cls.Action -eq 'mover') {
            Add-ArlMove -P $P -Item $c -Group $cls.Group -Note $cls.Note -Stamp $Stamp -Moves $Moves -Report $Report -Counts $Counts
            $moved++
        } elseif ($cls.Action -eq 'conserva') {
            $kept = $true
            Add-ArlReport $Report 'Conserva' $c.Rel
        } else {
            $unknown = $true; $Counts.desconocidos++
            if ($cls.Note -eq 'SOSPECHA') { $Counts.sospechosos++ }
            Add-ArlReport $Report 'Desconocido' ($c.Rel + ' -> ' + $c.Target + '  ' + $cls.Note)
        }
    }
    return @{ Cleared = (-not $unknown -and -not $kept); Unknown = $unknown; Kept = $kept; Moved = $moved }
}

# Emits directory actions (mkdir / acl-set / acl-reset) for one protected or plain directory.
function Add-ArlDirPlan($P, $DirActions, [string]$Path, $Sddl, [string]$Scope) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        $a = New-ArlAction 'mkdir'; $a.path = $Path; $a.existed = $false
        if ($null -ne $Sddl) { $a.sddl_after = $Sddl; $a.note = 'protected' } else { $a.note = 'plain' }
        [void]$DirActions.Add($a); return
    }
    $current = (Get-Acl -LiteralPath $Path).Sddl
    if ($null -ne $Sddl) {
        if ((ConvertTo-ArlSddlKey $current) -ne (ConvertTo-ArlSddlKey $Sddl)) {
            $a = New-ArlAction 'acl-set'; $a.path = $Path; $a.existed = $true; $a.sddl_before = $current; $a.sddl_after = $Sddl; [void]$DirActions.Add($a)
        }
    } elseif (-not (Test-ArlChildSddl $current $Scope)) {
        $a = New-ArlAction 'acl-reset'; $a.path = $Path; $a.existed = $true; $a.sddl_before = $current; [void]$DirActions.Add($a)
    }
}

function New-ArlPlan($P, $Inv, [string]$Stamp) {
    $P.ArchiveDir = Join-Path $P.ArchiveRoot $Stamp
    $script:ArlPlannedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:ArlGroupNeeded = @{}
    $script:ArlPlannedLaunchers = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Counts = New-ArlCounts
    $buckets = @('Crear', 'Reemplazar', 'Mover', 'Archivar', 'Conserva', 'Desconocido', 'Informe', 'Pendiente', 'Aviso')
    $Report = @{}; foreach ($b in $buckets) { $Report[$b] = [System.Collections.Generic.List[string]]::new() }

    $dirActions = [System.Collections.Generic.List[object]]::new()
    $cardActions = [System.Collections.Generic.List[object]]::new()
    $shortcutActions = [System.Collections.Generic.List[object]]::new()
    $moveActions = [System.Collections.Generic.List[object]]::new()
    $archiveFolderActions = [System.Collections.Generic.List[object]]::new()

    # 1. Card and icons (write only when content differs). The guide folder is needed if any of these run.
    $guideNeeded = $false
    $cardHash = Get-ArlBytesSha256 ([System.IO.File]::ReadAllBytes($P.CardSource))
    if ((-not (Test-Path -LiteralPath $P.Card -PathType Leaf)) -or ((Get-ArlFileSha256 $P.Card) -ne $cardHash)) {
        $guideNeeded = $true
        $a = New-ArlAction 'copy-card'; $a.path = $P.Card; $a.source = $P.CardSource; $a.sha256_new = $cardHash
        if (Test-Path -LiteralPath $P.Card -PathType Leaf) { $a.backup = Join-Path (Join-Path $P.ArchiveDir 'reemplazados\Guia-Operador') 'cual-uso.html'; $a.sha256_old = (Get-ArlFileSha256 $P.Card) }
        [void]$cardActions.Add($a)
        Add-ArlReport $Report 'Crear' 'Guia-Operador\cual-uso.html'
    }
    foreach ($ic in (Get-ArlIconSet $P)) {
        $pngPath = Join-Path $P.Icons $ic.Png
        $fresh = Get-ArlPixelHash (Get-ArlIconBitmap -File $ic.Source -Index $ic.Index)
        if ((-not (Test-Path -LiteralPath $pngPath -PathType Leaf)) -or ((Get-ArlPngPixelHash $pngPath) -ne $fresh)) {
            $guideNeeded = $true
            $a = New-ArlAction 'write-icon'; $a.path = $pngPath; $a.source = $ic.Source; $a.arguments = [string]$ic.Index
            if (Test-Path -LiteralPath $pngPath -PathType Leaf) { $a.backup = Join-Path (Join-Path $P.ArchiveDir 'reemplazados\Guia-Operador\iconos') $ic.Png; $a.sha256_old = (Get-ArlFileSha256 $pngPath) }
            [void]$cardActions.Add($a)
            Add-ArlReport $Report 'Crear' ('Guia-Operador\iconos\' + $ic.Png)
        }
    }

    # 2. The four final shortcuts.
    $colada = $null
    $publicByLeaf = @{}
    foreach ($it in $Inv.Public) { $publicByLeaf[$it.Leaf] = $it }
    foreach ($row in $P.FinalRows) {
        $leaf = $row.Name + '.lnk'
        $path = Join-Path $P.PublicDesktop $leaf
        $exp = Resolve-ArlRowFields $P $row
        $existing = $publicByLeaf[$leaf]
        $isColada = [string]::Equals($row.Name, $P.FinalRows[0].Name, [System.StringComparison]::Ordinal)
        if ($null -ne $existing -and (Test-ArlFieldsEqual -Actual $existing.Lnk -Expected $exp)) {
            if ($isColada) { $colada = $path }
            continue
        }
        if ($null -ne $existing) {
            $a = New-ArlAction 'replace-shortcut'; $a.path = $path
            $a.backup = Join-Path (Join-Path $P.ArchiveDir 'reemplazados\Escritorio') $leaf
            $a.sha256_old = $existing.Sha256; $a.fields = $exp; $a.target = $exp.Target; $a.arguments = $exp.Arguments
            [void]$shortcutActions.Add($a); $Counts.reemplazar++
            Add-ArlReport $Report 'Reemplazar' ($leaf + ' -> ' + $exp.Target)
        } else {
            $a = New-ArlAction 'create-shortcut'; $a.path = $path
            $a.fields = $exp; $a.target = $exp.Target; $a.arguments = $exp.Arguments
            [void]$shortcutActions.Add($a); $Counts.crear++
            Add-ArlReport $Report 'Crear' ($leaf + ' -> ' + $exp.Target)
        }
        if ($isColada) { $colada = $path }
    }

    # 3. Moves: public top level, folders, then Piso desktop.
    foreach ($it in $Inv.Public) {
        $cls = Get-ArlItemClass -P $P -Item $it -Scope 'publico'
        switch ($cls.Action) {
            'nada' { }
            'reemplazar' { }
            'conserva' { Add-ArlReport $Report 'Conserva' $it.Leaf }
            'mover' { Add-ArlMove -P $P -Item $it -Group $cls.Group -Note $cls.Note -Stamp $Stamp -Moves $moveActions -Report $Report -Counts $Counts }
            'carpeta' {
                $res = Add-ArlFolderContents -P $P -Item $it -Stamp $Stamp -Moves $moveActions -Report $Report -Counts $Counts
                $tokenMatch = $it.Leaf -match ('(?i)(' + $script:ArlTokenUnion + ')')
                if ($res.Cleared -and ($res.Moved -gt 0 -or $tokenMatch)) {
                    $dest = Resolve-ArlCollision -Desired (Join-Path (Join-Path $P.ArchiveDir 'carpetas-vacias') $it.Leaf) -Stamp $Stamp
                    $a = New-ArlAction 'archive-folder'; $a.source = $it.Path; $a.destination = $dest; $a.source_owner_sid = $it.OwnerSid; $a.source_sddl = $it.Sddl
                    [void]$archiveFolderActions.Add($a); $Counts.archivar++
                    Add-ArlReport $Report 'Archivar' ($it.Leaf + '\ -> carpetas-vacias\')
                } elseif ($res.Unknown) {
                    $Counts.avisos++
                    Add-ArlReport $Report 'Aviso' ('carpeta con elementos desconocidos, se deja: ' + $it.Leaf)
                } elseif ($res.Kept) {
                    $Counts.avisos++
                    Add-ArlReport $Report 'Aviso' ('carpeta con elementos que se conservan, se deja: ' + $it.Leaf)
                } elseif ($res.Moved -eq 0) {
                    $Counts.desconocidos++
                    Add-ArlReport $Report 'Desconocido' ($it.Leaf + '\ (carpeta)')
                }
            }
            'desconocido' {
                $Counts.desconocidos++
                if ($cls.Note -eq 'SOSPECHA') { $Counts.sospechosos++ }
                Add-ArlReport $Report 'Desconocido' ($it.Leaf + ' -> ' + $it.Target + '  ' + $cls.Note)
            }
        }
    }
    foreach ($it in $Inv.Piso) {
        $cls = Get-ArlItemClass -P $P -Item $it -Scope 'piso'
        if ($cls.Action -eq 'mover') { Add-ArlMove -P $P -Item $it -Group $cls.Group -Note $cls.Note -Stamp $Stamp -Moves $moveActions -Report $Report -Counts $Counts }
        elseif ($cls.Action -eq 'conserva') { Add-ArlReport $Report 'Conserva' ('Piso: ' + $it.Leaf) }
        elseif ($cls.Action -eq 'desconocido') { $Counts.desconocidos++; if ($cls.Note -eq 'SOSPECHA') { $Counts.sospechosos++ }; Add-ArlReport $Report 'Desconocido' ('Piso: ' + $it.Leaf) }
    }

    # 4. Report-only scopes (never mutated).
    foreach ($od in $Inv.Others) {
        foreach ($it in $od.Items) {
            if (@('.lnk', '.url') -contains $it.Ext -and $it.Target -and ($null -ne (Get-ArlTargetRule -P $P -Target $it.Target -Leaf $it.Leaf -Arguments ([string]$it.Lnk.Arguments)))) {
                Add-ArlReport $Report 'Informe' ($od.User + ': ' + $it.Leaf + ' -> ' + $it.Target)
            }
        }
    }
    foreach ($it in $Inv.Pins) {
        if (@('.lnk', '.url') -contains $it.Ext -and $it.Target -and ($null -ne (Get-ArlTargetRule -P $P -Target $it.Target -Leaf $it.Leaf -Arguments ([string]$it.Lnk.Arguments)))) {
            $Counts.pendientes_manuales++
            Add-ArlReport $Report 'Pendiente' ('Barra de tareas de Piso: ' + $it.Leaf + ' -> ' + $it.Target + ' (desanclar a mano)')
        }
    }
    foreach ($it in $Inv.Accesos) { Add-ArlReport $Report 'Informe' ('Administradores\Accesos: ' + $it.Leaf) }

    # Piso read access on kept targets (AVISO only; R5 already proved presence).
    foreach ($t in @($P.ChispaExe, $P.PassiveStd, $P.PassiveNorm, $P.Card)) {
        if ((Test-Path -LiteralPath $t) -and -not (Test-ArlPisoCanRead $t)) {
            $Counts.avisos++
            Add-ArlReport $Report 'Aviso' ('sin permiso de lectura para usuarios (Piso): ' + $t)
        }
    }

    # 5. Directory actions, prepended now that we know which groups and the guide are needed.
    if ($script:ArlGroupNeeded.Keys.Count -gt 0) { Add-ArlDirPlan -P $P -DirActions $dirActions -Path $P.Tools -Sddl $script:SddlAdminOnly -Scope 'raiz' }
    foreach ($g in $script:ArlGroups) {
        if ($script:ArlGroupNeeded[$g]) { Add-ArlDirPlan -P $P -DirActions $dirActions -Path $P.GroupPaths[$g] -Sddl $null -Scope 'herramientas' }
    }
    if ($guideNeeded) {
        Add-ArlDirPlan -P $P -DirActions $dirActions -Path $P.Guide -Sddl $script:SddlGuide -Scope 'guia'
        Add-ArlDirPlan -P $P -DirActions $dirActions -Path $P.Icons -Sddl $null -Scope 'guia'
    }

    # 6. Assemble in contract order and number the sequence.
    $ordered = [System.Collections.Generic.List[object]]::new()
    foreach ($a in $dirActions) { [void]$ordered.Add($a) }
    foreach ($a in $cardActions) { [void]$ordered.Add($a) }
    foreach ($a in $shortcutActions) { [void]$ordered.Add($a) }
    foreach ($a in $moveActions) { [void]$ordered.Add($a) }
    foreach ($a in $archiveFolderActions) { [void]$ordered.Add($a) }
    $seq = 1
    foreach ($a in $ordered) { $a.seq = $seq; $seq++ }
    return @{ Actions = $ordered; Counts = $Counts; Report = $Report; Colada = $colada }
}

function Write-ArlReport($Report, [string]$FechaModo) {
    Write-ArlLine ('REVISION ' + $FechaModo)
    $map = [ordered]@{ Crear = 'SE CREA'; Reemplazar = 'SE REEMPLAZA'; Mover = 'SE MUEVE'; Archivar = 'SE ARCHIVA'
        Conserva = 'SE CONSERVA'; Desconocido = 'DESCONOCIDO (no se toca)'; Informe = 'SOLO INFORME'; Pendiente = 'PENDIENTE MANUAL'; Aviso = 'AVISO' }
    foreach ($k in $map.Keys) {
        foreach ($line in $Report[$k]) { Write-ArlLine ($map[$k].PadRight(24) + $line) }
    }
}
# The single chokepoint for every filesystem or ACL mutation. Nothing else in the file writes, moves,
# deletes, sets an ACL or saves a shortcut; the CI test proves that by AST extent. -WhatIf makes the
# first call return $false (M10), which is how a dry run of -Apply stops before touching anything.
function Invoke-ArlAction {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [hashtable]$P,
        [string]$Op,
        [string]$Path,
        [string]$Destination = '',
        [string]$Sddl = '',
        [string]$OwnerSid = '',
        [hashtable]$Fields = $null,
        [byte[]]$Bytes = $null,
        [string]$TempPath = ''
    )
    if (-not $PSCmdlet.ShouldProcess($Path, $Op)) { return $false }

    # Guard every path we are about to WRITE (a copy reads its source, so only its destination is guarded).
    $targets = [System.Collections.Generic.List[string]]::new()
    if ($Op -eq 'copy-file') { [void]$targets.Add($Destination) }
    elseif ($Op -like 'move-*') { [void]$targets.Add($Path); [void]$targets.Add($Destination) }
    else { [void]$targets.Add($Path); if ($TempPath) { [void]$targets.Add($TempPath) } }
    $allowed = @($P.WriteRoots)
    if ($Op -like 'mkdir*') { $allowed = $allowed + @(@{ Path = $P.Staging; AllowEqual = $true }) }
    $stRoot = $env:ARL_DESKTOP_SELFTEST_ROOT
    foreach ($t in $targets) {
        if ([string]::IsNullOrEmpty($t)) { throw ('ruta vacia para ' + $Op) }
        if (Test-ArlDotDot $t) { throw ('ruta con .. no permitida: ' + $t) }
        foreach ($n in $P.NeverRoots) { if (Test-ArlUnder -Path $t -Root $n -AllowEqual) { throw ('ruta protegida (no se toca): ' + $t) } }
        if (-not (Test-ArlUnderAny -Path $t -Roots $allowed)) { throw ('ruta fuera de las carpetas permitidas: ' + $t) }
        if ($stRoot -and -not (Test-ArlUnder -Path $t -Root (Get-ArlLongPath $stRoot) -AllowEqual)) { throw ('autoprueba: ruta fuera del arbol temporal: ' + $t) }
    }

    switch ($Op) {
        'mkdir-protected' {
            # CreateDirectory silently returns an existing folder with its old ACL; a folder that appeared
            # between plan and apply (a race) must stop the run instead of being trusted as protected.
            if (Test-Path -LiteralPath $Path) { throw ('ya existe la carpeta: ' + $Path) }
            $ds = New-Object System.Security.AccessControl.DirectorySecurity
            $ds.SetSecurityDescriptorSddlForm($Sddl)
            if ($PSVersionTable.PSEdition -eq 'Core') { [void][System.IO.FileSystemAclExtensions]::CreateDirectory($ds, $Path) }
            else { [void][System.IO.Directory]::CreateDirectory($Path, $ds) }
            & icacls $Path /setowner '*S-1-5-32-544' /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('icacls setowner fallo (' + $LASTEXITCODE + '): ' + $Path) }
            if ((ConvertTo-ArlSddlKey (Get-Acl -LiteralPath $Path).Sddl) -ne (ConvertTo-ArlSddlKey $Sddl)) { throw ('la carpeta no quedo con los permisos pedidos: ' + $Path) }
        }
        'mkdir-plain' { [void][System.IO.Directory]::CreateDirectory($Path) }
        'move-file' {
            $a = 0
            while ($true) {
                try { [System.IO.File]::Move($Path, $Destination); break }
                catch [System.IO.IOException] {
                    if ($_.Exception.HResult -eq -2147024864 -and $a -lt 5) { $a++; Start-Sleep -Milliseconds 200; continue }
                    throw
                }
            }
        }
        'move-dir' {
            $a = 0
            while ($true) {
                try { [System.IO.Directory]::Move($Path, $Destination); break }
                catch [System.IO.IOException] {
                    if ($_.Exception.HResult -eq -2147024864 -and $a -lt 5) { $a++; Start-Sleep -Milliseconds 200; continue }
                    throw
                }
            }
        }
        'copy-file' { [System.IO.File]::Copy($Path, $Destination, $false) }
        'write-new' {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
            try { $fs.Write($Bytes, 0, $Bytes.Length) } finally { $fs.Dispose() }
        }
        'write-replace' {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('write-replace requiere un archivo existente: ' + $Path) }
            try {
                $fs = [System.IO.File]::Open($TempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
                try { $fs.Write($Bytes, 0, $Bytes.Length) } finally { $fs.Dispose() }
                # A scanner or indexer holding the manifest for a moment is a sharing/lock violation, not a failure.
                # No backup is [NullString]::Value: PowerShell hands $null to a string parameter as "", which
                # Replace refuses as a path ("The path is not of a legal form").
                $a = 0
                while ($true) {
                    try { [System.IO.File]::Replace($TempPath, $Path, [NullString]::Value); break }
                    catch [System.IO.IOException] {
                        if ((@(-2147024864, -2147024863) -contains $_.Exception.HResult) -and $a -lt 5) { $a++; Start-Sleep -Milliseconds 200; continue }
                        throw
                    }
                }
            } finally {
                if (Test-Path -LiteralPath $TempPath -PathType Leaf) { [System.IO.File]::Delete($TempPath) }
            }
        }
        'delete-file' { [System.IO.File]::Delete($Path) }
        'delete-dir' { [System.IO.Directory]::Delete($Path, $false) }
        'acl-reset' {
            & icacls $Path /reset /T /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('icacls /reset fallo (' + $LASTEXITCODE + '): ' + $Path) }
            & icacls $Path /setowner '*S-1-5-32-544' /T /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('icacls /setowner fallo (' + $LASTEXITCODE + '): ' + $Path) }
        }
        'set-sd' {
            $ds = New-Object System.Security.AccessControl.DirectorySecurity
            $ds.SetSecurityDescriptorSddlForm($Sddl)
            $di = Get-Item -LiteralPath $Path -Force
            if ($PSVersionTable.PSEdition -eq 'Core') { [System.IO.FileSystemAclExtensions]::SetAccessControl($di, $ds) }
            else { $di.SetAccessControl($ds) }
        }
        'set-dacl' {
            # Undo of acl-set: only the DACL (and its protection flag) goes back; the owner is a separate
            # set-owner step, because writing an owner we do not hold as a privilege fails on some hosts.
            $ds = New-Object System.Security.AccessControl.DirectorySecurity
            $ds.SetSecurityDescriptorSddlForm($Sddl, [System.Security.AccessControl.AccessControlSections]::Access)
            $di = Get-Item -LiteralPath $Path -Force
            if ($PSVersionTable.PSEdition -eq 'Core') { [System.IO.FileSystemAclExtensions]::SetAccessControl($di, $ds) }
            else { $di.SetAccessControl($ds) }
        }
        'set-owner' {
            $sid = if ($OwnerSid) { $OwnerSid } else { 'S-1-5-32-544' }
            & icacls $Path /setowner ('*' + $sid) /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('icacls /setowner fallo (' + $LASTEXITCODE + '): ' + $Path) }
        }
        'restore-acl' {
            # Undo of a move: re-inherit from the destination desktop and hand ownership back to the SID the
            # item had before it was moved (not BA like acl-reset). The caller then compares the result with
            # the recorded SDDL by semantic key (ConvertTo-ArlSddlKey), not byte for byte.
            & icacls $Path /reset /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('icacls /reset fallo (' + $LASTEXITCODE + '): ' + $Path) }
            $sid = if ($OwnerSid) { $OwnerSid } else { 'S-1-5-32-544' }
            & icacls $Path /setowner ('*' + $sid) /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('icacls /setowner fallo (' + $LASTEXITCODE + '): ' + $Path) }
        }
        'save-shortcut' {
            if (Test-Path -LiteralPath $Path) { throw ('ya existe el acceso directo: ' + $Path) }
            $shell = New-Object -ComObject WScript.Shell
            try {
                $sc = $shell.CreateShortcut($Path)
                $sc.TargetPath = [string]$Fields.Target
                $sc.Arguments = [string]$Fields.Arguments
                $sc.WorkingDirectory = [string]$Fields.WorkDir
                if ($Fields.Icon) { $sc.IconLocation = [string]$Fields.Icon }
                $sc.Description = [string]$Fields.Description
                $sc.WindowStyle = 1
                $sc.Save()
            } finally { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
        }
        default { throw ('operacion desconocida: ' + $Op) }
    }
    return $true
}

# Resets one child of a protected folder back to inherited ACLs + owner BA. The plan emits an acl-reset
# action per moved item; this is its executor. (M04 target: a mutant that also resets $P.Tools breaks C10.)
function Reset-ArlChildAcl($P, [string]$Parent, [string]$Leaf) {
    return (Invoke-ArlAction -P $P -Op 'acl-reset' -Path (Join-Path $Parent $Leaf))
}

function Test-ArlPisoCanRead([string]$Path) {
    try { $acl = Get-Acl -LiteralPath $Path } catch { return $true }
    $need = [int][System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    foreach ($r in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        $sid = $r.IdentityReference.Value
        $isUser = (@('S-1-5-32-545', 'S-1-5-4', 'S-1-5-11', 'S-1-1-0') -contains $sid) -or $sid.StartsWith('S-1-5-21')
        if ($isUser -and (([int]$r.FileSystemRights -band $need) -eq $need)) { return $true }
    }
    return $false
}

# Extracts icon $Index from $File as a Bitmap (48px), or $null. Prefers SHDefExtractIconW; falls back to
# ExtractIconExW. The caller disposes the bitmap.
function Get-ArlIconBitmap {
    param([string]$File, [int]$Index)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $null }
    Import-ArlNative
    Add-Type -AssemblyName System.Drawing
    $large = [IntPtr]::Zero; $small = [IntPtr]::Zero; $hicon = [IntPtr]::Zero
    try {
        $hr = [ArlDesktop.Native]::SHDefExtractIconW($File, $Index, 0, [ref]$large, [ref]$small, 1048624)
        if ($hr -eq 0 -and $large -ne [IntPtr]::Zero) { $hicon = $large }
        else {
            $la = New-Object IntPtr[] 1; $sa = New-Object IntPtr[] 1
            $n = [ArlDesktop.Native]::ExtractIconExW($File, $Index, $la, $sa, 1)
            if ($n -gt 0 -and $la[0] -ne [IntPtr]::Zero) { $large = $la[0]; $hicon = $large }
            elseif ($n -gt 0 -and $sa[0] -ne [IntPtr]::Zero) { $small = $sa[0]; $hicon = $small }
        }
        if ($hicon -eq [IntPtr]::Zero) { return $null }
        $ico = [System.Drawing.Icon]::FromHandle($hicon)
        try { return $ico.ToBitmap() } finally { $ico.Dispose() }
    } finally {
        if ($large -ne [IntPtr]::Zero) { [void][ArlDesktop.Native]::DestroyIcon($large) }
        if ($small -ne [IntPtr]::Zero -and $small -ne $large) { [void][ArlDesktop.Native]::DestroyIcon($small) }
    }
}

# A hash of the raw ARGB pixels (not the file bytes), so two visually identical PNGs compare equal.
# The byte copy is reached by reflection to keep the array-copy token out of everything but the chokepoint.
# The buffer comes from Array.CreateInstance, not New-Object: New-Object output is PSObject-wrapped, and
# MethodInfo.Invoke does not unwrap it (both engines refuse: PSObject cannot be converted to Byte[]).
function Get-ArlPixelHash($Bitmap) {
    if ($null -eq $Bitmap) { return '' }
    Add-Type -AssemblyName System.Drawing
    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $len = [Math]::Abs($data.Stride) * $Bitmap.Height
        $buf = [System.Array]::CreateInstance([byte], $len)
        $m = [System.Runtime.InteropServices.Marshal].GetMethod('Copy', [type[]]@([IntPtr], [byte[]], [int], [int]))
        [void]$m.Invoke($null, @($data.Scan0, $buf, 0, $len))
        return ($Bitmap.Width.ToString() + 'x' + $Bitmap.Height.ToString() + ':' + (Get-ArlBytesSha256 $buf))
    } finally { $Bitmap.UnlockBits($data) }
}

function Get-ArlPngPixelHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    Add-Type -AssemblyName System.Drawing
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ms = New-Object System.IO.MemoryStream (, $bytes)
    try {
        $bmp = New-Object System.Drawing.Bitmap $ms
        try { return (Get-ArlPixelHash $bmp) } finally { $bmp.Dispose() }
    } finally { $ms.Dispose() }
}

# PNG bytes for one icon (source + index). Save() to a MemoryStream is not a filesystem mutation, so the
# byte-producing path stays outside the chokepoint; the bytes are written to disk only via write-new.
function Export-ArlIconPng([string]$Source, [int]$Index) {
    $bmp = Get-ArlIconBitmap -File $Source -Index $Index
    if ($null -eq $bmp) { throw ('no se pudo extraer el icono: ' + $Source + ',' + $Index) }
    try {
        $ms = New-Object System.IO.MemoryStream
        try { $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); return $ms.ToArray() } finally { $ms.Dispose() }
    } finally { $bmp.Dispose() }
}
function New-ArlManifest($P, $Actions, [string]$CardSha) {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return [ordered]@{
        schema = 'arl-operator-desktop-manifest-v1'
        created_at_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        computer = [string]$env:COMPUTERNAME
        user = [string]$id.Name
        engine = ($PSVersionTable.PSEdition + ' ' + $PSVersionTable.PSVersion.ToString())
        script_path = [string]$PSCommandPath
        script_sha256 = (Get-ArlFileSha256 $PSCommandPath)
        card_sha256 = $CardSha
        roots = [ordered]@{ public_desktop = $P.PublicDesktop; operator_desktop = $P.OperatorDesktop; tools_root = $P.Tools; guide_root = $P.Guide; archive_dir = $P.ArchiveDir }
        state = 'planning'
        archive_created = @()
        stop_reason = ''
        actions = @($Actions)
    }
}

# -Initial creates the file (write-new); every later call replaces it in place (write-replace) and then
# re-sets the owner to BUILTIN\Administrators so -Undo's trust check accepts it. (M03 target: the initial.)
function Write-ArlManifest($P, $Manifest, [string]$Path, [switch]$Initial) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-ArlJson $Manifest))
    if ($Initial) { Invoke-ArlAction -P $P -Op 'write-new' -Path $Path -Bytes $bytes | Out-Null }
    else {
        # A per-write temp name: a .tmp left behind by a killed run can never block the next write.
        $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        Invoke-ArlAction -P $P -Op 'write-replace' -Path $Path -TempPath $tmp -Bytes $bytes | Out-Null
    }
    Invoke-ArlAction -P $P -Op 'set-owner' -Path $Path | Out-Null
}

# The write on a path that is already failing (error, time limit, undo step). A second exception here must
# not hide the first one or leave the loop without a result line; the last good manifest stays on disk.
function Write-ArlManifestSafe($P, $Manifest, [string]$Path) {
    try { Write-ArlManifest -P $P -Manifest $Manifest -Path $Path }
    catch { Write-ArlLine ('AVISO  no se pudo guardar el manifiesto: ' + [string]$_.Exception.Message) }
}

# Self-test only: ends the process at a named point inside an action, to prove -Undo recovers a run that
# died between two steps of one action. Inert unless the self-test root is set.
function Invoke-ArlTestKill([string]$Point) {
    if ($env:ARL_DESKTOP_SELFTEST_ROOT -and $env:ARL_DESKTOP_FAIL_INSIDE_ACTION -eq $Point) { [Environment]::Exit(9) }
}

function Confirm-ArlParent($P, [string]$ChildPath) {
    $dir = Split-Path -Parent $ChildPath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { Invoke-ArlAction -P $P -Op 'mkdir-plain' -Path $dir | Out-Null }
}

# Preserves an item we are about to overwrite by moving it into the archive first. Shared by the card,
# the icons and the shortcut-replace path so there is one move-then-keep line to reason about (M14 target).
function Move-ArlExistingToBackup($P, [string]$Path, [string]$Backup) {
    Confirm-ArlParent -P $P -ChildPath $Backup
    return (Invoke-ArlAction -P $P -Op 'move-file' -Path $Path -Destination $Backup)
}

# Builds the shortcut in the archive, verifies its fields round-trip, moves it onto the public desktop and
# resets its ACL so it inherits (BU read) from the desktop.
function Set-ArlCreateShortcut($P, $Action) {
    $finalLeaf = Split-Path -Leaf $Action.path
    $nuevo = Join-Path (Join-Path $P.ArchiveDir 'nuevos') $finalLeaf
    Confirm-ArlParent -P $P -ChildPath $nuevo
    Invoke-ArlAction -P $P -Op 'save-shortcut' -Path $nuevo -Fields $Action.fields | Out-Null
    $back = Read-ArlShortcut $nuevo
    if (-not (Test-ArlFieldsEqual -Actual $back -Expected $Action.fields)) { throw ('el acceso directo no coincide tras crearlo: ' + $finalLeaf) }
    # Recorded before the move so a run that dies after it still lets -Undo recognise its own file.
    $Action.sha256_new = Get-ArlFileSha256 $nuevo
    Invoke-ArlAction -P $P -Op 'move-file' -Path $nuevo -Destination $Action.path | Out-Null
    Invoke-ArlTestKill 'creado-sin-acl'
    Reset-ArlChildAcl -P $P -Parent $P.PublicDesktop -Leaf $finalLeaf | Out-Null
    $Action.sha256_new = Get-ArlFileSha256 $Action.path
}

function Invoke-ArlExecuteAction($P, $Action) {
    switch ($Action.kind) {
        'mkdir' {
            if ($Action.note -eq 'protected') { Invoke-ArlAction -P $P -Op 'mkdir-protected' -Path $Action.path -Sddl $Action.sddl_after | Out-Null }
            else { Invoke-ArlAction -P $P -Op 'mkdir-plain' -Path $Action.path | Out-Null }
            $Action.sddl_after = (Get-Acl -LiteralPath $Action.path).Sddl
        }
        'acl-set' {
            Invoke-ArlAction -P $P -Op 'set-sd' -Path $Action.path -Sddl $Action.sddl_after | Out-Null
            $Action.sddl_after = (Get-Acl -LiteralPath $Action.path).Sddl
        }
        'acl-reset' {
            $dir = Split-Path -Parent $Action.path
            $leaf = Split-Path -Leaf $Action.path
            Reset-ArlChildAcl -P $P -Parent $dir -Leaf $leaf | Out-Null
            $Action.sddl_after = (Get-Acl -LiteralPath $Action.path).Sddl
        }
        'copy-card' {
            if ($Action.backup) { Move-ArlExistingToBackup -P $P -Path $Action.path -Backup $Action.backup | Out-Null }
            Invoke-ArlAction -P $P -Op 'copy-file' -Path $Action.source -Destination $Action.path | Out-Null
            $Action.sha256_new = Get-ArlFileSha256 $Action.path
        }
        'write-icon' {
            if ($Action.backup) { Move-ArlExistingToBackup -P $P -Path $Action.path -Backup $Action.backup | Out-Null }
            $bytes = Export-ArlIconPng -Source $Action.source -Index ([int]$Action.arguments)
            Invoke-ArlAction -P $P -Op 'write-new' -Path $Action.path -Bytes $bytes | Out-Null
            $Action.sha256_new = Get-ArlFileSha256 $Action.path
        }
        'create-shortcut' { Set-ArlCreateShortcut -P $P -Action $Action }
        'replace-shortcut' {
            # replace: keep the drifted original in the archive, then write the correct shortcut in its place
            $prev = $Action.backup
            Move-ArlExistingToBackup -P $P -Path $Action.path -Backup $prev | Out-Null
            Invoke-ArlTestKill 'respaldado'
            Set-ArlCreateShortcut -P $P -Action $Action
        }
        'move' {
            Confirm-ArlParent -P $P -ChildPath $Action.destination
            Invoke-ArlAction -P $P -Op 'move-file' -Path $Action.source -Destination $Action.destination | Out-Null
            Invoke-ArlTestKill 'movido'
            $Action.sha256 = Get-ArlFileSha256 $Action.destination
        }
        'archive-folder' {
            Confirm-ArlParent -P $P -ChildPath $Action.destination
            Invoke-ArlAction -P $P -Op 'move-dir' -Path $Action.source -Destination $Action.destination | Out-Null
        }
        default { throw ('accion desconocida: ' + $Action.kind) }
    }
}

# Executes the plan under a crash-safe manifest. Returns @{ Status; Manifest; Partial }.
#   status aplicado           everything applied and re-verified
#   status cambios-pendientes -WhatIf: the first mutation returned $false, nothing was written
#   status error              partial application; the manifest is left for -Undo
function Invoke-ArlApply($P, $Plan, [string]$CardSha) {
    $actions = @($Plan.Actions)
    if ($actions.Count -eq 0) { return @{ Status = 'sin-cambios'; Manifest = $null; Partial = $false } }

    # The archive root (desktop-archive) must itself carry the admin-only SDDL exactly (C10), not the
    # inherited ACL a bare directory create of the timestamp folder would leave on it. Create it protected
    # first when missing; then the per-run timestamp folder, also protected.
    if (-not (Test-Path -LiteralPath $P.ArchiveRoot -PathType Container)) {
        if (-not (Invoke-ArlAction -P $P -Op 'mkdir-protected' -Path $P.ArchiveRoot -Sddl $script:SddlAdminOnly)) {
            return @{ Status = 'cambios-pendientes'; Manifest = $null; Partial = $false }
        }
    }
    $archiveExisted = Test-Path -LiteralPath $P.ArchiveDir -PathType Container
    if (-not (Invoke-ArlAction -P $P -Op 'mkdir-protected' -Path $P.ArchiveDir -Sddl $script:SddlAdminOnly)) {
        return @{ Status = 'cambios-pendientes'; Manifest = $null; Partial = $false }
    }
    $manifest = New-ArlManifest -P $P -Actions $actions -CardSha $CardSha
    $manifest.archive_created = @([ordered]@{ path = $P.ArchiveDir; existed = $archiveExisted })
    $manifest.state = 'applying'
    $manifestPath = Join-Path $P.ArchiveDir 'move-manifest.json'
    Write-ArlManifest -P $P -Manifest $manifest -Path $manifestPath -Initial

    # The time limit scales with the plan (each action is a manifest write plus one or two file operations,
    # so a large desktop on a slow disk is not cut off halfway); it only stops between actions.
    $deadline = (Get-Date).AddSeconds(60 + 10 * $actions.Count)
    $failAfter = 0
    if ($env:ARL_DESKTOP_SELFTEST_ROOT -and $env:ARL_DESKTOP_FAIL_AFTER_ACTION) { $failAfter = [int]$env:ARL_DESKTOP_FAIL_AFTER_ACTION }
    $done = 0
    foreach ($a in $actions) {
        if ((Get-Date) -gt $deadline) {
            $manifest.stop_reason = 'tiempo'; $manifest.state = 'failed-partial'
            Write-ArlManifestSafe -P $P -Manifest $manifest -Path $manifestPath
            return @{ Status = 'error'; Manifest = $manifestPath; Partial = $true }
        }
        # Both manifest writes sit inside the try: a write that fails after the action ran still ends in a
        # failed-partial manifest and a result line, never in an uncaught error with the state left at applying.
        try {
            $a.status = 'in-progress'
            Write-ArlManifest -P $P -Manifest $manifest -Path $manifestPath
            Invoke-ArlExecuteAction -P $P -Action $a
            $a.status = 'done'
            Write-ArlManifest -P $P -Manifest $manifest -Path $manifestPath
        } catch {
            if ([string]$a.status -ne 'done') { $a.status = 'failed'; $a.undo_reason = [string]$_.Exception.Message }
            $manifest.stop_reason = 'error'; $manifest.state = 'failed-partial'
            Write-ArlLine ('ERROR  ' + [string]$a.seq + ' ' + [string]$a.kind + ': ' + [string]$_.Exception.Message)
            Write-ArlManifestSafe -P $P -Manifest $manifest -Path $manifestPath
            return @{ Status = 'error'; Manifest = $manifestPath; Partial = $true }
        }
        $done++
        if ($failAfter -gt 0 -and $done -ge $failAfter) {
            $manifest.stop_reason = 'prueba'; $manifest.state = 'failed-partial'
            Write-ArlManifestSafe -P $P -Manifest $manifest -Path $manifestPath
            return @{ Status = 'error'; Manifest = $manifestPath; Partial = $true }
        }
    }
    $manifest.state = 'applied'; $manifest.stop_reason = ''
    Write-ArlManifest -P $P -Manifest $manifest -Path $manifestPath
    return @{ Status = 'aplicado'; Manifest = $manifestPath; Partial = $false }
}
$script:ArlKnownKinds = @('mkdir', 'acl-set', 'acl-reset', 'copy-card', 'write-icon', 'create-shortcut', 'replace-shortcut', 'move', 'archive-folder')

# Every applied manifest under the archive root, oldest first: @{ Ts; Path; State }.
function Get-ArlManifests($P) {
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $P.ArchiveRoot -PathType Container)) { return @($out) }
    foreach ($d in @(Get-ChildItem -LiteralPath $P.ArchiveRoot -Force -Directory -ErrorAction SilentlyContinue)) {
        if ($d.Name -notmatch '^\d{8}-\d{6}$') { continue }
        $m = Join-Path $d.FullName 'move-manifest.json'
        if (-not (Test-Path -LiteralPath $m -PathType Leaf)) { continue }
        $state = ''
        try { $j = [System.IO.File]::ReadAllText($m) | ConvertFrom-Json; $state = [string]$j.state } catch { continue }
        [void]$out.Add(@{ Ts = $d.Name; Path = $m; State = $state })
    }
    # The key goes through a script block: Windows PowerShell 5.1 Sort-Object does not read a hashtable key by
    # property name, so -Property Ts left the order scrambled and LIFO named the wrong newest run (M24, C12).
    return @($out | Sort-Object -Property { [string]$_.Ts })
}

# A run killed mid-apply or mid-undo leaves its manifest at applying or undoing; those stay reversible, and
# a repeat -Undo on undone-partial retries what was skipped. (M21: dropping applying strands a killed run.)
$script:ArlReversibleStates = @('applying', 'applied', 'failed-partial', 'undoing', 'undone-partial')

# Chooses the manifest to reverse. -Manifest must name the newest eligible one (LIFO, R10); with no
# parameter the newest eligible is taken. Returns @{ None; Path }.
function Select-ArlManifest($P, [string]$ManifestParam) {
    $all = @(Get-ArlManifests $P)
    $eligible = @($all | Where-Object { $script:ArlReversibleStates -contains $_.State })
    if ($ManifestParam) {
        $mp = Get-ArlLongPath $ManifestParam
        $match = $null
        foreach ($e in $all) { if ([string]::Equals((Get-ArlLongPath $e.Path), $mp, [System.StringComparison]::OrdinalIgnoreCase)) { $match = $e } }
        if ($null -eq $match) { throw (New-ArlRefusal 'R11' ('el manifiesto indicado no existe en ' + $P.ArchiveRoot)) }
        if ($script:ArlReversibleStates -notcontains $match.State) { throw (New-ArlRefusal 'R11' ('el manifiesto indicado no es reversible (estado ' + $match.State + ')')) }
        if ($eligible.Count -gt 0 -and $match.Ts -ne $eligible[-1].Ts) { throw (New-ArlRefusal 'R10' ('hay un respaldo mas reciente sin deshacer; deshaga primero ' + $eligible[-1].Ts)) }
        return @{ None = $false; Path = $match.Path }
    }
    if ($eligible.Count -eq 0) { return @{ None = $true; Path = $null } }
    return @{ None = $false; Path = $eligible[-1].Path }
}

# Any failure here means exit 2, rechazado, nothing moved (R11; a stale-LIFO -Manifest is R10 earlier).
function Assert-ArlManifestTrusted($P, [string]$ManifestPath, $Manifest) {
    $tsDir = Split-Path -Parent $ManifestPath
    $archiveParent = Split-Path -Parent $tsDir
    $tsName = Split-Path -Leaf $tsDir
    if ($tsName -notmatch '^\d{8}-\d{6}$') { throw (New-ArlRefusal 'R11' ('carpeta de respaldo con nombre invalido: ' + $tsName)) }
    $expected = Join-Path (Join-Path $P.ArchiveRoot $tsName) 'move-manifest.json'
    if (-not [string]::Equals((Get-ArlLongPath $ManifestPath), (Get-ArlLongPath $expected), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-ArlRefusal 'R11' ('el manifiesto no esta en la ruta esperada: ' + $ManifestPath))
    }
    if (Test-ArlReparseChain $ManifestPath) { throw (New-ArlRefusal 'R11' ('enlace (junction o symlink) en la ruta del manifiesto')) }
    foreach ($node in @($archiveParent, $tsDir, $ManifestPath)) {
        $o = Get-ArlOwnerSid $node
        if (@($script:SidBA, $script:SidSY) -notcontains $o) { throw (New-ArlRefusal 'R11' ('dueno no administrador en el respaldo: ' + $node)) }
    }
    foreach ($node in @($archiveParent, $tsDir, $ManifestPath)) {
        if (@(Get-ArlWriters $node).Count -gt 0) { throw (New-ArlRefusal 'R11' ('permisos de escritura no administrativos en el respaldo: ' + $node)) }
    }
    if ([string]$Manifest.schema -ne 'arl-operator-desktop-manifest-v1') { throw (New-ArlRefusal 'R11' 'esquema de manifiesto desconocido') }
    if ([string]$Manifest.computer -ne [string]$env:COMPUTERNAME) { throw (New-ArlRefusal 'R11' ('el manifiesto es de otro equipo: ' + $Manifest.computer)) }
    $r = $Manifest.roots
    if (([string]$r.public_desktop -ne $P.PublicDesktop) -or ([string]$r.operator_desktop -ne $P.OperatorDesktop) -or ([string]$r.tools_root -ne $P.Tools) -or ([string]$r.guide_root -ne $P.Guide)) {
        throw (New-ArlRefusal 'R11' 'las carpetas del manifiesto no coinciden con las de este equipo')
    }
    $trustRoots = @(
        @{ Path = [string]$r.public_desktop; AllowEqual = $true }, @{ Path = [string]$r.operator_desktop; AllowEqual = $true },
        @{ Path = $P.Tools; AllowEqual = $true }, @{ Path = $P.Guide; AllowEqual = $true }, @{ Path = [string]$r.archive_dir; AllowEqual = $true }
    )
    foreach ($a in @($Manifest.actions)) {
        foreach ($fld in @('path', 'source', 'destination', 'backup', 'temp_path')) {
            $val = [string]$a.$fld
            if ([string]::IsNullOrEmpty($val)) { continue }
            # Only a move or an archived folder is written back to its source. The card and icon sources
            # (the shipped card, shell32.dll, dosbox-x-arl.exe) are read-only inputs that undo never writes.
            if ($fld -eq 'source' -and @('move', 'archive-folder') -notcontains [string]$a.kind) { continue }
            if (Test-ArlDotDot $val) { throw (New-ArlRefusal 'R11' ('ruta con .. en el manifiesto: ' + $val)) }
            try { $candidate = [System.IO.Path]::GetFullPath($val).TrimEnd('\') }
            catch { throw (New-ArlRefusal 'R11' ('ruta invalida en el manifiesto: ' + $val)) }
            if (-not (Test-ArlUnderAny -Path $candidate -Roots $trustRoots)) { throw (New-ArlRefusal 'R11' ('ruta fuera de las carpetas confiables: ' + $val)) }
        }
        if ($script:ArlKnownKinds -notcontains [string]$a.kind) { throw (New-ArlRefusal 'R11' ('accion desconocida en el manifiesto: ' + [string]$a.kind)) }
    }
}

function Set-ArlUndoSkipped($Action, [string]$Reason) { $Action.status = 'undo-skipped'; $Action.undo_reason = $Reason }

# Undo moves a created/replaced/copied file aside only when it is still what apply wrote. (M19: a
# create-shortcut undo without this check removes an operator's later edit; C04b catches it.)
# The recorded hash decides when the manifest has one. A run killed inside the action never saved that hash,
# so the file is then compared with what the action would have written: the shortcut fields, the card
# source bytes, or the icon pixels extracted again from its source.
function Test-ArlLnkMatchesAction([string]$Path, $Action) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $expected = [string]$Action.sha256_new
    if ($expected) { return [string]::Equals((Get-ArlFileSha256 $Path), $expected, [System.StringComparison]::OrdinalIgnoreCase) }
    switch ([string]$Action.kind) {
        { $_ -eq 'create-shortcut' -or $_ -eq 'replace-shortcut' } {
            if ($null -eq $Action.fields) { return $false }
            $want = @{}
            foreach ($k in @('Target', 'Arguments', 'WorkDir', 'Icon', 'Description', 'WindowStyle')) { $want[$k] = $Action.fields.$k }
            return (Test-ArlFieldsEqual -Actual (Read-ArlShortcut $Path) -Expected $want)
        }
        'copy-card' {
            $src = [string]$Action.source
            if (-not $src -or -not (Test-Path -LiteralPath $src -PathType Leaf)) { return $false }
            return [string]::Equals((Get-ArlFileSha256 $Path), (Get-ArlFileSha256 $src), [System.StringComparison]::OrdinalIgnoreCase)
        }
        'write-icon' {
            $bmp = Get-ArlIconBitmap -File ([string]$Action.source) -Index ([int]$Action.arguments)
            if ($null -eq $bmp) { return $false }
            try { $fresh = Get-ArlPixelHash $bmp } finally { $bmp.Dispose() }
            return ($fresh -and ($fresh -eq (Get-ArlPngPixelHash $Path)))
        }
    }
    return $false
}

# The owner SID recorded inside an SDDL string, or '' when there is none.
function Get-ArlSddlOwnerSid([string]$Sddl) {
    if (-not $Sddl) { return '' }
    try {
        $raw = New-Object System.Security.AccessControl.RawSecurityDescriptor $Sddl
        if ($null -eq $raw.Owner) { return '' }
        return $raw.Owner.Value
    } catch { return '' }
}

# Undo never deletes a file it put down: it moves it into the run's archive folder (deshecho\<seq>-<name>),
# admin-only like the rest of the archive, so a wrong guess about what apply wrote is still recoverable.
function Move-ArlAsideForUndo($P, [string]$ArchiveDir, $Action, [string]$Path) {
    $leafName = Split-Path -Leaf $Path
    $aside = Join-Path (Join-Path $ArchiveDir 'deshecho') ([string]$Action.seq + '-' + $leafName)
    if (Test-Path -LiteralPath $aside) {
        $aside = Join-Path (Join-Path $ArchiveDir 'deshecho') ([string]$Action.seq + '-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmssfff') + '-' + $leafName)
    }
    Confirm-ArlParent -P $P -ChildPath $aside
    Invoke-ArlAction -P $P -Op 'move-file' -Path $Path -Destination $aside | Out-Null
    Reset-ArlChildAcl -P $P -Parent (Split-Path -Parent $aside) -Leaf (Split-Path -Leaf $aside) | Out-Null
}

# Puts a backed-up original back at its path and lets it inherit from its folder again.
function Restore-ArlBackup($P, [string]$Backup, [string]$Path) {
    Invoke-ArlAction -P $P -Op 'move-file' -Path $Backup -Destination $Path | Out-Null
    Reset-ArlChildAcl -P $P -Parent (Split-Path -Parent $Path) -Leaf (Split-Path -Leaf $Path) | Out-Null
}

# Re-inherit the moved-back item's ACL and give it back its original owner. (M13: skipping this leaves the
# restored item owned by BA with H's admin-only ACL; C04's SDDL comparison catches it.)
function Restore-ArlSourceAcl($P, [string]$Path, [string]$OwnerSid, [string]$SourceSddl) {
    return (Invoke-ArlAction -P $P -Op 'restore-acl' -Path $Path -OwnerSid $OwnerSid)
}

# True when the moved-back item carries the ACL it had before apply (semantic SDDL key, not byte for byte).
function Test-ArlSourceAclRestored($Action) {
    return ((ConvertTo-ArlSddlKey (Get-Acl -LiteralPath $Action.source).Sddl) -eq (ConvertTo-ArlSddlKey ([string]$Action.source_sddl)))
}

# Undo of acl-set and of a directory acl-reset: the DACL goes back first, then the owner as a separate step,
# because writing an owner inside the same security descriptor fails on hosts where we do not hold it.
function Restore-ArlDirAcl($P, $Action) {
    $before = [string]$Action.sddl_before
    if (-not $before) { return }
    Invoke-ArlAction -P $P -Op 'set-dacl' -Path $Action.path -Sddl $before | Out-Null
    $wantOwner = Get-ArlSddlOwnerSid $before
    if ($wantOwner -and ($wantOwner -ne (Get-ArlOwnerSid $Action.path))) { Invoke-ArlAction -P $P -Op 'set-owner' -Path $Action.path -OwnerSid $wantOwner | Out-Null }
}

# Each branch looks at what is on disk before it acts, so it is safe on a done, in-progress, failed or
# undo-skipped action and on a second -Undo after a first one was cut off. Undo never deletes a file: what
# apply put down is moved aside into the run's archive (deshecho\); only an empty folder apply created is removed.
function Invoke-ArlUndoAction($P, $Action, [string]$ArchiveDir) {
    $a = $Action
    switch ([string]$a.kind) {
        'archive-folder' {
            $srcThere = Test-Path -LiteralPath $a.source
            if ((Test-Path -LiteralPath $a.destination -PathType Container) -and -not $srcThere) {
                Invoke-ArlAction -P $P -Op 'move-dir' -Path $a.destination -Destination $a.source | Out-Null
                $a.status = 'undone'
            } elseif ($srcThere -and -not (Test-Path -LiteralPath $a.destination)) { $a.status = 'undone' }
            else { Set-ArlUndoSkipped -Action $a -Reason 'origen ocupado o destino ausente' }
        }
        'move' {
            $srcThere = Test-Path -LiteralPath $a.source
            $recorded = [string]$a.sha256
            if ((Test-Path -LiteralPath $a.destination -PathType Leaf) -and -not $srcThere -and $recorded -and [string]::Equals((Get-ArlFileSha256 $a.destination), $recorded, [System.StringComparison]::OrdinalIgnoreCase)) {
                Invoke-ArlAction -P $P -Op 'move-file' -Path $a.destination -Destination $a.source | Out-Null
                Restore-ArlSourceAcl -P $P -Path $a.source -OwnerSid $a.source_owner_sid -SourceSddl $a.source_sddl | Out-Null
                if (-not (Test-ArlSourceAclRestored $a)) { Set-ArlUndoSkipped -Action $a -Reason 'acl' } else { $a.status = 'undone' }
            } elseif ($srcThere -and -not (Test-Path -LiteralPath $a.destination)) {
                # The move never happened (failed or cut off before it) or an earlier -Undo already put it back.
                if ([string]$a.source_sddl -and -not (Test-ArlSourceAclRestored $a)) { Set-ArlUndoSkipped -Action $a -Reason 'acl' } else { $a.status = 'undone' }
            } else { Set-ArlUndoSkipped -Action $a -Reason 'movido o modificado despues de aplicar' }
        }
        'create-shortcut' {
            $created = $a.path
            if (-not (Test-Path -LiteralPath $created -PathType Leaf)) { $a.status = 'undone'; return }
            if (-not (Test-ArlLnkMatchesAction -Path $created -Action $a)) { Set-ArlUndoSkipped -Action $a -Reason 'modificado despues de aplicar'; return }
            Move-ArlAsideForUndo -P $P -ArchiveDir $ArchiveDir -Action $a -Path $created
            $a.status = 'undone'
        }
        { @('replace-shortcut', 'copy-card', 'write-icon') -contains $_ } {
            $current = [string]$a.path
            $backup = [string]$a.backup
            $expectBackup = [bool]$backup
            # The backup is checked against the hash recorded at plan time BEFORE anything moves, so a missing
            # or changed backup never costs the file that is in place now.
            $backupOk = $expectBackup -and (Test-Path -LiteralPath $backup -PathType Leaf) -and [string]::Equals((Get-ArlFileSha256 $backup), [string]$a.sha256_old, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not (Test-Path -LiteralPath $current -PathType Leaf)) {
                # Cut off between the backup and the new file (or the operator removed the new one).
                if ($backupOk) { Restore-ArlBackup -P $P -Backup $backup -Path $current; $a.status = 'undone' }
                elseif ($expectBackup) { Set-ArlUndoSkipped -Action $a -Reason 'respaldo ausente o cambiado' }
                else { $a.status = 'undone' }
                return
            }
            # An earlier -Undo already put the original back but could not save the manifest.
            if ($expectBackup -and -not (Test-Path -LiteralPath $backup) -and [string]::Equals((Get-ArlFileSha256 $current), [string]$a.sha256_old, [System.StringComparison]::OrdinalIgnoreCase)) { $a.status = 'undone'; return }
            if (-not (Test-ArlLnkMatchesAction -Path $current -Action $a)) { Set-ArlUndoSkipped -Action $a -Reason 'modificado despues de aplicar'; return }
            if ($expectBackup -and -not $backupOk) { Set-ArlUndoSkipped -Action $a -Reason 'respaldo ausente o cambiado'; return }
            Move-ArlAsideForUndo -P $P -ArchiveDir $ArchiveDir -Action $a -Path $current
            if ($backupOk) { Restore-ArlBackup -P $P -Backup $backup -Path $current }
            $a.status = 'undone'
        }
        'acl-set' {
            if (-not (Test-Path -LiteralPath $a.path -PathType Container)) { Set-ArlUndoSkipped -Action $a -Reason 'carpeta ausente'; return }
            Restore-ArlDirAcl -P $P -Action $a
            $a.status = 'undone'
        }
        'acl-reset' {
            # A moved or created item's reset is undone by that item's own undo; a folder that existed before
            # apply gets its recorded DACL and owner back.
            if ($a.existed -eq $true -and [string]$a.sddl_before -and (Test-Path -LiteralPath $a.path -PathType Container)) { Restore-ArlDirAcl -P $P -Action $a }
            $a.status = 'undone'
        }
        'mkdir' {
            if ($a.existed -ne $false) { $a.status = 'undone'; return }
            if (-not (Test-Path -LiteralPath $a.path -PathType Container)) { $a.status = 'undone'; return }
            if (@(Get-ChildItem -LiteralPath $a.path -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                Invoke-ArlAction -P $P -Op 'delete-dir' -Path $a.path | Out-Null
                $a.status = 'undone'
            } else { Set-ArlUndoSkipped -Action $a -Reason 'no vacia' }
        }
        default { Set-ArlUndoSkipped -Action $a -Reason ('accion desconocida: ' + [string]$a.kind) }
    }
}

function Invoke-ArlUndo($P, [string]$ManifestParam, [switch]$WhatIf) {
    $sel = Select-ArlManifest -P $P -ManifestParam $ManifestParam
    if ($sel.None) { return @{ Status = 'sin-cambios'; Manifest = $null; Skipped = @(); Colada = $null } }
    $manifestPath = $sel.Path
    $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    Assert-ArlManifestTrusted -P $P -ManifestPath $manifestPath -Manifest $manifest
    $archiveDir = Split-Path -Parent $manifestPath
    # in-progress: a run killed inside that action; failed: an action that threw part way; undo-skipped: what an
    # earlier -Undo could not do, retried now. planned actions never ran and are left alone.
    $acts = @($manifest.actions | Where-Object { @('done', 'in-progress', 'failed', 'undo-skipped') -contains [string]$_.status } | Sort-Object -Property seq -Descending)
    if ($WhatIf) {
        Write-ArlLine ('DESHACER (revision): ' + $manifestPath)
        foreach ($a in $acts) { Write-ArlLine ('  ' + [string]$a.seq + '  ' + [string]$a.kind + '  ' + [string]$a.path) }
        $colada = if (Test-Path -LiteralPath $P.ColadaPath) { $P.ColadaPath } else { $null }
        return @{ Status = 'cambios-pendientes'; Manifest = $manifestPath; Skipped = @(); Colada = $colada }
    }
    $manifest.state = 'undoing'
    Write-ArlManifest -P $P -Manifest $manifest -Path $manifestPath
    foreach ($a in $acts) {
        try { Invoke-ArlUndoAction -P $P -Action $a -ArchiveDir $archiveDir }
        catch { Set-ArlUndoSkipped -Action $a -Reason ([string]$_.Exception.Message) }
        Write-ArlManifestSafe -P $P -Manifest $manifest -Path $manifestPath
    }
    # The run counts as undone only when every action that ran is undone.
    $pending = @($manifest.actions | Where-Object { @('planned', 'undone') -notcontains [string]$_.status } | Sort-Object -Property seq -Descending)
    $skipped = @($pending | ForEach-Object { [string]$_.seq + ':' + [string]$_.kind + ' (' + [string]$_.undo_reason + ')' })
    if ($pending.Count -gt 0) { $manifest.state = 'undone-partial' } else { $manifest.state = 'undone' }
    Write-ArlManifestSafe -P $P -Manifest $manifest -Path $manifestPath
    foreach ($s in $skipped) { Write-ArlLine ('NO SE DESHIZO  ' + $s) }
    $colada = if (Test-Path -LiteralPath $P.ColadaPath) { $P.ColadaPath } else { $null }
    if ($pending.Count -gt 0) { return @{ Status = 'deshecho-parcial'; Manifest = $manifestPath; Skipped = $skipped; Colada = $colada } }
    return @{ Status = 'deshecho'; Manifest = $manifestPath; Skipped = @(); Colada = $colada }
}
#endregion implementacion
#region autoprueba
# Everything in this region is the built-in self-test. It is the ONLY place besides Invoke-ArlAction
# where mutating tokens (New-Item, Set-Acl, icacls, .Save(), ...) are allowed: the static scanner in
# Test-SetArlOperatorDesktop.ps1 whitelists this region by name. The test builds a throwaway tree under
# %TEMP%, drives THIS script as a child process against it, and checks the ARL-DESKTOP-RESULT line and
# the exit code. On a non-Windows engine (developer laptop) it prints one SKIP line and returns 0.

# Accented labels are assembled from [char] codes so the .ps1 stays ASCII with no BOM (PS 5.1 reads a
# BOM-less file as ANSI and would corrupt a literal accent).
$script:ArlAccentO = [string][char]0x00F3   # o with acute

function Get-ArlStPaths([string]$T) {
    $p = @{}
    $p.T = $T
    $p.PublicDesktop = Join-Path $T 'Users\Public\Desktop'
    $p.OperatorDesktop = Join-Path $T 'Users\Piso\Desktop'
    $p.UsersRoot = Join-Path $T 'Users'
    $p.ArlRoot = Join-Path $T 'ARL'
    $p.SystemRoot = Join-Path $T 'Windows'
    $p.EdgePath = Join-Path $T 'Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    $p.CardSource = Join-Path $T 'card\cual-uso.html'
    $p.Tools = Join-Path $p.ArlRoot 'Herramientas-Admin'
    $p.Guide = Join-Path $p.ArlRoot 'Guia-Operador'
    $p.Icons = Join-Path $p.Guide 'iconos'
    $p.Card = Join-Path $p.Guide 'cual-uso.html'
    $p.Staging = Join-Path $p.ArlRoot '_staging'
    $p.ArchiveRoot = Join-Path $p.Staging 'desktop-archive'
    $p.Toolkit = Join-Path $p.ArlRoot 'DOSBox-X-ARL'
    $p.Contrib = Join-Path $p.Toolkit 'contrib\arl'
    $p.OperatorDir = Join-Path $p.ArlRoot 'ChispaOperator'
    $p.Bridge = Join-Path $p.ArlRoot 'ChispaBridge'
    $p.DosboxExe = Join-Path $p.Toolkit 'dosbox-x-arl.exe'
    $p.ChispaExe = Join-Path $p.OperatorDir 'Chispa.Operator.exe'
    $p.OperatorSettings = Join-Path $p.OperatorDir 'operator-settings.json'
    $p.ShellDll = Join-Path $p.SystemRoot 'System32\shell32.dll'
    $p.PisoPins = Join-Path $p.UsersRoot 'Piso\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    return $p
}

function Get-ArlStChildArgs([hashtable]$SP) {
    return @(
        '-PublicDesktop', $SP.PublicDesktop, '-OperatorDesktop', $SP.OperatorDesktop, '-UsersRoot', $SP.UsersRoot,
        '-ArlRoot', $SP.ArlRoot, '-EdgePath', $SP.EdgePath, '-SystemRoot', $SP.SystemRoot, '-CardSource', $SP.CardSource
    )
}

# Runs THIS script as a child against the fake tree. Returns @{ Exit; Result; Lines }.
function Invoke-ArlStChild([string]$T, [string[]]$Mode, [hashtable]$Extra) {
    $SP = Get-ArlStPaths $T
    $exe = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + $Mode + (Get-ArlStChildArgs $SP)
    $savedRoot = $env:ARL_DESKTOP_SELFTEST_ROOT; $savedDepth = $env:ARL_DESKTOP_SELFTEST_DEPTH; $savedFail = $env:ARL_DESKTOP_FAIL_AFTER_ACTION
    $savedInside = $env:ARL_DESKTOP_FAIL_INSIDE_ACTION
    $env:ARL_DESKTOP_SELFTEST_ROOT = $T
    $env:ARL_DESKTOP_SELFTEST_DEPTH = '1'
    if ($null -ne $Extra -and $Extra.ContainsKey('FailAfter')) { $env:ARL_DESKTOP_FAIL_AFTER_ACTION = [string]$Extra.FailAfter } else { $env:ARL_DESKTOP_FAIL_AFTER_ACTION = $null }
    if ($null -ne $Extra -and $Extra.ContainsKey('FailInside')) { $env:ARL_DESKTOP_FAIL_INSIDE_ACTION = [string]$Extra.FailInside } else { $env:ARL_DESKTOP_FAIL_INSIDE_ACTION = $null }
    try {
        $lines = & $exe @argv 2>&1 | ForEach-Object { [string]$_ }
        $code = $LASTEXITCODE
    } finally {
        $env:ARL_DESKTOP_SELFTEST_ROOT = $savedRoot; $env:ARL_DESKTOP_SELFTEST_DEPTH = $savedDepth; $env:ARL_DESKTOP_FAIL_AFTER_ACTION = $savedFail
        $env:ARL_DESKTOP_FAIL_INSIDE_ACTION = $savedInside
    }
    $result = $null
    foreach ($ln in @($lines)) {
        if ($ln -like 'ARL-DESKTOP-RESULT *') {
            try { $result = $ln.Substring('ARL-DESKTOP-RESULT '.Length) | ConvertFrom-Json } catch { $result = $null }
        }
    }
    return @{ Exit = $code; Result = $result; Lines = @($lines) }
}

# A byte/ACL snapshot of a tree, keyed by relative path. The _staging subtree (archive + manifest) is
# excluded so a snapshot taken before apply equals one taken after undo (spec C04).
function Get-ArlStSnapshot([string]$Root) {
    $snap = @{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $snap }
    $stagingLeaf = '\_staging\'
    foreach ($it in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue)) {
        $full = $it.FullName
        if ($full -like ('*' + $stagingLeaf + '*')) { continue }
        $rel = $full.Substring($Root.Length)
        $entry = @{ Dir = [bool]$it.PSIsContainer; Sddl = ''; Owner = ''; Hash = '' }
        try { $acl = Get-Acl -LiteralPath $full; $entry.Sddl = $acl.Sddl; $entry.Owner = [string]$acl.Owner } catch { }
        if (-not $it.PSIsContainer) { try { $entry.Hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() } catch { } }
        $snap[$rel] = $entry
    }
    return $snap
}

# Compares two snapshots. Returns a list of human-readable differences (empty = identical).
function Compare-ArlStSnapshot($Before, $After, [switch]$IgnoreSddl) {
    $diffs = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $Before.Keys) {
        if (-not $After.ContainsKey($k)) { [void]$diffs.Add('falta: ' + $k); continue }
        $b = $Before[$k]; $a = $After[$k]
        if ($b.Hash -ne $a.Hash) { [void]$diffs.Add('hash: ' + $k) }
        if (-not $IgnoreSddl -and (ConvertTo-ArlSddlKey $b.Sddl) -ne (ConvertTo-ArlSddlKey $a.Sddl)) { [void]$diffs.Add('sddl: ' + $k) }
    }
    foreach ($k in $After.Keys) { if (-not $Before.ContainsKey($k)) { [void]$diffs.Add('sobra: ' + $k) } }
    return @($diffs)
}

# --- fake-tree primitives -------------------------------------------------------------------------------
function New-ArlStDir([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

function New-ArlStFile([string]$Path, [string]$Content) {
    New-ArlStDir (Split-Path -Parent $Path)
    Set-Content -LiteralPath $Path -Value $Content -Encoding Ascii -NoNewline
}

function New-ArlStCmd([string]$Path) { New-ArlStFile -Path $Path -Content "@echo off`r`nexit /b 0`r`n" }

function New-ArlStLnk([string]$Path, [string]$Target, [string]$Arguments, [string]$WorkDir, [string]$Icon, [string]$Description) {
    New-ArlStDir (Split-Path -Parent $Path)
    $shell = New-Object -ComObject WScript.Shell
    try {
        $sc = $shell.CreateShortcut($Path)
        $sc.TargetPath = $Target
        if ($Arguments) { $sc.Arguments = $Arguments }
        if ($WorkDir) { $sc.WorkingDirectory = $WorkDir }
        if ($Icon) { $sc.IconLocation = $Icon }
        if ($Description) { $sc.Description = $Description }
        $sc.Save()
    } finally { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}

function New-ArlStUrl([string]$Path, [string]$Url) {
    New-ArlStFile -Path $Path -Content ("[InternetShortcut]`r`nURL=" + $Url + "`r`n")
}

# Applies the admin-only SDDL to a folder the same way the script does, so a pre-created H (C08) or a
# tampered manifest owner (C12) can be set up exactly.
function Set-ArlStOwnerAdmins([string]$Path) { & icacls $Path /setowner '*S-1-5-32-544' /C /Q | Out-Null }
function Set-ArlStProtect([string]$Path, [string]$Sddl) {
    $sd = New-Object System.Security.AccessControl.DirectorySecurity
    $sd.SetSecurityDescriptorSddlForm($Sddl)
    Set-Acl -LiteralPath $Path -AclObject $sd
}
function Add-ArlStUserWrite([string]$Path, [string]$Sid) {
    $acl = Get-Acl -LiteralPath $Path
    # A file ACE takes no inheritance flags (AddAccessRule refuses them: "No flags can be set").
    $inherit = if (Test-Path -LiteralPath $Path -PathType Container) { 'ContainerInherit,ObjectInherit' } else { 'None' }
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(([System.Security.Principal.SecurityIdentifier]$Sid), 'Modify', $inherit, 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# --- default owner of new objects (C10) ------------------------------------------------------------------
# Whoever creates a file or folder owns it unless the creator sets another owner. An elevated admin's token
# hands new objects to BUILTIN\Administrators, so on a GitHub runner or an admin console a folder the script
# forgets to give an owner still looks right; SYSTEM (the host's scheduled task) keeps them itself and C10
# fails there. The self-test's apply therefore runs with the process token's default owner set to the
# account's own SID (SYSTEM stays SYSTEM, an admin becomes its user SID), never Administrators, so C10 judges
# the script and not the account running it. P/Invoke through Add-Type -MemberDefinition, like Import-ArlNative.
function Import-ArlStTokenNative {
    if ('ArlDesktop.StToken' -as [type]) { return }
    $members = @'
[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool CloseHandle(IntPtr hObject);
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool GetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, int TokenInformationLength, out int ReturnLength);
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool SetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, int TokenInformationLength);
'@
    Add-Type -Namespace ArlDesktop -Name StToken -MemberDefinition $members
}

# The default owner of this process's token (TokenOwner, class 4: a TOKEN_OWNER is one pointer to a SID).
function Get-ArlStTokenOwner {
    Import-ArlStTokenNative
    $h = [IntPtr]::Zero
    if (-not [ArlDesktop.StToken]::OpenProcessToken([ArlDesktop.StToken]::GetCurrentProcess(), 0x0008, [ref]$h)) {
        throw ('OpenProcessToken fallo: ' + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    $buf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(256)
    try {
        $len = 0
        if (-not [ArlDesktop.StToken]::GetTokenInformation($h, 4, $buf, 256, [ref]$len)) {
            throw ('GetTokenInformation fallo: ' + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        return [System.Security.Principal.SecurityIdentifier]::new([System.Runtime.InteropServices.Marshal]::ReadIntPtr($buf))
    } finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
        [void][ArlDesktop.StToken]::CloseHandle($h)
    }
}

# Sets this process's default owner for new objects (TOKEN_QUERY | TOKEN_ADJUST_DEFAULT). The SID is written
# right after the pointer in the same buffer; the token keeps its own copy.
function Set-ArlStTokenOwner([System.Security.Principal.SecurityIdentifier]$Sid) {
    Import-ArlStTokenNative
    $bin = [System.Array]::CreateInstance([byte], $Sid.BinaryLength)
    $Sid.GetBinaryForm($bin, 0)
    $size = [IntPtr]::Size + $bin.Length
    $buf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    $h = [IntPtr]::Zero
    try {
        $sidAt = [IntPtr]::Add($buf, [IntPtr]::Size)
        [System.Runtime.InteropServices.Marshal]::Copy($bin, 0, $sidAt, $bin.Length)
        [System.Runtime.InteropServices.Marshal]::WriteIntPtr($buf, $sidAt)
        if (-not [ArlDesktop.StToken]::OpenProcessToken([ArlDesktop.StToken]::GetCurrentProcess(), 0x0088, [ref]$h)) {
            throw ('OpenProcessToken fallo: ' + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        if (-not [ArlDesktop.StToken]::SetTokenInformation($h, 4, $buf, $size)) {
            throw ('SetTokenInformation fallo (' + $Sid.Value + '): ' + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
    } finally {
        if ($h -ne [IntPtr]::Zero) { [void][ArlDesktop.StToken]::CloseHandle($h) }
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
    }
}

# Runs one child of this script with the default owner described above; the child process starts with a copy
# of this token. A probe folder made first proves it took (its owner comes back as the result's ProbeOwner,
# which C10 requires not to be Administrators). The token's own default owner is put back afterwards.
function Invoke-ArlStChildCreatorOwner([string]$T, [string[]]$Mode) {
    $original = Get-ArlStTokenOwner
    Set-ArlStTokenOwner ([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
    try {
        $probe = Join-Path $T 'sonda-dueno'
        New-Item -ItemType Directory -Path $probe | Out-Null
        $probeOwner = Get-ArlOwnerSid $probe
        Remove-Item -LiteralPath $probe -Force
        $res = Invoke-ArlStChild $T $Mode
        $res.ProbeOwner = $probeOwner
        return $res
    } finally {
        Set-ArlStTokenOwner $original
    }
}
# Copies a real icon-bearing binary into the fake toolkit so R4 (icon index extracts) can pass. shell32
# icons live in SystemResources\shell32.dll.mun on Win10+, so prefer it; dosbox-x-arl.exe stands in for
# any PE whose icon 0 extracts (powershell/regedit/explorer).
function Copy-ArlStShell32([string]$Dest) {
    New-ArlStDir (Split-Path -Parent $Dest)
    $mun = Join-Path $env:SystemRoot 'SystemResources\shell32.dll.mun'
    $sys = Join-Path $env:SystemRoot 'System32\shell32.dll'
    $src = if (Test-Path -LiteralPath $mun) { $mun } else { $sys }
    Copy-Item -LiteralPath $src -Destination $Dest -Force
}
function Copy-ArlStIconExe([string]$Dest) {
    New-ArlStDir (Split-Path -Parent $Dest)
    foreach ($cand in @((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), (Join-Path $env:SystemRoot 'regedit.exe'), (Join-Path $env:SystemRoot 'explorer.exe'))) {
        if (-not (Test-Path -LiteralPath $cand)) { continue }
        $bmp = Get-ArlIconBitmap -File $cand -Index 0
        if ($null -ne $bmp) { $bmp.Dispose(); Copy-Item -LiteralPath $cand -Destination $Dest -Force; return }
    }
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Destination $Dest -Force
}

# Builds every ARL support file the checks (R3/R4/R5) require, plus the card and the system stand-ins.
function New-ArlStBaseTree([string]$T) {
    $SP = Get-ArlStPaths $T
    foreach ($d in @($SP.PublicDesktop, $SP.OperatorDesktop, $SP.Toolkit, $SP.Contrib, $SP.OperatorDir, $SP.Bridge, (Join-Path $SP.ArlRoot 'diagnostics'), (Join-Path $SP.ArlRoot 'tools'))) { New-ArlStDir $d }
    Copy-ArlStShell32 $SP.ShellDll
    Copy-ArlStIconExe $SP.DosboxExe
    New-ArlStFile (Join-Path $SP.OperatorDir 'Chispa.Operator.exe') 'MZ stub'
    $launcher = Join-Path $SP.Toolkit 'Launch-ArlImpactReactiveSafeTrace.cmd'
    New-ArlStCmd $launcher
    New-ArlStFile $SP.OperatorSettings ('{ "launcherPath": "' + ($launcher -replace '\\', '\\\\') + '" }')
    New-ArlStCmd (Join-Path $SP.Contrib 'Launch-ArlStandardizationPassiveTrace.cmd')
    New-ArlStCmd (Join-Path $SP.Contrib 'Launch-ArlNormalizationPassiveTrace.cmd')
    New-ArlStFile (Join-Path $SP.Contrib 'Launch-ArlPassiveWorkflowTrace.ps1') "exit 0`r`n"
    New-ArlStCmd (Join-Path $SP.Contrib 'Run-ArlOperatorPreflight.cmd')
    New-ArlStCmd (Join-Path $SP.Contrib 'Approve-LatestArlReport.cmd')
    New-ArlStCmd (Join-Path $SP.Bridge 'Launch-ArlBridgeSmoke.cmd')
    New-ArlStCmd (Join-Path $SP.Bridge 'Launch-ArlBridgeSafeLoop.cmd')
    New-ArlStCmd (Join-Path $SP.Bridge 'Launch-ArlBridgeDiverseValues.cmd')
    New-ArlStCmd (Join-Path $SP.Toolkit 'Launch-ArlImpactCycles6000Trace.cmd')
    New-ArlStFile $SP.EdgePath 'MZ edge stub'
    # Card: copy the repo card if present next to this script, else synthesize a minimal ASCII one.
    $repoCard = Join-Path (Split-Path -Parent $PSCommandPath) 'operator-desktop\cual-uso.html'
    New-ArlStDir (Split-Path -Parent $SP.CardSource)
    if (Test-Path -LiteralPath $repoCard) { Copy-Item -LiteralPath $repoCard -Destination $SP.CardSource -Force }
    else { New-ArlStFile $SP.CardSource (Get-ArlStMinimalCard) }
    return $SP
}

# A minimal card that satisfies R5 when the repo card is not shipped alongside the script.
function Get-ArlStMinimalCard {
    $rows = Get-ArlFinalRows
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!doctype html><html><head><meta charset="utf-8"><title>Cual uso</title></head><body>')
    foreach ($r in $rows) { [void]$sb.Append('<h2>' + $r.Name + '</h2>') }
    foreach ($png in @('analizar-colada.png', 'guia.png', 'serrano.png')) { [void]$sb.Append('<img src="iconos/' + $png + '" alt="">') }
    [void]$sb.Append('<p>SIN CHISPA</p></body></html>')
    return $sb.ToString()
}

# The 13 items of spec 3.1 (8 inside ARL Diagnostics, 5 at top level), all targeting the fake tree.
function New-ArlStMoveMap([string]$T) {
    $SP = Get-ArlStPaths $T
    $D = $SP.PublicDesktop
    $diag = Join-Path $D 'ARL Diagnostics'
    New-ArlStDir $diag
    New-ArlStLnk (Join-Path $diag '01 Bridge Emulator - IMPACT.lnk') (Join-Path $SP.Bridge 'Launch-ArlBridgeSmoke.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $diag '02 Bridge Emulator - Safe Loop.lnk') (Join-Path $SP.Bridge 'Launch-ArlBridgeSafeLoop.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $diag '03 Bridge Emulator - Diverse Values.lnk') (Join-Path $SP.Bridge 'Launch-ArlBridgeDiverseValues.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $diag '10 Direct Serial - Baseline.lnk') (Join-Path $SP.Toolkit 'Launch-ArlImpactCycles6000Trace.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $diag '20 Inspect Last ARL Run.lnk') (Join-Path $SP.Toolkit 'Inspect-ArlCurrentRun.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $diag '30 Print Epson Raw.lnk') (Join-Path $SP.Toolkit 'Print-LatestArlLpt-Epson-Raw-Send.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $diag '31 Print HP Text.lnk') (Join-Path $SP.Toolkit 'Print-LatestArlLpt-HPSmartTank-Text-Send.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $diag 'Diagnostics - Serial Traces.lnk') (Join-Path $SP.ArlRoot 'diagnostics') '' '' '' ''
    New-ArlStLnk (Join-Path $D '01 PRECHECK.lnk') (Join-Path $SP.Contrib 'Run-ArlOperatorPreflight.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $D '03 APPROVE LAST REPORT.lnk') (Join-Path $SP.Contrib 'Approve-LatestArlReport.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $D '04 STANDARDIZATION PASSIVE.lnk') (Join-Path $SP.Contrib 'Launch-ArlStandardizationPassiveTrace.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $D '05 NORMALIZATION PASSIVE.lnk') (Join-Path $SP.Contrib 'Launch-ArlNormalizationPassiveTrace.cmd') '' '' '' ''
    New-ArlStLnk (Join-Path $D 'ARL 3460 - Analizar.lnk') $SP.ChispaExe '' '' '' ''
    # kept items and the hidden desktop.ini stay on D untouched
    foreach ($k in @('Epson Photo+ Tool.lnk', 'Epson Photo+.lnk', 'Microsoft Edge.lnk')) { New-ArlStLnk (Join-Path $D $k) $SP.EdgePath '' '' '' '' }
    New-ArlStUrl (Join-Path $D 'Manual Epson L6270.url') 'https://epson.example/manual'
    $ini = Join-Path $D 'desktop.ini'
    New-ArlStFile $ini "[.ShellClassInfo]`r`n"
    (Get-Item -LiteralPath $ini -Force).Attributes = 'Hidden,System'
    return $SP
}

# Convenience: the four final .lnk paths and the three icon PNG paths.
function Get-ArlStFinalLeaves { return @((Get-ArlFinalRows) | ForEach-Object { $_.Name + '.lnk' }) }

function Invoke-ArlStGroup1([string]$T) {
    $SP = New-ArlStBaseTree $T
    New-ArlStMoveMap $T | Out-Null
    $preDesktop = Get-ArlStSnapshot $SP.PublicDesktop
    $preToolkit = Get-ArlStSnapshot $SP.Toolkit
    $preBridge = Get-ArlStSnapshot $SP.Bridge
    $preOperator = Get-ArlStSnapshot $SP.OperatorDir

    # C01: dry run leaves everything untouched and creates no archive.
    $dry = Invoke-ArlStChild $T @('-Apply', '-WhatIf')
    $c01 = ($dry.Exit -eq 0) -and ($null -ne $dry.Result) -and ($dry.Result.status -eq 'cambios-pendientes') -and
        (-not (Test-Path -LiteralPath $SP.ArchiveRoot)) -and (@(Compare-ArlStSnapshot $preDesktop (Get-ArlStSnapshot $SP.PublicDesktop)).Count -eq 0)
    Add-ArlStResult 'C01' 'ensayo sin cambios' $c01 ('exit=' + $dry.Exit + ' status=' + $(if ($dry.Result) { $dry.Result.status } else { 'nulo' }))

    # C02: apply. It runs with the default owner of new objects set to the account itself, never Administrators, the
    # way a scheduled task runs it as SYSTEM (Invoke-ArlStChildCreatorOwner); C10 below reads what it left.
    $ap = Invoke-ArlStChildCreatorOwner $T @('-Apply')
    $r = $ap.Result
    $finals = Get-ArlStFinalLeaves
    $finalsOk = $true; foreach ($f in $finals) { if (-not (Test-Path -LiteralPath (Join-Path $SP.PublicDesktop $f) -PathType Leaf)) { $finalsOk = $false } }
    $iconsOk = $true; foreach ($png in @('analizar-colada.png', 'guia.png', 'serrano.png')) { if (-not (Test-Path -LiteralPath (Join-Path $SP.Icons $png) -PathType Leaf)) { $iconsOk = $false } }
    $cardOk = Test-Path -LiteralPath $SP.Card -PathType Leaf
    $movedOk = (Test-Path -LiteralPath (Join-Path $SP.Tools 'Simuladores\01 Bridge Emulator - IMPACT.lnk')) -and
        (Test-Path -LiteralPath (Join-Path $SP.Tools 'Accesos-anteriores\ARL 3460 - Analizar.lnk')) -and
        (Test-Path -LiteralPath (Join-Path $SP.Tools 'Verificacion-y-aprobacion\01 PRECHECK.lnk')) -and
        (Test-Path -LiteralPath (Join-Path $SP.Tools 'Diagnostico\10 Direct Serial - Baseline.lnk'))
    $diagGone = -not (Test-Path -LiteralPath (Join-Path $SP.PublicDesktop 'ARL Diagnostics'))
    $countsOk = ($null -ne $r) -and ($r.status -eq 'aplicado') -and ($r.counts.crear -eq 4) -and ($r.counts.reemplazar -eq 0) -and
        ($r.counts.mover -eq 13) -and ($r.counts.archivar -eq 1) -and ($r.counts.desconocidos -eq 0) -and ($r.counts.sospechosos -eq 0)
    $coladaOk = ($null -ne $r) -and ($r.colada_shortcut) -and ([string]::Equals([string]$r.colada_shortcut, (Join-Path $SP.PublicDesktop ((Get-ArlFinalRows)[0].Name + '.lnk')), [System.StringComparison]::OrdinalIgnoreCase))
    $c02 = ($ap.Exit -eq 0) -and $finalsOk -and $iconsOk -and $cardOk -and $movedOk -and $diagGone -and $countsOk -and $coladaOk
    Add-ArlStResult 'C02' 'aplicar deja el escritorio final' $c02 ('exit=' + $ap.Exit + ' mover=' + $(if ($r) { $r.counts.mover } else { '?' }) + ' finals=' + $finalsOk + ' iconos=' + $iconsOk + ' colada=' + $coladaOk)

    # C10: H, its children and the archive carry the exact admin-only SDDL; the guide adds BU read. Every child of H
    # and the icon folder is owned by Administrators, compared by SID. The apply above ran with a default owner that
    # is not Administrators (the probe proves it), so a folder the script creates without setting its owner fails
    # here whoever runs the self-test: SYSTEM on the host's scheduled task, or an elevated admin.
    $probeOk = [bool]$ap.ProbeOwner -and ($ap.ProbeOwner -ne $script:SidBA)
    $toolsOk = Test-ArlStAdminOnly $SP.Tools
    $archiveOk = Test-ArlStAdminOnly $SP.ArchiveRoot
    $guideOk = Test-ArlStGuideSddl $SP.Guide
    $badChildren = @(Get-ArlStChildrenNotAdmin $SP.Tools 'herramientas')
    $iconsOwner = if (Test-Path -LiteralPath $SP.Icons -PathType Container) { Get-ArlOwnerSid $SP.Icons } else { '' }
    $iconsOk = ($iconsOwner -eq $script:SidBA) -and (Test-ArlChildSddl (Get-Acl -LiteralPath $SP.Icons).Sddl 'guia')
    $c10 = $probeOk -and $toolsOk -and $archiveOk -and $guideOk -and ($badChildren.Count -eq 0) -and $iconsOk
    Add-ArlStResult 'C10' 'permisos exactos en H, respaldo y guia' $c10 ('sonda=' + $ap.ProbeOwner + ' H=' + $toolsOk + ' respaldo=' + $archiveOk +
        ' guia=' + $guideOk + ' iconos=' + $iconsOwner + ' hijos-mal=[' + (@($badChildren | Select-Object -First 4) -join '; ') + ']')

    # C03: a second apply is a no-op and writes no new archive.
    $archivesBefore = @(Get-ChildItem -LiteralPath $SP.ArchiveRoot -Directory -Force -ErrorAction SilentlyContinue).Count
    $ap2 = Invoke-ArlStChild $T @('-Apply')
    $archivesAfter = @(Get-ChildItem -LiteralPath $SP.ArchiveRoot -Directory -Force -ErrorAction SilentlyContinue).Count
    $c03 = ($ap2.Exit -eq 0) -and ($null -ne $ap2.Result) -and ($ap2.Result.status -eq 'sin-cambios') -and ($archivesBefore -eq $archivesAfter)
    Add-ArlStResult 'C03' 'segunda aplicacion sin cambios' $c03 ('status=' + $(if ($ap2.Result) { $ap2.Result.status } else { 'nulo' }) + ' respaldos ' + $archivesBefore + '->' + $archivesAfter)

    # C12: four tampered manifest copies are each refused (exit 2) and move nothing.
    Invoke-ArlStC12 $T $SP

    # C04: undo restores the pre-apply snapshot exactly (paths, hashes, SDDL), and a second undo is a no-op.
    $undo = Invoke-ArlStChild $T @('-Undo')
    $postDesktop = Get-ArlStSnapshot $SP.PublicDesktop
    $diffs = Compare-ArlStSnapshot $preDesktop $postDesktop
    $undo2 = Invoke-ArlStChild $T @('-Undo')
    $c04 = ($undo.Exit -eq 0) -and ($null -ne $undo.Result) -and ($undo.Result.status -eq 'deshecho') -and (@($diffs).Count -eq 0) -and
        ($null -ne $undo2.Result) -and ($undo2.Result.status -eq 'sin-cambios')
    Add-ArlStResult 'C04' 'deshacer restaura el estado previo' $c04 ('exit=' + $undo.Exit + ' dif=' + (@($diffs) -join ','))

    # C09 dynamic: the toolkit, bridge and operator trees are byte-identical before and after the cycle.
    $c09 = (@(Compare-ArlStSnapshot $preToolkit (Get-ArlStSnapshot $SP.Toolkit)).Count -eq 0) -and
        (@(Compare-ArlStSnapshot $preBridge (Get-ArlStSnapshot $SP.Bridge)).Count -eq 0) -and
        (@(Compare-ArlStSnapshot $preOperator (Get-ArlStSnapshot $SP.OperatorDir)).Count -eq 0)
    Add-ArlStResult 'C09' 'no se toca toolkit, bridge ni operador' $c09 ''
}
# The expected admin-only descriptor, built from fragments so the exact `(A;OICI;FA;;;BA)` + closing
# quote that mutant M18 targets stays UNIQUE to the one constant in the implementation region. Using the
# in-code constant here would hide M18 (the mutant would change both sides together).
function Get-ArlStExpectedAdminSddl { return 'O:BAG:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;' + 'BA' + ')' }

function Test-ArlStAdminOnly([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    return (ConvertTo-ArlSddlKey (Get-Acl -LiteralPath $Path).Sddl) -eq (ConvertTo-ArlSddlKey (Get-ArlStExpectedAdminSddl))
}
function Test-ArlStGuideSddl([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    return (ConvertTo-ArlSddlKey (Get-Acl -LiteralPath $Path).Sddl) -eq (ConvertTo-ArlSddlKey $script:SddlGuide)
}
# Every item under $Root whose owner is not Administrators (S-1-5-32-544, by SID: SYSTEM does not count) or whose
# ACL is not only inherited admin ACEs, as 'relative-path (owner SID)'. Empty when all are right.
function Get-ArlStChildrenNotAdmin([string]$Root, [string]$Scope) {
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($c in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue)) {
        $o = Get-ArlOwnerSid $c.FullName
        if (($o -ne $script:SidBA) -or (-not (Test-ArlChildSddl (Get-Acl -LiteralPath $c.FullName).Sddl $Scope))) {
            [void]$out.Add($c.FullName.Substring($Root.Length) + ' (' + $o + ')')
        }
    }
    return @($out)
}

# The applied manifest of the current tree (there is exactly one after a clean apply).
function Get-ArlStManifestPath([hashtable]$SP) {
    $d = @(Get-ChildItem -LiteralPath $SP.ArchiveRoot -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($d.Count -eq 0) { return $null }
    return (Join-Path $d[-1].FullName 'move-manifest.json')
}

# Writes a tampered copy of the real manifest into a NEWER archive folder so LIFO accepts it and the
# refusal comes from the trust check (R11), then returns its path. Cleaned up by the caller.
function Write-ArlStTamperManifest([hashtable]$SP, [scriptblock]$Mutate, [switch]$UserWritable) {
    $real = Get-ArlStManifestPath $SP
    $obj = [System.IO.File]::ReadAllText($real) | ConvertFrom-Json
    & $Mutate $obj
    $tsDir = Join-Path $SP.ArchiveRoot '29991231-235959'
    New-ArlStDir $tsDir
    $file = Join-Path $tsDir 'move-manifest.json'
    Set-Content -LiteralPath $file -Value ($obj | ConvertTo-Json -Depth 12) -Encoding Ascii
    Set-ArlStProtect $tsDir (Get-ArlStExpectedAdminSddl)
    Set-ArlStOwnerAdmins $tsDir
    & icacls $file /reset /C /Q | Out-Null
    Set-ArlStOwnerAdmins $file
    if ($UserWritable) { Add-ArlStUserWrite $file 'S-1-5-32-545' }   # Users: an explicit non-admin writer
    return $file
}
function Remove-ArlStTamper([hashtable]$SP) {
    $tsDir = Join-Path $SP.ArchiveRoot '29991231-235959'
    if (Test-Path -LiteralPath $tsDir) { & icacls $tsDir /reset /T /C /Q | Out-Null; Remove-Item -LiteralPath $tsDir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-ArlStC12([string]$T, [hashtable]$SP) {
    $toolsBefore = Get-ArlStSnapshot $SP.Tools
    $cases = @(
        @{ Name = 'destino fuera de confianza'; Writable = $false; Mutate = { param($m) foreach ($a in $m.actions) { if ($a.kind -eq 'move') { $a.destination = (Join-Path $SP.Toolkit 'x.lnk'); break } } } },
        @{ Name = 'ruta con puntos'; Writable = $false; Mutate = { param($m) foreach ($a in $m.actions) { if ($a.kind -eq 'move') { $a.destination = (Join-Path $SP.Tools '..\DOSBox-X-ARL\x.lnk'); break } } } },
        @{ Name = 'manifiesto escribible por usuarios'; Writable = $true; Mutate = { param($m) } },
        @{ Name = 'raiz de herramientas cambiada'; Writable = $false; Mutate = { param($m) $m.roots.tools_root = $SP.Toolkit } }
    )
    $ok = $true; $detail = ''
    foreach ($c in $cases) {
        $path = Write-ArlStTamperManifest -SP $SP -Mutate $c.Mutate -UserWritable:$c.Writable
        $res = Invoke-ArlStChild $T @('-Undo', '-Manifest', $path)
        $moved = @(Compare-ArlStSnapshot $toolsBefore (Get-ArlStSnapshot $SP.Tools)).Count -ne 0
        # The refusal must be the trust check itself (R11): an earlier R10 (LIFO picked the wrong newest run)
        # would also exit 2 and hide a trust check that no longer runs (M08, M17, M24).
        $ids = if ($null -ne $res.Result) { @($res.Result.failed_controls) } else { @() }
        if (($res.Exit -ne 2) -or $moved -or ($ids -notcontains 'R11')) { $ok = $false; $detail += ($c.Name + '(exit=' + $res.Exit + ' rechazo=' + ($ids -join ',') + ') ') }
        Remove-ArlStTamper $SP
    }
    Add-ArlStResult 'C12' 'manifiestos manipulados rechazados' $ok $detail
}

# C04b: an operator edits the created colada shortcut, so undo must leave it in place (undo-skipped) and
# report a partial undo (exit 3). M19 (dropping the byte-match guard) would delete the edited file.
function Invoke-ArlStGroup2([string]$T) {
    $SP = New-ArlStBaseTree $T
    New-ArlStMoveMap $T | Out-Null
    Invoke-ArlStChild $T @('-Apply') | Out-Null
    $colada = Join-Path $SP.PublicDesktop ((Get-ArlFinalRows)[0].Name + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    try { $sc = $shell.CreateShortcut($colada); $sc.Description = 'editado por el operador'; $sc.Save() } finally { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    $undo = Invoke-ArlStChild $T @('-Undo')
    $c04b = ($undo.Exit -eq 3) -and ($null -ne $undo.Result) -and ($undo.Result.status -eq 'deshecho-parcial') -and (Test-Path -LiteralPath $colada -PathType Leaf)
    Add-ArlStResult 'C04b' 'deshacer respeta un acceso editado' $c04b ('exit=' + $undo.Exit + ' existe=' + (Test-Path -LiteralPath $colada))
}

# C05: any missing required input (R3), an unreadable icon source (R4) or a card missing an icon
# reference (R5) refuses with exit 2 and writes no archive. M01 (R3 never fires) is caught here.
function Invoke-ArlStGroup3([string]$T) {
    $required = @('ChispaExe', 'OperatorSettings', 'PassiveStd', 'PassiveNorm', 'PassiveWorkflow', 'DosboxExe', 'ShellDll', 'CardSource', 'EdgePath')
    $ok = $true; $detail = ''
    foreach ($key in $required) {
        $sub = Join-Path $T ('r3-' + $key)
        $SP = New-ArlStBaseTree $sub
        New-ArlStMoveMap $sub | Out-Null
        $victim = $SP[$key]
        if ($key -eq 'PassiveStd') { $victim = Join-Path $SP.Contrib 'Launch-ArlStandardizationPassiveTrace.cmd' }
        elseif ($key -eq 'PassiveNorm') { $victim = Join-Path $SP.Contrib 'Launch-ArlNormalizationPassiveTrace.cmd' }
        elseif ($key -eq 'PassiveWorkflow') { $victim = Join-Path $SP.Contrib 'Launch-ArlPassiveWorkflowTrace.ps1' }
        Remove-Item -LiteralPath $victim -Force -ErrorAction SilentlyContinue
        $res = Invoke-ArlStChild $sub @('-Apply')
        if (($res.Exit -ne 2) -or (Test-Path -LiteralPath $SP.ArchiveRoot)) { $ok = $false; $detail += ('R3:' + $key + '(exit=' + $res.Exit + ') ') }
    }
    # R4: replace the icon-bearing exe with a data file so icon index 0 cannot be read.
    $subR4 = Join-Path $T 'r4'
    $SP4 = New-ArlStBaseTree $subR4
    New-ArlStMoveMap $subR4 | Out-Null
    Set-Content -LiteralPath $SP4.DosboxExe -Value 'no soy un ejecutable' -Encoding Ascii -NoNewline
    $r4 = Invoke-ArlStChild $subR4 @('-Apply')
    if (($r4.Exit -ne 2) -or (Test-Path -LiteralPath $SP4.ArchiveRoot)) { $ok = $false; $detail += ('R4(exit=' + $r4.Exit + ') ') }
    # R5: a card that never references iconos/guia.png.
    $subR5 = Join-Path $T 'r5'
    $SP5 = New-ArlStBaseTree $subR5
    New-ArlStMoveMap $subR5 | Out-Null
    Set-Content -LiteralPath $SP5.CardSource -Value '<html><body>Analizar colada sin iconos</body></html>' -Encoding Ascii -NoNewline
    $r5 = Invoke-ArlStChild $subR5 @('-Apply')
    if (($r5.Exit -ne 2) -or (Test-Path -LiteralPath $SP5.ArchiveRoot)) { $ok = $false; $detail += ('R5(exit=' + $r5.Exit + ') ') }
    Add-ArlStResult 'C05' 'faltantes e insumos invalidos rechazados' $ok $detail
}

# C06: unknown items inside ARL Diagnostics are left in place, counted (desconocidos=3) and the folder is
# kept. M11 (unknown -> mover) would move them out. C07 then re-creates two legacy shortcuts.
function Invoke-ArlStGroup4([string]$T) {
    $SP = New-ArlStBaseTree $T
    New-ArlStMoveMap $T | Out-Null
    $diag = Join-Path $SP.PublicDesktop 'ARL Diagnostics'
    New-ArlStLnk (Join-Path $diag 'Planilla turnos.lnk') (Join-Path $T 'otros\planilla.xlsx') '' '' '' ''
    New-ArlStFile (Join-Path $diag 'notas.txt') 'apuntes del turno'
    New-ArlStLnk (Join-Path $diag ('Diagn' + $script:ArlAccentO + 'stico [copia].lnk')) (Join-Path $T 'otros\bloc.exe') '' '' '' ''
    $ap = Invoke-ArlStChild $T @('-Apply')
    $r = $ap.Result
    $keptUnknown = (Test-Path -LiteralPath (Join-Path $diag 'Planilla turnos.lnk')) -and (Test-Path -LiteralPath (Join-Path $diag 'notas.txt')) -and (Test-Path -LiteralPath $diag -PathType Container)
    $c06 = ($ap.Exit -eq 0) -and ($null -ne $r) -and ($r.counts.desconocidos -eq 3) -and $keptUnknown
    Add-ArlStResult 'C06' 'lo desconocido no se toca' $c06 ('desconocidos=' + $(if ($r) { $r.counts.desconocidos } else { '?' }) + ' intacto=' + $keptUnknown)

    # C07: a re-created legacy colada shortcut becomes a duplicate; a re-created emulator goes to Simuladores.
    New-ArlStLnk (Join-Path $SP.PublicDesktop 'ARL 3460 - Analizar.lnk') $SP.ChispaExe '' '' '' ''
    New-ArlStCmd (Join-Path $SP.Contrib 'Launch-ArlImpactEmulatorFormatSafeLoopTrace.cmd')
    New-ArlStLnk (Join-Path $SP.PublicDesktop '90 EMULATOR.lnk') (Join-Path $SP.Contrib 'Launch-ArlImpactEmulatorFormatSafeLoopTrace.cmd') '' '' '' ''
    $ap2 = Invoke-ArlStChild $T @('-Apply')
    $archives = @(Get-ChildItem -LiteralPath $SP.ArchiveRoot -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)
    $a2 = if ($archives.Count -ge 2) { $archives[-1].FullName } else { '' }
    $dupOk = $a2 -and (Test-Path -LiteralPath (Join-Path $a2 'duplicados\ARL 3460 - Analizar.lnk'))
    $emuOk = Test-Path -LiteralPath (Join-Path $SP.Tools 'Simuladores\90 EMULATOR.lnk')
    # The legacy colada shortcut belongs in Accesos-anteriores, never Diagnostico: without its own rule it
    # falls to the under-ARL rule and still lands a duplicate there (M06).
    $legacyOk = (Test-Path -LiteralPath (Join-Path $SP.Tools 'Accesos-anteriores\ARL 3460 - Analizar.lnk') -PathType Leaf) -and
        (@(Get-ChildItem -LiteralPath (Join-Path $SP.Tools 'Diagnostico') -Filter 'ARL 3460 - Analizar*' -Force -ErrorAction SilentlyContinue).Count -eq 0)
    $chispaOnD = @(Get-ChildItem -LiteralPath $SP.PublicDesktop -Filter *.lnk -Force -ErrorAction SilentlyContinue | Where-Object {
        $lnk = (Read-ArlShortcut $_.FullName); $lnk -and ([System.IO.Path]::GetFileName($lnk.Target) -eq 'Chispa.Operator.exe') }).Count
    $c07 = ($ap2.Exit -eq 0) -and $dupOk -and $emuOk -and $legacyOk -and ($chispaOnD -eq 1)
    Add-ArlStResult 'C07' 'duplicado a duplicados; emulador a Simuladores' $c07 ('dup=' + $dupOk + ' emu=' + $emuOk + ' anteriores=' + $legacyOk + ' chispaEnD=' + $chispaOnD)
}

# C08: a pre-existing H (exact SDDL, owner BA) already holding a DIFFERENT file at a move destination:
# the pre-placed file is untouched and the incoming one gets a ` (<ts>)` collision suffix. M02 (collision
# resolver returns the desired path unchanged) is caught here.
function Invoke-ArlStGroup5([string]$T) {
    $SP = New-ArlStBaseTree $T
    New-ArlStMoveMap $T | Out-Null
    $diagDir = Join-Path $SP.Tools 'Diagnostico'
    New-ArlStDir $SP.Tools
    Set-ArlStProtect $SP.Tools (Get-ArlStExpectedAdminSddl)
    Set-ArlStOwnerAdmins $SP.Tools
    New-ArlStDir $diagDir
    $preplaced = Join-Path $diagDir '20 Inspect Last ARL Run.lnk'
    New-ArlStLnk $preplaced (Join-Path $SP.Toolkit 'algo-distinto.cmd') '' '' '' 'preexistente'
    $preHash = (Get-FileHash -LiteralPath $preplaced -Algorithm SHA256).Hash.ToLowerInvariant()
    $ap = Invoke-ArlStChild $T @('-Apply')
    $sameHash = ((Get-FileHash -LiteralPath $preplaced -Algorithm SHA256).Hash.ToLowerInvariant() -eq $preHash)
    $suffixed = @(Get-ChildItem -LiteralPath $diagDir -Filter '20 Inspect Last ARL Run (*).lnk' -Force -ErrorAction SilentlyContinue).Count -ge 1
    $c08 = ($ap.Exit -eq 0) -and $sameHash -and $suffixed
    Add-ArlStResult 'C08' 'colision conserva el archivo previo' $c08 ('intacto=' + $sameHash + ' sufijo=' + $suffixed)
}
# --- result accounting + raw child + junction primitive ------------------------------------------------
$script:ArlStResults = [System.Collections.Generic.List[object]]::new()
$script:ArlStJunctions = [System.Collections.Generic.List[string]]::new()

function Add-ArlStResult([string]$Id, [string]$Name, [bool]$Pass, [string]$Detail) {
    [void]$script:ArlStResults.Add(@{ Id = $Id; Name = $Name; Pass = $Pass; Detail = $Detail })
    if ($Pass) { Write-ArlLine ('  PASS  ' + $Id + '  ' + $Name) }
    else { Write-ArlLine ('  FAIL  ' + $Id + '  ' + $Name + '  ' + $Detail) }
}

# Like Invoke-ArlStChild but with a caller-supplied argv (no fixed path parameters), for the R2 cases (C19).
function Invoke-ArlStRaw([string]$T, [string[]]$Argv) {
    $exe = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
    $full = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + $Argv
    $savedRoot = $env:ARL_DESKTOP_SELFTEST_ROOT; $savedDepth = $env:ARL_DESKTOP_SELFTEST_DEPTH
    $env:ARL_DESKTOP_SELFTEST_ROOT = $T
    $env:ARL_DESKTOP_SELFTEST_DEPTH = '1'
    try {
        $lines = & $exe @full 2>&1 | ForEach-Object { [string]$_ }
        $code = $LASTEXITCODE
    } finally {
        $env:ARL_DESKTOP_SELFTEST_ROOT = $savedRoot; $env:ARL_DESKTOP_SELFTEST_DEPTH = $savedDepth
    }
    $result = $null
    foreach ($ln in @($lines)) {
        if ($ln -like 'ARL-DESKTOP-RESULT *') {
            try { $result = $ln.Substring('ARL-DESKTOP-RESULT '.Length) | ConvertFrom-Json } catch { $result = $null }
        }
    }
    return @{ Exit = $code; Result = $result; Lines = @($lines) }
}

# Creates a directory junction $Link -> $Target and records it for teardown (never a symlink: junctions
# need no privilege and are exactly what an operator's roaming profile tooling tends to leave behind).
function New-ArlStJunction([string]$Link, [string]$Target) {
    New-ArlStDir $Target
    New-ArlStDir (Split-Path -Parent $Link)
    New-Item -ItemType Junction -Path $Link -Value $Target | Out-Null
    [void]$script:ArlStJunctions.Add($Link)
}

# C11: a junction anywhere in Staging, ArchiveRoot, Tools, Guide or the desktops makes -Apply refuse (R6)
# before it writes anything; the junction target is left byte-for-byte untouched and no manifest appears.
function Invoke-ArlStGroup6([string]$T) {
    $ok = $true; $detail = ''
    $cases = @(
        @{ Name = 'j-tools'; Key = 'Tools' },
        @{ Name = 'j-guide'; Key = 'Guide' },
        @{ Name = 'j-archive'; Key = 'ArchiveRoot' },
        @{ Name = 'j-diag'; Key = 'Diag' }
    )
    foreach ($c in $cases) {
        $sub = Join-Path $T $c.Name
        $SP = New-ArlStBaseTree $sub
        $victima = Join-Path $sub 'victima'
        New-ArlStDir $victima
        New-ArlStFile (Join-Path $victima 'marcador.txt') 'no me toques'
        if ($c.Key -eq 'Diag') {
            New-ArlStMoveMap $sub | Out-Null
            $diagPath = Join-Path $SP.PublicDesktop 'ARL Diagnostics'
            & icacls $diagPath /reset /T /C /Q | Out-Null
            Remove-Item -LiteralPath $diagPath -Recurse -Force -ErrorAction SilentlyContinue
            New-ArlStJunction $diagPath $victima
        } else {
            if ($c.Key -eq 'ArchiveRoot') { New-ArlStDir $SP.Staging }
            New-ArlStJunction $SP[$c.Key] $victima
        }
        $before = Get-ArlStSnapshot $victima
        $res = Invoke-ArlStChild $sub @('-Apply')
        $after = Get-ArlStSnapshot $victima
        $unchanged = (@(Compare-ArlStSnapshot $before $after).Count -eq 0)
        $noManifest = -not (Test-Path -LiteralPath (Join-Path $victima 'move-manifest.json'))
        # The refusal must be R6: a later ownership or writer refusal (R7) of the junction target also exits 2
        # and would hide a reparse check that no longer runs (M07).
        $ids = if ($null -ne $res.Result) { @($res.Result.failed_controls) } else { @() }
        if (($res.Exit -ne 2) -or (-not $unchanged) -or (-not $noManifest) -or ($ids -notcontains 'R6')) {
            $ok = $false; $detail += ($c.Name + '(exit=' + $res.Exit + ' rechazo=' + ($ids -join ',') + ' intacto=' + $unchanged + ' sinmanif=' + $noManifest + ') ')
        }
    }
    Add-ArlStResult 'C11' 'enlaces (junctions) rechazados' $ok $detail
}

# C16: -Apply stopped after the first action (ARL_DESKTOP_FAIL_AFTER_ACTION) leaves a failed-partial
# manifest with both done and planned actions, and -Undo puts the public desktop back exactly. M03
# (dropping the initial manifest write) makes the manifest unreadable, so undo cannot recover: caught here.
function Invoke-ArlStGroup7([string]$T) {
    $SP = New-ArlStBaseTree $T
    New-ArlStMoveMap $T | Out-Null
    $pre = Get-ArlStSnapshot $SP.PublicDesktop
    $ap = Invoke-ArlStChild $T @('-Apply') @{ FailAfter = 1 }
    $failedOk = ($ap.Exit -eq 1) -and ($null -ne $ap.Result) -and ($ap.Result.status -eq 'error')
    $man = Get-ArlStManifestPath $SP
    $stateOk = $false; $mixOk = $false
    if ($man -and (Test-Path -LiteralPath $man -PathType Leaf)) {
        $obj = [System.IO.File]::ReadAllText($man) | ConvertFrom-Json
        $stateOk = ([string]$obj.state -eq 'failed-partial')
        $doneN = @($obj.actions | Where-Object { [string]$_.status -eq 'done' }).Count
        $planN = @($obj.actions | Where-Object { [string]$_.status -eq 'planned' }).Count
        $mixOk = ($doneN -ge 1) -and ($planN -ge 1)
    }
    $undo = Invoke-ArlStChild $T @('-Undo')
    $post = Get-ArlStSnapshot $SP.PublicDesktop
    $restored = ($undo.Exit -eq 0) -and (@(Compare-ArlStSnapshot $pre $post).Count -eq 0)
    $c16 = $failedOk -and $stateOk -and $mixOk -and $restored
    Add-ArlStResult 'C16' 'aplicacion interrumpida se deshace' $c16 ('exit=' + $ap.Exit + ' estado=' + $(if ($man) { [string]$obj.state } else { 'sin-manifiesto' }) + ' mezcla=' + $mixOk + ' restaurado=' + $restored)
}

# C17: Piso (operator) desktop items ARE moved; other users' desktops and the taskbar pins are report-only
# (SOLO INFORME / PENDIENTE MANUAL) and never touched. M15 (skipping the operator desktop) is caught here.
# C18: the drifted public colada is replaced (its old copy kept under reemplazados\Escritorio) and -Undo
# restores the exact drifted bytes. M12/M14/M18 all show up on this shortcut.
function Invoke-ArlStGroup8([string]$T) {
    $SP = New-ArlStBaseTree $T
    New-ArlStMoveMap $T | Out-Null
    # Piso emulator: a DIFFERENT launcher than the public '01 Bridge Emulator - IMPACT.lnk' (smoke), so it
    # collides at Simuladores\01 Bridge Emulator - IMPACT.lnk and takes a ` (<ts>)` suffix (not a duplicate).
    New-ArlStLnk (Join-Path $SP.OperatorDesktop '01 Bridge Emulator - IMPACT.lnk') (Join-Path $SP.Bridge 'Launch-ArlBridgeSafeLoop.cmd') '' '' '' ''
    $jc = Join-Path $SP.UsersRoot 'jcarlos\Desktop'
    New-ArlStLnk (Join-Path $jc '01 PRECHECK.lnk') (Join-Path $SP.Contrib 'Run-ArlOperatorPreflight.cmd') '' '' '' ''
    $svc = Join-Path $SP.UsersRoot 'svc-claude\Desktop'
    New-ArlStLnk (Join-Path $svc 'ARL x.lnk') $SP.ChispaExe '' '' '' ''
    New-ArlStLnk (Join-Path $SP.PisoPins 'ARL pin.lnk') (Join-Path $SP.Bridge 'Launch-ArlBridgeSmoke.cmd') '' '' '' ''
    $colada = Join-Path $SP.PublicDesktop ((Get-ArlFinalRows)[0].Name + '.lnk')
    New-ArlStLnk $colada (Join-Path $SP.Bridge 'Launch-ArlBridgeSmoke.cmd') '' '' '' 'colada a la deriva'
    $coladaShaOrig = (Get-FileHash -LiteralPath $colada -Algorithm SHA256).Hash.ToLowerInvariant()

    $preJc = Get-ArlStSnapshot $jc
    $preSvc = Get-ArlStSnapshot $svc
    $prePins = Get-ArlStSnapshot $SP.PisoPins

    $ap = Invoke-ArlStChild $T @('-Apply')
    $r = $ap.Result

    $simDir = Join-Path $SP.Tools 'Simuladores'
    $suffixed = @(Get-ChildItem -LiteralPath $simDir -Filter '01 Bridge Emulator - IMPACT (*).lnk' -Force -ErrorAction SilentlyContinue).Count -ge 1
    $goneFromOp = -not (Test-Path -LiteralPath (Join-Path $SP.OperatorDesktop '01 Bridge Emulator - IMPACT.lnk'))
    $jcUnchanged = (@(Compare-ArlStSnapshot $preJc (Get-ArlStSnapshot $jc)).Count -eq 0)
    $svcUnchanged = (@(Compare-ArlStSnapshot $preSvc (Get-ArlStSnapshot $svc)).Count -eq 0)
    $pinsUnchanged = (@(Compare-ArlStSnapshot $prePins (Get-ArlStSnapshot $SP.PisoPins)).Count -eq 0)
    $pendientes = ($null -ne $r) -and ([int]$r.counts.pendientes_manuales -ge 1)
    $informe = @($ap.Lines | Where-Object { $_ -like '*SOLO INFORME*' }).Count -ge 1
    $c17 = ($ap.Exit -eq 0) -and $suffixed -and $goneFromOp -and $jcUnchanged -and $svcUnchanged -and $pinsUnchanged -and $pendientes -and $informe
    Add-ArlStResult 'C17' 'piso movido; otros usuarios y anclajes solo informe' $c17 ('sufijo=' + $suffixed + ' piso=' + $goneFromOp + ' jc=' + $jcUnchanged + ' svc=' + $svcUnchanged + ' pins=' + $pinsUnchanged + ' pend=' + $pendientes + ' informe=' + $informe)

    $reemplazar = ($null -ne $r) -and ([int]$r.counts.reemplazar -eq 1)
    $archive = Get-ArlStManifestPath $SP
    $archDir = if ($archive) { Split-Path -Parent $archive } else { '' }
    $backup = if ($archDir) { Join-Path $archDir 'reemplazados\Escritorio\Analizar colada.lnk' } else { '' }
    $backupOk = $backup -and (Test-Path -LiteralPath $backup -PathType Leaf) -and ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -eq $coladaShaOrig)
    $coladaFixed = $false
    if (Test-Path -LiteralPath $colada -PathType Leaf) {
        $lnk = Read-ArlShortcut $colada
        $coladaFixed = $lnk -and ([System.IO.Path]::GetFileName($lnk.Target) -eq 'Chispa.Operator.exe')
    }
    $undo = Invoke-ArlStChild $T @('-Undo')
    $coladaBack = (Test-Path -LiteralPath $colada -PathType Leaf) -and ((Get-FileHash -LiteralPath $colada -Algorithm SHA256).Hash.ToLowerInvariant() -eq $coladaShaOrig)
    $c18 = ($ap.Exit -eq 0) -and $reemplazar -and $backupOk -and $coladaFixed -and ($undo.Exit -eq 0) -and $coladaBack
    Add-ArlStResult 'C18' 'la colada a la deriva se reemplaza y se restaura' $c18 ('reemplazar=' + $(if ($r) { $r.counts.reemplazar } else { '?' }) + ' respaldo=' + $backupOk + ' arreglada=' + $coladaFixed + ' restaurada=' + $coladaBack)
}

# C19: a path parameter outside the temp tree (or with -SelfTest, or -SelfTest -WhatIf) is refused (R2 on a
# direct call; inside this harness the depth guard makes the -SelfTest cases refuse with R9). The outside-temp
# case passes every other path under the temp tree, so only the -ArlRoot check can refuse it; a second -Apply
# passes only -ArlRoot under the temp tree and must be refused as mixed paths. M16 (R2 falls through) is
# caught because the -Apply cases then reach R3 or the real desktops instead of failed_controls carrying 'R2'.
function Invoke-ArlStGroup9([string]$T) {
    New-ArlStDir $T
    $SP = Get-ArlStPaths $T
    $r1 = Invoke-ArlStRaw $T @('-Apply', '-PublicDesktop', $SP.PublicDesktop, '-OperatorDesktop', $SP.OperatorDesktop, '-UsersRoot', $SP.UsersRoot,
        '-EdgePath', $SP.EdgePath, '-SystemRoot', $SP.SystemRoot, '-CardSource', $SP.CardSource, '-ArlRoot', 'C:\ARL-fuera-de-temp')
    $r1ok = ($r1.Exit -eq 2) -and ($null -ne $r1.Result) -and (@($r1.Result.failed_controls) -contains 'R2')
    $r2 = Invoke-ArlStRaw $T @('-SelfTest', '-PublicDesktop', (Join-Path $T 'x'))
    $r2ok = ($r2.Exit -eq 2)
    $r3 = Invoke-ArlStRaw $T @('-SelfTest', '-WhatIf')
    $r3ok = ($r3.Exit -eq 2)
    # Only -ArlRoot under the temp folder, every other path left at the real machine's value: all or nothing.
    $r4 = Invoke-ArlStRaw $T @('-Apply', '-ArlRoot', (Join-Path $T 'ARL'))
    $r4ok = ($r4.Exit -eq 2) -and ($null -ne $r4.Result) -and (@($r4.Result.failed_controls) -contains 'R2')
    $c19 = $r1ok -and $r2ok -and $r3ok -and $r4ok
    Add-ArlStResult 'C19' 'rutas fuera de la temporal y autoprueba con rutas rechazadas' $c19 ('arl=' + $r1.Exit + '/R2=' + $r1ok + ' ruta=' + $r2.Exit + ' whatif=' + $r3.Exit + ' mezcla=' + $r4.Exit + '/R2=' + $r4ok)
}

# C20: a run killed INSIDE one action (ARL_DESKTOP_FAIL_INSIDE_ACTION ends the process between two steps of
# that action) leaves the manifest at applying with that action in-progress, and -Undo still puts both
# desktops back. Three cut points: a move done but not recorded, a drifted shortcut already in the backup
# with nothing in its place, and a new shortcut on the desktop before its ACL reset. M21 (applying not
# reversible) and M22 (an unrecorded shortcut never recognised) are caught here.
function Invoke-ArlStGroup10([string]$T) {
    $ok = $true; $detail = ''
    $cases = @(
        @{ Name = 'a'; Point = 'movido'; MoveMap = $true; Colada = $false },
        @{ Name = 'b'; Point = 'respaldado'; MoveMap = $false; Colada = $true },
        @{ Name = 'c'; Point = 'creado-sin-acl'; MoveMap = $false; Colada = $false }
    )
    foreach ($c in $cases) {
        $sub = Join-Path $T $c.Name
        $SP = New-ArlStBaseTree $sub
        if ($c.MoveMap) { New-ArlStMoveMap $sub | Out-Null }
        $colada = Join-Path $SP.PublicDesktop ((Get-ArlFinalRows)[0].Name + '.lnk')
        $coladaSha = ''
        if ($c.Colada) {
            New-ArlStLnk $colada (Join-Path $SP.Bridge 'Launch-ArlBridgeSmoke.cmd') '' '' '' 'colada a la deriva'
            $coladaSha = (Get-FileHash -LiteralPath $colada -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $prePub = Get-ArlStSnapshot $SP.PublicDesktop
        $preOp = Get-ArlStSnapshot $SP.OperatorDesktop
        $ap = Invoke-ArlStChild $sub @('-Apply') @{ FailInside = $c.Point }
        $killed = ($ap.Exit -eq 9)
        $man = Get-ArlStManifestPath $SP
        $state = 'sin-manifiesto'; $inProgress = 0
        if ($man -and (Test-Path -LiteralPath $man -PathType Leaf)) {
            $obj = [System.IO.File]::ReadAllText($man) | ConvertFrom-Json
            $state = [string]$obj.state
            $inProgress = @($obj.actions | Where-Object { [string]$_.status -eq 'in-progress' }).Count
        }
        $undo = Invoke-ArlStChild $sub @('-Undo')
        $undoOk = ($undo.Exit -eq 0) -and ($null -ne $undo.Result) -and ([string]$undo.Result.status -eq 'deshecho')
        # A restored backup inherits its ACL from the desktop again, so the drifted case compares bytes only.
        $diffs = @(Compare-ArlStSnapshot $prePub (Get-ArlStSnapshot $SP.PublicDesktop) -IgnoreSddl:$c.Colada) + @(Compare-ArlStSnapshot $preOp (Get-ArlStSnapshot $SP.OperatorDesktop))
        $same = ($diffs.Count -eq 0)
        if ($c.Colada) { $same = $same -and (Test-Path -LiteralPath $colada -PathType Leaf) -and ((Get-FileHash -LiteralPath $colada -Algorithm SHA256).Hash.ToLowerInvariant() -eq $coladaSha) }
        $caseOk = $killed -and ($state -eq 'applying') -and ($inProgress -eq 1) -and $undoOk -and $same
        if (-not $caseOk) {
            $ok = $false
            $detail += ($c.Name + '(corte=' + $c.Point + ' exit=' + $ap.Exit + ' estado=' + $state + ' en-curso=' + $inProgress + ' deshacer=' + $undo.Exit + '/' + $(if ($undo.Result) { [string]$undo.Result.status } else { '?' }) + ' igual=' + $same + ' ' + (($diffs | Select-Object -First 3) -join '; ') + ') ')
        }
    }
    Add-ArlStResult 'C20' 'aplicacion cortada dentro de una accion se deshace' $ok $detail
}

# C21: the shortcuts Chispa's deploy scripts lay on the public desktop, with the names, targets, working
# folders and icon they use on Chispa main 4d72e1d (deploy scripts unchanged at b9c5053): Install-DosboxArlArtifact.ps1 (every DOSBox-X-ARL install:
# 00 DIRECTSERIAL BYPASS, 01 OBSERVE ONLY, 02 REACTIVE SAFE, 90 EMULATOR, Diagnosticos ARL),
# Reset-ArlDesktopShortcuts.ps1 (Diagnostics - Serial Traces at the top level) and
# Install-ArlOperatorExperience.ps1 (ARL 3460 - Analizar). -Apply must move each one to its admin group and
# leave the four final icons. Then Install-ArlOperatorShortcuts.ps1's set is laid down on top, as the next
# deploy does: revisar must report cambios-pendientes (the rollout gate relies on it), -Apply clears them
# (a different target takes a suffix, the same launcher goes to duplicados) and a last revisar is
# sin-cambios. M23 (targets under the ARL root no longer routed to Diagnostico) is caught here.
function Invoke-ArlStGroup11([string]$T) {
    $SP = New-ArlStBaseTree $T
    $icon = $SP.DosboxExe + ',0'
    $diagDir = Join-Path $SP.ArlRoot 'diagnostics'
    $toolsDir = Join-Path $SP.ArlRoot 'tools'
    $bypassKit = Join-Path $SP.Toolkit 'Launch-ArlImpactDirectSerialBypass.cmd'
    $bypassTools = Join-Path $toolsDir 'Launch-ImpactDirectSerialBypass.cmd'
    $observe = Join-Path $SP.Toolkit 'Launch-ArlImpactObserveOnlyTrace.cmd'
    $reactive = Join-Path $SP.Toolkit 'Launch-ArlImpactReactiveSafeTrace.cmd'
    $emu = Join-Path $SP.Contrib 'Launch-ArlImpactEmulatorFormatSafeLoopTrace.cmd'
    foreach ($f in @($bypassKit, $bypassTools, $observe, $emu)) { New-ArlStCmd $f }
    $D = $SP.PublicDesktop

    $round1 = @(
        @{ Name = '00 DIRECTSERIAL BYPASS'; Target = $bypassKit; WorkDir = $SP.Toolkit; Description = ''; Group = 'Diagnostico' },
        @{ Name = '01 OBSERVE ONLY'; Target = $observe; WorkDir = $SP.Toolkit; Description = ''; Group = 'Diagnostico' },
        @{ Name = '02 REACTIVE SAFE'; Target = $reactive; WorkDir = $SP.Toolkit; Description = ''; Group = 'Diagnostico' },
        @{ Name = '90 EMULATOR'; Target = $emu; WorkDir = $SP.Contrib; Description = ''; Group = 'Simuladores' },
        @{ Name = 'Diagnosticos ARL'; Target = $diagDir; WorkDir = $diagDir; Description = ''; Group = 'Diagnostico' },
        @{ Name = 'Diagnostics - Serial Traces'; Target = $diagDir; WorkDir = $diagDir; Description = ''; Group = 'Diagnostico' },
        @{ Name = 'ARL 3460 - Analizar'; Target = $SP.ChispaExe; WorkDir = $SP.OperatorDir; Description = 'Analizar muestras con el ARL 3460'; Group = 'Accesos-anteriores' }
    )
    foreach ($l in $round1) { New-ArlStLnk (Join-Path $D ($l.Name + '.lnk')) $l.Target '' $l.WorkDir $icon $l.Description }
    $ap1 = Invoke-ArlStChild $T @('-Apply')
    $r1 = $ap1.Result
    $placed = @($round1 | Where-Object { (-not (Test-Path -LiteralPath (Join-Path $D ($_.Name + '.lnk')))) -and (Test-Path -LiteralPath (Join-Path (Join-Path $SP.Tools $_.Group) ($_.Name + '.lnk')) -PathType Leaf) })
    $finalsOk = $true
    foreach ($f in (Get-ArlStFinalLeaves)) { if (-not (Test-Path -LiteralPath (Join-Path $D $f) -PathType Leaf)) { $finalsOk = $false } }
    $round1Ok = ($ap1.Exit -eq 0) -and ($null -ne $r1) -and ([string]$r1.status -eq 'aplicado') -and ([int]$r1.counts.mover -eq $round1.Count) -and
        ([int]$r1.counts.desconocidos -eq 0) -and ($placed.Count -eq $round1.Count) -and $finalsOk

    $round2 = @(
        @{ Name = '00 DIRECTSERIAL BYPASS'; Target = $bypassTools; WorkDir = $toolsDir },
        @{ Name = '01 OBSERVE ONLY'; Target = $observe; WorkDir = $SP.Toolkit },
        @{ Name = '02 REACTIVE SAFE'; Target = $reactive; WorkDir = $SP.Toolkit },
        @{ Name = '90 EMULATOR'; Target = $emu; WorkDir = $SP.Contrib },
        @{ Name = 'Diagnosticos ARL'; Target = $diagDir; WorkDir = $diagDir }
    )
    foreach ($l in $round2) { New-ArlStLnk (Join-Path $D ($l.Name + '.lnk')) $l.Target '' $l.WorkDir $icon '' }
    $rev = Invoke-ArlStChild $T @()
    $revOk = ($rev.Exit -eq 0) -and ($null -ne $rev.Result) -and ([string]$rev.Result.status -eq 'cambios-pendientes') -and
        ([int]$rev.Result.counts.mover -eq 1) -and ([int]$rev.Result.counts.archivar -eq ($round2.Count - 1))
    $ap2 = Invoke-ArlStChild $T @('-Apply')
    $left = @($round2 | Where-Object { Test-Path -LiteralPath (Join-Path $D ($_.Name + '.lnk')) })
    $suffixed = @(Get-ChildItem -LiteralPath (Join-Path $SP.Tools 'Diagnostico') -Filter '00 DIRECTSERIAL BYPASS (*).lnk' -Force -ErrorAction SilentlyContinue).Count -eq 1
    $archives = @(Get-ChildItem -LiteralPath $SP.ArchiveRoot -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)
    $dups = 0
    if ($archives.Count -ge 2) {
        foreach ($l in @($round2 | Select-Object -Skip 1)) { if (Test-Path -LiteralPath (Join-Path (Join-Path $archives[-1].FullName 'duplicados') ($l.Name + '.lnk')) -PathType Leaf) { $dups++ } }
    }
    $rev2 = Invoke-ArlStChild $T @()
    $round2Ok = $revOk -and ($ap2.Exit -eq 0) -and ($null -ne $ap2.Result) -and ([string]$ap2.Result.status -eq 'aplicado') -and ($left.Count -eq 0) -and
        $suffixed -and ($dups -eq ($round2.Count - 1)) -and ($rev2.Exit -eq 0) -and ($null -ne $rev2.Result) -and ([string]$rev2.Result.status -eq 'sin-cambios')

    $c21 = $round1Ok -and $round2Ok
    Add-ArlStResult 'C21' 'accesos de los instaladores de Chispa van a Herramientas-Admin' $c21 ('ronda1=' + $round1Ok + ' exit=' + $ap1.Exit +
        ' mover=' + $(if ($r1) { $r1.counts.mover } else { '?' }) + ' desconocidos=' + $(if ($r1) { $r1.counts.desconocidos } else { '?' }) +
        ' en-grupo=' + $placed.Count + '/' + $round1.Count + ' finales=' + $finalsOk +
        ' revisar=' + $(if ($rev.Result) { [string]$rev.Result.status + '/m' + $rev.Result.counts.mover + '/a' + $rev.Result.counts.archivar } else { 'nulo' }) +
        ' ronda2-exit=' + $ap2.Exit + ' quedan=' + $left.Count + ' sufijo=' + $suffixed + ' duplicados=' + $dups +
        ' revisar-final=' + $(if ($rev2.Result) { [string]$rev2.Result.status } else { 'nulo' }))
}
# --- static (source-level) controls ---------------------------------------------------------------------
# These read the shipped .ps1 and card and need no Windows APIs, so they run on any engine: the test
# harness dot-sources this file and calls them directly, which also works on a developer machine off
# Windows. CI itself runs only on windows-latest. C09 is both static (this) and dynamic (group 1); the
# ids coincide on purpose and the final tally keeps them distinct.

# Card text as a reader sees it: entities decoded, accents folded, lower case. Used for the wording checks,
# so "arg&oacute;n" on the card matches "argon" on the notice Chispa prints.
function ConvertTo-ArlStReadable([string]$Html) {
    $t = [System.Net.WebUtility]::HtmlDecode(($Html -replace '<[^>]+>', ' ')).Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return (($sb.ToString() -replace '\s+', ' ').ToLowerInvariant())
}

# C15: the card is ASCII, offline, names every final icon, and says what the paper Chispa prints says.
# Wording pinned to Chispa b9c5053 (SinChispaNoticeComposer, unchanged since 4d72e1d; Chispa.Operator's launcher
# error popup): its ForbiddenWording list never appears, the notice title and its QUE HACER steps appear on the
# technicians' page, and no emulator jargon leaks in. Structure: two printable pages, technicians first; the
# full Serrano icon names only on the second page; printed body type of 14pt or more. Serrano's spark check
# reads IMPACT's screen on every B/C session (and today's last colada sheet as an extra stop) and never
# sends him to burn a sample in the daily icon. The page count itself is checked by rendering (see the PR),
# not here.
function Invoke-ArlStCardStatic([string]$CardPath = '') {
    $card = if ($CardPath) { $CardPath } else { Join-Path (Split-Path -Parent $PSCommandPath) 'operator-desktop\cual-uso.html' }
    if (-not (Test-Path -LiteralPath $card -PathType Leaf)) { Add-ArlStResult 'C15' 'tarjeta cual-uso.html valida' $false 'no existe junto al script'; return }
    $cardBytes = [System.IO.File]::ReadAllBytes($card)
    $ascii = (@($cardBytes | Where-Object { $_ -gt 0x7F }).Count -eq 0)
    $text = [System.Text.Encoding]::ASCII.GetString($cardBytes)
    $rows = @(Get-ArlFinalRows)
    $names = @($rows | ForEach-Object { $_.Name })
    $missing = @($names | Where-Object { $text.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 })
    $wantPng = @((Get-ArlIconSet @{ DosboxExe = ''; ShellDll = '' }) | ForEach-Object { $_.Png } | Sort-Object)
    $gotPng = @([regex]::Matches($text, '(?i)src\s*=\s*"iconos/([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $pngOk = (($wantPng -join '|') -eq ($gotPng -join '|'))
    $noWeb = ($text -notmatch '(?i)https?:') -and ($text -notmatch '(?i)<script')

    $read = ConvertTo-ArlStReadable $text
    $forbidden = @('ruido', 'razon', 'no repita', 'fuera de banda', 'dosbox', '(stand)', 'nullmodem', 'directserial', 'emulator')
    $saysForbidden = @($forbidden | Where-Object { $read.IndexOf($_, [System.StringComparison]::Ordinal) -ge 0 })

    # The spark check never creates a colada record: burning a sample in the daily icon prints a sheet that is
    # already on the portal (the NO VALIDA case on page two), so no sentence may tell anyone to burn in it.
    $noThrowaway = -not [regex]::IsMatch($read, 'queme[^.]*en analizar colada')

    $sections = @([regex]::Matches($text, '(?s)<section class="hoja pagina ([a-z]+)">(.*?)</section>'))
    $shapeOk = ($sections.Count -eq 2) -and ($sections[0].Groups[1].Value -eq 'tecnicos') -and ($sections[1].Groups[1].Value -eq 'serrano')
    $wordingOk = $false; $pageOneClean = $false; $sparkOk = $false; $noDailyTest = $false
    if ($shapeOk) {
        # Page two opens with the spark box, pinned word for word (tags and accents dropped), before the B/C
        # rows. A list of required phrases let every weakening a reviewer planted through: dropping the
        # prohibition or the SIN CHISPA stop, making the screen check apply only on days with no colada, a
        # 1 kp floor, a sentence appended to accept anyway. The screen check runs on every B/C session, since a
        # sheet from earlier in the day says nothing about later (the spark stopped on the afternoon of
        # 2026-09-09; standardization-20260909-170217 was dark). Its floor is Chispa's BurnSparkClassifier.SparkedMaximumFloorKilopulses,
        # 10 kp, the limit the SIN CHISPA sheet prints; "no se puede leer" covers the groups Chispa b9c5053
        # withholds with no sheet at all (no_readable_intensities).
        $twoHtml = $sections[1].Groups[2].Value
        $twoRead = ConvertTo-ArlStReadable $twoHtml
        $sparkBox = 'antes de aceptar: revise que haya chispa ' +
            'si la ultima hoja de colada real de hoy es aviso: sin chispa , no empiece y avise a calidad. ' +
            'si es reporte de analisis , de todos modos haga el punto 2. ' +
            'siempre, en su primera quema de b o c y antes de aceptar, vea en la pantalla de impact la intensidad de cada canal. ' +
            'si el canal mas alto queda por debajo de 10 kp (el mismo limite que imprime la hoja sin chispa) o no se puede leer: ' +
            'pare, no acepte los factores y siga el punto sin chispa de abajo. ' +
            'no use analizar colada para probar la chispa: esa hoja se envia al portal.'
        $boxes = @([regex]::Matches($twoHtml, '(?s)<div class="caja[^"]*">\s*<h2>Antes de aceptar: revise que haya chispa</h2>.*?</div>'))
        $firstRow = $twoHtml.IndexOf('<span class="letra">B</span>', [System.StringComparison]::Ordinal)
        $sparkOk = ($boxes.Count -eq 1) -and ((ConvertTo-ArlStReadable $boxes[0].Value).Trim() -eq $sparkBox) -and
            ($firstRow -gt $boxes[0].Index)
        # Anywhere on page two, a sentence may name Analizar colada next to a burn, a test, a sample or the spark
        # only to forbid it: any other such sentence sends Ing. Serrano to burn a colada record in the daily icon.
        $prohibition = 'no use analizar colada para probar la chispa: esa hoja se envia al portal'
        $dailyTest = @($twoRead.Split('.') | ForEach-Object { $_.Trim() } | Where-Object {
                ($_.IndexOf('analizar colada', [System.StringComparison]::Ordinal) -ge 0) -and ($_ -match 'quem|prueb|prob|muestra|chispa') -and ($_ -ne $prohibition) })
        $noDailyTest = ($dailyTest.Count -eq 0)
        $one = $sections[0].Groups[2].Value
        $oneRead = ConvertTo-ArlStReadable $one
        $must = @('arl 3460 - aviso: sin chispa', 'prepare de nuevo la muestra y repita la quema', 'revise fuente de chispa, argon y soporte')
        $wordingOk = (@($must | Where-Object { $oneRead.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 }).Count -eq 0) -and
            ($one.IndexOf($rows[0].Name, [System.StringComparison]::Ordinal) -ge 0)
        $serranoNames = @($names | Where-Object { $_.StartsWith('Ing. Serrano - ', [System.StringComparison]::Ordinal) })
        $pageOneClean = ($serranoNames.Count -eq 2) -and (@($serranoNames | Where-Object { $one.IndexOf($_, [System.StringComparison]::Ordinal) -ge 0 }).Count -eq 0)
    }
    $printPt = 0.0
    $pm = [regex]::Match($text, '(?s)@media print\s*\{\s*body\s*\{[^}]*?font-size:\s*([0-9.]+)pt')
    if ($pm.Success) { $printPt = [double]::Parse($pm.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) }
    $printOk = ($printPt -ge 14)

    $c15 = $ascii -and (@($missing).Count -eq 0) -and $pngOk -and $noWeb -and (@($saysForbidden).Count -eq 0) -and $shapeOk -and $wordingOk -and $pageOneClean -and $printOk -and $sparkOk -and $noThrowaway -and $noDailyTest
    Add-ArlStResult 'C15' 'tarjeta cual-uso.html valida' $c15 ('ascii=' + $ascii + ' faltan=[' + (@($missing) -join ',') + '] png=' + $pngOk + '(' + ($gotPng -join ',') + ') web=' + $noWeb +
        ' prohibidas=[' + (@($saysForbidden) -join ',') + '] paginas=' + $shapeOk + ' chispa=' + $wordingOk + ' hoja1-sin-serrano=' + $pageOneClean + ' letra=' + $printPt +
        ' revision-chispa=' + $sparkOk + ' sin-quema-de-prueba=' + $noThrowaway + ' hoja2-sin-prueba-diaria=' + $noDailyTest)
}

# C09 static: no process/serial verbs anywhere, and every filesystem/ACL mutation verb lives either in the
# autoprueba region (this test scaffolding) or inside the Invoke-ArlAction chokepoint (proved by AST extent).
# Tokens are assembled from fragments so the only literal end-region marker in the file is the real
# closing marker, and so the banned strings themselves never appear verbatim in the source.
function Invoke-ArlStSourceStatic {
    $text = [System.IO.File]::ReadAllText($PSCommandPath)
    $tag = '#' + 'region autoprueba'
    $endTag = '#' + 'endregion autoprueba'
    $regionStart = $text.IndexOf($tag, [System.StringComparison]::Ordinal)
    $endAt = $text.IndexOf($endTag, [System.StringComparison]::Ordinal)
    if ($regionStart -lt 0 -or $endAt -lt 0) { Add-ArlStResult 'C09' 'sin procesos ni mutaciones fuera del punto unico' $false 'no se hallo la region autoprueba'; return }
    $regionEnd = $endAt + $endTag.Length
    $outside = $text.Substring(0, $regionStart) + $text.Substring($regionEnd)

    $banned = @(('Get' + '-Process'), ('Stop' + '-Process'), ('Start' + '-Process'), ('Diagnostics.' + 'Process'),
        ('task' + 'kill'), ('Invoke' + '-Item'), ('sc' + '.exe'), ('Restart' + '-'), ('System.IO.' + 'Ports'),
        ('Serial' + 'Port'), ('COM' + '5'))
    $foundBanned = @($banned | Where-Object { $outside.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })

    $errs = $null; $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$errs)
    $fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ArlAction' }, $true))
    if ($fn.Count -ne 1) { Add-ArlStResult 'C09' 'sin procesos ni mutaciones fuera del punto unico' $false ('Invoke-ArlAction aparece ' + $fn.Count + ' veces'); return }
    $actStart = $fn[0].Extent.StartOffset
    $actEnd = $fn[0].Extent.EndOffset

    $mut = @(('New' + '-Item'), ('Set' + '-Acl'), ('Remove' + '-Item'), ('Copy' + '-Item'), ('Move' + '-Item'),
        ('Set' + '-Content'), ('Rename' + '-Item'), ('ic' + 'acls'), ('SetAccess' + 'Control'),
        (']::' + 'Move('), (']::' + 'Delete('), (']::' + 'Copy('), (']::' + 'Replace('), ('Create' + 'Directory'), ('.Save' + '()'))
    $violations = [System.Collections.Generic.List[string]]::new()
    foreach ($tok in $mut) {
        $from = 0
        while ($true) {
            $i = $text.IndexOf($tok, $from, [System.StringComparison]::Ordinal)
            if ($i -lt 0) { break }
            $inRegion = ($i -ge $regionStart -and $i -lt $regionEnd)
            $inAction = ($i -ge $actStart -and $i -lt $actEnd)
            if (-not $inRegion -and -not $inAction) { [void]$violations.Add($tok + '@' + $i) }
            $from = $i + $tok.Length
        }
    }
    $c09 = (@($foundBanned).Count -eq 0) -and (@($violations).Count -eq 0)
    Add-ArlStResult 'C09' 'sin procesos ni mutaciones fuera del punto unico' $c09 ('prohibidos=[' + (@($foundBanned) -join ',') + '] fuera=[' + (@($violations) -join ',') + ']')
}

function Invoke-ArlStStatic {
    # C13: the script is ASCII with no BOM (PS 5.1 reads a BOM-less file as ANSI).
    $bytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
    $nonAscii = @($bytes | Where-Object { $_ -gt 0x7F }).Count
    Add-ArlStResult 'C13' 'el script es ASCII sin BOM' ($nonAscii -eq 0) ('bytes >=0x80: ' + $nonAscii)

    # C14: operator-facing names and icon file names match none of the old cleanup tokens.
    $union = '(?i)(' + $script:ArlTokenUnion + ')'
    $labels = @((Get-ArlFinalRows) | ForEach-Object { $_.Name })
    $labels += @('Guia-Operador', 'cual-uso.html', 'iconos')
    $labels += @((Get-ArlIconSet @{ DosboxExe = ''; ShellDll = '' }) | ForEach-Object { $_.Png })
    $hits = @($labels | Where-Object { $_ -match $union })
    Add-ArlStResult 'C14' 'nombres visibles sin jerga tecnica' (@($hits).Count -eq 0) ('coinciden: ' + (@($hits) -join ', '))

    Invoke-ArlStCardStatic
    Invoke-ArlStSourceStatic
}

# --- top-level driver ------------------------------------------------------------------------------------
function Invoke-ArlSelfTest([string[]]$Controls) {
    if (-not (Test-ArlWindows)) {
        Write-ArlLine '  SKIP  autoprueba solo en Windows'
        Write-ArlResult 'autoprueba' 'autoprueba-ok' $null $null (New-ArlCounts) @()
        return 0
    }
    $want = [System.Collections.Generic.List[string]]::new()
    foreach ($c in @($Controls)) { foreach ($p in ([string]$c).Split(',')) { $tok = $p.Trim(); if ($tok) { [void]$want.Add($tok) } } }
    $filter = @($want)
    $wanted = { param($ids) if ($filter.Count -eq 0) { return $true } foreach ($id in $ids) { if ($filter -contains $id) { return $true } } return $false }

    $script:ArlStResults = [System.Collections.Generic.List[object]]::new()
    $script:ArlStJunctions = [System.Collections.Generic.List[string]]::new()
    $T = Join-Path (Get-ArlLongPath ([IO.Path]::GetTempPath())) ('arl-desktop-autoprueba-' + [guid]::NewGuid().ToString('N'))

    $groups = @(
        @{ Name = 'estatico'; Controls = @('C13', 'C14', 'C15', 'C09'); Run = { param($d) Invoke-ArlStStatic } },
        @{ Name = 'g1'; Controls = @('C01', 'C02', 'C10', 'C03', 'C12', 'C04', 'C09'); Run = { param($d) Invoke-ArlStGroup1 $d } },
        @{ Name = 'g2'; Controls = @('C04b'); Run = { param($d) Invoke-ArlStGroup2 $d } },
        @{ Name = 'g3'; Controls = @('C05'); Run = { param($d) Invoke-ArlStGroup3 $d } },
        @{ Name = 'g4'; Controls = @('C06', 'C07'); Run = { param($d) Invoke-ArlStGroup4 $d } },
        @{ Name = 'g5'; Controls = @('C08'); Run = { param($d) Invoke-ArlStGroup5 $d } },
        @{ Name = 'g6'; Controls = @('C11'); Run = { param($d) Invoke-ArlStGroup6 $d } },
        @{ Name = 'g7'; Controls = @('C16'); Run = { param($d) Invoke-ArlStGroup7 $d } },
        @{ Name = 'g8'; Controls = @('C17', 'C18'); Run = { param($d) Invoke-ArlStGroup8 $d } },
        @{ Name = 'g9'; Controls = @('C19'); Run = { param($d) Invoke-ArlStGroup9 $d } },
        @{ Name = 'g10'; Controls = @('C20'); Run = { param($d) Invoke-ArlStGroup10 $d } },
        @{ Name = 'g11'; Controls = @('C21'); Run = { param($d) Invoke-ArlStGroup11 $d } }
    )
    try {
        foreach ($g in $groups) {
            if (-not (& $wanted $g.Controls)) { continue }
            $dir = if ($g.Name -eq 'estatico') { $T } else { Join-Path $T $g.Name }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try { & $g.Run $dir }
            catch {
                $msg = [string]$_.Exception.Message
                foreach ($id in $g.Controls) { if (& $wanted @($id)) { Add-ArlStResult $id ('grupo ' + $g.Name) $false ('excepcion: ' + $msg) } }
            }
            $sw.Stop()
            Write-ArlLine ('  tiempo ' + $g.Name + ': ' + [int]$sw.Elapsed.TotalSeconds + ' s')
        }
    } finally {
        foreach ($j in @($script:ArlStJunctions)) { try { [IO.Directory]::Delete($j, $false) } catch { } }
        $script:ArlStJunctions = [System.Collections.Generic.List[string]]::new()
        $tmpRoot = Get-ArlLongPath ([IO.Path]::GetTempPath())
        if ((Test-ArlUnder -Path $T -Root $tmpRoot) -and $T.Contains('arl-desktop-autoprueba-') -and (Test-Path -LiteralPath $T)) {
            & icacls $T /reset /T /C /Q | Out-Null
            Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $failedIds = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $script:ArlStResults) {
        if ($r.Pass) { continue }
        if (($filter.Count -gt 0) -and (-not ($filter -contains $r.Id))) { continue }
        if (-not $failedIds.Contains($r.Id)) { [void]$failedIds.Add($r.Id) }
    }
    $failed = @($failedIds)
    if ($failed.Count -eq 0) {
        Write-ArlResult 'autoprueba' 'autoprueba-ok' $null $null (New-ArlCounts) @()
        return 0
    }
    foreach ($id in $failed) { Write-ArlLine ('FAIL  ' + $id) }
    Write-ArlResult 'autoprueba' 'autoprueba-fallo' $null $null (New-ArlCounts) $failed
    return 1
}
#endregion autoprueba

# Dispatch. Sits outside both regions: it only calls the functions above, never mutates directly.
# $Bound is the script's own $PSBoundParameters (a function has its own, empty, one) and $WhatIf the
# script-scope $WhatIfPreference, both captured at the single call site below.
function Invoke-ArlMain([hashtable]$Bound, [bool]$WhatIf) {
    $mode = 'revisar'
    if ($SelfTest) { $mode = 'autoprueba' } elseif ($Undo) { $mode = 'deshacer' } elseif ($Apply) { $mode = 'aplicar' }

    try {
        Assert-ArlEnvironment $bound                                   # R9
        if ($SelfTest -and $env:ARL_DESKTOP_SELFTEST_DEPTH) { throw (New-ArlRefusal 'R9' 'la autoprueba no puede ejecutar otra autoprueba') }
        Assert-ArlPathParameters $bound                                # R2 (+ SelfTest/path/WhatIf refusal)

        if ($SelfTest) {
            Assert-ArlElevated                                         # R1
            return (Invoke-ArlSelfTest -Controls $Controls)
        }

        if ($Apply -or $Undo) { Assert-ArlElevated }                   # R1
        $P = Resolve-ArlPaths $bound

        if ($Undo) {
            $res = Invoke-ArlUndo -P $P -ManifestParam $Manifest -WhatIf:$whatIf
            Write-ArlResult 'deshacer' $res.Status $res.Colada $res.Manifest (New-ArlCounts) @()
            return (Get-ArlExitCode $res.Status)
        }

        Assert-ArlTargetsPresent $P                                    # R3
        Assert-ArlIconsExtract $P                                      # R4
        Assert-ArlCardValid $P                                         # R5
        # UTC, so the newest-first order of the archive folders survives a clock or time-zone change.
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        $P.ArchiveDir = Join-Path $P.ArchiveRoot $stamp
        Assert-ArlNoReparse $P                                         # R6
        Assert-ArlFolderOwnership $P $P.ArchiveDir                     # R7
        Assert-ArlPathTypes $P                                         # R8

        $inv = Get-ArlDesktopInventory $P
        $plan = New-ArlPlan -P $P -Inv $inv -Stamp $stamp
        Write-ArlReport $plan.Report ((Get-Date).ToString('yyyy-MM-dd HH:mm') + ' ' + $mode)

        if (@($plan.Actions).Count -eq 0) {
            Write-ArlLine 'SIN CAMBIOS: el escritorio ya esta como debe'
            Write-ArlResult $mode 'sin-cambios' $plan.Colada $null $plan.Counts @()
            return 0
        }
        if (-not $Apply) {
            Write-ArlResult $mode 'cambios-pendientes' $plan.Colada $null $plan.Counts @()
            return 0
        }

        $cardSha = Get-ArlBytesSha256 ([System.IO.File]::ReadAllBytes($P.CardSource))
        $res = Invoke-ArlApply -P $P -Plan $plan -CardSha $cardSha
        $status = $res.Status
        if ($status -eq 'aplicado' -and -not $whatIf) {
            $inv2 = Get-ArlDesktopInventory $P
            $plan2 = New-ArlPlan -P $P -Inv $inv2 -Stamp ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
            if (@($plan2.Actions).Count -ne 0) { $status = 'error' }
        }
        $colada = $plan.Colada
        if ($Apply -and -not $whatIf -and $status -eq 'aplicado') { $colada = if (Test-Path -LiteralPath $P.ColadaPath) { $P.ColadaPath } else { $null } }
        if ($status -eq 'error') { Write-ArlLine 'ERROR: aplicacion parcial. Ejecute -Undo para revertir.' }
        elseif ($status -eq 'aplicado' -and $plan.Counts.sospechosos -gt 0) { Write-ArlLine 'AVISO: quedan accesos sospechosos en el escritorio publico' }
        Write-ArlResult $mode $status $colada $res.Manifest $plan.Counts @()
        return (Get-ArlExitCode $status)
    } catch {
        $msg = [string]$_.Exception.Message
        $m = [regex]::Match($msg, '^ARL-RECHAZO\|([^|]+)\|(.*)$')
        if ($m.Success) {
            Write-ArlLine ('RECHAZADO ' + $m.Groups[1].Value + ': ' + $m.Groups[2].Value)
            Write-ArlResult $mode 'rechazado' $null $null (New-ArlCounts) @($m.Groups[1].Value)
            return 2
        }
        # A folder or file the account cannot open is a permissions refusal (R1), not a crash. Errors inside
        # the apply loop never reach here (they end in a failed-partial manifest), so this is a pre-apply or
        # pre-undo read; the fix is an elevated console with the right account, not a retry.
        $inner = $_.Exception
        while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        if (($_.Exception -is [System.UnauthorizedAccessException]) -or ($inner -is [System.UnauthorizedAccessException]) -or ($msg -match '(?i)access (to the path .* )?is denied|acceso denegado')) {
            Write-ArlLine ('RECHAZADO R1: sin permiso para una carpeta o archivo (' + $msg + ')')
            Write-ArlResult $mode 'rechazado' $null $null (New-ArlCounts) @('R1')
            return 2
        }
        Write-ArlLine ('ERROR: ' + $msg)
        Write-ArlResult $mode 'error' $null $null (New-ArlCounts) @()
        return 1
    }
}

# Dot-sourcing (the CI parse check and pure-function smoke) defines the functions without running anything.
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-ArlMain -Bound $PSBoundParameters -WhatIf ([bool]$WhatIfPreference)) }
