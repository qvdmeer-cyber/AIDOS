[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosAutonomousRepair.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-ARR([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-autonomous-review-repair-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$registry=Join-Path $base 'registry'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/executions/EXEC-1/revision-1') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/reviews/REV-1') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/autonomous-review-repair.git'

    [ordered]@{schema_version='0.1';project_id='ARR';project_mode='NEW_PROJECT';repository='https://example.invalid/autonomous-review-repair.git';official_root=$projectRoot;project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='ARR';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abcdef1';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='ARR'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='ARR'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='ARR';state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=1;codex_session_id=$null;review_id='REV-1';lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM

    $execution=[ordered]@{schema_version='0.1';execution_id='EXEC-1';revision=1;project_id='ARR';project_mode='NEW_PROJECT';workstream=$null;preparation=[ordered]@{baseline_commit='abcdef1';access_sha256=(Get-FileHash (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Algorithm SHA256).Hash.ToLowerInvariant();evidence_inventory_sha256=(Get-FileHash (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Algorithm SHA256).Hash.ToLowerInvariant();current_product_state_id=$null;current_product_state_commit=$null;current_product_state_contract_version=$null;discovery_catalog_version=$null};definition=[ordered]@{id='DEF-1';version=1};goal='Initial accepted implementation';scope=[ordered]@{definition_ref='.aidos/definitions/DEF-1/v1/DEFINITION.json';implementation_policy='accepted scope'};acceptance=@([ordered]@{criterion='validate'});authority=[ordered]@{filesystem_write=@('.');git_commit=$false;git_push=$false;network=$false};knowledge_selection=@();validators=@('npm run validate');validation=[ordered]@{mode='ALL';requirements=@([ordered]@{type='PATH_EXISTS';path='package.json'})};executor_profile=[ordered]@{model='codex-cli-default';reasoning_effort='medium'};stop_conditions=@('TER_REVIEW')}
    $execution|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/executions/EXEC-1/revision-1/EXECUTION.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';review_id='REV-1';project_id='ARR';project_root=$projectRoot;definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=1;transport_state='DECIDED';package_path='.aidos/reviews/REV-1/package';package_manifest_path='.aidos/reviews/REV-1/package/MANIFEST.json';package_manifest_sha256=('a'*64);assignment_path='.aidos/reviews/REV-1/package/REVIEW_ASSIGNMENT.json';assignment_sha256=('b'*64);assignment=[ordered]@{};response=[ordered]@{repair_guidance=@('Fix the reviewed contract mismatch.');outcome='REPAIR'};response_sha256=('c'*64);response_received_at='2026-08-18T00:00:00Z';response_received_by='BRIDGE';response_accepted_at='2026-08-18T00:00:00Z';response_accepted_by='BRIDGE';evidence_refs=@([ordered]@{kind='VALIDATION';path='.aidos/executions/EXEC-1/revision-1/VALIDATION.json';sha256=('d'*64)});published_at='2026-08-18T00:00:00Z';published_by='BRIDGE';updated_at='2026-08-18T00:00:01Z';decision=[ordered]@{outcome='REPAIR';target_state='TASK_READY';reason='Repair is inside accepted scope.';decided_by='WORKER_AGENT';decided_at='2026-08-18T00:00:01Z'};consume_ack=$null;consumed_at=$null;consumed_by=$null;cleaned_at=$null;abandonment=$null}|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/reviews/REV-1/REVIEW.json') -Encoding utf8NoBOM
    '{}'|Set-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Encoding utf8NoBOM
    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init

    $project=[pscustomobject][ordered]@{schema_version='0.2';project_id='ARR';repository='https://example.invalid/autonomous-review-repair.git';local_root=$projectRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'};allowed_persistence_paths=@('.aidos')}
    $repair=Ensure-AidosReviewRepairRevision -Project $project
    Assert-ARR ($repair.status -eq 'PLANNED') 'REPAIR review creates a new immutable repair revision'
    Assert-ARR ([int]$repair.execution.revision -eq 2) 'review repair increments revision exactly once'
    Assert-ARR ([string]$repair.execution.scope.repair.kind -eq 'REVIEW_REPAIR') 'new revision records repair provenance'
    Assert-ARR (@($repair.execution.scope.repair.guidance) -contains 'Fix the reviewed contract mismatch.') 'review repair guidance is carried into revision+1'
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 30
    Assert-ARR ([string]$state.execution_id -eq 'EXEC-1' -and [int]$state.revision -eq 2 -and [string]$state.state -eq 'TASK_READY') 'state rebinds to repair revision before Worker redispatch'
    $again=Ensure-AidosReviewRepairRevision -Project $project
    Assert-ARR ($again.status -eq 'NO_REPAIR_REVIEW') 'repair preflight is idempotent on revision+1 and does not create revision+2 without a new review'

    # The central transport dispatcher runs only after the host interactive gate.
    # Verify that when Definition transport consumes no capacity, portfolio review
    # is delegated through the same bounded dispatcher path.
    $global:ReviewTransportCalled=0
    $transport=Invoke-AidosRuntimeActorTransportDispatch -RegistryRoot $registry -MaxItems 1 -ActorTransportDispatcher {param($p,$a,$s);throw 'actor transport should not run in empty registry'} -ReviewTransportDispatcher {
        param($registryRoot,$processName,$remaining)
        $global:ReviewTransportCalled++
        [pscustomobject][ordered]@{status='PROCESSED';processed=1;results=@([pscustomobject]@{status='CONSUMED'})}
    }
    Assert-ARR ($global:ReviewTransportCalled -eq 1) 'portfolio review uses central gated runtime transport dispatcher'
    Assert-ARR ($transport.status -eq 'PROCESSED' -and $transport.processed -eq 1) 'review transport contributes to bounded dispatcher work accounting'
} finally {
    Remove-Variable -Name ReviewTransportCalled -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed autonomous review/repair assertions"
