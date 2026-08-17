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

# Pass all paths as positional bash arguments. This avoids nested PowerShell/Bash
# quoting and keeps the durable repository assignment as the only prompt source.
$command=@'
set -euo pipefail
repo_root="$1"
codex_path="$2"
assignment_name="$3"
cd "$repo_root"
test -x "$codex_path"
test -f "$assignment_name"
prompt="$(cat "$assignment_name")"
exec "$codex_path" exec "$prompt"
'@

Write-Host "Starting Codex implementation from $assignmentName in $WslRepoRoot"
Write-Host 'Codex owns repository implementation work; it must stop at any explicit human/security bootstrap gate.'

& wsl.exe -d $WslDistribution -- bash -lc $command -- $WslRepoRoot $CodexPath $assignmentName
if($LASTEXITCODE -ne 0){ throw "Codex build bootstrap exited with code $LASTEXITCODE." }
