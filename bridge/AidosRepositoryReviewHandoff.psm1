Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousReview.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffPersistence.psm1') -DisableNameChecking

function New-AidosRepositoryReviewResponseTemplate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Assignment,[Parameter(Mandatory)][string]$AssignmentSha256)
    [pscustomobject][ordered]@{
        schema_version='0.1'
        envelope_type='REVIEW_RESPONSE'
        review_id=[string]$Assignment.review_id
        project_id=[string]$Assignment.project_id
        project_root=[string]$Assignment.project_root
        project_mode=[string]$Assignment.project_mode
        definition_id=[string]$Assignment.definition_id
        definition_version=[int]$Assignment.definition_version
        execution_id=[string]$Assignment.execution_id
        revision=[int]$Assignment.revision
        reviewer_role=[string]$Assignment.reviewer_role
        reviewer_identity=[string]$Assignment.reviewer_identity
        assignment_sha256=$AssignmentSha256
        package_manifest_sha256=[string]$Assignment.package_manifest_sha256
        outcome='REQUIRED: one allowed_outcome from the assignment'
        reason='REQUIRED: concise evidence-based review rationale'
        evidence_refs='REQUIRED_NONEMPTY: exact path and sha256 objects from assignment.evidence_refs'
        repair_guidance=@()
        responded_at='REQUIRED: ISO-8601 completion timestamp'
        responded_by=[string]$Assignment.reviewer_identity
    }
}

function New-AidosRepositoryReviewAssignmentBody {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Assignment,[Parameter(Mandatory)][string]$AssignmentSha256,[Parameter(Mandatory)][string]$PayloadRef)
    $template=New-AidosRepositoryReviewResponseTemplate -Assignment $Assignment -AssignmentSha256 $AssignmentSha256
    @"
# AIDOS Thinker review handoff

AIDOS Core assigned review $([string]$Assignment.review_id) to the bound Thinker conversation.

Read the exact review assignment at $PayloadRef and every referenced evidence item. Review only the assignment, manifest and bound evidence. Return one exact REVIEW_RESPONSE through the AIDOS handoff action. Do not infer from chat history and do not start another actor.

BEGIN_REVIEW_RESPONSE_JSON
$($template|ConvertTo-Json -Depth 100)
END_REVIEW_RESPONSE_JSON
"@
}

function Get-AidosRepositoryReviewResultProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ReviewId,
        [Parameter(Mandatory)][string]$ResponseSha256
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $recordPath=Get-AidosReviewRecordPath -ProjectRoot $root -ReviewId $ReviewId
    if(-not(Test-Path -LiteralPath $recordPath -PathType Leaf)){throw 'Durable review record was not persisted by Core.'}
    $record=Read-AidosReviewRecord -ProjectRoot $root -ReviewId $ReviewId
    if(-not[string]::Equals([string]$record.response_sha256,$ResponseSha256,[StringComparison]::OrdinalIgnoreCase)){throw 'Durable review record does not contain the submitted response hash.'}
    if(-not$record.response_accepted_at -or -not$record.decision){throw 'Durable review record does not prove response acceptance and decision.'}
    if([string]$record.transport_state-ne'CLEANED' -or -not$record.consumed_at -or -not$record.consume_ack -or -not$record.cleaned_at){throw 'Durable review record does not prove response consumption and cleanup.'}
    [pscustomobject][ordered]@{
        record=$record
        payload_path=$recordPath
        payload_ref=[IO.Path]::GetRelativePath($root,$recordPath).Replace('\','/')
        payload_sha256=(Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash.ToLowerInvariant()
        response_sha256=$ResponseSha256.ToLowerInvariant()
    }
}

function Publish-AidosRepositoryReviewHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $state=Get-AidosState -ProjectRoot $root
    $published=$null
    if([string]$state.state-eq'REVIEW_READY'){$published=Publish-AidosAutonomousReview -Project $Project;$state=Get-AidosState -ProjectRoot $root}
    if([string]$state.state-ne'GPT_REVIEWING' -or [string]::IsNullOrWhiteSpace([string]$state.review_id)){throw "Repository review handoff requires GPT_REVIEWING, found '$($state.state)'."}
    $reviewId=[string]$state.review_id
    $record=Read-AidosReviewRecord -ProjectRoot $root -ReviewId $reviewId
    if([string]$record.transport_state-ne'PUBLISHED'){throw "Repository review handoff requires PUBLISHED review transport, found '$($record.transport_state)'."}
    $assignmentPath=Get-AidosAutonomousReviewAssignmentPath -ProjectRoot $root -Record $record
    if(-not(Test-Path -LiteralPath $assignmentPath -PathType Leaf)){throw 'Canonical review assignment is missing.'}
    $assignment=Read-AidosJson -Path $assignmentPath
    $assignmentSha=(Get-FileHash -LiteralPath $assignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]$record.assignment_sha256-ne$assignmentSha){throw 'Review assignment hash differs from durable review record.'}
    $payloadRef=[IO.Path]::GetRelativePath($root,$assignmentPath).Replace('\','/')
    $existing=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($existing -and [string]$existing.metadata.kind-eq'ASSIGNMENT'){
        if([string]$existing.metadata.to_actor-eq'THINKER' -and [string]$existing.metadata.action-eq'REVIEW' -and [string]$existing.metadata.payload_ref-eq$payloadRef -and [string]$existing.metadata.payload_sha256-eq$assignmentSha){return [pscustomobject][ordered]@{status='ALREADY_PUBLISHED';review=$published;handoff=$existing;persistence=[pscustomobject]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}}}
        throw 'Another repository actor assignment is already active.'
    }
    $sourceRefs=@($assignment.evidence_refs|ForEach-Object {[string]$_.path})
    $sourceRefs+=@([string]$assignment.package_manifest_path)
    $sourceRefs=@($sourceRefs|Where-Object {-not[string]::IsNullOrWhiteSpace($_)}|Select-Object -Unique)
    $binding=[pscustomobject][ordered]@{project_state='GPT_REVIEWING';definition_id=[string]$assignment.definition_id;definition_version=[int]$assignment.definition_version;execution_id=[string]$assignment.execution_id;revision=[int]$assignment.revision;review_id=$reviewId}
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id=[string]$Project.project_id;kind='ASSIGNMENT';from_actor='CORE';to_actor='THINKER';status='READY';parent_handoff_id=if($existing){[string]$existing.metadata.handoff_id}else{$null};created_at=[DateTimeOffset]::UtcNow.ToString('o');action='REVIEW';payload_ref=$payloadRef;payload_sha256=$assignmentSha;binding=$binding;source_refs=$sourceRefs
    }
    if($existing){Test-AidosRepositoryHandoffTransition -Previous $existing -Next $metadata|Out-Null}
    $body=New-AidosRepositoryReviewAssignmentBody -Assignment $assignment -AssignmentSha256 $assignmentSha -PayloadRef $payloadRef
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId $(if($existing){[string]$existing.metadata.handoff_id}else{$null})
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_REVIEW_HANDOFF_PUBLISHED' -Actor SYSTEM -Payload @{handoff_id=[string]$metadata.handoff_id;review_id=$reviewId;assignment_ref=$payloadRef;assignment_sha256=$assignmentSha}|Out-Null
    $changed=@(Get-AidosRepositoryHandoffChangedPaths -Project $Project|Where-Object {$_.path.StartsWith('.aidos/',[StringComparison]::Ordinal)}|ForEach-Object path)
    $persistence=Invoke-AidosRepositoryHandoffGitPersistence -Project $Project -Paths $changed -CommitMessage ("AIDOS publish Thinker review handoff $reviewId") -Push:$Push
    [pscustomobject][ordered]@{status='PUBLISHED';review=$published;handoff=$handoff;assignment=$assignment;persistence=$persistence}
}

