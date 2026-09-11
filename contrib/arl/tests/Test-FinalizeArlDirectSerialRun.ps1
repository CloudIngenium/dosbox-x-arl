<#
.SYNOPSIS
    Behavioural tests for Finalize-ArlDirectSerialRun.ps1 (and the passive-workflow snapshot it
    diffs through Capture-ArlWorkflowSnapshot.ps1).

.DESCRIPTION
    The finalizer's wait is the one place where a lab session can be lost outright, so the
    property under test is not "does it wait" but "does the run survive the wait, whatever
    DOSBox does". Until 2026-07-26 reaching the timeout threw, and two real production sessions
    were stranded that way -- unfinalized, therefore never uploaded, and discovered only because
    someone went looking for a specific colada.

    Also pinned here since 2026-09-11:
    - A session in which the guest opened no .RES file copies only the .RES files modified during
      the session window, and lists any changed file it did not copy. Tested under the engine the
      lab runs the finalizer with (Windows PowerShell 5.1, whose ConvertFrom-Json does not
      enumerate a JSON array). The four 2026-09-09 normalization bundles each carried 171
      historic .RES files instead, and were quarantined.
    - The passive snapshot set includes every top-level .GPX and IMPACT.INI, copied byte-exact.

    Run from anywhere:  pwsh -NoProfile -File contrib/arl/tests/Test-FinalizeArlDirectSerialRun.ps1
    Exits non-zero if any check fails.
#>
[CmdletBinding()]
param(
    # Directory holding the scripts under test. Defaults to contrib/arl next to this tests/
    # folder; pointing it at a mutated copy is how mutants are run.
    [string]$ToolkitDir = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ToolkitDir)) { $ToolkitDir = Split-Path -Parent $PSScriptRoot }
$finalizer = Join-Path $ToolkitDir 'Finalize-ArlDirectSerialRun.ps1'
$snapshotScript = Join-Path $ToolkitDir 'Capture-ArlWorkflowSnapshot.ps1'
foreach ($path in @($finalizer, $snapshotScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "script under test not found: $path" }
}

$failures = 0
function Assert-Equal([string]$Name, $Expected, $Actual) {
    if ($Expected -eq $Actual) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name -- expected '$Expected', got '$Actual'"; $script:failures++ }
}
function Assert-True([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { Write-Host "  PASS  $Name" }
    else { Write-Host "  FAIL  $Name $Detail"; $script:failures++ }
}

# A process we can hold open (or let exit) to stand in for DOSBox on any platform.
function Start-Placeholder([int]$Seconds) {
    if ($IsWindows) { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "timeout /t $Seconds /nobreak" -WindowStyle Hidden -PassThru }
    else { Start-Process -FilePath '/bin/sleep' -ArgumentList "$Seconds" -PassThru }
}

# A "DOSBox" that has already exited, so the finalizer goes straight to collection.
function New-ExitedParent {
    $process = Start-Placeholder 1
    $startTime = $process.StartTime
    $process.WaitForExit()
    return [pscustomobject]@{ Id = $process.Id; StartTime = $startTime }
}

function New-RunDirectory([string]$Root, [string]$Name) {
    $run = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $run | Out-Null
    return $run
}

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

# CP437 content: an ASCII tag plus bytes a text re-encode would mangle (box drawing, accented
# letters, CR LF, the DOS EOF marker), so only a byte-exact copy survives a hash comparison.
function New-Cp437Bytes([string]$Tag) {
    $bytes = New-Object System.Collections.Generic.List[byte]
    foreach ($ch in $Tag.ToCharArray()) { $bytes.Add([byte][char]$ch) }
    foreach ($b in @(0x80, 0x82, 0xA5, 0xB0, 0xC4, 0xDB, 0xE1, 0xFE, 0x0D, 0x0A, 0x1A)) { $bytes.Add([byte]$b) }
    return ,$bytes.ToArray()
}
function Write-Cp437File([string]$Path, [string]$Tag) { [IO.File]::WriteAllBytes($Path, (New-Cp437Bytes $Tag)) }
function Set-LastWriteUtc([string]$Path, [int]$Year, [int]$Month, [int]$Day) {
    (Get-Item -LiteralPath $Path).LastWriteTimeUtc = New-Object DateTime ($Year, $Month, $Day, 12, 0, 0, [DateTimeKind]::Utc)
}

# The engines the finalizer is run under. The lab launches it with Windows PowerShell 5.1
# (Start-ArlTraceRun: System32\WindowsPowerShell\v1.0\powershell.exe), whose ConvertFrom-Json
# writes a JSON array to the pipeline as ONE object; pwsh 7 enumerates it. 'pwsh-ps51-json'
# reproduces the 5.1 shape inside pwsh with -NoEnumerate, so the host's behaviour is pinned on
# every platform; on Windows the real powershell.exe runs as well.
$engines = @('pwsh')
if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('NoEnumerate')) { $engines += 'pwsh-ps51-json' }
if ($IsWindows) { $engines += 'powershell.exe' }

