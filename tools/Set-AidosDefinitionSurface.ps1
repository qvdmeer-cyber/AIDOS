[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [Parameter(Mandatory)][string]$SurfaceId,
    [Parameter(Mandatory)][ValidateSet('COMPLETE','NOT_APPLICABLE','INCOMPLETE','DECISION_REQUIRED','BLOCKED')][string]$Status,
    [string]$Summary = '',
    [string]$DecisionRef,
    [string]$SourceRef,
    [int]$OpenQuestionCount = 0,
    [string]$HumanDecisionId,
    [string]$HumanDecisionAt,
    [string]$AutoDecisionId,
    [string]$AutoDecisionAt,
    [ValidateSet('HUMAN','AUTO','SYSTEM','REPO_VERIFIED')][string]$DecisionKind,
    [string]$DecisionId,
    [string]$DecisionAt,
    [string]$CatalogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($CatalogPath)) { $CatalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'catalog\definition-surfaces.catalog.json' }
$progressPath = Join-Path $root ('.aidos\definitions\{0}\v{1}\PROGRESS.json' -f $DefinitionId, $DefinitionVersion)
foreach ($path in @($CatalogPath,$progressPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" } }

$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json -Depth 50
$progress = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json -Depth 50
if (@($catalog.surfaces | Where-Object { $_.id -eq $SurfaceId }).Count -ne 1) { throw "Unknown Definition surface: $SurfaceId" }
if ($progress.definition_id -ne $DefinitionId -or $progress.definition_version -ne $DefinitionVersion) { throw 'Definition progress binding mismatch.' }

function Ensure-ProgressProperty([string]$Name,$Value) {
    if ($null -eq $progress.PSObject.Properties[$Name]) { $progress | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
foreach ($pair in @(
    @('last_decision_id',$null),@('last_decision_kind',$null),@('last_decision_at',$null),
    @('last_human_decision_id',$null),@('last_human_decision_at',$null),
    @('last_auto_decision_id',$null),@('last_auto_decision_at',$null)
)) { Ensure-ProgressProperty -Name $pair[0] -Value $pair[1] }

$surface = @($progress.surfaces | Where-Object { $_.surface_id -eq $SurfaceId })
if ($surface.Count -ne 1) { throw "Progress does not contain exactly one '$SurfaceId' surface." }
$now = [DateTimeOffset]::UtcNow.ToString('o')
$surface[0].status = $Status
$surface[0].summary = $Summary
$surface[0].open_question_count = $OpenQuestionCount
$surface[0].updated_at = $now
if (-not [string]::IsNullOrWhiteSpace($DecisionRef) -and @($surface[0].decision_refs) -notcontains $DecisionRef) { $surface[0].decision_refs += $DecisionRef }
if (-not [string]::IsNullOrWhiteSpace($SourceRef) -and @($surface[0].source_refs) -notcontains $SourceRef) { $surface[0].source_refs += $SourceRef }

$completeStatuses = @($catalog.complete_statuses)
$complete = @($progress.surfaces | Where-Object { $completeStatuses -contains $_.status }).Count
$incomplete = @($progress.surfaces).Count - $complete
$next = @($progress.surfaces | Where-Object { $completeStatuses -notcontains $_.status } | Select-Object -First 1)
$progress.complete_count = $complete
$progress.incomplete_count = $incomplete
$progress.next_surface = if ($next.Count -gt 0) { $next[0].surface_id } else { $null }
if ($incomplete -eq 0 -and $progress.status -ne 'ACCEPTED') { $progress.status = 'READY_FOR_REVIEW' }
elseif ($incomplete -gt 0 -and $progress.status -ne 'REOPENED') { $progress.status = 'IN_PROGRESS' }

if (-not [string]::IsNullOrWhiteSpace($HumanDecisionId)) {
    $progress.last_human_decision_id = $HumanDecisionId
    $progress.last_human_decision_at = if ([string]::IsNullOrWhiteSpace($HumanDecisionAt)) { $now } else { $HumanDecisionAt }
    $progress.last_decision_id = $HumanDecisionId
    $progress.last_decision_kind = 'HUMAN'
    $progress.last_decision_at = $progress.last_human_decision_at
}
if (-not [string]::IsNullOrWhiteSpace($AutoDecisionId)) {
    $progress.last_auto_decision_id = $AutoDecisionId
    $progress.last_auto_decision_at = if ([string]::IsNullOrWhiteSpace($AutoDecisionAt)) { $now } else { $AutoDecisionAt }
    $progress.last_decision_id = $AutoDecisionId
    $progress.last_decision_kind = 'AUTO'
    $progress.last_decision_at = $progress.last_auto_decision_at
}
if (-not [string]::IsNullOrWhiteSpace($DecisionId)) {
    if ([string]::IsNullOrWhiteSpace($DecisionKind)) { throw 'DecisionId requires DecisionKind.' }
    $progress.last_decision_id = $DecisionId
    $progress.last_decision_kind = $DecisionKind
    $progress.last_decision_at = if ([string]::IsNullOrWhiteSpace($DecisionAt)) { $now } else { $DecisionAt }
}
$progress.updated_at = $now

if ($PSCmdlet.ShouldProcess($progressPath, "Update Definition surface '$SurfaceId' to '$Status'")) {
    [System.IO.File]::WriteAllText($progressPath, ($progress | ConvertTo-Json -Depth 50) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Definition progress: $complete/$(@($progress.surfaces).Count) surfaces complete; next=$($progress.next_surface)"
}
