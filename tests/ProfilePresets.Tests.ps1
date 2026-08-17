Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogValidator = Join-Path $repoRoot 'tools\Test-AidosProfileCatalog.ps1'
$resolver = Join-Path $repoRoot 'tools\Resolve-AidosProjectApplicability.ps1'
$definitionApplicability = Join-Path $repoRoot 'tools\New-AidosDefinitionApplicability.ps1'

function Assert-ProfileTest([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "PROFILE TEST FAILED: $Message" }
}

& $catalogValidator -AidosRoot $repoRoot

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('aidos-profile-test-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $api = & $resolver -ProjectRoot $temp -ProjectId 'TEST-API' -PresetIds @('API_SERVICE','OPENAI_API','AUTHENTICATED_USER_DATA') -SelectionSource HUMAN_ACCEPTED
    $ui = @($api.resolved_surfaces | Where-Object { $_.surface_id -eq 'ui_structure' } | Select-Object -First 1)
    $apiContract = @($api.resolved_surfaces | Where-Object { $_.surface_id -eq 'api_contracts' } | Select-Object -First 1)
    $security = @($api.resolved_surfaces | Where-Object { $_.surface_id -eq 'security_privacy' } | Select-Object -First 1)
    Assert-ProfileTest ($ui.Count -eq 1 -and $ui[0].state -eq 'NOT_APPLICABLE') 'API service does not inherit UI requirement.'
    Assert-ProfileTest ($apiContract.Count -eq 1 -and $apiContract[0].state -eq 'APPLICABLE') 'API service requires API contracts.'
    Assert-ProfileTest ($security.Count -eq 1 -and $security[0].state -eq 'APPLICABLE') 'Authenticated/OpenAI API profile requires security/privacy.'

    $web = & $resolver -ProjectRoot $temp -ProjectId 'TEST-WEB' -PresetIds @('CONTENT_WEBSITE','MULTILINGUAL','REACT') -SelectionSource HUMAN_ACCEPTED
    $localization = @($web.resolved_surfaces | Where-Object { $_.surface_id -eq 'localization' } | Select-Object -First 1)
    $visual = @($web.resolved_surfaces | Where-Object { $_.surface_id -eq 'visual_design' } | Select-Object -First 1)
    Assert-ProfileTest ($localization[0].state -eq 'APPLICABLE') 'Multilingual capability upgrades localization to applicable.'
    Assert-ProfileTest ($visual[0].state -eq 'APPLICABLE') 'Web/React profile requires visual design.'

    $chatgpt = & $resolver -ProjectRoot $temp -ProjectId 'TEST-CHATGPT' -PresetIds @('CHATGPT_APP') -SelectionSource HUMAN_ACCEPTED
    $tools = @($chatgpt.resolved_surfaces | Where-Object { $_.surface_id -eq 'tool_contracts' } | Select-Object -First 1)
    $conversation = @($chatgpt.resolved_surfaces | Where-Object { $_.surface_id -eq 'conversation_interaction' } | Select-Object -First 1)
    Assert-ProfileTest ($tools[0].state -eq 'APPLICABLE') 'ChatGPT app requires tool contracts.'
    Assert-ProfileTest ($conversation[0].state -eq 'APPLICABLE') 'ChatGPT app requires conversation interaction.'

    $overrideJson = '[{"surface_id":"ui_structure","state":"APPLICABLE","reason":"Verified project evidence exposes an operator UI.","source_ref":"evidence:operator-ui"}]'
    $apiWithUi = & $resolver -ProjectRoot $temp -ProjectId 'TEST-API-UI' -PresetIds @('API_SERVICE') -OverridesJson $overrideJson
    $overriddenUi = @($apiWithUi.resolved_surfaces | Where-Object { $_.surface_id -eq 'ui_structure' } | Select-Object -First 1)
    Assert-ProfileTest ($overriddenUi[0].state -eq 'APPLICABLE' -and $overriddenUi[0].override_applied) 'Verified project override wins over archetype default.'

    # Restore TEST-API as the active project applicability profile before creating its Definition applicability.
    $api = & $resolver -ProjectRoot $temp -ProjectId 'TEST-API' -PresetIds @('API_SERVICE','OPENAI_API','AUTHENTICATED_USER_DATA') -SelectionSource HUMAN_ACCEPTED
    $definition = & $definitionApplicability -ProjectRoot $temp -ProjectId 'TEST-API' -DefinitionId 'DEF-1' -DefinitionVersion 1 -AffectedSurfaceIds @('api_contracts','security_privacy') -NotAffectedSurfaceIds @('performance_scale','runtime_deployment','observability','recovery_rollback','compatibility')
    $definitionUi = @($definition.development_surfaces | Where-Object { $_.surface_id -eq 'ui_structure' } | Select-Object -First 1)
    $definitionApi = @($definition.development_surfaces | Where-Object { $_.surface_id -eq 'api_contracts' } | Select-Object -First 1)
    Assert-ProfileTest ($definitionUi[0].definition_state -eq 'NOT_APPLICABLE') 'Project-inapplicable UI remains out of Definition.'
    Assert-ProfileTest ($definitionApi[0].definition_state -eq 'AFFECTED') 'Affected API contract enters Definition applicability.'

    Write-Host 'AIDOS profile preset tests PASS.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
