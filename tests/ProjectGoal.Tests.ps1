[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectGoal.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Goal([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-GoalThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-project-goal-'+[guid]::NewGuid().ToString('N'));$projectRoot=Join-Path $base 'project';$registryRoot=Join-Path $base 'registry'
try{
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    &git -C $projectRoot init -q;&git -C $projectRoot config user.email 'aidos-tests@example.invalid';&git -C $projectRoot config user.name 'AIDOS Tests';&git -C $projectRoot remote add origin 'https://example.invalid/project-goal.git'
    [ordered]@{schema_version='0.1';project_id='PROJECT-GOAL';project_mode='NEW_PROJECT';repository='https://example.invalid/project-goal.git';official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='PROJECT-GOAL';state='IDLE';definition_id='DEF-COMPLETED';definition_version=2;execution_id='EXEC-COMPLETED';revision=4;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result='.aidos/old-result.json';git_head=$null;validation_result='.aidos/old-validation.json';updated_at='2026-08-21T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';mode='RUNNING';requested_by='CHATGPT_OPERATOR';control_id=[guid]::NewGuid().ToString();updated_at='2026-08-21T00:00:00Z'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/runtime/operator-control.json') -Encoding utf8NoBOM
    $resolve=Join-Path $root 'tools/Resolve-AidosProjectApplicability.ps1';$profile=&$resolve -ProjectRoot $projectRoot -ProjectId 'PROJECT-GOAL' -PresetIds @('WEB_APPLICATION') -SelectionSource BASELINE_DERIVED -OverridesJson '[]' -AidosRoot $root
    $overrides=@($profile.resolved_surfaces|Where-Object {$_.state -eq 'UNRESOLVED'}|ForEach-Object {[ordered]@{surface_id=[string]$_.surface_id;state='APPLICABLE';reason='Project goal test resolves applicability.';source_ref='.aidos/PROJECT.json'}})
    if($overrides.Count){&$resolve -ProjectRoot $projectRoot -ProjectId 'PROJECT-GOAL' -PresetIds @('WEB_APPLICATION') -SelectionSource BASELINE_DERIVED -OverridesJson ($overrides|ConvertTo-Json -Depth 20 -Compress) -AidosRoot $root|Out-Null}
    &git -C $projectRoot add .;&git -C $projectRoot commit -q -m fixture
    Register-AidosPreparationProject -RegistryRoot $registryRoot -ProjectId 'PROJECT-GOAL' -Repository 'https://example.invalid/project-goal.git' -LocalRoot $projectRoot -ProjectMode NEW_PROJECT -AllowedPersistencePaths @('.aidos')|Out-Null
    Set-AidosPreparationProjectPhase -RegistryRoot $registryRoot -ProjectId 'PROJECT-GOAL' -Phase RUNTIME -Status PROMOTED|Out-Null
    $project=Get-AidosRegisteredProject -RegistryRoot $registryRoot -ProjectId 'PROJECT-GOAL'
    Assert-GoalThrows {Submit-AidosProjectGoal -Project $project -Goal 'short'} 'at least 10' 'short goals fail closed'
    $accepted=Submit-AidosProjectGoal -Project $project -Goal 'Build the complete user-facing project interface from accepted evidence.' -SubmittedBy CHATGPT_OPERATOR
    Assert-Goal ([string]$accepted.status-eq'ACCEPTED' -and [string]$accepted.acknowledgement-match'^AIDOS_GOAL_ACCEPTED::GOAL-') 'valid chat goal receives a durable Core acknowledgement'
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20
    Assert-Goal ([string]$state.state-eq'WAITING_DEFINITION' -and [string]$state.definition_id-eq[string]$accepted.definition_id) 'goal creates an exact new Definition state binding'
    Assert-Goal ($null-eq$state.execution_id -and $null-eq$state.revision -and $null-eq$state.terminal_result) 'new goal clears completed execution binding'
    $goal=Get-AidosDefinitionProjectGoal -ProjectRoot $projectRoot -DefinitionId ([string]$accepted.definition_id) -DefinitionVersion 1
    Assert-Goal ([string]$goal.goal.goal-eq'Build the complete user-facing project interface from accepted evidence.' -and [string]$goal.goal.previous_definition_id-eq'DEF-COMPLETED') 'goal artifact preserves exact human text and prior lineage'
    Assert-Goal ((Get-Content -LiteralPath $goal.path -Raw|Test-Json -SchemaFile (Join-Path $root 'schemas/project-goal.schema.json'))) 'persisted project goal validates against its Core schema'
    $bound=[pscustomobject]@{assignment=[pscustomobject]@{action='RESUME_DEFINITION';binding=[pscustomobject]@{definition_id=[string]$accepted.definition_id;definition_version=1}}}
    $documents=@(Get-AidosDesktopThinkerAuthorizedDocuments -ProjectRoot $projectRoot -BoundAssignment $bound)
    Assert-Goal (@($documents.path)-contains[string]$accepted.goal_ref) 'exact bound goal is an authorized Definition Thinker source'
    Assert-Goal (Test-Path -LiteralPath (Join-Path $projectRoot ".aidos/definitions/$($accepted.definition_id)/v1/PROGRESS.json")) 'new Definition workspace is initialized before acceptance returns'
    Assert-Goal ([string]$accepted.persistence.status-eq'PERSISTED' -and -not[bool]$accepted.persistence.pushed) 'goal, binding and workspace are committed together'
    Assert-Goal (-not(@(&git -C $projectRoot status --porcelain))) 'accepted goal leaves a clean project worktree'
    Assert-GoalThrows {Submit-AidosProjectGoal -Project $project -Goal 'A different simultaneous project goal must be rejected.'} 'requires IDLE' 'second goal cannot overwrite an active Definition'
    Write-Output "PASS: $passed project goal assertions"
}finally{if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}}
