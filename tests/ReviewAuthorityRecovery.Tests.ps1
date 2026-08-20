[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$modulePath=Join-Path $root 'bridge/AidosReviewAuthorityRecovery.psm1'
$toolPath=Join-Path $root 'tools/Request-AidosIndependentReReview.ps1'
Import-Module $modulePath -Force -DisableNameChecking

$script:passed=0
function Assert-ReReview([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

function New-ReviewRecord {
    param(
        [string]$Reason='Independent evidence confirms the accepted execution passed validation.',
        [string]$RespondedAt='2026-08-20T10:10:00.0000000+00:00',
        [object[]]$RepairGuidance=@()
    )
    [pscustomobject][ordered]@{
        review_id='review-authority-1'
        response=[pscustomobject][ordered]@{
            outcome='PASS'
            reason=$Reason
            repair_guidance=@($RepairGuidance)
            responded_at=$RespondedAt
        }
    }
}

$placeholder=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord -Reason 'Replace with the evidence-based review reason.')
Assert-ReReview (-not[bool]$placeholder.valid -and [bool]$placeholder.recoverable -and [string]$placeholder.reason-eq'UNRESOLVED_RESPONSE_TEMPLATE') 'legacy placeholder review is classified as recoverable invalid authority'

$required=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord -RepairGuidance @('REQUIRED: replace or remove'))
Assert-ReReview (-not[bool]$required.valid -and [string]$required.reason-eq'UNRESOLVED_RESPONSE_TEMPLATE') 'nested unresolved response values invalidate review authority'

$badTime=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord -RespondedAt 'not-a-time')
Assert-ReReview (-not[bool]$badTime.valid -and [string]$badTime.reason-eq'REVIEW_TIMESTAMP_INVALID') 'invalid response timestamp is recoverable authority failure'

