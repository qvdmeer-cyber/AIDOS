[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [switch]$RequireResolved,
    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$projectProfilePath = Join-Path $root '.aidos\profile\PROJECT_APPLICABILITY.json'
$definitionPath = Join-Path $root ('.aidos\definitions\{0}\v{1}\APPLICABILITY.json' -f $DefinitionId, $DefinitionVersion)
foreach ($path in @($projectProfilePath,$definitionPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Applicability artifact missing: $path" }
}

$project = Get-Content -LiteralPath $projectProfilePath -Raw | ConvertFrom-Json -Depth 100
$definition = Get-Content -LiteralPath $definitionPath -Raw | ConvertFrom-Json -Depth 100
$errors = [System.Collections.Generic.List[string]]::new()

if ($definition.project_id -ne $project.project_id) { $errors.Add('Definition/project applicability project_id mismatch.') }
if ($definition.definition_id -ne $DefinitionId -or [int]$definition.definition_version -ne $DefinitionVersion) { $errors.Add('Definition applicability identity mismatch.') }

$coreExpected = @('goal_scope','current_state_delta','functional_behavior','acceptance_coverage','out_of_scope','unresolved_assumptions')
$coreActual = @($definition.core_surfaces)
if ($coreActual.Count -ne $coreExpected.Count) { $errors.Add('Definition applicability must contain exactly six core surfaces.') }
foreach ($core in $coreExpected) { if ($coreActual -notcontains $core) { $errors.Add("Missing core Definition surface '$core'.") } }

$projectById = @{}
foreach ($surface in @($project.resolved_surfaces)) {
    if ($projectById.ContainsKey([string]$surface.surface_id)) { $errors.Add("Duplicate project applicability surface '$($surface.surface_id)'."); continue }
    $projectById[[string]$surface.surface_id] = $surface
}
$definitionById = @{}
foreach ($surface in @($definition.development_surfaces)) {
    if ($definitionById.ContainsKey([string]$surface.surface_id)) { $errors.Add("Duplicate Definition applicability surface '$($surface.surface_id)'."); continue }
    $definitionById[[string]$surface.surface_id] = $surface
}

$unresolved = 0
foreach ($surfaceId in $projectById.Keys) {
    if (-not $definitionById.ContainsKey($surfaceId)) { $errors.Add("Definition applicability omits project surface '$surfaceId'."); continue }
    $p = $projectById[$surfaceId]
    $d = $definitionById[$surfaceId]
    if ([string]$d.project_state -ne [string]$p.state) { $errors.Add("Definition applicability project_state differs for '$surfaceId'.") }

    if ($p.state -eq 'NOT_APPLICABLE' -and $d.definition_state -ne 'NOT_APPLICABLE') {
        $errors.Add("Project-NOT_APPLICABLE surface '$surfaceId' must remain NOT_APPLICABLE in Definition applicability.")
    }
    if ($p.state -in @('APPLICABLE','CONDITIONAL') -and $d.definition_state -eq 'NOT_APPLICABLE') {
        $errors.Add("Project surface '$surfaceId' cannot become NOT_APPLICABLE merely because a Definition does not affect it; use NOT_AFFECTED.")
    }
    if ($p.state -eq 'UNRESOLVED' -and $d.definition_state -ne 'DECISION_REQUIRED') {
        $errors.Add("Unresolved project applicability '$surfaceId' must remain DECISION_REQUIRED until project applicability is resolved.")
    }
    if ($d.definition_state -eq 'DECISION_REQUIRED') { $unresolved++ }
}
foreach ($surfaceId in $definitionById.Keys) {
    if (-not $projectById.ContainsKey($surfaceId)) { $errors.Add("Definition applicability references unknown project surface '$surfaceId'.") }
}
if ([int]$definition.unresolved_count -ne $unresolved) { $errors.Add("Stored unresolved_count '$($definition.unresolved_count)' differs from calculated '$unresolved'.") }
if ($RequireResolved -and $unresolved -gt 0) { $errors.Add("$unresolved development surface(s) remain DECISION_REQUIRED.") }

$result = [pscustomobject][ordered]@{
    pass = ($errors.Count -eq 0)
    project_id = [string]$definition.project_id
    definition_id = [string]$definition.definition_id
    definition_version = [int]$definition.definition_version
    total_development_surfaces = $projectById.Count
    unresolved_count = $unresolved
    errors = @($errors)
}

if ($NoExit) { return $result }
$status = if ($result.pass) { 'PASS' } else { 'FAIL' }
Write-Host "AIDOS Definition Applicability: $status · unresolved $unresolved / $($projectById.Count)"
foreach ($error in $errors) { Write-Host "ERROR: $error" }
if (-not $result.pass) { exit 1 }
