[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosHumanInput.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosAutonomousIntegration.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosAutonomousExecution.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosReviewBlocker.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosWorkerDispatchGuard.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-RIC([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-review-integration-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
try {
    foreach($dir in @('.aidos/documentation','.aidos/evidence','.aidos/runtime','.aidos/profile','.aidos/executions/EXEC-1/revision-1','.aidos/reviews/REV-PASS','.aidos/reviews/REV-BLOCK')){New-Item -ItemType Directory -Path (Join-Path $projectRoot $dir) -Force|Out-Null}
    & git -C $projectRoot init -q;& git -C $projectRoot config user.email 'aidos-tests@example.invalid';& git -C $projectRoot config user.name 'AIDOS Tests';& git -C $projectRoot remote add origin 'https://example.invalid/review-integration.git'
    [ordered]@{schema_version='0.1';project_id='RIC';project_mode='NEW_PROJECT';repository='https://example.invalid/review-integration.git';official_root=$projectRoot;project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='RIC';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abcdef1';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='RIC'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='RIC'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='RIC';state='IDLE';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=1;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    $accessHash=(Get-FileHash (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Algorithm SHA256).Hash.ToLowerInvariant();$evidenceHash=(Get-FileHash (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $execution=[ordered]@{schema_version='0.1';execution_id='EXEC-1';revision=1;project_id='RIC';project_mode='NEW_PROJECT';workstream=$null;preparation=[ordered]@{baseline_commit='abcdef1';access_sha256=$accessHash;evidence_inventory_sha256=$evidenceHash;current_product_state_id=$null;current_product_state_commit=$null;current_product_state_contract_version=$null;discovery_catalog_version=$null};definition=[ordered]@{id='DEF-1';version=1};goal='Implement accepted change';scope=[ordered]@{definition_ref='.aidos/definitions/DEF-1/v1/DEFINITION.json';implementation_policy='accepted'};acceptance=@([ordered]@{criterion='pass'});authority=[ordered]@{filesystem_write=@('.');git_commit=$false;git_push=$false;network=$false};knowledge_selection=@();validators=@('npm run validate');validation=[ordered]@{mode='ALL';requirements=@([ordered]@{type='PATH_EXISTS';path='package.json'})};executor_profile=[ordered]@{model='codex-cli-default';reasoning_effort='medium'};stop_conditions=@('TER_REVIEW')}
    $execution|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/executions/EXEC-1/revision-1/EXECUTION.json') -Encoding utf8NoBOM
    [ordered]@{status='PASS';checked_at='2026-08-18T00:00:00Z';requirements=@();validators=@()}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/executions/EXEC-1/revision-1/VALIDATION.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';review_id='REV-PASS';project_id='RIC';project_root=$projectRoot;definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=1;transport_state='CLEANED';package_path='.aidos/runtime/reviews/REV-PASS';package_manifest_path='.aidos/runtime/reviews/REV-PASS/MANIFEST.json';package_manifest_sha256=('a'*64);assignment_path='.aidos/runtime/reviews/REV-PASS/REVIEW_ASSIGNMENT.json';assignment_sha256=('b'*64);assignment=[ordered]@{};response=[ordered]@{outcome='PASS'};response_sha256=('c'*64);response_received_at='2026-08-18T00:00:00Z';response_received_by='TEST';response_accepted_at='2026-08-18T00:00:00Z';response_accepted_by='TEST';evidence_refs=@([ordered]@{kind='VALIDATION';path='.aidos/executions/EXEC-1/revision-1/VALIDATION.json';sha256=('d'*64)});published_at='2026-08-18T00:00:00Z';published_by='BRIDGE';updated_at='2026-08-18T00:00:00Z';decision=[ordered]@{outcome='PASS';target_state='IDLE';reason='Accepted';decided_by='WORKER_AGENT';decided_at='2026-08-18T00:00:00Z'};consume_ack=$null;consumed_at='2026-08-18T00:00:00Z';consumed_by='BRIDGE';cleaned_at='2026-08-18T00:00:00Z';abandonment=$null}|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/reviews/REV-PASS/REVIEW.json') -Encoding utf8NoBOM
    '{"scripts":{"validate":"echo pass"}}'|Set-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Encoding utf8NoBOM
    'before'|Set-Content -LiteralPath (Join-Path $projectRoot 'app.txt') -Encoding utf8NoBOM
    & git -C $projectRoot add .;& git -C $projectRoot commit -q -m init

    # PASS integration: intent exists before acceptance; Worker delta remains
    # uncommitted until Core integrates it.
    'after'|Set-Content -LiteralPath (Join-Path $projectRoot 'app.txt') -Encoding utf8NoBOM
    New-AidosPassIntegrationIntent -ProjectRoot $projectRoot -ReviewId 'REV-PASS' -ExecutionId 'EXEC-1' -Revision 1|Out-Null
    $project=[pscustomobject][ordered]@{project_id='RIC';repository='https://example.invalid/review-integration.git';local_root=$projectRoot;stage='RUNTIME';status='PROMOTED';allowed_persistence_paths=@('.aidos');git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}
    $integrated=Invoke-AidosPassIntegration -Project $project -ReviewId 'REV-PASS'
    Assert-RIC ($integrated.status -eq 'APPLIED') 'PASS review integrates Worker delta'
    Assert-RIC ((Get-Content -LiteralPath (Join-Path $projectRoot 'app.txt') -Raw).Trim() -eq 'after') 'accepted Worker content remains after integration'
    Assert-RIC (@(& git -C $projectRoot status --porcelain).Count -eq 0) 'PASS integration closes with a clean worktree'
    $intent=Get-Content -LiteralPath (Get-AidosIntegrationIntentPath -ProjectRoot $projectRoot -ReviewId 'REV-PASS') -Raw|ConvertFrom-Json -Depth 20
    Assert-RIC ([string]$intent.status -eq 'APPLIED' -and -not[string]::IsNullOrWhiteSpace([string]$intent.integration_commit)) 'integration intent records applied commit'
    Assert-RIC (Test-AidosIntegrationPathAuthorized -Execution ([pscustomobject]$execution) -Path '.aidos/runtime/test.json') '.aidos lifecycle paths remain Core-authorized during integration'

    # A Worker may have already committed the exact execution result before
    # Core receives PASS. A clean, bound worktree is then a valid no-op
    # integration and must not be treated as a missing delta.
    $cleanReview=(Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/reviews/REV-PASS/REVIEW.json') -Raw).Replace('REV-PASS','REV-CLEAN')
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/reviews/REV-CLEAN') -Force|Out-Null
    $cleanReview|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/reviews/REV-CLEAN/REVIEW.json') -Encoding utf8NoBOM
    New-AidosPassIntegrationIntent -ProjectRoot $projectRoot -ReviewId 'REV-CLEAN' -ExecutionId 'EXEC-1' -Revision 1|Out-Null
    $cleanIntegrated=Invoke-AidosPassIntegration -Project $project -ReviewId 'REV-CLEAN'
    Assert-RIC ($cleanIntegrated.status -eq 'APPLIED' -and $cleanIntegrated.commit) 'clean PASS integration records current HEAD without a delta commit'

    # Worker commit authority guard: clean initial dispatch binds HEAD; any Worker
    # commit is deterministically rejected even if content could otherwise pass.
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20;$state.state='TASK_READY';$state.execution_id='EXEC-1';$state.revision=1;$state.updated_at=[DateTimeOffset]::UtcNow.ToString('o');$state|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    & git -C $projectRoot add .aidos/STATE.json;& git -C $projectRoot commit -q -m 'prepare guard'
    $guard=New-AidosWorkerDispatchGuard -ProjectRoot $projectRoot
    'illegal commit'|Set-Content -LiteralPath (Join-Path $projectRoot 'illegal.txt') -Encoding utf8NoBOM;& git -C $projectRoot add illegal.txt;& git -C $projectRoot commit -q -m 'worker should not commit'
    $guardResult=Test-AidosWorkerDispatchGuard -ProjectRoot $projectRoot -ExecutionId 'EXEC-1' -Revision 1
    Assert-RIC ($guardResult.status -eq 'AUTHORITY_VIOLATION') 'Worker Git commit authority violation is detected'
    Assert-RIC ([string](Get-AidosState $projectRoot).state -eq 'RECOVERY_REQUIRED') 'Worker Git authority violation forces recovery'

    # Reset fixture to a BLOCKER review and prove durable Human Input + repair.
    & git -C $projectRoot reset --hard HEAD~1 -q
    $state=Get-AidosState $projectRoot;$state.state='WAITING_USER';$state.execution_id='EXEC-1';$state.revision=1;$state.review_id=$null;$state|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';review_id='REV-BLOCK';project_id='RIC';project_root=$projectRoot;definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=1;transport_state='CLEANED';package_path='.aidos/runtime/reviews/REV-BLOCK';package_manifest_path='.aidos/runtime/reviews/REV-BLOCK/MANIFEST.json';package_manifest_sha256=('a'*64);assignment_path='.aidos/runtime/reviews/REV-BLOCK/REVIEW_ASSIGNMENT.json';assignment_sha256=('b'*64);assignment=[ordered]@{};response=[ordered]@{repair_guidance=@();outcome='BLOCKER'};response_sha256=('c'*64);response_received_at='2026-08-18T00:00:00Z';response_received_by='TEST';response_accepted_at='2026-08-18T00:00:00Z';response_accepted_by='TEST';evidence_refs=@();published_at='2026-08-18T00:00:00Z';published_by='BRIDGE';updated_at='2026-08-18T00:00:00Z';decision=[ordered]@{outcome='BLOCKER';target_state='WAITING_USER';reason='Human authority required';decided_by='WORKER_AGENT';decided_at='2026-08-18T00:00:00Z'};consume_ack=$null;consumed_at='2026-08-18T00:00:00Z';consumed_by='BRIDGE';cleaned_at='2026-08-18T00:00:00Z';abandonment=$null}|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/reviews/REV-BLOCK/REVIEW.json') -Encoding utf8NoBOM
    $hir=New-AidosReviewBlockerHumanInput -Project $project -ReviewId 'REV-BLOCK'
    Assert-RIC ($hir.status -eq 'WAITING_HUMAN') 'BLOCKER review publishes durable Human Input'
    $request=Get-Content -LiteralPath (Join-Path $projectRoot $hir.request_ref) -Raw|ConvertFrom-Json -Depth 30
    Assert-RIC ([string]$request.phase -eq 'REVIEW' -and @($request.options).Count -eq 3) 'review blocker request exposes bounded continuation choices'
    Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId ([string]$hir.request_id) -RespondedBy TEST -SelectedOptionId REPAIR_WITHIN_DEFINITION -Text 'Repair the technical blocker only.'|Out-Null
    $resumed=Invoke-AidosReviewBlockerResume -Project $project -RequestId ([string]$hir.request_id) -AidosRoot $root
    Assert-RIC ($resumed.outcome -eq 'REPAIR_WITHIN_DEFINITION') 'human blocker repair decision resumes automatically'
    $newState=Get-AidosState $projectRoot
    Assert-RIC ([string]$newState.state -eq 'TASK_READY' -and [int]$newState.revision -eq 2) 'human blocker repair produces revision+1 TASK_READY'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed review integration closure assertions"
