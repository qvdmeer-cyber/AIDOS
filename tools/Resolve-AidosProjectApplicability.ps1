[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string[]]$PresetIds,
    [ValidateSet('HUMAN_ACCEPTED','DISCOVERY_DERIVED','BASELINE_DERIVED','MIGRATED')][string]$SelectionSource = 'HUMAN_ACCEPTED',
    [string]$OverridesJson = '[]',
    [string]$AidosRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$aidos = [System.IO.Path]::GetFullPath($AidosRoot)
$surfaceCatalogPath = Join-Path $aidos 'catalog\development-surfaces.catalog.json'
$presetCatalogPath = Join-Path $aidos 'catalog\profile-presets.catalog.json'
foreach ($path in @($surfaceCatalogPath,$presetCatalogPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required AIDOS catalog not found: $path" }
}

$surfaceCatalog = Get-Content -LiteralPath $surfaceCatalogPath -Raw | ConvertFrom-Json -Depth 100
$presetCatalog = Get-Content -LiteralPath $presetCatalogPath -Raw | ConvertFrom-Json -Depth 100
if ($surfaceCatalog.catalog_version -ne '0.1.0' -or $presetCatalog.catalog_version -ne '0.1.0') {
    throw 'Unsupported AIDOS profile/development-surface catalog version.'
}

$surfaceById = @{}
foreach ($surface in @($surfaceCatalog.surfaces)) {
    if ($surfaceById.ContainsKey([string]$surface.id)) { throw "Duplicate development surface '$($surface.id)'." }
    $surfaceById[[string]$surface.id] = $surface
}

$presetById = @{}
foreach ($preset in @($presetCatalog.presets)) {
    if ($presetById.ContainsKey([string]$preset.preset_id)) { throw "Duplicate profile preset '$($preset.preset_id)'." }
    $presetById[[string]$preset.preset_id] = $preset
    foreach ($rule in @($preset.applicability_rules)) {
        if (-not $surfaceById.ContainsKey([string]$rule.surface_id)) {
            throw "Preset '$($preset.preset_id)' references unknown development surface '$($rule.surface_id)'."
        }
    }
}

$selected = [System.Collections.Generic.List[object]]::new()
$selectedObjects = [System.Collections.Generic.List[object]]::new()
$seenPresetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($presetId in $PresetIds) {
    if (-not $seenPresetIds.Add($presetId)) { continue }
    if (-not $presetById.ContainsKey($presetId)) { throw "Unknown AIDOS profile preset '$presetId'." }
    $preset = $presetById[$presetId]
    if ($preset.maturity -eq 'DEPRECATED') { throw "Preset '$presetId' is deprecated and may not be newly selected." }
    $selectedObjects.Add($preset)
    $selected.Add([ordered]@{
        preset_id = $preset.preset_id
        version = [int]$preset.version
        category = $preset.category
        selection_source = $SelectionSource
    })
}

$archetypes = @($selectedObjects | Where-Object { $_.category -eq 'PRODUCT_ARCHETYPE' })
if ($presetCatalog.resolution_policy.exactly_one_product_archetype -eq $true -and $archetypes.Count -ne 1) {
    throw "Exactly one PRODUCT_ARCHETYPE preset is required; found $($archetypes.Count)."
}

try { $overrides = @($OverridesJson | ConvertFrom-Json -Depth 50) } catch { throw "OverridesJson is invalid JSON: $($_.Exception.Message)" }
$overrideBySurface = @{}
foreach ($override in $overrides) {
    if ([string]::IsNullOrWhiteSpace([string]$override.surface_id)) { throw 'Applicability override requires surface_id.' }
    if (-not $surfaceById.ContainsKey([string]$override.surface_id)) { throw "Override references unknown development surface '$($override.surface_id)'." }
    if ([string]$override.state -notin @('APPLICABLE','CONDITIONAL','NOT_APPLICABLE')) { throw "Invalid override state '$($override.state)'." }
    if ([string]::IsNullOrWhiteSpace([string]$override.reason) -or [string]::IsNullOrWhiteSpace([string]$override.source_ref)) {
        throw "Override '$($override.surface_id)' requires reason and source_ref."
    }
    if ($overrideBySurface.ContainsKey([string]$override.surface_id)) { throw "Duplicate applicability override '$($override.surface_id)'." }
    $overrideBySurface[[string]$override.surface_id] = $override
}

$rank = @{ NOT_APPLICABLE = 1; CONDITIONAL = 2; APPLICABLE = 3 }
$resolvedSurfaces = [System.Collections.Generic.List[object]]::new()
$conflicts = [System.Collections.Generic.List[object]]::new()

foreach ($surface in @($surfaceCatalog.surfaces)) {
    $surfaceId = [string]$surface.id
    $contributions = [System.Collections.Generic.List[object]]::new()
    foreach ($preset in $selectedObjects) {
        foreach ($rule in @($preset.applicability_rules | Where-Object { $_.surface_id -eq $surfaceId })) {
            $contributions.Add([pscustomobject]@{
                preset_ref = "$($preset.preset_id)@v$($preset.version)"
                state = [string]$rule.state
                reason = [string]$rule.reason
            })
        }
    }

    if ($overrideBySurface.ContainsKey($surfaceId)) {
        $override = $overrideBySurface[$surfaceId]
        $resolvedSurfaces.Add([ordered]@{
            surface_id = $surfaceId
            state = [string]$override.state
            preset_refs = @($contributions | ForEach-Object { $_.preset_ref })
            override_applied = $true
            reason = [string]$override.reason
        })
        continue
    }

    if ($contributions.Count -eq 0) {
        $resolvedSurfaces.Add([ordered]@{
            surface_id = $surfaceId
            state = 'UNRESOLVED'
            preset_refs = @()
            override_applied = $false
            reason = 'No selected preset classifies this development surface.'
        })
        continue
    }

    $states = @($contributions | ForEach-Object { $_.state } | Select-Object -Unique)
    $winner = $contributions | Sort-Object { -$rank[$_.state] } | Select-Object -First 1
    if ($states.Count -gt 1) {
        $conflicts.Add([ordered]@{
            surface_id = $surfaceId
            preset_refs = @($contributions | ForEach-Object { $_.preset_ref })
            states = @($states)
            resolution = "Conservative preset precedence selected '$($winner.state)'. Verified project evidence or an explicit project override takes precedence over this profile resolution."
        })
    }
    $reasons = @($contributions | Where-Object { $_.state -eq $winner.state } | ForEach-Object { $_.reason } | Select-Object -Unique)
    $resolvedSurfaces.Add([ordered]@{
        surface_id = $surfaceId
        state = [string]$winner.state
        preset_refs = @($contributions | ForEach-Object { $_.preset_ref })
        override_applied = $false
        reason = ($reasons -join ' | ')
    })
}

$now = [DateTimeOffset]::UtcNow.ToString('o')
$result = [ordered]@{
    schema_version = '0.1'
    surface_catalog_version = [string]$surfaceCatalog.catalog_version
    preset_catalog_version = [string]$presetCatalog.catalog_version
    project_id = $ProjectId
    selected_presets = @($selected)
    overrides = @($overrides | ForEach-Object {
        [ordered]@{ surface_id=[string]$_.surface_id; state=[string]$_.state; reason=[string]$_.reason; source_ref=[string]$_.source_ref }
    })
    resolved_surfaces = @($resolvedSurfaces)
    conflicts = @($conflicts)
    updated_at = $now
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root '.aidos\profile\PROJECT_APPLICABILITY.json'
}
$output = [System.IO.Path]::GetFullPath($OutputPath)
if ($PSCmdlet.ShouldProcess($output, 'Write resolved AIDOS Project Applicability Profile')) {
    $parent = Split-Path -Parent $output
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($output, ($result | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    $unresolved = @($resolvedSurfaces | Where-Object { $_.state -eq 'UNRESOLVED' }).Count
    Write-Host "Resolved project applicability for '$ProjectId': $($selected.Count) presets; $($resolvedSurfaces.Count) surfaces; $unresolved unresolved; $($conflicts.Count) preset tension(s)."
}

$result
