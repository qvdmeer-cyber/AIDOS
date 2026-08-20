Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousRepair.psm1') -DisableNameChecking

function Test-AidosReviewAuthorityValueResolved {
    param($Value)
    if($null-eq$Value){return $true}
    if($Value -is [string]){
        $text=([string]$Value).Trim()
        if($text -match '^(?i:REQUIRED|REQUIRED_NONEMPTY)\s*:'){return $false}
        if([string]::Equals($text,'Replace with the evidence-based review reason.',[StringComparison]::Ordinal)){return $false}
        return $true
    }
    if($Value -is [Collections.IDictionary]){
        foreach($key in @($Value.Keys)){if(-not(Test-AidosReviewAuthorityValueResolved -Value $Value[$key])){return $false}}
        return $true
    }
    if($Value -is [Collections.IEnumerable] -and -not($Value -is [pscustomobject])){
        foreach($item in @($Value)){if(-not(Test-AidosReviewAuthorityValueResolved -Value $item)){return $false}}
        return $true
    }
    foreach($property in @($Value.PSObject.Properties|Where-Object {$_.MemberType -in @('NoteProperty','Property')})){
        if(-not(Test-AidosReviewAuthorityValueResolved -Value $property.Value)){return $false}
    }
    $true
}

function Get-AidosReviewAuthorityAssessment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ReviewRecord)
    $response=$ReviewRecord.response
    if($null-eq$response){
        return [pscustomobject][ordered]@{valid=$false;recoverable=$false;reason='REVIEW_RESPONSE_MISSING';review_id=[string]$ReviewRecord.review_id}
    }
    if(-not(Test-AidosReviewAuthorityValueResolved -Value $response)){
        return [pscustomobject][ordered]@{valid=$false;recoverable=$true;reason='UNRESOLVED_RESPONSE_TEMPLATE';review_id=[string]$ReviewRecord.review_id}
    }
    if([string]::IsNullOrWhiteSpace([string]$response.reason)){
        return [pscustomobject][ordered]@{valid=$false;recoverable=$true;reason='REVIEW_REASON_MISSING';review_id=[string]$ReviewRecord.review_id}
    }
    $respondedAt=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$response.responded_at,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$respondedAt)){
        return [pscustomobject][ordered]@{valid=$false;recoverable=$true;reason='REVIEW_TIMESTAMP_INVALID';review_id=[string]$ReviewRecord.review_id}
    }
    [pscustomobject][ordered]@{valid=$true;recoverable=$false;reason='VALID';review_id=[string]$ReviewRecord.review_id}
}

function Get-AidosReviewAuthorityAuditPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId)
    Join-Path (Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ".aidos/reviews/$ReviewId") 'AUTHORITY_AUDIT.json'
}

function Request-AidosIndependentReReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ReviewId
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    Test-AidosProjectBinding $root|Out-Null
    $state=Get-AidosState $root
    $record=Read-AidosReviewRecord -ProjectRoot $root -ReviewId $ReviewId
    if([string]$record.review_id-ne$ReviewId){throw 'Review authority recovery identity mismatch.'}
    if([string]$record.transport_state-ne'CLEANED'){throw "Independent re-review requires a CLEANED historical review, found '$($record.transport_state)'."}
    if([string]$state.state-ne'IDLE' -and [string]$state.state-ne'TASK_READY'){throw "Independent re-review requires IDLE or its already-planned TASK_READY recovery, found '$($state.state)'."}
    if([string]$state.execution_id-ne[string]$record.execution_id){throw 'Historical review execution differs from current project binding.'}
    if([int]$state.revision-lt[int]$record.revision){throw 'Current project revision predates the historical review.'}
    $assessment=Get-AidosReviewAuthorityAssessment -ReviewRecord $record
    if($assessment.valid){throw 'Historical review response is authority-valid; independent template recovery is not applicable.'}
    if(-not$assessment.recoverable){throw "Historical review is invalid but cannot be recovered automatically: $($assessment.reason)"}

    $auditPath=Get-AidosReviewAuthorityAuditPath -ProjectRoot $root -ReviewId $ReviewId
    $existingAudit=if(Test-Path -LiteralPath $auditPath -PathType Leaf){Read-AidosJson $auditPath}else{$null}
    if($existingAudit){
        if([string]$existingAudit.review_id-ne$ReviewId -or [string]$existingAudit.execution_id-ne[string]$record.execution_id -or [int]$existingAudit.source_revision-ne[int]$record.revision){throw 'Existing review authority audit binding mismatch.'}
        if($existingAudit.recovery_revision -and [int]$state.revision-ge[int]$existingAudit.recovery_revision){
            return [pscustomobject][ordered]@{status='ALREADY_PLANNED';audit=$existingAudit;assessment=$assessment}
        }
    }

    $executionPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$record.execution_id) -Revision ([int]$record.revision)
    if(-not(Test-Path -LiteralPath $executionPath -PathType Leaf)){throw 'Historical review execution artifact is missing.'}
    $execution=Read-AidosJson $executionPath
    $recordRef=[IO.Path]::GetRelativePath($root,(Get-AidosReviewRecordPath $root $ReviewId)).Replace('\','/')
    $guidance=@(
        "The historical review $ReviewId is not valid authority because its response retained an unresolved response-template value ($($assessment.reason)).",
        'Do not treat the historical PASS decision as evidence. Inspect the currently integrated implementation and the exact bound execution/result/validation evidence independently.',
        'Do not change accepted product scope. Make source changes only when deterministic inspection or validation proves a defect.',
        'Run every registered validator and return TER_REVIEW so AIDOS publishes a fresh review with an evidence-based reason.'
    )
    $project=[pscustomobject][ordered]@{project_id=[string]$record.project_id;local_root=$root}
    $planned=Write-AidosRepairRevision -Project $project -CurrentExecution $execution -RepairKind 'REVIEW_AUTHORITY_RECOVERY' -Guidance $guidance -EvidenceRefs @($recordRef)
    $audit=[ordered]@{
        schema_version='0.1'
        audit_type='REVIEW_AUTHORITY_RECOVERY'
        review_id=$ReviewId
        project_id=[string]$record.project_id
        execution_id=[string]$record.execution_id
        source_revision=[int]$record.revision
        historical_outcome=[string]$record.response.outcome
        authority_status='INVALID'
        authority_reason=[string]$assessment.reason
        recovery_revision=[int]$planned.execution.revision
        recovery_execution_path=[IO.Path]::GetRelativePath($root,[string]$planned.execution_path).Replace('\','/')
        evidence_refs=@($recordRef)
        planned_at=[DateTimeOffset]::UtcNow.ToString('o')
        planned_by='SYSTEM'
    }
    Write-AidosJsonAtomic $auditPath $audit
    Add-AidosEvent -ProjectRoot $root -EventType 'REVIEW_AUTHORITY_RECOVERY_PLANNED' -Actor SYSTEM -Payload @{review_id=$ReviewId;execution_id=[string]$record.execution_id;source_revision=[int]$record.revision;recovery_revision=[int]$planned.execution.revision;authority_reason=[string]$assessment.reason;audit_ref=[IO.Path]::GetRelativePath($root,$auditPath).Replace('\','/')}|Out-Null
    [pscustomobject][ordered]@{status=[string]$planned.status;audit=[pscustomobject]$audit;assessment=$assessment;repair=$planned}
}

Export-ModuleMember -Function Test-AidosReviewAuthorityValueResolved,Get-AidosReviewAuthorityAssessment,Get-AidosReviewAuthorityAuditPath,Request-AidosIndependentReReview
