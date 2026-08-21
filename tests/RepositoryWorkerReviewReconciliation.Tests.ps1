[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryWorkerHandoff.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Reconcile([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-ReconcileThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){try{&$Action;throw "ASSERTION FAILED: $Message"}catch{if($_.Exception.Message-notmatch$Pattern){throw}};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-worker-review-reconcile-'+[guid]::NewGuid().ToString('N'))
$reviewId='REVIEW-STALE';$reviewRoot=Join-Path $temp ".aidos/reviews/$reviewId"
New-Item -ItemType Directory -Path $reviewRoot,(Join-Path $temp '.aidos/events') -Force|Out-Null
try{
    [ordered]@{schema_version='0.1';project_id='P1'}|ConvertTo-Json|Set-Content (Join-Path $temp '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='P1';state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=5;review_id=$null}|ConvertTo-Json|Set-Content (Join-Path $temp '.aidos/STATE.json') -Encoding utf8NoBOM
    $assignmentSha=('a'*64);$responseSha=('b'*64)
    $record=[ordered]@{schema_version='0.1';review_id=$reviewId;project_id='P1';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=4;assignment_sha256=$assignmentSha;response_sha256=$responseSha;response_accepted_at='2026-08-21T12:00:00Z';decision=[ordered]@{outcome='REPAIR';target_state='TASK_READY'};transport_state='CLEANED';consumed_at='2026-08-21T12:00:01Z';consume_ack=[ordered]@{review_id=$reviewId};cleaned_at='2026-08-21T12:00:02Z'}
    $record|ConvertTo-Json -Depth 20|Set-Content (Join-Path $reviewRoot 'REVIEW.json') -Encoding utf8NoBOM
    $binding=[pscustomobject][ordered]@{project_state='GPT_REVIEWING';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=4;review_id=$reviewId}
    $metadata=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id='P1';kind='ASSIGNMENT';from_actor='CORE';to_actor='THINKER';status='READY';parent_handoff_id=[guid]::NewGuid().ToString();created_at='2026-08-21T11:00:00Z';action='REVIEW';payload_ref=".aidos/runtime/reviews/$reviewId/REVIEW_ASSIGNMENT.json";payload_sha256=$assignmentSha;binding=$binding;source_refs=@()}
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $temp -Metadata $metadata -Body 'Stale review assignment.'
    $project=[pscustomobject]@{project_id='P1';local_root=$temp}

    $result=Resolve-AidosRepositoryWorkerStaleConsumedReviewAssignment -Project $project -Handoff $handoff
    Assert-Reconcile ([string]$result.metadata.kind-eq'RESULT' -and [string]$result.metadata.action-eq'REVIEW_RESULT') 'cleaned review assignment becomes a Core-bound result'
    Assert-Reconcile ([string]$result.metadata.parent_handoff_id-eq[string]$metadata.handoff_id) 'reconciled result preserves the exact stale parent'
    Assert-Reconcile ([string]$result.metadata.payload_ref-eq".aidos/reviews/$reviewId/REVIEW.json") 'reconciled result binds the durable review record'
    $events=@(Get-Content (Join-Path $temp ('.aidos/events/'+(Get-Date).ToUniversalTime().ToString('yyyy-MM')+'.jsonl'))|ForEach-Object {$_|ConvertFrom-Json -Depth 30})
    Assert-Reconcile (@($events|Where-Object event_type -eq 'REPOSITORY_STALE_REVIEW_ASSIGNMENT_RECONCILED').Count-eq1) 'reconciliation is durably evented'

    $record.transport_state='DECIDED';$record.consumed_at=$null;$record.consume_ack=$null;$record.cleaned_at=$null
    $record|ConvertTo-Json -Depth 20|Set-Content (Join-Path $reviewRoot 'REVIEW.json') -Encoding utf8NoBOM
    Assert-ReconcileThrows {Resolve-AidosRepositoryWorkerStaleConsumedReviewAssignment -Project $project -Handoff $handoff|Out-Null} 'Another repository actor assignment' 'unconsumed review remains a hard Worker blocker'
    Write-Output "PASS: $passed Worker review reconciliation assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
