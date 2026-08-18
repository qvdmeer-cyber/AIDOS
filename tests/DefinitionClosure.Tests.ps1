[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDefinitionRuntime.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDefinitionClosure.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosHumanInput.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Closure([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-definition-closure-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$registry=Join-Path $base 'registry'
$contractsRoot=Join-Path $base 'contracts'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'docs') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $contractsRoot 'schemas') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $contractsRoot 'tools') -Force|Out-Null

    # Reuse the repository's contract validator implementation while keeping the
    # test fixture isolated from any external checkout.
    Copy-Item -LiteralPath (Join-Path (Split-Path $root -Parent) 'AIDOS-Contracts/schemas/auto-decision.schema.json') -Destination (Join-Path $contractsRoot 'schemas/auto-decision.schema.json') -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path (Split-Path $root -Parent) 'AIDOS-Contracts/tools/Test-AidosDecisionAssessment.ps1') -Destination (Join-Path $contractsRoot 'tools/Test-AidosDecisionAssessment.ps1') -ErrorAction SilentlyContinue
    if(-not(Test-Path -LiteralPath (Join-Path $contractsRoot 'schemas/auto-decision.schema.json'))){
        # Definition without Auto Decisions only needs a contracts root that the
        # decision validator can traverse; copy the current shared contract repo
        # when tests run in the standard sibling-checkout layout, otherwise use
        # the repository fixture path supplied by CI.
        $contractsCandidate=Join-Path $root '../AIDOS-Contracts'
        if(Test-Path -LiteralPath $contractsCandidate -PathType Container){$contractsRoot=[IO.Path]::GetFullPath($contractsCandidate)}
    }

    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/definition-closure.git'

    $definitionId='DEF-CLOSURE-001'
    [ordered]@{
        schema_version='0.1';project_id='DEFINITION-CLOSURE';project_mode='NEW_PROJECT';repository='https://example.invalid/definition-closure.git';official_root=$projectRoot;default_branch='main';
        canonical_sources=@('docs/','.aidos/documentation/PROJECT_BASELINE.json');project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';runner_policy='UNATTENDED_ALLOWED';
        git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}
    }|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='DEFINITION-CLOSURE';state='WAITING_DEFINITION';definition_id=$definitionId;definition_version=1;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{
        contract_version='0.3.0';catalog_version='0.2.0';project_id='DEFINITION-CLOSURE';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abcdef1';
        items=[ordered]@{
            'purpose.desired_outcomes'=[ordered]@{status='HUMAN_ACCEPTED';value='Deliver the accepted product autonomously.'}
            'purpose.success_boundary'=[ordered]@{status='HUMAN_ACCEPTED';value='The accepted operator flow works and deterministic validation passes.'}
            'scope.out_of_scope'=[ordered]@{status='HUMAN_ACCEPTED';value=@('Unaccepted scope expansion')}
        }
    }|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='DEFINITION-CLOSURE'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='DEFINITION-CLOSURE'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $projectRoot 'docs/PRODUCT.md') -Value '# Product' -Encoding utf8NoBOM

    & (Join-Path $root 'tools/Resolve-AidosProjectApplicability.ps1') -ProjectRoot $projectRoot -ProjectId 'DEFINITION-CLOSURE' -PresetIds @('WEB_APPLICATION') -SelectionSource BASELINE_DERIVED -AidosRoot $root|Out-Null
    Ensure-AidosDefinitionWorkspace -ProjectRoot $projectRoot -AidosRoot $root|Out-Null

    $appPath=Join-Path $projectRoot ('.aidos/definitions/{0}/v1/APPLICABILITY.json' -f $definitionId)
    $app=Get-Content -LiteralPath $appPath -Raw|ConvertFrom-Json -Depth 100
    foreach($surface in @($app.surfaces|Where-Object {[string]$_.definition_state-eq'DECISION_REQUIRED'})){
        & (Join-Path $root 'tools/Set-AidosDefinitionApplicabilitySurface.ps1') -ProjectRoot $projectRoot -DefinitionId $definitionId -DefinitionVersion 1 -SurfaceId ([string]$surface.surface_id) -DefinitionState AFFECTED -Reason 'Test Definition affects the project surface.' -SourceRefs @('.aidos/documentation/PROJECT_BASELINE.json')|Out-Null
    }
    $catalog=Get-Content -LiteralPath (Join-Path $root 'catalog/definition-surfaces.catalog.json') -Raw|ConvertFrom-Json -Depth 50
    foreach($surface in @($catalog.surfaces)){
        & (Join-Path $root 'tools/Set-AidosDefinitionSurface.ps1') -ProjectRoot $projectRoot -DefinitionId $definitionId -DefinitionVersion 1 -SurfaceId ([string]$surface.id) -Status COMPLETE -Summary ("Resolved $($surface.id) for closure test.") -SourceRef '.aidos/documentation/PROJECT_BASELINE.json' -OpenQuestionCount 0|Out-Null
    }

    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m 'ready definition'
    [ordered]@{schema_version='0.2';project_id='DEFINITION-CLOSURE';repository='https://example.invalid/definition-closure.git';local_root=$projectRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-18T00:00:00Z';updated_at='2026-08-18T00:00:00Z';promoted_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $registry 'projects/DEFINITION-CLOSURE.json') -Encoding utf8NoBOM
    $project=Get-Content -LiteralPath (Join-Path $registry 'projects/DEFINITION-CLOSURE.json') -Raw|ConvertFrom-Json -Depth 30

    # Use the real readiness validator when the sibling Contracts repository is
    # present. In isolated CI the Core repository still exercises closure state
    # through a minimal no-auto-decision contracts fixture supplied below.
    if(-not(Test-Path -LiteralPath (Join-Path $contractsRoot 'schemas/auto-decision.schema.json'))){
        New-Item -ItemType Directory -Path (Join-Path $contractsRoot 'schemas') -Force|Out-Null
        '{"type":"object"}'|Set-Content -LiteralPath (Join-Path $contractsRoot 'schemas/auto-decision.schema.json') -Encoding utf8NoBOM
    }

    $published=Publish-AidosDefinitionFinalAcceptance -Project $project -AidosRoot $root -ContractsRoot $contractsRoot
    Assert-Closure ($published.status -eq 'WAITING_HUMAN') 'converged Definition publishes exactly one final acceptance gate'
    $definition=Get-Content -LiteralPath (Join-Path $projectRoot $published.definition_ref) -Raw|ConvertFrom-Json -Depth 100
    Assert-Closure ([string]$definition.status -eq 'USER_REVIEW') 'canonical Definition enters USER_REVIEW before execution'
    Assert-Closure ([string]$definition.goal -eq 'Deliver the accepted product autonomously.') 'canonical Definition carries accepted project goal'
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20
    Assert-Closure ([string]$state.state -eq 'WAITING_USER') 'final Definition gate is durable WAITING_USER state'

    Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId ([string]$published.request_id) -RespondedBy TEST -SelectedOptionId ACCEPT|Out-Null
    $resumed=Invoke-AidosDefinitionFinalAcceptanceResume -Project $project -RequestId ([string]$published.request_id) -AidosRoot $root
    Assert-Closure ($resumed.outcome -eq 'ACCEPTED') 'final acceptance processor accepts converged Definition'
    $accepted=Get-Content -LiteralPath (Join-Path $projectRoot $published.definition_ref) -Raw|ConvertFrom-Json -Depth 100
    Assert-Closure ([string]$accepted.status -eq 'ACCEPTED' -and [string]$accepted.accepted_by -eq 'TEST') 'canonical Definition records explicit human acceptance'
    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20
    Assert-Closure ([string]$state.state -eq 'TASK_READY') 'accepted Definition unlocks TASK_READY and nothing further'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed Definition closure assertions"
