[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [ValidateSet('Publish','Recover','RepairLegacyCorrelation','Consume','Cleanup','Abandon','Reconcile')][string]$Mode = 'Consume',
    [string]$ExecutionPath,
    [string]$ReviewId,
    [string]$ResponseJson,
    [string]$ResponsePath,
    [string]$Reason,
    [ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor = 'WORKER_AGENT'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking

switch ($Mode) {
    'Publish' {
        if (-not $ExecutionPath) { throw 'Publish mode requires ExecutionPath.' }
        Publish-AidosReviewPackage -ProjectRoot $ProjectRoot -ExecutionPath $ExecutionPath -ReviewId $ReviewId | ConvertTo-Json -Depth 100
    }
    'Recover' {
        if (-not $ExecutionPath) { throw 'Recover mode requires ExecutionPath.' }
        Repair-AidosReviewPackage -ProjectRoot $ProjectRoot -ExecutionPath $ExecutionPath -ReviewId $ReviewId | ConvertTo-Json -Depth 100
    }
    'RepairLegacyCorrelation' {
        if (-not $ExecutionPath) { throw 'RepairLegacyCorrelation mode requires ExecutionPath.' }
        Repair-AidosLegacyReviewAssignmentCorrelation -ProjectRoot $ProjectRoot -ExecutionPath $ExecutionPath -ReviewId $ReviewId | ConvertTo-Json -Depth 100
    }
    'Consume' {
        if (-not $ResponseJson -and -not $ResponsePath) { throw 'Consume mode requires ResponseJson or ResponsePath.' }
        $consumerArgs=@{ProjectRoot=$ProjectRoot;Actor=$Actor}
        if($ResponseJson){ $consumerArgs.ResponseJson=$ResponseJson }
        if($ResponsePath){ $consumerArgs.ResponsePath=$ResponsePath }
        Invoke-AidosReviewConsumer @consumerArgs | ConvertTo-Json -Depth 100
    }
    'Cleanup' {
        if (-not $ReviewId) { throw 'Cleanup mode requires ReviewId.' }
        Invoke-AidosReviewCleanup -ProjectRoot $ProjectRoot -ReviewId $ReviewId -Actor $Actor | ConvertTo-Json -Depth 100
    }
    'Abandon' {
        if (-not $ReviewId) { throw 'Abandon mode requires ReviewId.' }
        if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Abandon mode requires Reason.' }
        Abandon-AidosReview -ProjectRoot $ProjectRoot -ReviewId $ReviewId -Reason $Reason -Actor $Actor | ConvertTo-Json -Depth 100
    }
    'Reconcile' {
        Invoke-AidosReviewReconciliation -ProjectRoot $ProjectRoot | ConvertTo-Json -Depth 100
    }
}
