[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDefinitionResultConsumer.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Gate([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-project-applicability-gate-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path (Join-Path $temp '.aidos/profile') -Force|Out-Null
    Assert-Gate (-not(Test-AidosProjectApplicabilityResolvedForDefinition -ProjectRoot $temp)) 'missing profile is not Definition-ready'

    $profile=[ordered]@{project_id='P1';resolved_surfaces=@([ordered]@{surface_id='content_information_architecture';state='UNRESOLVED'})}
    $profile|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $temp '.aidos/profile/PROJECT_APPLICABILITY.json') -Encoding utf8NoBOM
    Assert-Gate (-not(Test-AidosProjectApplicabilityResolvedForDefinition -ProjectRoot $temp)) 'UNRESOLVED surface blocks Definition'

    $profile.resolved_surfaces[0].state='CONDITIONAL'
    $profile|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $temp '.aidos/profile/PROJECT_APPLICABILITY.json') -Encoding utf8NoBOM
    Assert-Gate (Test-AidosProjectApplicabilityResolvedForDefinition -ProjectRoot $temp) 'CONDITIONAL is a resolved project applicability state'

    $manager=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Raw -Encoding UTF8
    Assert-Gate ($manager.Contains("if(-not(Test-AidosProjectApplicabilityResolvedForDefinition -ProjectRoot `$root))")) 'runtime manager routes unresolved project applicability before START_DEFINITION'
    $assignments=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Raw -Encoding UTF8
    Assert-Gate ($assignments.Contains('START_DEFINITION requires fully resolved Project Applicability with no UNRESOLVED surfaces.')) 'assignment boundary independently guards START_DEFINITION'
    Assert-Gate ($assignments.Contains('Project Applicability is already fully resolved.')) 'RESOLVE_PROJECT_APPLICABILITY permits refinement only while unresolved'

    $consumer=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRuntimeActorResultConsumer.psm1') -Raw -Encoding UTF8
    Assert-Gate ($consumer.Contains('Existing fully resolved Project Applicability does not match completed actor result; refusing replacement.')) 'fully resolved applicability cannot be silently replaced'
    Assert-Gate ($consumer.Contains("Where-Object {[string]`$_.state-eq'UNRESOLVED'}")) 'existing unresolved applicability may be refined by a new applicability result'

    $existing=[pscustomobject]@{project_mode='EXISTING_PROJECT';local_root=$temp;project_id='P1'}
    $assignment=[pscustomobject]@{action='START_DEFINITION'}
    $recovery=Invoke-AidosLegacyNewProjectApplicabilityRecovery -Project $existing -Assignment $assignment -Output ([pscustomobject]@{}) -AidosRoot $root
    Assert-Gate ([string]$recovery.status-eq'NOT_APPLICABLE') 'legacy recovery is never applied to EXISTING_PROJECT'

    $definitionConsumer=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosDefinitionResultConsumer.psm1') -Raw -Encoding UTF8
    Assert-Gate ($definitionConsumer.Contains("`$Project.project_mode-ne'NEW_PROJECT' -or [string]`$Assignment.action-ne'START_DEFINITION'")) 'legacy recovery is bounded to NEW_PROJECT START_DEFINITION'
    Assert-Gate ($definitionConsumer.Contains("`$projectState=if(`$definitionState-eq'AFFECTED'){'APPLICABLE'}else{'NOT_APPLICABLE'}")) 'legacy recovery maps whole-product Definition applicability to project applicability deterministically'
    Assert-Gate ($definitionConsumer.Contains('PROJECT_APPLICABILITY_RECOVERED_FROM_LEGACY_DEFINITION')) 'legacy recovery is evented durably'
    Assert-Gate ($definitionConsumer.Contains("'tools/New-AidosDefinitionApplicability.ps1'")) 'legacy recovery rebuilds Definition applicability after project-scope repair'

    $setter=Get-Content -LiteralPath (Join-Path $root 'tools/Set-AidosDefinitionApplicabilitySurface.ps1') -Raw -Encoding UTF8
    Assert-Gate ($setter.Contains("if(`$DefinitionState -eq 'AFFECTED'){throw")) 'project NOT_APPLICABLE keeps a hard conflict branch for AFFECTED Definition results'
    Assert-Gate ($setter.Contains('cannot be affected by Definition.')) 'AFFECTED conflict branch is explicit'
    Assert-Gate ($setter.Contains("status='ALREADY_NOT_APPLICABLE'")) 'project NOT_APPLICABLE plus NOT_AFFECTED is consumed idempotently'
    Assert-Gate ($setter.Contains("definition_state='NOT_APPLICABLE'")) 'idempotent result preserves canonical Definition NOT_APPLICABLE state'

    Write-Output "PASS: $passed project applicability / Definition gate assertions"
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
