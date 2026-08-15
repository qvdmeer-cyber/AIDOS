param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string]$ManifestPath = ".aidos/documentation/MANIFEST.json"
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Error "AIDOS project documentation validation failed: $Message"
    exit 1
}

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    Fail "ProjectRoot does not exist: $root"
}

$manifestFull = [System.IO.Path]::GetFullPath((Join-Path $root $ManifestPath))
if (-not $manifestFull.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    Fail "Manifest escapes ProjectRoot: $manifestFull"
}
if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) {
    Fail "Manifest not found: $manifestFull"
}

try {
    $manifest = Get-Content -LiteralPath $manifestFull -Raw | ConvertFrom-Json
}
catch {
    Fail "Manifest is not valid JSON: $($_.Exception.Message)"
}

foreach ($required in @('schema_version','project_id','baseline_revision','status','concerns')) {
    if (-not ($manifest.PSObject.Properties.Name -contains $required)) {
        Fail "Missing required property '$required'."
    }
}

if ($manifest.schema_version -ne '0.1') {
    Fail "Unsupported schema_version '$($manifest.schema_version)'."
}
if ([string]::IsNullOrWhiteSpace([string]$manifest.project_id)) {
    Fail 'project_id is empty.'
}

$allowedCoverage = @('COVERED','PARTIAL','MISSING','CONFLICT','NOT_APPLICABLE','STALE')
$allowedProvenance = @('REPO_VERIFIED','HUMAN_ACCEPTED','INFERRED','UNKNOWN','CONFLICT')
$seen = @{}

foreach ($concern in @($manifest.concerns)) {
    if ([string]::IsNullOrWhiteSpace([string]$concern.id)) {
        Fail 'A concern has no id.'
    }
    if ($seen.ContainsKey([string]$concern.id)) {
        Fail "Duplicate concern id '$($concern.id)'."
    }
    $seen[[string]$concern.id] = $true

    if ($allowedCoverage -notcontains [string]$concern.coverage) {
        Fail "Concern '$($concern.id)' has invalid coverage '$($concern.coverage)'."
    }
    if ($allowedProvenance -notcontains [string]$concern.provenance) {
        Fail "Concern '$($concern.id)' has invalid provenance '$($concern.provenance)'."
    }

    if ($concern.coverage -eq 'COVERED') {
        if ([string]::IsNullOrWhiteSpace([string]$concern.canonical_source)) {
            Fail "Covered concern '$($concern.id)' has no canonical_source."
        }

        $source = [System.IO.Path]::GetFullPath((Join-Path $root ([string]$concern.canonical_source)))
        if (-not $source.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            Fail "Canonical source for '$($concern.id)' escapes ProjectRoot: $source"
        }
        if (-not (Test-Path -LiteralPath $source)) {
            Fail "Canonical source for '$($concern.id)' does not exist: $source"
        }
    }
}

if ($manifest.status -eq 'ACCEPTED') {
    foreach ($concern in @($manifest.concerns)) {
        if ($concern.coverage -in @('MISSING','CONFLICT','STALE')) {
            Fail "Accepted baseline contains material unresolved coverage state '$($concern.coverage)' for '$($concern.id)'."
        }
        if ($concern.provenance -in @('UNKNOWN','CONFLICT','INFERRED') -and $concern.coverage -ne 'NOT_APPLICABLE') {
            Fail "Accepted baseline contains unaccepted provenance '$($concern.provenance)' for '$($concern.id)'."
        }
    }

    if (@($manifest.known_conflicts).Count -gt 0) {
        Fail 'Accepted baseline still lists known_conflicts.'
    }
    if (@($manifest.open_material_gaps).Count -gt 0) {
        Fail 'Accepted baseline still lists open_material_gaps.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.accepted_commit)) {
        Fail 'Accepted baseline has no accepted_commit.'
    }
}

Write-Output ([pscustomobject]@{
    status = 'PASS'
    project_id = [string]$manifest.project_id
    documentation_status = [string]$manifest.status
    baseline_revision = [int]$manifest.baseline_revision
    concerns = @($manifest.concerns).Count
    manifest = $manifestFull
} | ConvertTo-Json -Depth 4)
