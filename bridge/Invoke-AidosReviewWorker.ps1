[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AssignmentPath,
    [ValidateSet('PASS','REPAIR','BLOCKER','DISCOVERY_REFRESH_REQUIRED','WAITING_INTERACTIVE_SESSION')][string]$Outcome = 'PASS',
    [string]$Reason = 'external worker stub review',
    [string[]]$RepairGuidance = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking

function Get-TextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

$AssignmentPath = Resolve-AidosFileSystemPath $AssignmentPath
$assignmentText = Get-Content -LiteralPath $AssignmentPath -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace([string]$assignmentText)) { throw 'Assignment envelope is empty.' }
$assignment = $assignmentText | ConvertFrom-Json -Depth 100
$projectRoot = Resolve-AidosFileSystemPath ([string]$assignment.project_root)
$reviewerBinding = Get-AidosReviewReviewerBinding $projectRoot
$manifestPath = Join-Path $projectRoot ([string]$assignment.package_manifest_path)
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Required review manifest not found: $manifestPath" }
$manifest = Read-AidosJson $manifestPath
$manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
Test-AidosReviewAssignmentBinding $projectRoot $assignment $manifest $manifestSha $reviewerBinding | Out-Null

$assignmentSha = Get-TextSha256 $assignmentText
$evidenceRefs = @()
foreach ($ref in @($assignment.evidence_refs)) {
    $source = Join-Path $projectRoot ([string]$ref.path)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required review evidence not found: $source" }
    $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne [string]$ref.sha256) { throw "Required review evidence hash mismatch for '$([string]$ref.path)'." }
    $evidenceRefs += [ordered]@{ kind = [string]$ref.kind; path = [string]$ref.path; sha256 = [string]$ref.sha256 }
}

$response = [ordered]@{
    schema_version='0.1'
    envelope_type='REVIEW_RESPONSE'
    review_id=[string]$assignment.review_id
    project_id=[string]$assignment.project_id
    project_root=[string]$assignment.project_root
    project_mode=[string]$assignment.project_mode
    definition_id=[string]$assignment.definition_id
    definition_version=[int]$assignment.definition_version
    execution_id=[string]$assignment.execution_id
    revision=[int]$assignment.revision
    reviewer_role=[string]$assignment.reviewer_role
    reviewer_identity=[string]$assignment.reviewer_identity
    assignment_sha256=$assignmentSha
    package_manifest_sha256=$manifestSha
    outcome=[string]$Outcome
    reason=[string]$Reason
    evidence_refs=@($evidenceRefs)
    repair_guidance=@($RepairGuidance)
    responded_at=[DateTimeOffset]::UtcNow.ToString('o')
    responded_by=[string]$assignment.reviewer_identity
}
$response | ConvertTo-Json -Depth 100
