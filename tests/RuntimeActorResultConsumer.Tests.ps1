[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorTransport.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorResultConsumer.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Consumer([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-result-consumer-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$registry=Join-Path $base 'registry'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'docs') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/applicability-consumer.git'
    [ordered]@{schema_version='0.1';project_id='APPLICABILITY-CONSUMER';project_mode='NEW_PROJECT';repository='https://example.invalid/applicability-consumer.git';official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='APPLICABILITY-CONSUMER';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='APPLICABILITY-CONSUMER';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abc';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='APPLICABILITY-CONSUMER'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='APPLICABILITY-CONSUMER'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    @'
# Product
This product is an interactive browser-based web application with a responsive operator interface.
'@|Set-Content -LiteralPath (Join-Path $projectRoot 'docs/PRODUCT.md') -Encoding utf8NoBOM
    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init

    $record=[ordered]@{schema_version='0.2';project_id='APPLICABILITY-CONSUMER';repository='https://example.invalid/applicability-consumer.git';local_root=$projectRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-18T00:00:00Z';updated_at='2026-08-18T00:00:00Z';promoted_at='2026-08-18T00:00:00Z'}
    $record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $registry 'projects/APPLICABILITY-CONSUMER.json') -Encoding utf8NoBOM
    $project=[pscustomobject]$record

    $selection=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    Assert-Consumer ($selection.action -eq 'RESOLVE_PROJECT_APPLICABILITY') 'missing Project Applicability creates pre-Definition actor action'
    $created=New-AidosRuntimeActorAssignment -Project $project -Selection $selection
    $a=$created.assignment
    Set-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$a.assignment_id) -Status ACTIVATED -TransportType TEST|Out-Null
    $result=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$a.assignment_id;assignment_sha256=[string]$created.assignment_sha256;
        project_id=[string]$a.project_id;actor_role=[string]$a.actor_role;actor_identity=[string]$a.actor_identity;action=[string]$a.action;binding=$a.binding;outcome='COMPLETED';
        result=[pscustomobject][ordered]@{result_type='PROJECT_APPLICABILITY_PROPOSAL';authority_classification='REPO_VERIFIABLE';preset_ids=@('WEB_APPLICATION');selection_source='BASELINE_DERIVED';overrides=@();rationale='Canonical product documentation explicitly describes an interactive browser-based web application.';source_refs=@('docs/PRODUCT.md')};responded_at='2026-08-18T00:00:01Z'
    }
    Save-AidosRuntimeActorResult -ProjectRoot $projectRoot -Result $result|Out-Null
    Assert-Consumer (@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $projectRoot).Count -eq 0) 'completed applicability result is excluded from pending dispatch before Core consumption'

    $consumed=Invoke-AidosRuntimeActorResultConsumerTick -RegistryRoot $registry -AidosRoot $root -MaxItems 1
    $detail=if($consumed.results.Count -gt 0 -and $consumed.results[0].PSObject.Properties['error']){[string]$consumed.results[0].error}else{($consumed|ConvertTo-Json -Depth 20 -Compress)}
    Assert-Consumer ($consumed.status -eq 'PROCESSED' -and $consumed.results[0].status -eq 'APPLIED') "Core consumes exact-bound applicability result; detail=$detail"
    $profilePath=Join-Path $projectRoot '.aidos/profile/PROJECT_APPLICABILITY.json'
    Assert-Consumer (Test-Path -LiteralPath $profilePath -PathType Leaf) 'canonical Project Applicability profile is persisted'
    $profile=Get-Content -LiteralPath $profilePath -Raw|ConvertFrom-Json -Depth 100
    Assert-Consumer (@($profile.selected_presets|Where-Object {$_.preset_id -eq 'WEB_APPLICATION' -and $_.category -eq 'PRODUCT_ARCHETYPE'}).Count -eq 1) 'WEB_APPLICATION is persisted as exactly one product archetype'
    Assert-Consumer ((Read-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$a.assignment_id)).status -eq 'CONSUMED') 'actor transport closes only after Core consumption'
    Assert-Consumer (@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $projectRoot).Count -eq 0) 'consumed applicability assignment leaves pending scheduler set'
    Assert-Consumer ((Get-AidosRuntimeNextActor -ProjectRoot $projectRoot).action -eq 'RESOLVE_PROJECT_APPLICABILITY') 'partial applicability result keeps Definition gated until remaining surfaces are resolved'

    $commits=@(& git -C $projectRoot log --format=%s -n 1)
    Assert-Consumer ([string]$commits[0] -match '^AIDOS consume actor result ') 'consumer commits durable result-derived project state'

    $invalidProjectRoot=Join-Path $base 'invalid-project'
    $invalidRegistry=Join-Path $base 'invalid-registry'
    New-Item -ItemType Directory -Path (Join-Path $invalidProjectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $invalidProjectRoot '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $invalidProjectRoot '.aidos/runtime') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $invalidProjectRoot 'docs') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $invalidRegistry 'projects') -Force|Out-Null
    & git -C $invalidProjectRoot init -q
    & git -C $invalidProjectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $invalidProjectRoot config user.name 'AIDOS Tests'
    & git -C $invalidProjectRoot remote add origin 'https://example.invalid/applicability-rejection.git'
    [ordered]@{schema_version='0.1';project_id='APPLICABILITY-REJECTION';project_mode='NEW_PROJECT';repository='https://example.invalid/applicability-rejection.git';official_root=$invalidProjectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$invalidProjectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $invalidProjectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='APPLICABILITY-REJECTION';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $invalidProjectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='APPLICABILITY-REJECTION';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abc';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $invalidProjectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='APPLICABILITY-REJECTION'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $invalidProjectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='APPLICABILITY-REJECTION'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $invalidProjectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    @'
# Product
This product is an interactive browser-based web application with a responsive operator interface.
'@|Set-Content -LiteralPath (Join-Path $invalidProjectRoot 'docs/PRODUCT.md') -Encoding utf8NoBOM
    & git -C $invalidProjectRoot add .
    & git -C $invalidProjectRoot commit -q -m init

    $invalidRecord=[ordered]@{schema_version='0.2';project_id='APPLICABILITY-REJECTION';repository='https://example.invalid/applicability-rejection.git';local_root=$invalidProjectRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$invalidProjectRoot;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-18T00:00:00Z';updated_at='2026-08-18T00:00:00Z';promoted_at='2026-08-18T00:00:00Z'}
    $invalidRecord|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $invalidRegistry 'projects/APPLICABILITY-REJECTION.json') -Encoding utf8NoBOM
    $invalidProject=[pscustomobject]$invalidRecord
    $invalidSelection=Get-AidosRuntimeNextActor -ProjectRoot $invalidProjectRoot
    $invalidCreated=New-AidosRuntimeActorAssignment -Project $invalidProject -Selection $invalidSelection
    $invalidAssignment=$invalidCreated.assignment
    Set-AidosRuntimeActorTransportState -ProjectRoot $invalidProjectRoot -AssignmentId ([string]$invalidAssignment.assignment_id) -Status ACTIVATED -TransportType TEST|Out-Null
    $invalidResult=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$invalidAssignment.assignment_id;assignment_sha256=[string]$invalidCreated.assignment_sha256;
        project_id=[string]$invalidAssignment.project_id;actor_role=[string]$invalidAssignment.actor_role;actor_identity=[string]$invalidAssignment.actor_identity;action=[string]$invalidAssignment.action;binding=$invalidAssignment.binding;outcome='COMPLETED';
        result=[pscustomobject][ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='';proposed_artifacts=@([pscustomobject][ordered]@{artifact_type='PROJECT_APPLICABILITY_PROPOSAL';authority_classification='REPO_VERIFIABLE';preset_ids=@();selection_source='BASELINE_DERIVED';overrides=@();source_refs=@()});human_input_request=$null};responded_at='2026-08-18T00:00:01Z'
    }
    Save-AidosRuntimeActorResult -ProjectRoot $invalidProjectRoot -Result $invalidResult|Out-Null
    $invalidResultPath=Get-AidosRuntimeActorResultPath -ProjectRoot $invalidProjectRoot -AssignmentId ([string]$invalidAssignment.assignment_id)

    $rejected=Invoke-AidosRuntimeActorResultConsumerTick -RegistryRoot $invalidRegistry -AidosRoot $root -MaxItems 1
    $rejectionDetail=if($rejected.results.Count -gt 0 -and $rejected.results[0].PSObject.Properties['error']){[string]$rejected.results[0].error}else{($rejected|ConvertTo-Json -Depth 30 -Compress)}
    Assert-Consumer ($rejected.status -eq 'PROCESSED' -and $rejected.results[0].status -eq 'REJECTED') "invalid applicability result is deterministically rejected; detail=$rejectionDetail"
    $failedTransport=Read-AidosRuntimeActorTransportState -ProjectRoot $invalidProjectRoot -AssignmentId ([string]$invalidAssignment.assignment_id)
    Assert-Consumer ([string]$failedTransport.status -eq 'FAILED') 'rejected result terminalizes its actor transport as FAILED'
    $expectedInvalidResultRef=[IO.Path]::GetRelativePath($invalidProjectRoot,$invalidResultPath).Replace('\','/')
    Assert-Consumer ([string]$failedTransport.result_ref -eq [string]$expectedInvalidResultRef) 'rejected transport preserves the immutable result reference'
    Assert-Consumer ([string]$failedTransport.last_error -match '^ACTOR_RESULT_REJECTED: ') 'rejected transport records the deterministic consumer reason'
    Assert-Consumer (Test-Path -LiteralPath $invalidResultPath -PathType Leaf) 'rejected immutable actor result remains preserved'
    Assert-Consumer (@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $invalidProjectRoot).Count -eq 0) 'failed actor attempt no longer blocks the pending scheduler set'
    Assert-Consumer ((Get-AidosRuntimeNextActor -ProjectRoot $invalidProjectRoot).action -eq 'RESOLVE_PROJECT_APPLICABILITY') 'failed pre-Definition attempt unlocks a fresh applicability assignment'
    $eventText=@(Get-ChildItem -LiteralPath (Join-Path $invalidProjectRoot '.aidos/events') -Filter '*.jsonl' -File -ErrorAction SilentlyContinue|ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw}) -join "`n"
    Assert-Consumer ($eventText -match 'ACTOR_RESULT_REJECTED') 'semantic rejection records durable recovery evidence'
    $rejectionCommit=@(& git -C $invalidProjectRoot log --format=%s -n 1)
    Assert-Consumer ([string]$rejectionCommit[0] -match '^AIDOS reject actor result ') 'semantic rejection is committed before replanning'

    $retry=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $invalidRegistry -AidosRoot $root -MaxProjects 1
    $retryResult=@($retry.results|Where-Object {$_.project_id -eq 'APPLICABILITY-REJECTION'})|Select-Object -First 1
    Assert-Consumer ($retry.status -eq 'ACTIONABLE' -and [string]$retryResult.status -eq 'ASSIGNED') 'project manager autonomously schedules the replacement applicability attempt'
    Assert-Consumer ([string]$retryResult.activation.assignment.assignment_id -ne [string]$invalidAssignment.assignment_id) 'replacement attempt receives a new immutable assignment identity'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed runtime actor result consumer assertions"
