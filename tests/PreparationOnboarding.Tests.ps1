[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosPreparationOnboarding.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Onboard([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-onboard-'+[guid]::NewGuid().ToString('N'))
$work=Join-Path $temp 'project';$bare=Join-Path $temp 'origin.git';$registry=Join-Path $temp 'registry'
try{
    New-Item -ItemType Directory -Path $work -Force|Out-Null
    & git init --bare $bare|Out-Null;& git -C $work init|Out-Null;& git -C $work config user.email 'aidos@test.invalid';& git -C $work config user.name 'AIDOS Test';& git -C $work remote add origin $bare
    foreach($d in @('.aidos/documentation','.aidos/evidence')){New-Item -ItemType Directory -Path (Join-Path $work $d) -Force|Out-Null}
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='ONBOARD-SMOKE';baseline_version=1;updated_at=$now;accepted_at=$now;accepted_by='human';accepted_commit='1234567';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $work '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='ONBOARD-SMOKE'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $work '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='ONBOARD-SMOKE'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $work '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    & git -C $work add .;& git -C $work commit -m seed|Out-Null;& git -C $work branch -M main;& git -C $work push -u origin main|Out-Null
    $record=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'ONBOARD-SMOKE' -Repository $bare -LocalRoot $work -ProjectMode NEW_PROJECT -RunnerPolicy UNATTENDED_ALLOWED -AllowedPersistencePaths @('.aidos')
    Set-AidosPreparationProjectPhase -RegistryRoot $registry -ProjectId 'ONBOARD-SMOKE' -Phase 'RUNTIME_ONBOARDING' -Status READY_FOR_ONBOARDING|Out-Null

    $result=Invoke-AidosPreparationRuntimeOnboarding -RegistryRoot $registry -ProjectId 'ONBOARD-SMOKE' -Push
    Assert-Onboard ($result.status -eq 'PROMOTED' -and $result.git.pushed) 'ready preparation project initializes and persists runtime state'
    $profile=Get-Content -LiteralPath (Join-Path $work '.aidos/PROJECT.json') -Raw|ConvertFrom-Json -Depth 30
    Assert-Onboard ($profile.project_id -eq 'ONBOARD-SMOKE' -and $profile.project_mode -eq 'NEW_PROJECT' -and $profile.runner_policy -eq 'UNATTENDED_ALLOWED') 'runtime profile preserves registry onboarding policy'
    Assert-Onboard ((Test-Path -LiteralPath (Join-Path $work '.aidos/AGENT_PROFILE.json')) -and (Test-Path -LiteralPath (Join-Path $work '.aidos/STATE.json'))) 'runtime projections are initialized'
    $registered=Get-AidosRegisteredProject -RegistryRoot $registry -ProjectId 'ONBOARD-SMOKE'
    Assert-Onboard ($registered.stage -eq 'RUNTIME' -and $registered.status -eq 'PROMOTED') 'registry transitions to runtime stage after binding and persistence'
    $again=Invoke-AidosPreparationRuntimeOnboarding -RegistryRoot $registry -ProjectId 'ONBOARD-SMOKE' -Push
    Assert-Onboard ($again.status -eq 'ALREADY_PROMOTED') 'runtime promotion is idempotent'
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
Write-Output "PASS: $passed preparation onboarding assertions"