function Invoke-Finalizer([string]$Engine, [hashtable]$Arguments) {
    switch ($Engine) {
        'pwsh' { & $finalizer @Arguments 6>$null | Out-Null }
        'pwsh-ps51-json' {
            & {
                param($Script, $Splat)
                function ConvertFrom-Json {
                    [CmdletBinding()]
                    param([Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)][AllowEmptyString()][string]$InputObject)
                    begin { $buffer = New-Object System.Collections.Generic.List[string] }
                    process { $buffer.Add($InputObject) }
                    end { Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject ($buffer -join "`n") -NoEnumerate }
                }
                & $Script @Splat
            } $finalizer $Arguments 6>$null | Out-Null
        }
        'powershell.exe' {
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $finalizer)
            foreach ($key in $Arguments.Keys) {
                $value = $Arguments[$key]
                if ($value -is [datetime]) { $value = $value.ToString('o') }
                $argList += @("-$key", [string]$value)
            }
            & powershell.exe @argList | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "powershell.exe finalizer exited $LASTEXITCODE" }
        }
        default { throw "unknown engine $Engine" }
    }
}

function Read-JsonFile([string]$Path) {
    # Assign first, then enumerate: safe under both engines (see Read-ArlResultFilesBefore).
    $parsed = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path))
    return ,@($parsed)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("finalize-tests-" + [guid]::NewGuid().ToString('N'))
$implus = Join-Path $root 'IMPLUS'
New-Item -ItemType Directory -Force -Path $implus | Out-Null

