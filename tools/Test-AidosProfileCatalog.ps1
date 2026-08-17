[CmdletBinding()]
param([string]$AidosRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($AidosRoot)
$surfacePath = Join-Path $root 'catalog\development-surfaces.catalog.json'
$presetPath = Join-Path $root 'catalog\profile-presets.catalog.json'
foreach ($path in @($surfacePath,$presetPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required catalog missing: $path" }
}

$surfaces = Get-Content -LiteralPath $surfacePath -Raw | ConvertFrom-Json -Depth 100
$presets = Get-Content -LiteralPath $presetPath -Raw | ConvertFrom-Json -Depth 100
if ($surfaces.catalog_version -ne '0.1.0') { throw 'Unexpected development surface catalog version.' }
if ($presets.catalog_version -ne '0.1.0') { throw 'Unexpected profile preset catalog version.' }
if ($presets.resolution_policy.exactly_one_product_archetype -ne $true) { throw 'Profile catalog must require exactly one product archetype.' }
if ($presets.resolution_policy.preset_never_overrides_verified_project_truth -ne $true) { throw 'Preset catalog must preserve verified project truth precedence.' }

$surfaceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($surface in @($surfaces.surfaces)) {
    if ([string]::IsNullOrWhiteSpace([string]$surface.id)) { throw 'Development surface id is empty.' }
    if (-not $surfaceIds.Add([string]$surface.id)) { throw "Duplicate development surface '$($surface.id)'." }
}
if ($surfaceIds.Count -lt 20) { throw "Expected broad development surface coverage; found only $($surfaceIds.Count)." }

$presetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$archetypeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$categories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($preset in @($presets.presets)) {
    if (-not $presetIds.Add([string]$preset.preset_id)) { throw "Duplicate profile preset '$($preset.preset_id)'." }
    [void]$categories.Add([string]$preset.category)
    if ($preset.category -eq 'PRODUCT_ARCHETYPE') { [void]$archetypeIds.Add([string]$preset.preset_id) }
    if ([int]$preset.version -lt 1) { throw "Preset '$($preset.preset_id)' has invalid version." }
    if ([string]$preset.maturity -notin @('CANDIDATE','PROVEN','DEPRECATED')) { throw "Preset '$($preset.preset_id)' has invalid maturity." }
    foreach ($rule in @($preset.applicability_rules)) {
        if (-not $surfaceIds.Contains([string]$rule.surface_id)) { throw "Preset '$($preset.preset_id)' references unknown surface '$($rule.surface_id)'." }
        if ([string]$rule.state -notin @('APPLICABLE','CONDITIONAL','NOT_APPLICABLE')) { throw "Preset '$($preset.preset_id)' uses invalid applicability '$($rule.state)'." }
        if ([string]::IsNullOrWhiteSpace([string]$rule.reason)) { throw "Preset '$($preset.preset_id)' rule '$($rule.surface_id)' lacks reason." }
    }
}

foreach ($category in @('PRODUCT_ARCHETYPE','CAPABILITY','INTEGRATION','STACK','INFRASTRUCTURE','EXPOSURE_RISK')) {
    if (-not $categories.Contains($category)) { throw "Missing profile category '$category'." }
}
foreach ($archetype in @('STATIC_MARKETING_SITE','CONTENT_WEBSITE','WEB_APPLICATION','MOBILE_APPLICATION','DESKTOP_APPLICATION','API_SERVICE','BACKGROUND_SERVICE','CLI_APPLICATION','LIBRARY_PACKAGE','BROWSER_EXTENSION','CMS_APPLICATION','CHATGPT_APP','MCP_SERVER')) {
    if (-not $archetypeIds.Contains($archetype)) { throw "Missing required initial product archetype '$archetype'." }
}

function Get-RuleState([string]$PresetId,[string]$SurfaceId) {
    $preset = @($presets.presets | Where-Object { $_.preset_id -eq $PresetId } | Select-Object -First 1)
    if ($preset.Count -ne 1) { throw "Preset not found for invariant check: $PresetId" }
    $rule = @($preset[0].applicability_rules | Where-Object { $_.surface_id -eq $SurfaceId } | Select-Object -First 1)
    if ($rule.Count -ne 1) { return $null }
    return [string]$rule[0].state
}

if ((Get-RuleState 'API_SERVICE' 'ui_structure') -ne 'NOT_APPLICABLE') { throw 'API_SERVICE must not inherently require UI structure.' }
if ((Get-RuleState 'API_SERVICE' 'api_contracts') -ne 'APPLICABLE') { throw 'API_SERVICE must require API contracts.' }
if ((Get-RuleState 'MOBILE_APPLICATION' 'device_platform') -ne 'APPLICABLE') { throw 'MOBILE_APPLICATION must require device/platform treatment.' }
if ((Get-RuleState 'CHATGPT_APP' 'tool_contracts') -ne 'APPLICABLE') { throw 'CHATGPT_APP must require tool contracts.' }
if ((Get-RuleState 'MCP_SERVER' 'tool_contracts') -ne 'APPLICABLE') { throw 'MCP_SERVER must require tool contracts.' }
if ((Get-RuleState 'OPENAI_API' 'tool_contracts') -ne $null) { throw 'OPENAI_API integration must not redefine the product archetype/tool surface by itself.' }

Write-Host "AIDOS profile catalog PASS: $($surfaceIds.Count) development surfaces; $($presetIds.Count) composable presets; $($archetypeIds.Count) product archetypes."
