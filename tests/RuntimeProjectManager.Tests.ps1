[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-RuntimeManager([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

function New-TestRuntimeProject {
    param([string]$Base,[string]$ProjectId,[string]$State='IDLE',[string]$ControlMode='RUNNING',[string]$DefinitionId,[switch]$WithApplicability)
    $projectRoot=Join-Path $Base $ProjectId
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin ("https://example.invalid/{0}.git" -f $ProjectId.ToLowerInvariant())
    [ordered]@{schema_version='0.1';project_id=$ProjectId;project_mode='NEW_PROJECT';repository=("https://example.invalid/{0}.git" -f $ProjectId.ToLowerInvariant());official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id=$ProjectId;state=$State;definition_id=if([string]::IsNullOrWhiteSpace($DefinitionId)){$null}else{$DefinitionId};definition_version=if([string]::IsNullOrWhiteSpace($DefinitionId)){$null}else{1};execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    if($WithApplicability){
        New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/profile') -Force|Out-Null
        [ordered]@{schema_version='0.1';project_id=$ProjectId;selected_presets=@([ordered]@{preset_id='WEB_APPLICATION';version=1;category='PRODUCT_ARCHETYPE';selection_source='BASELINE_DERIVED'});resolved_surfaces=@();conflicts=@();updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/profile/PROJECT_APPLICABILITY.json') -Encoding utf8NoBOM
    }
    if($ControlMode -ne 'RUNNING'){
        [ordered]@{schema_version='0.1';mode=$ControlMode;requested_by='TEST';control_id='control-1';updated_at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/runtime/operator-control.json') -Encoding utf8NoBOM
    }
    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init
    $projectRoot
}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-runtime-manager-'+[guid]::NewGuid().ToString('N'))
$registry=Join-Path $base 'registry'
try {
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects') -Force|Out-Null
    $idleRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-IDLE' -State IDLE
    $definitionReadyRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-DEFINITION-READY' -State IDLE -WithApplicability
    $completedIdleRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-COMPLETED-IDLE' -State IDLE -DefinitionId 'DEF-EXISTING' -WithApplicability
    $waitRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-WAIT' -State WAITING_USER
    $pausedRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-PAUSED' -State TASK_READY -ControlMode PAUSED
    foreach($entry in @(
        @{id='RUNTIME-IDLE';root=$idleRoot},@{id='RUNTIME-DEFINITION-READY';root=$definitionReadyRoot},@{id='RUNTIME-COMPLETED-IDLE';root=$completedIdleRoot},@{id='RUNTIME-WAIT';root=$waitRoot},@{id='RUNTIME-PAUSED';root=$pausedRoot}
    )){
        [ordered]@{schema_version='0.2';project_id=$entry.id;repository=("https://example.invalid/{0}.git" -f $entry.id.ToLowerInvariant());local_root=$entry.root;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$entry.root;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-18T00:00:00Z';updated_at='2026-08-18T00:00:00Z';promoted_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $registry ('projects/'+$entry.id+'.json')) -Encoding utf8NoBOM
    }

    $projects=@(Get-AidosRuntimeRegistryProjects -RegistryRoot $registry)
    Assert-RuntimeManager ($projects.Count -eq 5) 'all promoted runtime projects are discovered'

    $idle=Get-AidosRuntimeNextActor -ProjectRoot $idleRoot
    Assert-RuntimeManager ($idle.actor_identity -eq 'DEFINITION_AGENT' -and $idle.action -eq 'RESOLVE_PROJECT_APPLICABILITY' -and $idle.activatable) 'new IDLE project resolves Project Applicability before Definition'
    $definitionReady=Get-AidosRuntimeNextActor -ProjectRoot $definitionReadyRoot
    Assert-RuntimeManager ($definitionReady.action -eq 'START_DEFINITION' -and $definitionReady.activatable) 'resolved Project Applicability unlocks Definition start'
    $completedIdle=Get-AidosRuntimeNextActor -ProjectRoot $completedIdleRoot
    Assert-RuntimeManager ($completedIdle.action -eq 'WAIT_NEW_GOAL' -and -not$completedIdle.activatable) 'IDLE project with Definition lineage does not start a new Definition automatically'
    $waiting=Get-AidosRuntimeNextActor -ProjectRoot $waitRoot
    Assert-RuntimeManager ($waiting.actor_role -eq 'HUMAN' -and -not$waiting.activatable) 'WAITING_USER remains human-gated'
    $paused=Get-AidosRuntimeNextActor -ProjectRoot $pausedRoot
    Assert-RuntimeManager ($paused.action -eq 'CONTROL_BLOCKED' -and -not$paused.activatable) 'operator PAUSE blocks scheduler activation'

    $global:AidosActivatedProject=$null
    $tick=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $registry -MaxProjects 1 -ActorActivator {
        param($project,$selection)
        $global:AidosActivatedProject=[string]$project.project_id
        [pscustomobject]@{accepted=$true;action=[string]$selection.action}
    } -ResultConsumer {param($registryRoot,$max,$push);[pscustomobject]@{status='IDLE';processed=0;results=@()}}
    Assert-RuntimeManager ($tick.status -eq 'ACTIONABLE' -and $tick.processed -eq 1) 'manager activates at most configured projects'
    Assert-RuntimeManager ($global:AidosActivatedProject -eq 'RUNTIME-IDLE') 'manager prioritizes unresolved Project Applicability'

    $scheduled=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $registry -MaxProjects 1 -ResultConsumer {param($registryRoot,$max,$push);[pscustomobject]@{status='IDLE';processed=0;results=@()}}
    $scheduledResult=@($scheduled.results|Where-Object {$_.project_id -eq 'RUNTIME-IDLE'})[0]
    Assert-RuntimeManager ($scheduledResult.status -eq 'ASSIGNED' -and $scheduledResult.activation.assignment.action -eq 'RESOLVE_PROJECT_APPLICABILITY') 'default scheduling creates applicability assignment first'
    Assert-RuntimeManager (-not[string]::IsNullOrWhiteSpace([string]$scheduledResult.activation.assignment_sha256)) 'scheduled assignment exposes immutable assignment hash'
    Assert-RuntimeManager ($scheduledResult.persistence.status -eq 'PERSISTED') 'applicability scheduling is committed'
    $state=Get-Content -LiteralPath (Join-Path $idleRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20
    Assert-RuntimeManager ($state.state -eq 'IDLE' -and $null -eq $state.definition_id) 'applicability scheduling does not invent Definition lineage'

    $replay=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $registry -MaxProjects 1 -ResultConsumer {param($registryRoot,$max,$push);[pscustomobject]@{status='IDLE';processed=0;results=@()}}
    $replayResult=@($replay.results|Where-Object {$_.project_id -eq 'RUNTIME-IDLE'})[0]
    Assert-RuntimeManager ($replayResult.status -eq 'ASSIGNED' -and $replayResult.activation.status -eq 'ALREADY_PENDING') 'scheduler replay reuses pending applicability assignment'
    Assert-RuntimeManager ($replayResult.persistence.status -eq 'NO_CHANGES') 'scheduler replay is Git-idempotent'
} finally {
    Remove-Variable -Name AidosActivatedProject -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}

$reviewBase=Join-Path ([IO.Path]::GetTempPath()) ('aidos-runtime-review-reconcile-'+[guid]::NewGuid().ToString('N'))
$reviewRegistry=Join-Path $reviewBase 'registry'
try {
    New-Item -ItemType Directory -Path (Join-Path $reviewRegistry 'projects') -Force|Out-Null
    $reviewRoot=New-TestRuntimeProject -Base $reviewBase -ProjectId 'RUNTIME-REVIEW' -State GPT_REVIEWING -DefinitionId 'DEF-REVIEW'
    $reviewStatePath=Join-Path $reviewRoot '.aidos/STATE.json'
    $reviewState=Get-Content -LiteralPath $reviewStatePath -Raw|ConvertFrom-Json -Depth 20
    $reviewState.execution_id='EXEC-REVIEW'
    $reviewState.revision=4
    $reviewState.review_id='11111111-1111-4111-8111-111111111111'
    $reviewState|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $reviewStatePath -Encoding utf8NoBOM
    & git -C $reviewRoot add .aidos/STATE.json
    & git -C $reviewRoot commit -q -m review-state
    [ordered]@{schema_version='0.2';project_id='RUNTIME-REVIEW';repository='https://example.invalid/runtime-review.git';local_root=$reviewRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$reviewRoot;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-20T00:00:00Z';updated_at='2026-08-20T00:00:00Z';promoted_at='2026-08-20T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $reviewRegistry 'projects/RUNTIME-REVIEW.json') -Encoding utf8NoBOM

    $reviewSelection=Get-AidosRuntimeNextActor -ProjectRoot $reviewRoot
    Assert-RuntimeManager ($reviewSelection.action -eq 'RECONCILE_REVIEW' -and $reviewSelection.actor_identity -eq 'WORKER_AGENT' -and $reviewSelection.activatable) 'GPT_REVIEWING selects an activatable review reconciliation'

    $global:AidosReconciledReviewProject=$null
    $idleStage={param($a,$b,$c,$d);[pscustomobject][ordered]@{status='IDLE';processed=0;results=@()}}
    $reviewTick=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $reviewRegistry -MaxProjects 1 -ReviewPublisher {
        param($project)
        $global:AidosReconciledReviewProject=[string]$project.project_id
        [pscustomobject][ordered]@{status='PUBLISHED';review_id='11111111-1111-4111-8111-111111111111'}
    } -IntegrationProcessor $idleStage -ReviewBlockerResumer $idleStage -ResultConsumer $idleStage -FinalAcceptanceResumer $idleStage -HumanInputResumer $idleStage -DefinitionCloser $idleStage
    $reviewResult=@($reviewTick.results|Where-Object {$_.project_id -eq 'RUNTIME-REVIEW'})[0]
    Assert-RuntimeManager ($reviewTick.status -eq 'ACTIONABLE' -and $reviewTick.processed -eq 1) 'GPT_REVIEWING reconciliation is actionable'
    Assert-RuntimeManager ($reviewResult.status -eq 'REVIEW_RECONCILED') 'GPT_REVIEWING invokes the configured review publisher'
    Assert-RuntimeManager ($global:AidosReconciledReviewProject -eq 'RUNTIME-REVIEW') 'review reconciliation targets the exact selected project'
    Assert-RuntimeManager ($reviewResult.activation.status -eq 'PUBLISHED') 'review reconciliation preserves publisher evidence'
} finally {
    Remove-Variable -Name AidosReconciledReviewProject -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $reviewBase){Remove-Item -LiteralPath $reviewBase -Recurse -Force}
}

Write-Output "PASS: $passed runtime project manager assertions"