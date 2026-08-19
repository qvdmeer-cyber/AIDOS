[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
if($text -notmatch 'Invoke-AidosCurrentRepositoryThinkerTriggers'){throw 'ASSERTION FAILED: current Thinker trigger function missing.'}
if($text -notmatch 'Get-AidosPendingRuntimeActorAssignments -ProjectRoot \$root'){throw 'ASSERTION FAILED: current Thinker trigger must consult pending runtime assignments.'}
if($text -notmatch 'if\(\$pending\.Count-eq0\)\{continue\}'){throw 'ASSERTION FAILED: non-pending current Thinker assignments must be skipped.'}
Write-Output 'PASS: current Thinker trigger pending guard'
