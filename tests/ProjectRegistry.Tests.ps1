[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Registry([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-registry-'+[guid]::NewGuid().ToString('N'))
$work=Join-Path $temp 'project';$bare=Join-Path $temp 'origin.git';$registry=Join-Path $temp 'registry'
try{
    New-Item -ItemType Directory -Path $work -Force|Out-Null
    & git init --bare $bare | Out-Null
    & git -C $work init | Out-Null
    & git -C $work config user.email 'aidos@test.invalid'
    & git -C $work config user.name 'AIDOS Test'
    & git -C $work remote add origin $bare
    New-Item -ItemType Directory -Path (Join-Path $work '.aidos') -Force|Out-Null
    '{}'|Set-Content -LiteralPath (Join-Path $work '.aidos/seed.json') -Encoding utf8NoBOM
    'seed'|Set-Content -LiteralPath (Join-Path $work 'README.md') -Encoding utf8NoBOM
    & git -C $work add .
    & git -C $work commit -m seed | Out-Null
    & git -C $work branch -M main
    & git -C $work push -u origin main | Out-Null

    $record=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'REGISTRY-SMOKE' -Repository $bare -LocalRoot $work -AllowedPersistencePaths @('.aidos')
    Assert-Registry ($record.stage -eq 'PREPARATION' -and $record.status -eq 'ACTIVE') 'registers project before runtime onboarding'
    Assert-Registry ((Test-AidosRegistryProjectBinding $record).valid) 'validates repository binding without PROJECT.json'

    '{"changed":true}'|Set-Content -LiteralPath (Join-Path $work '.aidos/seed.json') -Encoding utf8NoBOM
    $persist=Invoke-AidosPreparationGitPersistence -Project $record -CommitMessage 'Persist preparation state' -Push
    Assert-Registry ($persist.status -eq 'PERSISTED' -and $persist.pushed) 'persists and pushes authorized preparation changes'
    Assert-Registry (@($persist.paths) -contains '.aidos/seed.json') 'records bounded changed path'

    'unauthorized'|Set-Content -LiteralPath (Join-Path $work 'README.md') -Encoding utf8NoBOM
    $blocked=$false
    try{Invoke-AidosPreparationGitPersistence -Project $record -CommitMessage 'must fail'|Out-Null}catch{$blocked=$_.Exception.Message -match 'Unauthorized changed path'}
    Assert-Registry $blocked 'fails closed when unauthorized worktree changes are present'
    & git -C $work restore README.md

    $phase=Set-AidosPreparationProjectPhase -RegistryRoot $registry -ProjectId 'REGISTRY-SMOKE' -Phase 'BASELINE_ACCEPTANCE' -Status READY_FOR_ONBOARDING
    Assert-Registry ($phase.preparation_phase -eq 'BASELINE_ACCEPTANCE' -and $phase.status -eq 'READY_FOR_ONBOARDING') 'tracks preparation lifecycle independently from project runtime'

    $duplicate=$false
    try{Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'REGISTRY-SMOKE' -Repository $bare -LocalRoot $work|Out-Null}catch{$duplicate=$_.Exception.Message -match 'already registered'}
    Assert-Registry $duplicate 'registration is fail-closed on duplicate project identity'
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
Write-Output "PASS: $passed project registry assertions"
