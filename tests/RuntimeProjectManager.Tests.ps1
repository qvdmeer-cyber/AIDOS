[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-RuntimeManager([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

function New-TestRuntimeProject {
    param([string]$Base,[string]$ProjectId,[string]$State='IDLE',[string]$ControlMode='RUNNING',[string]$DefinitionId)
    $projectRoot=Join-Path $Base $ProjectId
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin ("https://example.invalid/{0}.git" -f $ProjectId.ToLowerInvariant())
    [ordered]@{schema_version='0.1';project_id=$ProjectId;project_mode='NEW_PROJECT';repository=("https://example.invalid/{0}.git" -f $ProjectId.ToLowerInvariant());official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id=$ProjectId;state=$State;definition_id=if([string]::IsNullOrWhiteSpace($DefinitionId)){$null}else{$DefinitionId};definition_version=if([string]::IsNullOrWhiteSpace($DefinitionId)){$null}else{1};execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
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
    $completedIdleRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-COMPLETED-IDLE' -State IDLE -DefinitionId 'DEF-EXISTING'
    $waitRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-WAIT' -State WAITING_USER
    $pausedRoot=New-TestRuntimeProject -Base $base -ProjectId 'RUNTIME-PAUSED' -State TASK_READY -ControlMode PAUSED
    foreach($entry in @(
        @{id='RUNTIME-IDLE';root=$idleRoot},@{id='RUNTIME-COMPLETED-IDLE';root=$completedIdleRoot},@{id='RUNTIME-WAIT';root=$waitRoot},@{id='RUNTIME-PAUSED';root=$pausedRoot}
    )){
        [ordered]@{schema_version='0.2';project_id=$entry.id;repository=("https://example.invalid/{0}.git" -f $entry.id.ToLowerInvariant());local_root=$entry.root;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$entry.root;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-18T00:00:00Z';updated_at='2026-08-18T00:00:00Z';promoted_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $registry ('projects/'+$entry.id+'.json')) -Encoding utf8NoBOM
    }

    $projects=@(Get-AidosRuntimeRegistryProjects -RegistryRoot $registry)
    Assert-RuntimeManager ($projects.Count -eq 4) 'all promoted runtime projects are discovered'

    $idle=Get-AidosRuntimeNextActor -ProjectRoot $idleRoot
    Assert-RuntimeManager ($idle.actor_identity -eq 'DEFINITION_AGENT' -and $idle.action -eq 'START_DEFINITION' -and $idle.activatable) 'new IDLE project selects Definition Thinker'
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
    }
    Assert-RuntimeManager ($tick.status -eq 'ACTIONABLE' -and $tick.processed -eq 1) 'manager activates at most configured projects'
    Assert-RuntimeManager ($global:AidosActivatedProject -eq 'RUNTIME-IDLE') 'manager selects actionable new IDLE project over non-activatable projects'

    $noAdapter=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $registry -MaxProjects 1
    Assert-RuntimeManager (@($noAdapter.results|Where-Object {$_.status -eq 'ACTOR_ADAPTER_REQUIRED'}).Count -eq 1) 'missing actor adapter is explicit and fail-closed'
} finally {
    Remove-Variable -Name AidosActivatedProject -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed runtime project manager assertions"
