[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-WorkerSchedule([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-worker-schedule-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project';$registry=Join-Path $base 'registry'
try {
    foreach($path in @('.aidos/documentation','.aidos/evidence','.aidos/profile','.aidos/definitions/DEF-WORKER-001/v1','docs')){New-Item -ItemType Directory -Path (Join-Path $projectRoot $path) -Force|Out-Null}
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/worker-schedule.git'

    [ordered]@{schema_version='0.1';project_id='WORKER-SCHEDULE';project_mode='NEW_PROJECT';repository='https://example.invalid/worker-schedule.git';official_root=$projectRoot;default_branch='main';project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='WORKER-SCHEDULE';state='TASK_READY';definition_id='DEF-WORKER-001';definition_version=1;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='WORKER-SCHEDULE';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abcdef1';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='WORKER-SCHEDULE'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='WORKER-SCHEDULE'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';definition_id='DEF-WORKER-001';version=1;project_id='WORKER-SCHEDULE';status='ACCEPTED';goal='Implement accepted scope.';requirements=@();non_functional=@();acceptance=@([ordered]@{criterion='npm run validate passes';source_ref='docs/ENGINEERING.md'});out_of_scope=@();open_questions=@();sources=@('docs/ENGINEERING.md');decision_refs=@();auto_decision_refs=@();human_input_request_refs=@();progress_ref=$null;applicability_ref=$null;project_applicability_ref='.aidos/profile/PROJECT_APPLICABILITY.json';profile_refs=@('.aidos/profile/PROJECT_APPLICABILITY.json');accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST'}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/definitions/DEF-WORKER-001/v1/DEFINITION.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';surface_catalog_version='0.1.0';preset_catalog_version='0.1.0';project_id='WORKER-SCHEDULE';selected_presets=@([ordered]@{preset_id='WEB_APPLICATION';version=1;category='PRODUCT_ARCHETYPE';selection_source='BASELINE_DERIVED'},[ordered]@{preset_id='REACT';version=1;category='STACK';selection_source='BASELINE_DERIVED'});overrides=@();resolved_surfaces=@();conflicts=@();updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/profile/PROJECT_APPLICABILITY.json') -Encoding utf8NoBOM
    @'
# Engineering
- `npm ci` is the canonical reproducible restore path.
- Normal restore is online from the configured npm registry.
- `npm run validate` is the aggregate validator.
'@|Set-Content -LiteralPath (Join-Path $projectRoot 'docs/ENGINEERING.md') -Encoding utf8NoBOM
    '{"scripts":{"validate":"echo pass"}}'|Set-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Encoding utf8NoBOM
    & git -C $projectRoot add .;& git -C $projectRoot commit -q -m init

    [ordered]@{schema_version='0.2';project_id='WORKER-SCHEDULE';repository='https://example.invalid/worker-schedule.git';local_root=$projectRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-18T00:00:00Z';updated_at='2026-08-18T00:00:00Z';promoted_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $registry 'projects/WORKER-SCHEDULE.json') -Encoding utf8NoBOM

    $selection=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    Assert-WorkerSchedule ($selection.actor_identity-eq'EXECUTION_AGENT' -and $selection.action-eq'DISPATCH_EXECUTION' -and $selection.activatable) 'TASK_READY selects autonomous Execution Worker'

    $global:AidosWorkerExecutionPath=$null
    $tick=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $registry -MaxProjects 1 -ResultConsumer {param($r,$m,$p);[pscustomobject]@{status='IDLE';processed=0;results=@()}} -FinalAcceptanceResumer {param($r,$m,$p);[pscustomobject]@{status='IDLE';processed=0;results=@()}} -HumanInputResumer {param($r,$m,$p);[pscustomobject]@{status='IDLE';processed=0;results=@()}} -DefinitionCloser {param($r,$c,$m,$p);[pscustomobject]@{status='IDLE';processed=0;results=@()}} -WorkerInvoker {
        param($project,$executionPath)
        $global:AidosWorkerExecutionPath=[string]$executionPath
        [pscustomobject]@{status='REVIEW_READY';stub=$true}
    }
    $result=@($tick.results|Where-Object {$_.project_id-eq'WORKER-SCHEDULE'})[0]
    Assert-WorkerSchedule ($tick.status-eq'ACTIONABLE' -and $result.status-eq'WORKER_DISPATCHED') 'runtime manager dispatches the Worker without human relay'
    Assert-WorkerSchedule (-not[string]::IsNullOrWhiteSpace($global:AidosWorkerExecutionPath) -and (Test-Path -LiteralPath $global:AidosWorkerExecutionPath -PathType Leaf)) 'Worker receives a durable exact-bound Execution artifact'
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20
    Assert-WorkerSchedule (-not[string]::IsNullOrWhiteSpace([string]$state.execution_id) -and [int]$state.revision-eq1) 'scheduler persists execution/revision binding before Worker activation'
} finally {
    Remove-Variable -Name AidosWorkerExecutionPath -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed autonomous Worker scheduling assertions"
