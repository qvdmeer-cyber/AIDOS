param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [ValidateSet('NEW_PROJECT','EXISTING_PROJECT','REFRESH')]
    [string]$Mode = 'EXISTING_PROJECT'
)

$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "ProjectRoot does not exist: $root"
}

$documentationRoot = Join-Path $root '.aidos/documentation'
New-Item -ItemType Directory -Path $documentationRoot -Force | Out-Null

$manifestPath = Join-Path $documentationRoot 'MANIFEST.json'
$sessionPath = Join-Path $documentationRoot 'SESSION.json'

if (Test-Path -LiteralPath $manifestPath) {
    throw "Documentation manifest already exists: $manifestPath"
}
if (Test-Path -LiteralPath $sessionPath) {
    throw "Documentation session already exists: $sessionPath"
}

$concernIds = @(
    'identity','product','architecture','runtime','data','interfaces','development',
    'validation','deployment','security_privacy','operations','decisions','constraints'
)

$concerns = foreach ($id in $concernIds) {
    [ordered]@{
        id = $id
        coverage = 'MISSING'
        canonical_source = $null
        supporting_sources = @()
        provenance = 'UNKNOWN'
        notes = ''
        last_verified_commit = $null
    }
}

$manifest = [ordered]@{
    schema_version = '0.1'
    project_id = $ProjectId
    baseline_revision = 0
    status = 'UNINITIALIZED'
    accepted_at = $null
    accepted_commit = $null
    concerns = $concerns
    known_conflicts = @()
    open_material_gaps = @()
}

$session = [ordered]@{
    schema_version = '0.1'
    project_id = $ProjectId
    mode = $Mode
    state = 'INVENTORY'
    started_at = (Get-Date).ToUniversalTime().ToString('o')
    last_updated_at = (Get-Date).ToUniversalTime().ToString('o')
    questions = @()
    accepted_answers = @()
    pending_conflicts = @()
    notes = @()
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$session | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sessionPath -Encoding UTF8

Write-Output ([pscustomobject]@{
    status = 'CREATED'
    project_id = $ProjectId
    mode = $Mode
    manifest = $manifestPath
    session = $sessionPath
} | ConvertTo-Json -Depth 4)
