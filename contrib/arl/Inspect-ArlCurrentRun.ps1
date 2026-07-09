param(
    [string]$DiagnosticsRoot = "C:\ARL\diagnostics",
    [string]$ImplusPath = "C:\ARL\IMPLUS",
    [int]$Tail = 80
)

$ErrorActionPreference = "Stop"

function Read-SharedLines([string]$Path, [int]$LineTail = 0) {
    $share = [System.IO.FileShare]([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
    $stream = $null
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            break
        } catch [System.IO.IOException] {
            if ($attempt -eq 20) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        $lines = New-Object System.Collections.Generic.List[string]
        while (-not $reader.EndOfStream) {
            $lines.Add($reader.ReadLine())
        }
        if ($LineTail -gt 0 -and $lines.Count -gt $LineTail) {
            return $lines.GetRange($lines.Count - $LineTail, $LineTail)
        }
        return $lines
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$latest = Get-ChildItem -Path $DiagnosticsRoot -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $latest) {
    throw "No diagnostic runs found below $DiagnosticsRoot"
}

Write-Host "LATEST=$($latest.FullName) MTIME=$($latest.LastWriteTime)"
Get-ChildItem -LiteralPath $latest.FullName -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First 20 FullName, Length, LastWriteTime |
    Format-Table -AutoSize

$emulatorLog = Join-Path $latest.FullName "emulator.ndjson"
if (Test-Path -Path $emulatorLog -PathType Leaf) {
    $lines = @(Read-SharedLines $emulatorLog 0)
    $events = @($lines | ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $null -ne $_ })

    $resultReads = @($events | Where-Object { $_.event -eq "transaction_done" -and $_.input_ascii -like "#rd 246*" })
    $accepted = @($events | Where-Object { $_.event -eq "transaction_done" -and $_.input_ascii -like "#em 242*" })
    $rejected = @($events | Where-Object { $_.event -eq "transaction_done" -and $_.input_ascii -eq "?" })
    $fast = @($events | Where-Object { $_.event -eq "fast_response_match" })
    $control = @($events | Where-Object { $_.event -eq "control_response_match" })
    $noMatch = @($events | Where-Object { $_.event -eq "no_match" })
    $errors = @($events | Where-Object { $_.event -eq "transaction_error" })

    Write-Host ""
    if ($errors.Count -gt 0 -or $noMatch.Count -gt 0 -or $rejected.Count -gt 0) {
        Write-Host "RESULTADO: REVISAR - hubo rechazo, no_match o error."
    } elseif ($control.Count -gt 0 -and $accepted.Count -gt 0) {
        Write-Host "RESULTADO: BIEN - el control del emulador se aplico e IMPACT respondio #em."
    } elseif ($resultReads.Count -gt 0 -and $accepted.Count -gt 0) {
        Write-Host "RESULTADO: BIEN - IMPACT acepto resultados del emulador."
    } elseif ($resultReads.Count -gt 0) {
        Write-Host "RESULTADO: INCOMPLETO - hubo #rd pero no se ve #em todavia."
    } else {
        Write-Host "RESULTADO: SIN ANALISIS - todavia no se ve una lectura #rd."
    }
    Write-Host "EMULATOR_COUNTS lines=$($lines.Count) events=$($events.Count) rd_done=$($resultReads.Count) accepted_em=$($accepted.Count) reject_q=$($rejected.Count) fast=$($fast.Count) control=$($control.Count) no_match=$($noMatch.Count) errors=$($errors.Count)"
    if ($control.Count -gt 0) {
        $lastControl = $control | Select-Object -Last 1
        Write-Host "ULTIMO_CONTROL label=$($lastControl.rule) input=$($lastControl.input_ascii)"
    }
    if ($accepted.Count -gt 0) {
        $lastAccepted = $accepted | Select-Object -Last 1
        Write-Host "ULTIMO_ACCEPT input=$($lastAccepted.input_ascii)"
    }
    Write-Host "LAST_EMULATOR_EVENTS"
    $lines | Select-Object -Last $Tail | ForEach-Object { $_ }
}

foreach ($name in @("0.RES", "INTERFAC.DAT")) {
    $path = Join-Path $ImplusPath $name
    if (Test-Path -Path $path -PathType Leaf) {
        $file = Get-Item -LiteralPath $path
        Write-Host ""
        Write-Host "FILE=$path SIZE=$($file.Length) MTIME=$($file.LastWriteTime)"
        Read-SharedLines $path $Tail | ForEach-Object { $_ }
    }
}

$lpt = Get-ChildItem -LiteralPath $latest.FullName -Recurse -File -Filter "LPTCAP.PRN" -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -ne $lpt) {
    $bytes = [System.IO.File]::ReadAllBytes($lpt.FullName)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    Write-Host ""
    Write-Host "LPT=$($lpt.FullName) SIZE=$($lpt.Length) MTIME=$($lpt.LastWriteTime)"
    Write-Host "LPT_MARKERS FinalConcentration=$(([regex]::Matches($text, 'Final Concentration')).Count) Normalization=$(([regex]::Matches($text, '100% normalization')).Count) Absolute=$(([regex]::Matches($text, 'Absolute Intensities')).Count)"
    Read-SharedLines $lpt.FullName $Tail | ForEach-Object { $_ }
}
