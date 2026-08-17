[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [string]$CatalogPath,
    [switch]$RequireReady,
    [switch]$Json,
    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'catalog\definition-surfaces.catalog.json'
}
$progressPath = Join-Path $root ('.aidos\definitions\{0}\v{1}\PROGRESS.json' -f $DefinitionId, $DefinitionVersion)
foreach ($path in @($CatalogPath,$progressPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json -Depth 50
$progress = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json -Depth 50
$errors = [System.Collections.Generic.List[string]]::new()

if ($progress.catalog_version -ne $catalog.catalog_version) { $errors.Add('Definition progress catalog version mismatch.') }
if ($progress.definition_id -ne $DefinitionId -or $progress.definition_version -ne $DefinitionVersion) { $errors.Add('Definition progress binding mismatch.') }

$catalogIds = @($catalog.surfaces | ForEach-Object { $_.id })
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($surface in @($progress.surfaces)) {
    if (-not $seen.Add([string]$surface.surface_id)) { $errors.Add("Duplicate Definition surface '$($surface.surface_id)'.") }
    if ($catalogIds -notcontains $surface.surface_id) { $errors.Add("Unknown Definition surface '$($surface.surface_id)'.") }
    if ($surface.open_question_count -lt 0) { $errors.Add("Negative open_question_count for '$($surface.surface_id)'.") }
    if (($surface.status -in @('DECISION_REQUIRED','BLOCKED')) -and [string]::IsNullOrWhiteSpace([string]$surface.summary)) {
        $errors.Add("Surface '$($surface.surface_id)' status '$($surface.status)' requires a summary.")
    }
}
foreach ($surfaceId in $catalogIds) {
    if (-not $seen.Contains($surfaceId)) { $errors.Add("Missing required Definition surface '$surfaceId'.") }
}

$completeStatuses = @($catalog.complete_statuses)
$complete = @($progress.surfaces | Where-Object { $completeStatuses -contains $_.status }).Count
$incomplete = @($progress.surfaces).Count - $complete
$next = @($progress.surfaces | Where-Object { $completeStatuses -notcontains $_.status } | Select-Object -First 1)
$expectedNext = if ($next.Count -gt 0) { $next[0].surface_id } else { $null }
if ($progress.complete_count -ne $complete) { $errors.Add("complete_count mismatch: stored=$($progress.complete_count), calculated=$complete.") }
if ($progress.incomplete_count -ne $incomplete) { $errors.Add("incomplete_count mismatch: stored=$($progress.incomplete_count), calculated=$incomplete.") }
if ($progress.next_surface -ne $expectedNext) { $errors.Add("next_surface mismatch: stored='$($progress.next_surface)', calculated='$expectedNext'.") }
if ($RequireReady -and $incomplete -ne 0) { $errors.Add("Definition is not surface-complete: $incomplete surface(s) remain incomplete.") }
if ($RequireReady -and $progress.status -notin @('READY_FOR_REVIEW','ACCEPTED')) { $errors.Add("Definition progress status '$($progress.status)' is not ready/accepted.") }

$pass = $errors.Count -eq 0
$result = [pscustomobject][ordered]@{
    pass = $pass
    project_id = $progress.project_id
    definition_id = $progress.definition_id
    definition_version = $progress.definition_version
    complete_count = $complete
    total_count = @($catalog.surfaces).Count
    incomplete_count = $incomplete
    next_surface = $expectedNext
    last_human_decision_id = $progress.last_human_decision_id
    errors = @($errors)
}

if ($Json) { $result | ConvertTo-Json -Depth 20 }
elseif ($NoExit) { $result }
else {
    $state = if ($pass) { 'PASS' } else { 'FAIL' }
    Write-Host "AIDOS Definition Progress: $state · $complete/$(@($catalog.surfaces).Count) surfaces complete"
    if ($null -ne $expectedNext) { Write-Host "Next surface: $expectedNext" }
    foreach ($error in $errors) { Write-Host "ERROR: $error" }
}
if (-not $NoExit -and -not $pass) { exit 1 }
