[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorTransport.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Actor([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-actor-assignment-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/runtime-actor.git'
    [ordered]@{schema_version='0.1';project_id='RUNTIME-ACTOR';project_mode='NEW_PROJECT';repository='https://example.invalid/runtime-actor.git';official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='RUNTIME-ACTOR';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init

    $project=[pscustomobject]@{project_id='RUNTIME-ACTOR';local_root=$projectRoot}
    $applicability=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    Assert-Actor ($applicability.action -eq 'RESOLVE_PROJECT_APPLICABILITY') 'new project selects applicability before Definition'
    $appAssignment=New-AidosRuntimeActorAssignment -Project $project -Selection $applicability
    Assert-Actor ($appAssignment.status -eq 'PENDING' -and $null -eq $appAssignment.assignment.binding.definition_id) 'applicability assignment does not create Definition lineage'
    $state=Get-AidosState $projectRoot
    Assert-Actor ($state.state -eq 'IDLE' -and $null -eq $state.definition_id) 'applicability assignment leaves project IDLE'
    $appReplay=New-AidosRuntimeActorAssignment -Project $project -Selection $applicability
    Assert-Actor ($appReplay.status -eq 'ALREADY_PENDING') 'applicability assignment replay is idempotent'

    Set-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$appAssignment.assignment.assignment_id) -Status ABANDONED|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/profile') -Force|Out-Null
    [ordered]@{schema_version='0.1';project_id='RUNTIME-ACTOR';selected_presets=@([ordered]@{preset_id='WEB_APPLICATION';version=1;category='PRODUCT_ARCHETYPE';selection_source='BASELINE_DERIVED'});resolved_surfaces=@();conflicts=@();updated_at='2026-08-18T00:00:01Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/profile/PROJECT_APPLICABILITY.json') -Encoding utf8NoBOM

    $start=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    Assert-Actor ($start.action -eq 'START_DEFINITION') 'resolved Project Applicability unlocks Definition assignment'
    $created=New-AidosRuntimeActorAssignment -Project $project -Selection $start
    Assert-Actor ($created.status -eq 'PENDING') 'Definition start creates pending assignment'
    Assert-Actor (-not[string]::IsNullOrWhiteSpace([string]$created.assignment.binding.definition_id) -and [int]$created.assignment.binding.definition_version -eq 1) 'Definition assignment owns exact Definition binding'
    $state=Get-AidosState $projectRoot
    Assert-Actor ($state.state -eq 'WAITING_DEFINITION' -and [string]$state.definition_id -eq [string]$created.assignment.binding.definition_id) 'state transitions to WAITING_DEFINITION with same binding'
    Assert-Actor (@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $projectRoot).Count -eq 1) 'only Definition assignment remains pending after applicability closes'

    $resume=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    Assert-Actor ($resume.action -eq 'RESUME_DEFINITION') 'next scheduler tick selects Definition resume'
    $replayed=New-AidosRuntimeActorAssignment -Project $project -Selection $resume
    Assert-Actor ($replayed.status -eq 'ALREADY_PENDING') 'resume reuses pending START assignment'
    Assert-Actor (@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $projectRoot).Count -eq 1) 'Definition replay does not create duplicate assignment'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed runtime actor assignment assertions"