$valid=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord)
Assert-ReReview ([bool]$valid.valid -and -not[bool]$valid.recoverable -and [string]$valid.reason-eq'VALID') 'resolved evidence-based review remains authority-valid'

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-review-authority-recovery-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$reviewId='REV-FALSE-PASS'
$executionId='EXEC-AUTHORITY-1'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot ".aidos/executions/$executionId/revision-3") -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot ".aidos/reviews/$reviewId") -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/review-authority-recovery.git'

    [ordered]@{
        schema_version='0.1';project_id='REVIEW-AUTHORITY-RECOVERY';project_mode='NEW_PROJECT';repository='https://example.invalid/review-authority-recovery.git';official_root=$projectRoot;default_branch='main';
        project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';runner_policy='UNATTENDED_ALLOWED';
        git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}
    }|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='REVIEW-AUTHORITY-RECOVERY';baseline_version=1;accepted_at='2026-08-20T00:00:00Z';accepted_by='TEST';accepted_commit='abcdef1';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='REVIEW-AUTHORITY-RECOVERY'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='REVIEW-AUTHORITY-RECOVERY'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    [ordered]@{
        schema_version='0.1';project_id='REVIEW-AUTHORITY-RECOVERY';state='IDLE';definition_id='DEF-1';definition_version=1;execution_id=$executionId;revision=3;codex_session_id='thread-3';review_id=$null;lease_id=$null;
        terminal_result=".aidos/executions/$executionId/revision-3/RESULT.json";git_head='abcdef1234567';validation_result=".aidos/executions/$executionId/revision-3/VALIDATION.json";updated_at='2026-08-20T00:00:00Z'
    }|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM

    $execution=[ordered]@{
        schema_version='0.1';execution_id=$executionId;revision=3;project_id='REVIEW-AUTHORITY-RECOVERY';project_mode='NEW_PROJECT';workstream=$null;
        preparation=[ordered]@{baseline_commit='abcdef1';access_sha256=(Get-FileHash (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Algorithm SHA256).Hash.ToLowerInvariant();evidence_inventory_sha256=(Get-FileHash (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Algorithm SHA256).Hash.ToLowerInvariant();current_product_state_id=$null;current_product_state_commit=$null;current_product_state_contract_version=$null;discovery_catalog_version=$null};
        definition=[ordered]@{id='DEF-1';version=1};goal='Accepted implementation';scope=[ordered]@{definition_ref='.aidos/definitions/DEF-1/v1/DEFINITION.json';implementation_policy='accepted scope'};
        acceptance=@([ordered]@{criterion='validate'});authority=[ordered]@{filesystem_write=@('.');git_commit=$false;git_push=$false;network=$false};knowledge_selection=@();validators=@('npm run validate');
        validation=[ordered]@{mode='ALL';requirements=@([ordered]@{type='PATH_EXISTS';path='package.json'})};executor_profile=[ordered]@{model='codex-cli-default';reasoning_effort='medium'};stop_conditions=@('TER_REVIEW')
    }
    $executionPath=Join-Path $projectRoot ".aidos/executions/$executionId/revision-3/EXECUTION.json"
    $execution|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $executionPath -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='REVIEW-AUTHORITY-RECOVERY';execution_id=$executionId;revision=3;process_succeeded=$true;validation_status='PASS'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot ".aidos/executions/$executionId/revision-3/RESULT.json") -Encoding utf8NoBOM
    [ordered]@{status='PASS'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot ".aidos/executions/$executionId/revision-3/VALIDATION.json") -Encoding utf8NoBOM
    '{}'|Set-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Encoding utf8NoBOM

    $reviewRecord=[ordered]@{
        schema_version='0.1';review_id=$reviewId;project_id='REVIEW-AUTHORITY-RECOVERY';project_root=$projectRoot;definition_id='DEF-1';definition_version=1;execution_id=$executionId;revision=3;transport_state='CLEANED';
        package_path=".aidos/runtime/reviews/$reviewId";package_manifest_path=".aidos/runtime/reviews/$reviewId/MANIFEST.json";package_manifest_sha256=('a'*64);assignment_path=".aidos/runtime/reviews/$reviewId/REVIEW_ASSIGNMENT.json";assignment_sha256=('b'*64);assignment=[ordered]@{};
        response=[ordered]@{outcome='PASS';reason='Replace with the evidence-based review reason.';repair_guidance=@();responded_at='2026-08-20T00:00:00Z'};response_sha256=('c'*64);response_received_at='2026-08-20T00:00:01Z';response_received_by='WORKER_AGENT';response_accepted_at='2026-08-20T00:00:02Z';response_accepted_by='BRIDGE';
        evidence_refs=@();published_at='2026-08-20T00:00:00Z';published_by='BRIDGE';decision=[ordered]@{outcome='PASS';target_state='IDLE';reason='Replace with the evidence-based review reason.';decided_by='BRIDGE';decided_at='2026-08-20T00:00:02Z'};
        consume_ack=[ordered]@{review_id=$reviewId};consumed_at='2026-08-20T00:00:03Z';consumed_by='BRIDGE';cleaned_at='2026-08-20T00:00:04Z';abandonment=$null;updated_at='2026-08-20T00:00:04Z'
    }
    $reviewPath=Join-Path $projectRoot ".aidos/reviews/$reviewId/REVIEW.json"
    $reviewRecord|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $reviewPath -Encoding utf8NoBOM

    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init
    $historicalReviewHash=(Get-FileHash -LiteralPath $reviewPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $planned=Request-AidosIndependentReReview -ProjectRoot $projectRoot -ReviewId $reviewId
    Assert-ReReview ([string]$planned.status-eq'PLANNED') 'false historical PASS plans a fresh immutable recovery revision'
    Assert-ReReview ([int]$planned.audit.source_revision-eq3 -and [int]$planned.audit.recovery_revision-eq4) 'authority audit binds source revision 3 to recovery revision 4'
    Assert-ReReview ([string]$planned.audit.authority_reason-eq'UNRESOLVED_RESPONSE_TEMPLATE') 'authority audit records the exact invalidity reason'
    $revision4Path=Join-Path $projectRoot ".aidos/executions/$executionId/revision-4/EXECUTION.json"
    Assert-ReReview (Test-Path -LiteralPath $revision4Path -PathType Leaf) 'revision 4 execution is durable'
    $revision4=Get-Content -LiteralPath $revision4Path -Raw|ConvertFrom-Json -Depth 100
    Assert-ReReview ([string]$revision4.scope.repair.kind-eq'REVIEW_AUTHORITY_RECOVERY') 'revision 4 carries distinct authority-recovery provenance'
    Assert-ReReview (@($revision4.scope.repair.evidence_refs) -contains ".aidos/reviews/$reviewId/REVIEW.json") 'revision 4 binds the historical review record as evidence'
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 30
    Assert-ReReview ([string]$state.state-eq'TASK_READY' -and [int]$state.revision-eq4 -and [string]$state.execution_id-eq$executionId) 'project is rebound to TASK_READY revision 4 through the existing state machine'
    Assert-ReReview ((Get-FileHash -LiteralPath $reviewPath -Algorithm SHA256).Hash.ToLowerInvariant()-eq$historicalReviewHash) 'historical false-PASS review is preserved byte-for-byte'
    $auditPath=Get-AidosReviewAuthorityAuditPath -ProjectRoot $projectRoot -ReviewId $reviewId
    Assert-ReReview (Test-Path -LiteralPath $auditPath -PathType Leaf) 'authority audit is persisted beside the historical review'

    $again=Request-AidosIndependentReReview -ProjectRoot $projectRoot -ReviewId $reviewId
    Assert-ReReview ([string]$again.status-eq'ALREADY_PLANNED') 'repeated authority recovery is idempotent'
    Assert-ReReview (-not(Test-Path -LiteralPath (Join-Path $projectRoot ".aidos/executions/$executionId/revision-5/EXECUTION.json"))) 'idempotent recovery never creates revision 5'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}

$moduleSource=Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8
$toolSource=Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
Assert-ReReview ($moduleSource -match "transport_state-ne'CLEANED'") 'recovery is restricted to durable cleaned historical reviews'
Assert-ReReview ($moduleSource -match "RepairKind 'REVIEW_AUTHORITY_RECOVERY'") 'recovery uses a distinct durable repair kind'
Assert-ReReview ($moduleSource -match 'Write-AidosRepairRevision') 'recovery returns through the existing revision model rather than rewriting history'
Assert-ReReview ($moduleSource -match 'AUTHORITY_AUDIT\.json') 'recovery persists a bound authority audit'
Assert-ReReview ($toolSource -match 'Request-AidosIndependentReReview') 'operator entrypoint invokes the bounded recovery primitive'

Write-Output "PASS: $passed review authority recovery assertions"
