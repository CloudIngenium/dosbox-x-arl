# Patches the checked-out script in place (this CI job only) so child output and stacks are printed.
$f = Join-Path (Split-Path -Parent $PSScriptRoot) 'Set-ArlOperatorDesktop.ps1'
$text = [IO.File]::ReadAllText($f) -replace "`r`n", "`n"
$childPrint = '        if ($env:ARL_DEBUG_CHILD) { [Console]::Out.WriteLine(''    child '' + ($Mode -join '' '') + '' exit='' + $code); foreach ($dl in @($lines)) { [Console]::Out.WriteLine(''    child> '' + $dl) } }'
$groupPrint = '                if ($env:ARL_DEBUG_CHILD) { [Console]::Out.WriteLine(''    grupo-stack '' + $g.Name + '': '' + $_.InvocationInfo.PositionMessage + [Environment]::NewLine + $_.ScriptStackTrace) }'
$mainPrint = '        if ($env:ARL_DEBUG_CHILD) { Write-ArlLine (''ERROR-STACK: '' + $_.InvocationInfo.PositionMessage + [Environment]::NewLine + $_.ScriptStackTrace) }'
$pairs = [System.Collections.Generic.List[object]]::new()
$pairs.Add(@{ Anchor = "        `$code = `$LASTEXITCODE`n"; Add = $childPrint })
$pairs.Add(@{ Anchor = "                `$msg = [string]`$_.Exception.Message`n"; Add = $groupPrint })
$pairs.Add(@{ Anchor = "        Write-ArlLine ('ERROR: ' + `$msg)`n"; Add = $mainPrint })
foreach ($p in $pairs) {
    $i = $text.IndexOf($p.Anchor, [StringComparison]::Ordinal)
    if ($i -lt 0) { throw ('anchor not found: ' + $p.Anchor) }
    $j = $i + $p.Anchor.Length
    $text = $text.Substring(0, $j) + $p.Add + "`n" + $text.Substring($j)
}
[IO.File]::WriteAllText($f, $text, [System.Text.UTF8Encoding]::new($false))
'instrumented'
