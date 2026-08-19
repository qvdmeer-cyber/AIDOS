[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bridgePath=Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1'
$text=Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8

if($text.Contains('$assignment=$pending.assignment')){
    throw 'ASSERTION FAILED: repository bridge still treats raw pending assignment records as wrappers.'
}
if(-not$text.Contains('$assignment=$pending')){
    throw 'ASSERTION FAILED: repository bridge does not consume raw pending assignment records directly.'
}

$assignmentsPath=Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1'
$assignmentText=Get-Content -LiteralPath $assignmentsPath -Raw -Encoding UTF8
if(-not$assignmentText.Contains('if(-not$terminal){$record}')){
    throw 'ASSERTION FAILED: pending runtime actor assignment contract no longer returns raw records; update this regression with the contract.'
}

Write-Output 'PASS: repository bridge consumes raw pending runtime actor assignment records'
