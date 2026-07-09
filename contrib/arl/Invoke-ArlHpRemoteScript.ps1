param(
    [Parameter(Mandatory = $true)]
    [string]$LocalScriptPath,

    [string]$HostName = "LABORATORIO-ARL",
    [string]$UserName = "svc-claude",
    [string]$IdentityFile = "~/.ssh/svc-claude",
    [string]$RemoteDirectory = "C:/ARL/DOSBox-X-ARL/_remote",
    [switch]$KeepRemoteScript
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $LocalScriptPath -PathType Leaf)) {
    throw "Local script not found: $LocalScriptPath"
}

$scriptPath = (Resolve-Path -Path $LocalScriptPath).Path
$remoteName = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), (Split-Path -Leaf $scriptPath)
$remoteDirectoryWindows = $RemoteDirectory.Replace("/", "\")
$remotePathWindows = ($remoteDirectoryWindows.TrimEnd("\") + "\" + $remoteName)
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

$remotePathSftp = ConvertTo-ArlSftpPath $remotePathWindows

Write-Host "Connecting to $target with $IdentityFile"
$prepCode = Invoke-ArlRemotePowerShell "New-Item -ItemType Directory -Force -Path '$($remoteDirectoryWindows.Replace("'", "''"))' | Out-Null"
if ($prepCode -ne 0) {
    throw "Failed to prepare remote directory $RemoteDirectory on $target"
}

Write-Host "Uploading $scriptPath to $remotePathSftp"
& scp @sshBaseArgs $scriptPath "${target}:$remotePathSftp"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload script to $target"
}

Write-Host "Running remote script $remotePathWindows"
$exitCode = Invoke-ArlRemotePowerShell "& '$($remotePathWindows.Replace("'", "''"))'"

if (-not $KeepRemoteScript) {
    [void](Invoke-ArlRemotePowerShell "Remove-Item -LiteralPath '$($remotePathWindows.Replace("'", "''"))' -Force -ErrorAction SilentlyContinue")
}

if ($exitCode -ne 0) {
    throw "Remote script exited with code $exitCode"
}