function Submit-AidosRepositoryReviewResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$Request,[switch]$Push,[scriptblock]$ReviewConsumer)
    foreach($name in @('expected_parent_handoff_id','result')){if(-not$Request.PSObject.Properties[$name]){throw "Review result submission is missing '$name'."}}
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$handoff){throw 'No repository review assignment handoff is available.'}
    if([string]$handoff.metadata.kind-eq'RESULT'){
        if([string]$handoff.metadata.parent_handoff_id-eq[string]$Request.expected_parent_handoff_id){return [pscustomobject][ordered]@{status='ALREADY_ACCEPTED';handoff=$handoff}}
        throw 'Repository handoff already contains a different result.'
    }
    if([string]$handoff.metadata.action-ne'REVIEW' -or [string]$handoff.metadata.to_actor-ne'THINKER'){throw 'Current repository handoff is not a Thinker review assignment.'}
    if(-not[string]::Equals([string]$handoff.metadata.handoff_id,[string]$Request.expected_parent_handoff_id,[StringComparison]::OrdinalIgnoreCase)){throw 'Review result submission parent handoff is stale.'}
    $response=$Request.result
    if([string]$response.envelope_type-ne'REVIEW_RESPONSE'){throw 'Repository review submission requires REVIEW_RESPONSE.'}
    $reviewId=[string]$response.review_id
    if([string]$reviewId-ne[string]$handoff.metadata.binding.review_id){throw 'Review response identity differs from handoff binding.'}
    $responsePath=Join-Path $root ('.aidos/reviews/{0}/RESPONSE.repository-handoff.json' -f $reviewId)
    Write-AidosJsonAtomic -Path $responsePath -Value $response
    $responseSha=(Get-FileHash -LiteralPath $responsePath -Algorithm SHA256).Hash.ToLowerInvariant()
    try{$consumed=Invoke-AidosBoundReviewConsumer -Project $Project -ReviewId $reviewId -ResponsePath $responsePath -ReviewConsumer $ReviewConsumer}catch{Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue;throw}
    $proof=Get-AidosRepositoryReviewResultProof -ProjectRoot $root -ReviewId $reviewId -ResponseSha256 $responseSha
    $payloadRef=[string]$proof.payload_ref
    $payloadSha=[string]$proof.payload_sha256
    $state=Get-AidosState -ProjectRoot $root
    $binding=[pscustomobject][ordered]@{project_state=[string]$state.state;definition_id=[string]$response.definition_id;definition_version=[int]$response.definition_version;execution_id=[string]$response.execution_id;revision=[int]$response.revision;review_id=$reviewId}
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id=[string]$Project.project_id;kind='RESULT';from_actor='THINKER';to_actor='CORE';status='READY';parent_handoff_id=[string]$handoff.metadata.handoff_id;created_at=[DateTimeOffset]::UtcNow.ToString('o');action='REVIEW_RESULT';payload_ref=$payloadRef;payload_sha256=$payloadSha;binding=$binding;source_refs=@()
    }
    Test-AidosRepositoryHandoffTransition -Previous $handoff -Next $metadata|Out-Null
    $body="# AIDOS Thinker review result`n`nReview $reviewId returned outcome $([string]$response.outcome). Core validated and consumed the response."
    $written=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId ([string]$handoff.metadata.handoff_id)
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_REVIEW_RESULT_PUBLISHED' -Actor WORKER_AGENT -Payload @{handoff_id=[string]$metadata.handoff_id;parent_handoff_id=[string]$metadata.parent_handoff_id;review_id=$reviewId;outcome=[string]$response.outcome;payload_ref=$payloadRef}|Out-Null
    $changed=@(Get-AidosRepositoryHandoffChangedPaths -Project $Project|Where-Object {$_.path.StartsWith('.aidos/',[StringComparison]::Ordinal)}|ForEach-Object path)
    $persistence=Invoke-AidosRepositoryHandoffGitPersistence -Project $Project -Paths $changed -CommitMessage ("AIDOS publish Thinker review result $reviewId") -Push:$Push
    [pscustomobject][ordered]@{status='ACCEPTED';handoff=$written;consumed=$consumed;persistence=$persistence}
}

Export-ModuleMember -Function New-AidosRepositoryReviewResponseTemplate,New-AidosRepositoryReviewAssignmentBody,Get-AidosRepositoryReviewResultProof,Publish-AidosRepositoryReviewHandoff,Submit-AidosRepositoryReviewResult
