param(
    [string]$HostName = "LABORATORIO-ARL",
    [string]$UserName = "svc-claude",
    [string]$IdentityFile = "~/.ssh/svc-claude",
    [string]$RemoteDirectory = "C:\ARL\DOSBox-X-ARL\_remote"
)

$ErrorActionPreference = "Stop"

$target = "$UserName@$HostName"
$sshBaseArgs = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=10",
    "-o", "IdentitiesOnly=yes",
    "-i", $IdentityFile
)

function ConvertTo-ArlSftpPath([string]$WindowsPath) {
    $path = $WindowsPath.Replace("\", "/")
    if ($path -match '^([A-Za-z]):/(.*)$') {
        return "/$($matches[1].ToUpper()):/$($matches[2])"
    }
    return $path
}

function Invoke-ArlRemotePowerShell([string]$Script) {
    $wrappedScript = "`$ProgressPreference = 'SilentlyContinue'; " + $Script
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrappedScript))
    $output = & ssh @sshBaseArgs $target "powershell.exe" "-NoProfile" "-ExecutionPolicy" "Bypass" "-EncodedCommand" $encoded 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }
    return $exitCode
}

$results = New-Object System.Collections.Generic.List[object]

& ssh @sshBaseArgs $target "C:\Windows\System32\cmd.exe" "/c" "hostname" | Tee-Object -Variable hostOutput | Out-Null
$results.Add([pscustomobject]@{
    Check = "ssh-cmd"
    Passed = ($LASTEXITCODE -eq 0 -and ($hostOutput -join "`n") -match "Laboratorio-ARL")
    Detail = ($hostOutput -join " ").Trim()
})

$psCode = Invoke-ArlRemotePowerShell "Write-Output `"PS_OK=`$env:COMPUTERNAME`""
$results.Add([pscustomobject]@{
    Check = "ssh-powershell-encoded"
    Passed = ($psCode -eq 0)
    Detail = "exit=$psCode"
})

$remoteDirectoryWindows = $RemoteDirectory.Replace("/", "\")
$prepCode = Invoke-ArlRemotePowerShell "New-Item -ItemType Directory -Force -Path '$($remoteDirectoryWindows.Replace("'", "''"))' | Out-Null"
$results.Add([pscustomobject]@{
    Check = "remote-directory"
    Passed = ($prepCode -eq 0)
    Detail = $remoteDirectoryWindows
})

$tempFile = New-TemporaryFile
try {
    "arl remote access test $(Get-Date -Format o)" | Set-Content -Path $tempFile -Encoding ASCII
    $remoteTestPath = $remoteDirectoryWindows.TrimEnd("\") + "\remote-access-test.txt"
    $remoteSftpPath = ConvertTo-ArlSftpPath $remoteTestPath
    $batchFile = New-TemporaryFile
    @(
        "put $($tempFile.FullName) $remoteSftpPath",
        "ls $remoteSftpPath",
        "rm $remoteSftpPath"
    ) | Set-Content -Path $batchFile -Encoding ASCII
    & sftp @sshBaseArgs -b $batchFile $target | Tee-Object -Variable sftpOutput | Out-Null
    $results.Add([pscustomobject]@{
        Check = "sftp-put-ls-rm"
        Passed = ($LASTEXITCODE -eq 0)
        Detail = (($sftpOutput | Select-Object -Last 2) -join " ").Trim()
    })
} finally {
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    if ($batchFile) { Remove-Item -Path $batchFile -Force -ErrorAction SilentlyContinue }
}

$results | Format-Table -AutoSize

if ($results.Passed -contains $false) {
    throw "One or more ARL HP remote access checks failed."
}
