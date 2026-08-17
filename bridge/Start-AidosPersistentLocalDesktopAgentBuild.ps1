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

$escapedRoot=$WslRepoRoot.Replace("'","'\"'\"'")
$escapedCodex=$CodexPath.Replace("'","'\"'\"'")
$escapedAssignment=$assignmentName.Replace("'","'\"'\"'")

# Codex exec is intentionally given a prompt read from durable repository state.
# The human does not have to reproduce or maintain the implementation prompt.
$command="set -euo pipefail; cd '$escapedRoot'; test -x '$escapedCodex'; test -f '$escapedAssignment'; prompt=\$(cat '$escapedAssignment'); exec '$escapedCodex' exec \"\$prompt\""

Write-Host "Starting Codex implementation from $assignmentName in $WslRepoRoot"
Write-Host 'Codex owns repository implementation work; it must stop at any explicit human/security bootstrap gate.'

& wsl.exe -d $WslDistribution -- bash -lc $command
if($LASTEXITCODE -ne 0){ throw "Codex build bootstrap exited with code $LASTEXITCODE." }