try {
    # The HP runs Windows PowerShell 5.1, which reads a BOM-less .ps1 as the ANSI codepage --
    # so a UTF-8 character that parses fine under pwsh 7 becomes mojibake there and can break
    # the script outright. (A UTF-8 em dash in a comment did exactly that on 2026-07-26: 0 parse
    # errors on the authoring machine, 4 on the HP.) Keeping these scripts ASCII-only is cheaper
    # than reasoning about codepages, and this check is what makes that stick.
    Write-Host 'Scripts stay ASCII-only, so Windows PowerShell 5.1 cannot mis-decode them'
    foreach ($scriptPath in @($finalizer, $snapshotScript)) {
        $nonAscii = @(Select-String -Path $scriptPath -Pattern '[^\x00-\x7F]' -Encoding UTF8)
        if ($nonAscii.Count -gt 0) {
            $nonAscii | Select-Object -First 5 | ForEach-Object { Write-Host "        line $($_.LineNumber): $($_.Line.Trim())" }
        }
        Assert-Equal "$(Split-Path -Leaf $scriptPath) has no non-ASCII characters" 0 $nonAscii.Count
    }

    Write-Host 'DOSBox still open at the deadline: finalized anyway, then RE-finalized at the real exit'
    # The finalizer no longer returns at the timeout (it keeps waiting for the true exit), so it
    # runs as a background process and the test observes BOTH marker writes: the timeout bundle
    # while DOSBox still lives, and the rewritten marker after DOSBox exits. The hole this pins:
    # in production (2026-08-01..05) the +24 h marker was the ONLY collection, and days of burns
    # after it never reached the canonical bundle.
    $run = New-RunDirectory $root 'sample-analysis-timeout'
    $process = Start-Placeholder 25
    $markerPath = Join-Path $run 'directserial-finalized.json'
    $finalizerProcess = $null
    try {
        $startTimeText = $process.StartTime.ToString('o')
        $launch = @{
            FilePath = if ($IsWindows) { 'powershell.exe' } else { 'pwsh' }
            PassThru = $true
            ArgumentList = @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $finalizer,
                '-ParentPid', "$($process.Id)", '-ParentStartTime', $startTimeText,
                '-RunDirectory', $run, '-ImplusPath', $implus, '-WaitTimeoutSeconds', '2')
        }
        if ($IsWindows) { $launch.WindowStyle = 'Hidden' }
        $finalizerProcess = Start-Process @launch

        $deadline = [datetime]::UtcNow.AddSeconds(20)
        while (-not (Test-Path -LiteralPath $markerPath) -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
        Assert-Equal 'timeout marker written while DOSBox still lives' $true (Test-Path -LiteralPath $markerPath)
        if (Test-Path -LiteralPath $markerPath) {
            $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
            Assert-Equal 'outcome recorded as a timeout' 'timeout_parent_still_running' $marker.metadata.finalize_wait_outcome
        }

        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $deadline = [datetime]::UtcNow.AddSeconds(30)
        $refinalized = $null
        while ([datetime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 250
            if (-not (Test-Path -LiteralPath $markerPath)) { continue }
            try { $refinalized = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json } catch { continue }
            if ($refinalized.metadata.finalize_wait_outcome -ne 'timeout_parent_still_running') { break }
        }
        Assert-Equal 'marker rewritten at the real exit' 'parent_exited_after_timeout' $refinalized.metadata.finalize_wait_outcome
    } finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        if ($null -ne $finalizerProcess) { Stop-Process -Id $finalizerProcess.Id -Force -ErrorAction SilentlyContinue }
    }

    Write-Host 'DOSBox exits normally: unchanged fast path, recorded as a clean exit'
    $run2 = New-RunDirectory $root 'sample-analysis-clean-exit'
    $shortLived = Start-Placeholder 1
    $startTime = $shortLived.StartTime
    Start-Sleep -Seconds 3
    & $finalizer -ParentPid $shortLived.Id -ParentStartTime $startTime `
        -RunDirectory $run2 -ImplusPath $implus -WaitTimeoutSeconds 30 | Out-Null
    $marker2 = Get-Content -LiteralPath (Join-Path $run2 'directserial-finalized.json') -Raw | ConvertFrom-Json
    Assert-Equal 'outcome recorded as a clean exit' 'parent_exited' $marker2.metadata.finalize_wait_outcome

    # ------------------------------------------------------------------------------------------
    Write-Host 'No guest .RES open (normalization): only the .RES modified during the session are copied'
    # Mirrors the host: a monthly .RES archive going back years, a before list written by
    # Start-ArlTraceRun's own code before DOSBox starts, then a session that touches three files.
    $implusR = Join-Path $root 'IMPLUS-results'
    New-Item -ItemType Directory -Force -Path $implusR | Out-Null
    Write-Cp437File (Join-Path $implusR 'AL.CAL') 'AL.CAL'
    $historic = [ordered]@{ 'DEC-19.RES' = @(2019, 12, 31); 'JUL-24.RES' = @(2024, 7, 31); 'MAR-24.RES' = @(2024, 3, 31)
        'JAN-25.RES' = @(2025, 1, 31); 'FEB-25.RES' = @(2025, 2, 28); 'MAR-25.RES' = @(2025, 3, 31); 'SEP-26.RES' = @(2026, 9, 1) }
    foreach ($name in $historic.Keys) {
        $path = Join-Path $implusR $name
        Write-Cp437File $path "$name historic"
        $d = $historic[$name]; Set-LastWriteUtc $path $d[0] $d[1] $d[2]
    }
    $beforeListPath = Join-Path (New-RunDirectory $root 'launch') 'result-files-before.json'
    # Exactly Start-ArlTraceRun.ps1's writer: same shape, same serializer.
    $resultFilesBefore = @(Get-ChildItem -LiteralPath $implusR -File -Filter '*.RES' -ErrorAction SilentlyContinue | ForEach-Object {
        [ordered]@{
            name = $_.Name
            length = $_.Length
            last_write_utc = $_.LastWriteTimeUtc.ToString('o')
            last_write_utc_ticks = $_.LastWriteTimeUtc.Ticks
        }
    })
    [IO.File]::WriteAllText($beforeListPath, ($resultFilesBefore | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
    # The shape CI never exercised before: more than one .RES serializes as a JSON ARRAY.
    Assert-True 'precondition: the before list is a JSON array' ([IO.File]::ReadAllText($beforeListPath).TrimStart().StartsWith('['))

    $sessionParent = New-ExitedParent   # "DOSBox" starts after the before list, like the launcher
    # The session: one monthly file gets a burn, a new file appears, and one old file is rewritten
    # with an old timestamp (a restored copy) -- changed, but not by this session's clock.
    $sepPath = Join-Path $implusR 'SEP-26.RES'
    [IO.File]::WriteAllBytes($sepPath, [byte[]]([IO.File]::ReadAllBytes($sepPath) + (New-Cp437Bytes 'burn 2')))
    Write-Cp437File (Join-Path $implusR 'OCT-26.RES') 'OCT-26.RES new in session'
    $marPath = Join-Path $implusR 'MAR-24.RES'
    Write-Cp437File $marPath 'MAR-24.RES restored from a backup copy'
    Set-LastWriteUtc $marPath 2024 4 1
    $calibrationOnly = '{"epoch_ms":1,"event":"guest_impact_file_open","kind":"calibration","drive":"C:","path":"AL.CAL","access_mode":0}'

    foreach ($engine in $engines) {
        $runR = New-RunDirectory $root "normalization-$engine"
        Set-Content -LiteralPath (Join-Path $runR 'calibration-access.ndjson') -Value $calibrationOnly
        try {
            Invoke-Finalizer $engine @{ ParentPid = $sessionParent.Id; ParentStartTime = $sessionParent.StartTime
                RunDirectory = $runR; ImplusPath = $implusR; ResultFilesBeforePath = $beforeListPath }
        } catch {
            Write-Host "  FAIL  [$engine] finalizer threw: $($_.Exception.Message)"; $script:failures++; continue
        }
        $markerR = Get-Content -LiteralPath (Join-Path $runR 'directserial-finalized.json') -Raw | ConvertFrom-Json
        $copied = @(Get-ChildItem -LiteralPath $runR -File -Filter 'result-*.RES' | ForEach-Object Name | Sort-Object)
        Assert-Equal "[$engine] only the session's .RES files are copied" 'result-OCT-26.RES,result-SEP-26.RES' ($copied -join ',')
        $legacy = @($markerR.artifacts | Where-Object { $_.role -eq 'legacy_result' } | ForEach-Object { $_.name } | Sort-Object)
        Assert-Equal "[$engine] the marker lists only those as legacy_result" 'result-OCT-26.RES,result-SEP-26.RES' ($legacy -join ',')
        Assert-Equal "[$engine] result_file_candidates" 'OCT-26.RES,SEP-26.RES' $markerR.metadata.result_file_candidates
        Assert-Equal "[$engine] result_file_source" 'session_window_fallback' $markerR.metadata.result_file_source
        Assert-Equal "[$engine] fallback basis" 'before_list_and_session_window' $markerR.metadata.result_fallback_basis
        Assert-Equal "[$engine] captured count" '2' $markerR.metadata.result_fallback_captured_count
        Assert-Equal "[$engine] the changed-but-out-of-window file is listed, not copied" 'MAR-24.RES' $markerR.metadata.result_fallback_skipped
        foreach ($name in @('OCT-26.RES', 'SEP-26.RES')) {
            $copy = Join-Path $runR "result-$name"
            if (Test-Path -LiteralPath $copy) { Assert-Equal "[$engine] $name copied byte-exact" (Get-Sha256 (Join-Path $implusR $name)) (Get-Sha256 $copy) }
        }
        $selectionPath = Join-Path $runR 'finalizer-result-selection.json'
        $selectionListed = @($markerR.artifacts | Where-Object { $_.name -eq 'finalizer-result-selection.json' }).Count -eq 1
        Assert-True "[$engine] the selection is kept as evidence" ((Test-Path -LiteralPath $selectionPath) -and $selectionListed)
        if (Test-Path -LiteralPath $selectionPath) {
            $selection = (Read-JsonFile $selectionPath)[0]
            Assert-Equal "[$engine] every before-list entry was read" '7' ([string]$selection.before_list_entries)
            Assert-Equal "[$engine] skip reason recorded" 'length_changed_outside_session_window' ((@($selection.skipped) | ForEach-Object { $_.reason }) -join ',')
        }
    }

    Write-Host 'No readable before list: the session window alone decides, and says so'
    $runMissing = New-RunDirectory $root 'normalization-no-before-list'
    Set-Content -LiteralPath (Join-Path $runMissing 'calibration-access.ndjson') -Value $calibrationOnly
    Invoke-Finalizer 'pwsh' @{ ParentPid = $sessionParent.Id; ParentStartTime = $sessionParent.StartTime
        RunDirectory = $runMissing; ImplusPath = $implusR; ResultFilesBeforePath = (Join-Path $runMissing 'result-files-before.json') }
    $markerMissing = Get-Content -LiteralPath (Join-Path $runMissing 'directserial-finalized.json') -Raw | ConvertFrom-Json
    Assert-Equal 'window-only: the files written in the session are copied' 'OCT-26.RES,SEP-26.RES' $markerMissing.metadata.result_file_candidates
    Assert-Equal 'window-only: basis recorded' 'session_window_only' $markerMissing.metadata.result_fallback_basis
    Assert-Equal 'window-only: the missing list is recorded' 'missing' $markerMissing.metadata.result_fallback_before_list

    $runGarbled = New-RunDirectory $root 'normalization-garbled-before-list'
    Set-Content -LiteralPath (Join-Path $runGarbled 'calibration-access.ndjson') -Value $calibrationOnly
    $garbledList = Join-Path $runGarbled 'result-files-before.json'
    [IO.File]::WriteAllText($garbledList, '[{"length": 1}]')
    Invoke-Finalizer 'pwsh' @{ ParentPid = $sessionParent.Id; ParentStartTime = $sessionParent.StartTime
        RunDirectory = $runGarbled; ImplusPath = $implusR; ResultFilesBeforePath = $garbledList }
    $markerGarbled = Get-Content -LiteralPath (Join-Path $runGarbled 'directserial-finalized.json') -Raw | ConvertFrom-Json
    Assert-Equal 'unreadable list: falls back to the window, never to "everything"' 'OCT-26.RES,SEP-26.RES' $markerGarbled.metadata.result_file_candidates
    Assert-True 'unreadable list: the reason is recorded' ([string]$markerGarbled.metadata.result_fallback_before_list -like 'unreadable*')

    Write-Host 'A guest .RES open still wins over the fallback'
    $runOpened = New-RunDirectory $root 'sample-analysis-opened'
    Set-Content -LiteralPath (Join-Path $runOpened 'calibration-access.ndjson') -Value @(
        $calibrationOnly,
        '{"epoch_ms":2,"event":"guest_impact_file_open","kind":"result","drive":"C:","path":"SEP-26.RES","access_mode":2}')
    Invoke-Finalizer 'pwsh' @{ ParentPid = $sessionParent.Id; ParentStartTime = $sessionParent.StartTime
        RunDirectory = $runOpened; ImplusPath = $implusR; ResultFilesBeforePath = $beforeListPath }
    $markerOpened = Get-Content -LiteralPath (Join-Path $runOpened 'directserial-finalized.json') -Raw | ConvertFrom-Json
    Assert-Equal 'guest open: only the opened file' 'SEP-26.RES' $markerOpened.metadata.result_file
    Assert-Equal 'guest open: source recorded' 'guest_open_event' $markerOpened.metadata.result_file_source
    Assert-True 'guest open: no fallback selection written' (-not (Test-Path -LiteralPath (Join-Path $runOpened 'finalizer-result-selection.json')))

    # ------------------------------------------------------------------------------------------
    Write-Host 'Passive workflow snapshot: every top-level .GPX and IMPACT.INI, byte-exact, diffed by the finalizer'
    $implusW = Join-Path $root 'IMPLUS-workflow'
    $implusWSub = Join-Path $implusW 'SUB'
    New-Item -ItemType Directory -Force -Path $implusWSub | Out-Null
    $inSet = @('AL.CAL', 'AL.REG', 'AL.GPX', 'FE.GPX', 'PROFIL.GPX', 'IMPACT.INI', 'WORK.DAT', 'QUA.DAT', 'MAT.DAT', 'MESS.DAT')
    $outOfSet = @('IMPLUS.BAT', 'JUL-26.RES', 'NOTES.TXT', 'INTERFAC.DAT')
    foreach ($name in @($inSet + $outOfSet)) { Write-Cp437File (Join-Path $implusW $name) $name }
    Write-Cp437File (Join-Path $implusWSub 'NESTED.GPX') 'NESTED.GPX'

    $staging = Join-Path $root 'workflow-staging-test'
    $beforeDir = Join-Path $staging 'workflow-files-before'
    & $snapshotScript -ImplusPath $implusW -Destination $beforeDir -Phase before | Out-Null
    $manifest = Read-JsonFile (Join-Path $beforeDir 'snapshot-manifest.json')
    $snapshotNames = @($manifest | ForEach-Object { $_.name } | Sort-Object)
    Assert-Equal 'snapshot set is .CAL/.REG/.GPX, the four .DAT and IMPACT.INI, top level only' ((@($inSet) | Sort-Object) -join ',') ($snapshotNames -join ',')
    foreach ($name in @('AL.GPX', 'FE.GPX', 'PROFIL.GPX', 'IMPACT.INI')) { Assert-True "snapshot includes $name" ($snapshotNames -contains $name) }
    $notExact = @($manifest | Where-Object {
        $_.sha256 -ne (Get-Sha256 (Join-Path $implusW $_.name)) -or $_.sha256 -ne (Get-Sha256 (Join-Path $beforeDir $_.name))
    } | ForEach-Object { $_.name })
    Assert-Equal 'every snapshot copy is byte-exact (CP437, never re-encoded)' '' ($notExact -join ',')

    $originalSha = @{}
    foreach ($name in $inSet) { $originalSha[$name] = Get-Sha256 (Join-Path $implusW $name) }
    Write-Cp437File (Join-Path $implusW 'AL.GPX') 'AL.GPX drift + type standardization rewritten'
    Write-Cp437File (Join-Path $implusW 'IMPACT.INI') 'IMPACT.INI edited'

    $runW = New-RunDirectory $root 'standardization-workflow'
    $workflowParent = New-ExitedParent
    Invoke-Finalizer 'pwsh' @{ ParentPid = $workflowParent.Id; ParentStartTime = $workflowParent.StartTime
        RunDirectory = $runW; ImplusPath = $implusW; WorkflowKind = 'standardization'
        WorkflowSnapshotBeforePath = $beforeDir; WorkflowSnapshotScriptPath = $snapshotScript }
    $diff = Read-JsonFile (Join-Path $runW 'workflow-file-diff.json')
    $changeOf = @{}
    foreach ($entry in $diff) { $changeOf[$entry.name] = $entry.change }
    Assert-Equal 'AL.GPX is diffed as modified' 'modified' $changeOf['AL.GPX']
    Assert-Equal 'IMPACT.INI is diffed as modified' 'modified' $changeOf['IMPACT.INI']
    Assert-Equal 'FE.GPX is diffed as unchanged' 'unchanged' $changeOf['FE.GPX']
    Assert-Equal 'PROFIL.GPX is diffed as unchanged' 'unchanged' $changeOf['PROFIL.GPX']
    foreach ($name in @('AL.GPX', 'IMPACT.INI')) {
        $beforeCopy = Join-Path $runW "workflow-before-$name"
        $afterCopy = Join-Path $runW "workflow-after-$name"
        Assert-True "workflow-before-$name and workflow-after-$name are in the bundle" ((Test-Path -LiteralPath $beforeCopy) -and (Test-Path -LiteralPath $afterCopy))
        if (Test-Path -LiteralPath $beforeCopy) { Assert-Equal "workflow-before-$name holds the pre-session bytes" $originalSha[$name] (Get-Sha256 $beforeCopy) }
        if (Test-Path -LiteralPath $afterCopy) { Assert-Equal "workflow-after-$name holds the post-session bytes" (Get-Sha256 (Join-Path $implusW $name)) (Get-Sha256 $afterCopy) }
    }
    $markerW = Get-Content -LiteralPath (Join-Path $runW 'directserial-finalized.json') -Raw | ConvertFrom-Json
    Assert-Equal 'marker counts the two changed files' '2' $markerW.metadata.workflow_changed_file_count
    $gpxArtifacts = @($markerW.artifacts | Where-Object { $_.name -like 'workflow-*-AL.GPX' })
    Assert-Equal 'marker lists both AL.GPX copies' 2 $gpxArtifacts.Count
    Assert-True 'the before-snapshot staging is consumed' (-not (Test-Path -LiteralPath $staging))
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) { Write-Host "$failures failure(s)"; exit 1 }
Write-Host 'all passed'
