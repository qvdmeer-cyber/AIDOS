[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [ValidateSet('Publish','Consume','Cleanup','Reconcile')][string]$Mode = 'Consume',
    [string]$ExecutionPath,
    [string]$ReviewId,
    [ValidateSet('PASS','REPAIR','BLOCKER','DISCOVERY_REFRESH_REQUIRED','WAITING_INTERACTIVE_SESSION')][string]$Outcome,
    [string]$Reason = '',
    [ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor = 'WORKER_AGENT'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force

switch ($Mode) {
    'Publish' {
        if (-not $ExecutionPath) { throw 'Publish mode requires ExecutionPath.' }
        Publish-AidosReviewPackage -ProjectRoot $ProjectRoot -ExecutionPath $ExecutionPath -ReviewId $ReviewId | ConvertTo-Json -Depth 100
    }
    'Consume' {
        if (-not $ReviewId) { throw 'Consume mode requires ReviewId.' }
        if (-not $Outcome) { throw 'Consume mode requires Outcome.' }
        Invoke-AidosReviewConsumer -ProjectRoot $ProjectRoot -ReviewId $ReviewId -Outcome $Outcome -Reason $Reason -Actor $Actor | ConvertTo-Json -Depth 100
    }
    'Cleanup' {
        if (-not $ReviewId) { throw 'Cleanup mode requires ReviewId.' }
        Invoke-AidosReviewCleanup -ProjectRoot $ProjectRoot -ReviewId $ReviewId -Actor $Actor | ConvertTo-Json -Depth 100
    }
    'Reconcile' {
        Invoke-AidosReviewReconciliation -ProjectRoot $ProjectRoot | ConvertTo-Json -Depth 100
    }
}
