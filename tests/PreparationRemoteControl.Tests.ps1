[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Remote([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-remote-input-'+[guid]::NewGuid().ToString('N'))
$work=Join-Path $temp 'project';$publisher=Join-Path $temp 'publisher';$bare=Join-Path $temp 'origin.git';$registry=Join-Path $temp 'registry'
try{
    & git init --bare $bare|Out-Null;New-Item -ItemType Directory -Path $work -Force|Out-Null;& git -C $work init|Out-Null;& git -C $work config user.email 'aidos@test.invalid';& git -C $work config user.name 'AIDOS Test';& git -C $work remote add origin $bare
    foreach($d in @('.aidos/documentation','.aidos/human-input','.aidos/control/intents')){New-Item -ItemType Directory -Path (Join-Path $work $d) -Force|Out-Null}
    [ordered]@{project_id='REMOTE-SMOKE';baseline_version=1}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $work '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    $now=[DateTimeOffset]::UtcNow.ToString('o');$requestId='remote-hir-1'
    [ordered]@{contract_version='0.1.0';request_id=$requestId;project_id='REMOTE-SMOKE';workstream_id=$null;phase='PROJECT_BASELINE';request_type='PRODUCT_DECISION';status='WAITING';context_summary='test';question='Choose';options=@([ordered]@{option_id='A';label='A';description=$null});authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason=$null;binding=[ordered]@{baseline_version=1;definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;review_id=$null};requested_by=[ordered]@{actor='BUILDER';model=$null;session_id=$null};resume_actor_role='BUILDER';response=$null;evidence_refs=@();source_refs=@();created_at=$now;updated_at=$now}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $work ".aidos/human-input/$requestId.json") -Encoding utf8NoBOM
    & git -C $work add .;& git -C $work commit -m seed|Out-Null;& git -C $work branch -M main;& git -C $work push -u origin main|Out-Null
    $project=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'REMOTE-SMOKE' -Repository $bare -LocalRoot $work -AllowedPersistencePaths @('.aidos')

    & git clone -b main $bare $publisher|Out-Null;& git -C $publisher config user.email 'transport@test.invalid';& git -C $publisher config user.name 'Transport Test'
    $intentId='intent-1';$intentPath=Join-Path $publisher ".aidos/control/intents/$intentId.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $intentPath) -Force|Out-Null
    [ordered]@{schema_version='0.1';control_id=$intentId;command='SUBMIT_HUMAN_INPUT';project_id='REMOTE-SMOKE';workstream_id=$null;requested_by='human';status='RECEIVED';payload=[ordered]@{request_id=$requestId;selected_option_id='A';text=$null};submitted_at=$now;applied_at=$null;result=$null}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $intentPath -Encoding utf8NoBOM
    & git -C $publisher add .;& git -C $publisher commit -m 'Submit Human Input A'|Out-Null;& git -C $publisher push|Out-Null

    $resumeProcessor={param($project,$requestId)[pscustomobject]@{status='ACTOR_RESUME_REQUIRED';request_id=$requestId;resume_actor_role='BUILDER'}}
    $tick=Invoke-AidosPreparationDispatcherTick -RegistryRoot $registry -MaxItems 1 -Push -ResumeProcessor $resumeProcessor
    Assert-Remote ($tick.status -eq 'PROCESSED' -and $tick.processed -eq 1) 'dispatcher synchronizes and processes remote Human Input intent'
    $request=Get-Content -LiteralPath (Join-Path $work ".aidos/human-input/$requestId.json") -Raw|ConvertFrom-Json -Depth 30
    Assert-Remote ($request.status -eq 'RESOLVED' -and $request.response.selected_option_id -eq 'A' -and $request.response.responded_by -eq 'human') 'Core resolves canonical Human Input request from remote control intent'
    $intent=Get-Content -LiteralPath (Join-Path $work ".aidos/control/intents/$intentId.json") -Raw|ConvertFrom-Json -Depth 30
    Assert-Remote ($intent.status -eq 'APPLIED') 'remote transport intent records APPLIED lifecycle'
    $resume=Get-Content -LiteralPath (Join-Path $work ".aidos/runtime/resume/$requestId.json") -Raw|ConvertFrom-Json -Depth 30
    Assert-Remote ($resume.status -eq 'PENDING' -and $resume.request_id -eq $requestId) 'Human Input consumption creates durable resume intent'
    $status=& git -C $work status --porcelain
    Assert-Remote ([string]::IsNullOrWhiteSpace(($status -join ''))) 'dispatcher persists transport outcome and leaves preparation worktree clean'
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Output "PASS: $passed remote preparation control assertions"
