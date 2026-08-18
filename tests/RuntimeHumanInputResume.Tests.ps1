[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosHumanInput.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeHumanInputResume.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Resume([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-runtime-human-resume-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$registry=Join-Path $base 'registry'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/human-input-bindings') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/runtime-human-resume.git'
    [ordered]@{schema_version='0.1';project_id='RUNTIME-HUMAN';project_mode='NEW_PROJECT';repository='https://example.invalid/runtime-human-resume.git';official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='RUNTIME-HUMAN';state='WAITING_USER';definition_id='DEF-HUMAN';definition_version=1;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    & (Join-Path $root 'tools/New-AidosDefinitionProgress.ps1') -ProjectRoot $projectRoot -ProjectId 'RUNTIME-HUMAN' -DefinitionId 'DEF-HUMAN' -DefinitionVersion 1|Out-Null
    & (Join-Path $root 'tools/Set-AidosDefinitionSurface.ps1') -ProjectRoot $projectRoot -DefinitionId 'DEF-HUMAN' -DefinitionVersion 1 -SurfaceId goal_scope -Status DECISION_REQUIRED -Summary 'Human choice required.' -OpenQuestionCount 1|Out-Null

    $requestId='hir-runtime-1';$now='2026-08-18T00:00:01Z'
    $request=[ordered]@{contract_version='0.1.0';request_id=$requestId;project_id='RUNTIME-HUMAN';workstream_id=$null;phase='DEFINITION';request_type='PRODUCT_DECISION';status='WAITING';context_summary='Choose the bounded goal.';question='Which goal?';options=@([ordered]@{option_id='A';label='Goal A';description=$null},[ordered]@{option_id='B';label='Goal B';description=$null});authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason='Material product choice.';binding=[ordered]@{baseline_version=$null;definition_id='DEF-HUMAN';definition_version=1;execution_id=$null;revision=$null;review_id=$null};requested_by=[ordered]@{actor='DEFINITION_AGENT';model=$null;session_id=$null};resume_actor_role='THINKER';response=$null;evidence_refs=@();source_refs=@();created_at=$now;updated_at=$now}
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/human-input') -Force|Out-Null
    $request|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot ".aidos/human-input/$requestId.json") -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';request_id=$requestId;project_id='RUNTIME-HUMAN';phase='DEFINITION';processor='DEFINITION_SURFACE_HUMAN_ACCEPTED';target=[ordered]@{surface_id='goal_scope';completion_status='COMPLETE'};option_values=[ordered]@{A=[ordered]@{label='Goal A';description=$null};B=[ordered]@{label='Goal B';description=$null}};allow_text=$true;created_at=$now}|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot ".aidos/human-input-bindings/$requestId.json") -Encoding utf8NoBOM
    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init

    $response=Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId $requestId -RespondedBy TEST -SelectedOptionId A
    Assert-Resume ($response.status -eq 'RESOLVED') 'human response creates resolved request'
    $resumePath=Join-Path $projectRoot ".aidos/runtime/resume/$requestId.json"
    Assert-Resume ((Get-Content -LiteralPath $resumePath -Raw|ConvertFrom-Json).status -eq 'PENDING') 'human response creates pending runtime resume'

    $project=[pscustomobject][ordered]@{schema_version='0.2';project_id='RUNTIME-HUMAN';repository='https://example.invalid/runtime-human-resume.git';local_root=$projectRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at=$now;updated_at=$now;promoted_at=$now}
    $outcome=Invoke-AidosDefinitionHumanInputResume -Project $project -RequestId $requestId -AidosRoot $root
    Assert-Resume ($outcome.status -eq 'APPLIED') 'Definition Human Input resume applies deterministically'
    $progress=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/definitions/DEF-HUMAN/v1/PROGRESS.json') -Raw|ConvertFrom-Json -Depth 100
    $surface=@($progress.surfaces|Where-Object {$_.surface_id -eq 'goal_scope'})[0]
    Assert-Resume ($surface.status -eq 'COMPLETE' -and @($surface.decision_refs) -contains ".aidos/human-input/$requestId.json") 'resolved request closes exact target surface and is referenced'
    Assert-Resume ([string]$progress.last_human_decision_id -eq $requestId) 'Definition progress records the human decision lineage'
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 50
    Assert-Resume ($state.state -eq 'WAITING_DEFINITION') 'resume returns project to WAITING_DEFINITION'
    Assert-Resume ((Get-Content -LiteralPath $resumePath -Raw|ConvertFrom-Json).status -eq 'APPLIED') 'resume record becomes APPLIED'
    $next=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    Assert-Resume ($next.action -eq 'RESUME_DEFINITION' -and $next.activatable) 'Auto Define resumes after human choice'
    $replay=Invoke-AidosDefinitionHumanInputResume -Project $project -RequestId $requestId -AidosRoot $root
    Assert-Resume ($replay.status -eq 'ALREADY_APPLIED') 'runtime Human Input resume is idempotent'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed runtime Human Input resume assertions"
