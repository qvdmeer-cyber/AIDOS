[CmdletBinding()]
param(
    [string]$WslDistribution='Ubuntu',
    [string]$WslRepoRoot='/home/aidos/repos/AIDOS',
    [string]$CodexPath='/home/aidos/.local/bin/codex'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if(-not $IsWindows){ throw 'Persistent Local Desktop Agent build bootstrap must be launched from Windows PowerShell 7.' }

$assignmentName='START_PERSISTENT_LOCAL_DESKTOP_AGENT.md'
$windowsAssignment=Join-Path (Split-Path $PSScriptRoot -Parent) $assignmentName
if(-not (Test-Path -LiteralPath $windowsAssignment -PathType Leaf)){
    throw "Build assignment is missing: $windowsAssignment"
}

$wslLauncher="$WslRepoRoot/bridge/Start-AidosPersistentLocalDesktopAgentBuild.sh"

Write-Host "Starting Codex implementation from $assignmentName in $WslRepoRoot"
Write-Host 'Codex owns repository implementation work; it must stop at any explicit human/security bootstrap gate.'

$previousCodexPath=$env:AIDOS_CODEX_PATH
try {
    $env:AIDOS_CODEX_PATH=$CodexPath
    & wsl.exe -d $WslDistribution -- bash $wslLauncher
    if($LASTEXITCODE -ne 0){ throw "Codex build bootstrap exited with code $LASTEXITCODE." }
} finally {
    if($null -eq $previousCodexPath){
        Remove-Item Env:AIDOS_CODEX_PATH -ErrorAction SilentlyContinue
    } else {
        $env:AIDOS_CODEX_PATH=$previousCodexPath
    }
}
