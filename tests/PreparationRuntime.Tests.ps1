[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPreparationRuntime.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Prep([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-prep-'+[guid]::NewGuid().ToString('N'))
$work=Join-Path $temp 'project';$bare=Join-Path $temp 'origin.git';$registry=Join-Path $temp 'registry'
try{
    New-Item -ItemType Directory -Path $work -Force|Out-Null
    & git init --bare $bare | Out-Null
    & git -C $work init | Out-Null
    & git -C $work config user.email 'aidos@test.invalid'
    & git -C $work config user.name 'AIDOS Test'
    & git -C $work remote add origin $bare
    New-Item -ItemType Directory -Path (Join-Path $work '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $work '.aidos/human-input') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $work '.aidos/human-input-bindings') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $work '.aidos/runtime/resume') -Force|Out-Null
    [ordered]@{project_id='PREP-SMOKE';value='old'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $work '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    & git -C $work add .
    & git -C $work commit -m seed | Out-Null
    & git -C $work branch -M main
    & git -C $work push -u origin main | Out-Null

    $project=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'PREP-SMOKE' -Repository $bare -LocalRoot $work -AllowedPersistencePaths @('.aidos')
    $requestId='hir-prep-1';$now=[DateTimeOffset]::UtcNow.ToString('o')
    [ordered]@{contract_version='0.1.0';request_id=$requestId;project_id='PREP-SMOKE';workstream_id=$null;phase='PROJECT_BASELINE';request_type='PRODUCT_DECISION';status='RESOLVED';context_summary='x';question='x';options=@([ordered]@{option_id='A';label='A';description=$null});authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason=$null;binding=[ordered]@{baseline_version=1;definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;review_id=$null};requested_by=[ordered]@{actor='BUILDER';model=$null;session_id=$null};resume_actor_role='BUILDER';response=[ordered]@{responded_by='human';responded_at=$now;selected_option_id='A';text=$null};evidence_refs=@();source_refs=@();created_at=$now;updated_at=$now}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $work ".aidos/human-input/$requestId.json") -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';binding_type='HUMAN_INPUT_RESOLUTION';request_id=$requestId;project_id='PREP-SMOKE';phase='PROJECT_BASELINE';processor='BASELINE_ITEM_HUMAN_ACCEPTED';target=[ordered]@{item_key='example.item'};option_values=[ordered]@{A='new-value'};rationale_prefix='Human selected option';created_at=$now}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $work ".aidos/human-input-bindings/$requestId.json") -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';resume_id='resume-1';request_id=$requestId;project_id='PREP-SMOKE';workstream_id=$null;phase='PROJECT_BASELINE';resume_actor_role='BUILDER';binding=[ordered]@{baseline_version=1;definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;review_id=$null};response_ref=".aidos/human-input/$requestId.json";status='PENDING';created_at=$now;updated_at=$now;applied_at=$null;result=$null}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $work ".aidos/runtime/resume/$requestId.json") -Encoding utf8NoBOM

    $apply={param($project,$request,$binding,$value) [ordered]@{project_id='PREP-SMOKE';value=$value}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path ([string]$project.local_root) '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM;[pscustomobject]@{applied=$true;value=$value}}
    $validator={param($project,$request,$binding) [pscustomobject]@{pass=$true;next_item=$null;complete=1;incomplete=0}}
    $result=Invoke-AidosPreparationResume -RegistryRoot $registry -ProjectId 'PREP-SMOKE' -RequestId $requestId -ApplyProcessor $apply -Validator $validator -Push
    Assert-Prep ($result.status -eq 'APPLIED' -and $result.git.pushed) 'resolved Human Input applies, validates, commits and pushes without operator shell work'
    $resume=Get-Content -LiteralPath (Join-Path $work ".aidos/runtime/resume/$requestId.json") -Raw|ConvertFrom-Json -Depth 20
    Assert-Prep ($resume.status -eq 'APPLIED' -and -not[string]::IsNullOrWhiteSpace([string]$resume.result.git.commit)) 'resume intent closes durably with Git evidence'
    $registered=Get-AidosRegisteredProject -RegistryRoot $registry -ProjectId 'PREP-SMOKE'
    Assert-Prep ($registered.status -eq 'WAITING_HUMAN' -and $registered.preparation_phase -eq 'BASELINE_ACCEPTANCE') 'completed baseline moves preparation lifecycle to explicit acceptance gate'
    $again=Invoke-AidosPreparationResume -RegistryRoot $registry -ProjectId 'PREP-SMOKE' -RequestId $requestId -ApplyProcessor $apply -Validator $validator -Push
    Assert-Prep ($again.status -eq 'ALREADY_APPLIED') 'resume processing is idempotent after success'
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
Write-Output "PASS: $passed preparation runtime assertions"
