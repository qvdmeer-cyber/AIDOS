[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosAutonomousExecution.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Autonomous([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-autonomous-execution-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/profile') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/definitions/DEF-AUTO-001/v1') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'docs') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/autonomous-execution.git'

    [ordered]@{
        schema_version='0.1';project_id='AUTONOMOUS-EXECUTION';project_mode='NEW_PROJECT';repository='https://example.invalid/autonomous-execution.git';official_root=$projectRoot;default_branch='main';
        project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';runner_policy='UNATTENDED_ALLOWED';
        git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}
    }|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='AUTONOMOUS-EXECUTION';state='TASK_READY';definition_id='DEF-AUTO-001';definition_version=1;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='AUTONOMOUS-EXECUTION';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abcdef1';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='AUTONOMOUS-EXECUTION'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='AUTONOMOUS-EXECUTION'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    [ordered]@{
        schema_version='0.1';definition_id='DEF-AUTO-001';version=1;project_id='AUTONOMOUS-EXECUTION';status='ACCEPTED';goal='Build the accepted web application.';
        requirements=@([ordered]@{surface_id='functional_behavior';status='COMPLETE';summary='Accepted behavior';source_refs=@('docs/PRODUCT.md');decision_refs=@()});non_functional=@();
        acceptance=@([ordered]@{criterion='npm run validate passes';source_ref='docs/ENGINEERING.md'});out_of_scope=@('Unaccepted scope');open_questions=@();sources=@('docs/PRODUCT.md','docs/ENGINEERING.md');decision_refs=@();auto_decision_refs=@();human_input_request_refs=@();progress_ref=$null;applicability_ref=$null;project_applicability_ref='.aidos/profile/PROJECT_APPLICABILITY.json';profile_refs=@('.aidos/profile/PROJECT_APPLICABILITY.json');accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST'
    }|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/definitions/DEF-AUTO-001/v1/DEFINITION.json') -Encoding utf8NoBOM
    [ordered]@{
        schema_version='0.1';surface_catalog_version='0.1.0';preset_catalog_version='0.1.0';project_id='AUTONOMOUS-EXECUTION';
        selected_presets=@(
            [ordered]@{preset_id='WEB_APPLICATION';version=1;category='PRODUCT_ARCHETYPE';selection_source='BASELINE_DERIVED'},
            [ordered]@{preset_id='REACT';version=1;category='STACK';selection_source='BASELINE_DERIVED'}
        );overrides=@();resolved_surfaces=@();conflicts=@();updated_at='2026-08-18T00:00:00Z'
    }|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/profile/PROJECT_APPLICABILITY.json') -Encoding utf8NoBOM
    @'
# Engineering

- `npm ci` is the canonical reproducible restore path.
- Normal restore is online from the configured npm registry.
- The repository exposes `npm run validate` as the deterministic aggregate validation command.
'@|Set-Content -LiteralPath (Join-Path $projectRoot 'docs/ENGINEERING.md') -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $projectRoot 'docs/PRODUCT.md') -Value '# Product' -Encoding utf8NoBOM
    '{"scripts":{"validate":"echo pass"}}'|Set-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Encoding utf8NoBOM

    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init

    $network=Get-AidosDependencyNetworkAuthority -ProjectRoot $projectRoot
    Assert-Autonomous ($network.allowed -and $network.source_ref -eq 'docs/ENGINEERING.md') 'network authority is granted only from canonical project evidence'
    $profile=Resolve-AidosAutonomousExecutionProfile -ProjectRoot $projectRoot
    Assert-Autonomous ($profile.profile_id -eq 'WEB_APPLICATION_REACT') 'verified web+React applicability selects bounded Worker profile'
    Assert-Autonomous ($profile.network) 'bounded profile carries evidence-backed dependency network authority'
    Assert-Autonomous ($profile.evidence_requirements.Count -eq 1 -and $profile.evidence_requirements[0].path -eq 'package.json') 'Core does not impose Interface-specific source folders'

    $project=[pscustomobject][ordered]@{schema_version='0.2';project_id='AUTONOMOUS-EXECUTION';repository='https://example.invalid/autonomous-execution.git';local_root=$projectRoot;stage='RUNTIME';preparation_phase='RUNTIME';status='PROMOTED';project_mode='NEW_PROJECT';default_branch='main';runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'};allowed_persistence_paths=@('.aidos');registered_at='2026-08-18T00:00:00Z';updated_at='2026-08-18T00:00:00Z';promoted_at='2026-08-18T00:00:00Z'}
    $plan=New-AidosExecutionFromAcceptedDefinition -Project $project
    Assert-Autonomous ($plan.status -eq 'PLANNED') 'accepted Definition produces durable Execution without human relay'
    Assert-Autonomous ([string]$plan.execution.definition.id -eq 'DEF-AUTO-001' -and [int]$plan.execution.definition.version -eq 1) 'Execution binds exact accepted Definition lineage'
    Assert-Autonomous (-not$plan.execution.authority.git_commit -and -not$plan.execution.authority.git_push) 'Worker never receives integration/push authority'
    Assert-Autonomous ([bool]$plan.execution.authority.network) 'Execution records project-evidenced network authority explicitly'
    Assert-Autonomous (@($plan.execution.scope.authority_source_refs) -contains 'docs/ENGINEERING.md') 'network authority provenance is durable in Execution scope'

    $runtime=[pscustomobject]@{kind='WINDOWS_WSL';distribution='Ubuntu';project_root='/home/aidos/repos/test';codex_path='codex'}
    $args=@(Get-AidosAutonomousCodexArguments -Runtime $runtime -Execution $plan.execution -PromptText 'test')
    Assert-Autonomous ($args -contains 'workspace-write') 'Codex Worker uses workspace-write sandbox'
    Assert-Autonomous ($args -contains 'sandbox_workspace_write.network_access=true') 'evidence-backed network authority maps explicitly into workspace-write sandbox'
    Assert-Autonomous (-not($args -contains 'danger-full-access')) 'Worker adapter never uses danger-full-access'

    # Removing the canonical network grant must fail closed while preserving the
    # same product/stack profile.
    @'
# Engineering

- `npm ci` is the canonical reproducible restore path.
- The repository exposes `npm run validate`.
'@|Set-Content -LiteralPath (Join-Path $projectRoot 'docs/ENGINEERING.md') -Encoding utf8NoBOM
    $networkClosed=Get-AidosDependencyNetworkAuthority -ProjectRoot $projectRoot
    Assert-Autonomous (-not$networkClosed.allowed) 'missing explicit online-registry evidence removes network authority'
    $closedProfile=Resolve-AidosAutonomousExecutionProfile -ProjectRoot $projectRoot
    Assert-Autonomous (-not$closedProfile.network) 'profile remains usable but network fails closed without evidence'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed autonomous execution assertions"
