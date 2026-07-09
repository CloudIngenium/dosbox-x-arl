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
$remotePath = ($RemoteDirectory.TrimEnd("/") + "/" + $remoteName)
$target = "$UserName@$HostName"
$sshBaseArgs = @(
    "-o", "BatchMode=yes",
    "-o", "IdentitiesOnly=yes",
    "-i", $IdentityFile
)

Write-Host "Connecting to $target with $IdentityFile"
& ssh @sshBaseArgs $target "powershell -NoProfile -ExecutionPolicy Bypass -Command `"New-Item -ItemType Directory -Force -Path '$($RemoteDirectory.Replace('/', '\'))' | Out-Null`""
if ($LASTEXITCODE -ne 0) {
    throw "Failed to prepare remote directory $RemoteDirectory on $target"
}

Write-Host "Uploading $scriptPath to $remotePath"
& scp @sshBaseArgs $scriptPath "${target}:$remotePath"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload script to $target"
}

$remoteWindowsPath = $remotePath.Replace("/", "\")
Write-Host "Running remote script $remoteWindowsPath"
& ssh @sshBaseArgs $target "powershell -NoProfile -ExecutionPolicy Bypass -File `"$remoteWindowsPath`""
$exitCode = $LASTEXITCODE

if (-not $KeepRemoteScript) {
    & ssh @sshBaseArgs $target "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Remove-Item -LiteralPath '$remoteWindowsPath' -Force -ErrorAction SilentlyContinue`"" | Out-Null
}

if ($exitCode -ne 0) {
    throw "Remote script exited with code $exitCode"
}

