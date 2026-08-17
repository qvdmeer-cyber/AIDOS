[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [string[]]$AffectedSurfaceIds = @(),
    [string[]]$NotAffectedSurfaceIds = @(),
    [string]$ProjectApplicabilityPath,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($ProjectApplicabilityPath)) {
    $ProjectApplicabilityPath = Join-Path $root '.aidos\profile\PROJECT_APPLICABILITY.json'
}
if (-not (Test-Path -LiteralPath $ProjectApplicabilityPath -PathType Leaf)) {
    throw "Project applicability profile not found: $ProjectApplicabilityPath"
}
$profile = Get-Content -LiteralPath $ProjectApplicabilityPath -Raw | ConvertFrom-Json -Depth 100
if ($profile.project_id -ne $ProjectId) { throw 'Project applicability project_id does not match requested project.' }

$affected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$notAffected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($id in $AffectedSurfaceIds) { [void]$affected.Add($id) }
foreach ($id in $NotAffectedSurfaceIds) { [void]$notAffected.Add($id) }
foreach ($id in $affected) {
    if ($notAffected.Contains($id)) { throw "Development surface '$id' is both affected and not affected." }
}

$known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($surface in @($profile.resolved_surfaces)) { [void]$known.Add([string]$surface.surface_id) }
foreach ($id in @($AffectedSurfaceIds + $NotAffectedSurfaceIds)) {
    if (-not $known.Contains($id)) { throw "Unknown project development surface '$id'." }
}

$development = [System.Collections.Generic.List[object]]::new()
$unresolved = 0
foreach ($surface in @($profile.resolved_surfaces)) {
    $surfaceId = [string]$surface.surface_id
    $projectState = [string]$surface.state
    $definitionState = $null
    $reason = $null

    if ($projectState -eq 'NOT_APPLICABLE') {
        $definitionState = 'NOT_APPLICABLE'
        $reason = 'Project Applicability Profile marks this surface NOT_APPLICABLE.'
    } elseif ($affected.Contains($surfaceId)) {
        $definitionState = 'AFFECTED'
        $reason = 'Explicitly classified as affected by this Definition delta.'
    } elseif ($notAffected.Contains($surfaceId)) {
        $definitionState = 'NOT_AFFECTED'
        $reason = 'Explicitly classified as not affected by this Definition delta.'
    } else {
        $definitionState = 'DECISION_REQUIRED'
        $reason = if ($projectState -eq 'UNRESOLVED') {
            'Project applicability is unresolved; resolve project applicability before Definition may omit this surface.'
        } else {
            'Project surface exists or is conditional, but delta applicability has not yet been classified.'
        }
        $unresolved++
    }

    $development.Add([ordered]@{
        surface_id = $surfaceId
        project_state = $projectState
        definition_state = $definitionState
        reason = $reason
        source_refs = @('.aidos/profile/PROJECT_APPLICABILITY.json')
    })
}

$core = @('goal_scope','current_state_delta','functional_behavior','acceptance_coverage','out_of_scope','unresolved_assumptions')
$now = [DateTimeOffset]::UtcNow.ToString('o')
$result = [ordered]@{
    schema_version = '0.1'
    project_id = $ProjectId
    definition_id = $DefinitionId
    definition_version = $DefinitionVersion
    project_applicability_ref = '.aidos/profile/PROJECT_APPLICABILITY.json'
    core_surfaces = $core
    development_surfaces = @($development)
    unresolved_count = $unresolved
    updated_at = $now
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root ('.aidos\definitions\{0}\v{1}\APPLICABILITY.json' -f $DefinitionId, $DefinitionVersion)
}
$output = [System.IO.Path]::GetFullPath($OutputPath)
if ($PSCmdlet.ShouldProcess($output, 'Initialize Definition development-surface applicability')) {
    $parent = Split-Path -Parent $output
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($output, ($result | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Initialized Definition applicability for '$DefinitionId' v${DefinitionVersion}: $unresolved unresolved development surface(s)."
}

$result
