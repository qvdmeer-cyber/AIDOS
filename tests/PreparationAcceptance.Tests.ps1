[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosPreparationRuntime.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Accept([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-accept-'+[guid]::NewGuid().ToString('N'))
$work=Join-Path $temp 'project';$bare=Join-Path $temp 'origin.git';$registry=Join-Path $temp 'registry';$builder=Join-Path $temp 'builder';$contracts=Join-Path $temp 'contracts'
try{
    foreach($d in @($work,$builder,$contracts)){New-Item -ItemType Directory -Path $d -Force|Out-Null}
    New-Item -ItemType Directory -Path (Join-Path $builder 'tools') -Force|Out-Null
    & git init --bare $bare|Out-Null;& git -C $work init|Out-Null;& git -C $work config user.email 'aidos@test.invalid';& git -C $work config user.name 'AIDOS Test';& git -C $work remote add origin $bare
    foreach($d in @('.aidos/documentation','.aidos/human-input','.aidos/human-input-bindings','.aidos/runtime/resume')){New-Item -ItemType Directory -Path (Join-Path $work $d) -Force|Out-Null}
    [ordered]@{project_id='ACCEPT-SMOKE';baseline_version=1;accepted_at=$null;accepted_by=$null;accepted_commit=$null}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $work '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    & git -C $work add .;& git -C $work commit -m seed|Out-Null;& git -C $work branch -M main;& git -C $work push -u origin main|Out-Null
    $sourceHead=(& git -C $work rev-parse HEAD).Trim()

    @'
param([string]$ProjectRoot,[string]$ContractsRoot,[string]$AcceptedBy,[string]$AcceptedCommit)
$p=Join-Path $ProjectRoot '.aidos/documentation/PROJECT_BASELINE.json'
$b=Get-Content $p -Raw|ConvertFrom-Json
$b.accepted_at=[DateTimeOffset]::UtcNow.ToString('o');$b.accepted_by=$AcceptedBy;$b.accepted_commit=$AcceptedCommit
$b|ConvertTo-Json -Depth 20|Set-Content $p -Encoding utf8NoBOM
'@|Set-Content -LiteralPath (Join-Path $builder 'tools/Accept-AidosProjectBaseline.ps1') -Encoding utf8NoBOM
    @'
param([string]$ProjectRoot,[string]$ContractsRoot,[switch]$RequireAcceptance,[switch]$NoExit)
$b=Get-Content (Join-Path $ProjectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Raw|ConvertFrom-Json
$ok=(-not$RequireAcceptance)-or(-not[string]::IsNullOrWhiteSpace([string]$b.accepted_commit))
[pscustomobject]@{pass=$ok;next_item=$null;complete=1;incomplete=0}
'@|Set-Content -LiteralPath (Join-Path $builder 'tools/Test-AidosProjectBaseline.ps1') -Encoding utf8NoBOM

    $project=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'ACCEPT-SMOKE' -Repository $bare -LocalRoot $work -AllowedPersistencePaths @('.aidos')
    Set-AidosPreparationProjectPhase -RegistryRoot $registry -ProjectId 'ACCEPT-SMOKE' -Phase 'BASELINE_ACCEPTANCE' -Status WAITING_HUMAN|Out-Null
    $id='accept-1';$now=[DateTimeOffset]::UtcNow.ToString('o')
    [ordered]@{contract_version='0.1.0';request_id=$id;project_id='ACCEPT-SMOKE';workstream_id=$null;phase='PROJECT_BASELINE';request_type='AUTHORITY';status='RESOLVED';context_summary='FORMAL_BASELINE_ACCEPTANCE: test';question='Accept?';options=@([ordered]@{option_id='ACCEPT';label='Accept';description=$null},[ordered]@{option_id='REOPEN';label='Reopen';description=$null});authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason=$null;binding=[ordered]@{baseline_version=1;definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;review_id=$null};requested_by=[ordered]@{actor='SYSTEM';model=$null;session_id=$null};resume_actor_role='BUILDER';response=[ordered]@{responded_by='human';responded_at=$now;selected_option_id='ACCEPT';text=$null};evidence_refs=@();source_refs=@();created_at=$now;updated_at=$now}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $work ".aidos/human-input/$id.json") -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';binding_type='HUMAN_INPUT_RESOLUTION';request_id=$id;project_id='ACCEPT-SMOKE';phase='PROJECT_BASELINE';processor='BASELINE_ACCEPTANCE';target=[ordered]@{baseline_version=1};option_values=[ordered]@{ACCEPT=$true;REOPEN=$false};rationale_prefix='Human baseline acceptance decision';created_at=$now}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $work ".aidos/human-input-bindings/$id.json") -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';resume_id='resume-a';request_id=$id;project_id='ACCEPT-SMOKE';workstream_id=$null;phase='PROJECT_BASELINE';resume_actor_role='BUILDER';binding=[ordered]@{baseline_version=1;definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;review_id=$null};response_ref=".aidos/human-input/$id.json";status='PENDING';created_at=$now;updated_at=$now;applied_at=$null;result=$null}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $work ".aidos/runtime/resume/$id.json") -Encoding utf8NoBOM

    $result=Invoke-AidosPreparationResume -RegistryRoot $registry -ProjectId 'ACCEPT-SMOKE' -RequestId $id -BuilderRoot $builder -ContractsRoot $contracts -Push
    Assert-Accept ($result.status -eq 'APPLIED' -and $result.validation.pass -and $result.git.pushed) 'acceptance is applied, validated and pushed'
    $baseline=Get-Content -LiteralPath (Join-Path $work '.aidos/documentation/PROJECT_BASELINE.json') -Raw|ConvertFrom-Json
    Assert-Accept ($baseline.accepted_by -eq 'human' -and $baseline.accepted_commit -eq $sourceHead) 'acceptance binds the exact pre-acceptance source commit'
    $state=Get-AidosRegisteredProject -RegistryRoot $registry -ProjectId 'ACCEPT-SMOKE'
    Assert-Accept ($state.status -eq 'READY_FOR_ONBOARDING' -and $state.preparation_phase -eq 'RUNTIME_ONBOARDING') 'accepted baseline advances to runtime onboarding gate'
    $resume=Get-Content -LiteralPath (Join-Path $work ".aidos/runtime/resume/$id.json") -Raw|ConvertFrom-Json -Depth 30
    Assert-Accept ($resume.status -eq 'APPLIED' -and $resume.result.apply.accepted) 'resume records durable accepted outcome'
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Output "PASS: $passed preparation acceptance assertions"
