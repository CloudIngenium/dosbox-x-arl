param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("standardization", "normalization")]
    [string]$Workflow,

    [string]$ToolkitRoot = "C:\ARL\DOSBox-X-ARL",
    [string]$ImplusPath = "C:\ARL\IMPLUS",
    [string]$RunRoot = "C:\ARL\diagnostics"
)

$ErrorActionPreference = "Stop"
$startScript = Join-Path $ToolkitRoot "contrib\arl\Start-ArlTraceRun.ps1"
$snapshotScript = Join-Path $ToolkitRoot "contrib\arl\Capture-ArlWorkflowSnapshot.ps1"
foreach ($path in @($startScript, $snapshotScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required script not found: $path" }
}
if (@(Get-Process -Name "dosbox-x-arl", "dosbox-x" -ErrorAction SilentlyContinue).Count -gt 0) {
    throw "Close every DOSBox-X process before starting a passive workflow capture."
}

$staging = Join-Path $RunRoot ("workflow-staging-{0}" -f [guid]::NewGuid().ToString("N"))
$before = Join-Path $staging "workflow-files-before"
& $snapshotScript -ImplusPath $ImplusPath -Destination $before -Phase before | Out-Null

try {
    & $startScript `
        -Session $Workflow `
        -ImplusPath $ImplusPath `
        -RunRoot $RunRoot `
        -ComPort COM5 `
        -Cycles 12000 `
        -RxDelay 3000 `
        -TraceLevel basic `
        -TraceMaxMb 64 `
        -WindowResolution 1440x900 `
        -VideoOutput openglnb `
        -Aspect $false `
        -ArlResultObserve `
        -WorkflowKind $Workflow `
        -WorkflowSnapshotBeforePath $before `
        -WorkflowSnapshotScriptPath $snapshotScript `
        -Wait
} finally {
    if (Test-Path -LiteralPath $staging) {
        Write-Warning "Workflow finalization did not consume the before-snapshot; evidence remains at $staging"
    }
}
