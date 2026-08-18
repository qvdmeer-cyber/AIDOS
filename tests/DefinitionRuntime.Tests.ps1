[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDefinitionRuntime.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-DefinitionRuntime([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-definition-runtime-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos') -Force|Out-Null
    [ordered]@{schema_version='0.1';project_id='DEF-RUNTIME';project_mode='NEW_PROJECT';repository='https://example.invalid/def-runtime.git';official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='DEF-RUNTIME';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM

    $resolve=Join-Path $root 'tools/Resolve-AidosProjectApplicability.ps1'
    & $resolve -ProjectRoot $projectRoot -ProjectId 'DEF-RUNTIME' -PresetIds @('WEB_APPLICATION') -SelectionSource 'BASELINE_DERIVED' -OverridesJson '[]' -AidosRoot $root|Out-Null
    Assert-DefinitionRuntime (Test-Path -LiteralPath (Join-Path $projectRoot '.aidos/profile/PROJECT_APPLICABILITY.json')) 'Project Applicability precondition exists'

    Set-AidosState -ProjectRoot $projectRoot -NewState WAITING_DEFINITION -Actor SYSTEM -Patch @{definition_id='DEF-RUNTIME-001';definition_version=1}|Out-Null
    $first=Ensure-AidosDefinitionWorkspace -ProjectRoot $projectRoot -AidosRoot $root
    Assert-DefinitionRuntime ($first.status -eq 'INITIALIZED') 'first ensure initializes Definition workspace'
    Assert-DefinitionRuntime (@($first.created).Count -eq 2) 'first ensure creates applicability and progress artifacts'
    Assert-DefinitionRuntime ($first.applicability.pass -and $first.progress.pass) 'official Definition validators pass after initialization'
    Assert-DefinitionRuntime (Test-Path -LiteralPath (Join-Path $projectRoot '.aidos/definitions/DEF-RUNTIME-001/v1/APPLICABILITY.json')) 'Definition Applicability is durable'
    Assert-DefinitionRuntime (Test-Path -LiteralPath (Join-Path $projectRoot '.aidos/definitions/DEF-RUNTIME-001/v1/PROGRESS.json')) 'Definition Progress is durable'

    $second=Ensure-AidosDefinitionWorkspace -ProjectRoot $projectRoot -AidosRoot $root
    Assert-DefinitionRuntime ($second.status -eq 'READY' -and @($second.created).Count -eq 0) 'workspace ensure is idempotent on replay'

    $progressPath=Join-Path $projectRoot '.aidos/definitions/DEF-RUNTIME-001/v1/PROGRESS.json'
    $progress=Get-Content -LiteralPath $progressPath -Raw|ConvertFrom-Json -Depth 100
    $progress.definition_id='DEF-TAMPERED'
    $progress|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $progressPath -Encoding utf8NoBOM
    $blocked=$false
    try{Ensure-AidosDefinitionWorkspace -ProjectRoot $projectRoot -AidosRoot $root|Out-Null}catch{$blocked=$_.Exception.Message -match 'Definition Progress binding mismatch'}
    Assert-DefinitionRuntime $blocked 'tampered existing Definition workspace fails closed'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed Definition runtime assertions"
