[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [string]$CatalogPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Project root does not exist: $root" }
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'catalog\definition-surfaces.catalog.json'
}
if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) { throw "Definition surface catalog not found: $CatalogPath" }

$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json -Depth 50
if ($catalog.catalog_version -ne '0.1.0') { throw "Unsupported Definition surface catalog version '$($catalog.catalog_version)'." }

$definitionRoot = Join-Path $root ('.aidos\definitions\{0}\v{1}' -f $DefinitionId, $DefinitionVersion)
$progressPath = Join-Path $definitionRoot 'PROGRESS.json'
if ((Test-Path -LiteralPath $progressPath) -and -not $Force) { throw "Definition progress already exists: $progressPath" }

$now = [DateTimeOffset]::UtcNow.ToString('o')
$surfaces = foreach ($surface in $catalog.surfaces) {
    [ordered]@{
        surface_id = $surface.id
        status = 'INCOMPLETE'
        summary = ''
        decision_refs = @()
        source_refs = @()
        open_question_count = 0
        updated_at = $now
    }
}

$progress = [ordered]@{
    schema_version = '0.1'
    catalog_version = $catalog.catalog_version
    project_id = $ProjectId
    definition_id = $DefinitionId
    definition_version = $DefinitionVersion
    status = 'IN_PROGRESS'
    surfaces = @($surfaces)
    complete_count = 0
    incomplete_count = @($surfaces).Count
    next_surface = if (@($surfaces).Count -gt 0) { $surfaces[0].surface_id } else { $null }
    last_human_decision_id = $null
    last_human_decision_at = $null
    updated_at = $now
}

if ($PSCmdlet.ShouldProcess($progressPath, 'Initialize durable Definition surface progress')) {
    New-Item -ItemType Directory -Path $definitionRoot -Force | Out-Null
    [System.IO.File]::WriteAllText($progressPath, ($progress | ConvertTo-Json -Depth 50) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Initialized Definition progress: $progressPath"
}
