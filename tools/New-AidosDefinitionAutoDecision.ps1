[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ContractsRoot,
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [Parameter(Mandatory)][ValidateSet('DEFINITION_SURFACE','DEFINITION_FIELD')][string]$TargetType,
    [string]$SurfaceId,
    [string]$Field,
    [Parameter(Mandatory)][string]$ChosenValueJson,
    [string]$AlternativesJson = '[]',
    [Parameter(Mandatory)][string]$Rationale,
    [Parameter(Mandatory)][string]$AssessmentJson,
    [Parameter(Mandatory)][string]$DecidedByActor,
    [string]$DecidedByModel,
    [string]$SessionId,
    [string]$SupersedesDecisionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-AssessmentAllowed {
    param([Parameter(Mandatory)]$Assessment)
    if ($Assessment.contract_version -ne '0.1.0') { throw 'Decision Assessment must use contract 0.1.0.' }
    if ($Assessment.authority_classification -ne 'AUTO_DECIDABLE') { throw 'Only AUTO_DECIDABLE may create an Auto Decision.' }
    if ($Assessment.within_authority -ne $true) { throw 'Decision falls outside authority; HUMAN_REQUIRED.' }
    if ($Assessment.materially_equivalent_alternatives -eq $true) { throw 'Materially equivalent alternatives remain; HUMAN_REQUIRED.' }
    if ($Assessment.confidence -in @('LOW','NOT_APPLICABLE')) { throw 'Confidence does not permit autonomous decision; HUMAN_REQUIRED.' }
    if ($Assessment.reversibility -eq 'IRREVERSIBLE') { throw 'Irreversible decision requires human input.' }
    foreach ($name in @('product_business','security_privacy','destructive','external_cost_commitment','compatibility','blast_radius')) {
        if ([string]$Assessment.impacts.$name -in @('MEDIUM','HIGH')) { throw "Material $name impact requires human input." }
    }
    if ([string]$Assessment.missing_evidence -in @('MEDIUM','HIGH')) { throw 'Material missing evidence requires human input.' }
    if ($Assessment.confidence -eq 'MEDIUM' -and $Assessment.reversibility -ne 'REVERSIBLE') { throw 'MEDIUM-confidence Auto Decision must be fully REVERSIBLE.' }
}

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$contracts = [System.IO.Path]::GetFullPath($ContractsRoot)
$decisionCatalogPath = Join-Path $contracts 'catalog\decision-authority.catalog.json'
if (-not (Test-Path -LiteralPath $decisionCatalogPath -PathType Leaf)) { throw "Decision Governance catalog not found: $decisionCatalogPath" }
$decisionCatalog = Get-Content -LiteralPath $decisionCatalogPath -Raw | ConvertFrom-Json -Depth 100
if ($decisionCatalog.contract_version -ne '0.1.0') { throw "Unsupported Decision Governance contract '$($decisionCatalog.contract_version)'." }

try { $chosen = $ChosenValueJson | ConvertFrom-Json -Depth 100 } catch { throw "ChosenValueJson is invalid JSON: $($_.Exception.Message)" }
try { $alternatives = @($AlternativesJson | ConvertFrom-Json -Depth 100) } catch { throw "AlternativesJson is invalid JSON: $($_.Exception.Message)" }
try { $assessment = $AssessmentJson | ConvertFrom-Json -Depth 100 } catch { throw "AssessmentJson is invalid JSON: $($_.Exception.Message)" }
Test-AssessmentAllowed -Assessment $assessment

if ($TargetType -eq 'DEFINITION_SURFACE' -and [string]::IsNullOrWhiteSpace($SurfaceId)) { throw 'DEFINITION_SURFACE target requires SurfaceId.' }
if ($TargetType -eq 'DEFINITION_FIELD' -and [string]::IsNullOrWhiteSpace($Field)) { throw 'DEFINITION_FIELD target requires Field.' }
if ([int]$assessment.alternatives_count -ne @($alternatives).Count) { throw 'Decision Assessment alternatives_count must equal persisted alternatives_considered count.' }

$definitionRoot = Join-Path $root ('.aidos\definitions\{0}\v{1}' -f $DefinitionId,$DefinitionVersion)
$decisionsRoot = Join-Path $definitionRoot 'decisions'
$progressPath = Join-Path $definitionRoot 'PROGRESS.json'
if (-not (Test-Path -LiteralPath $definitionRoot -PathType Container)) { throw "Definition version root does not exist: $definitionRoot" }
if (-not (Test-Path -LiteralPath $progressPath -PathType Leaf)) { throw "Definition progress not found: $progressPath" }
$progress = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json -Depth 100
if ($progress.project_id -ne $ProjectId -or $progress.definition_id -ne $DefinitionId -or $progress.definition_version -ne $DefinitionVersion) { throw 'Definition/Progress binding mismatch.' }
if ($TargetType -eq 'DEFINITION_SURFACE' -and @($progress.surfaces | Where-Object { $_.surface_id -eq $SurfaceId }).Count -ne 1) { throw "Unknown Definition surface '$SurfaceId'." }

$decisionId = [guid]::NewGuid().ToString()
$now = [DateTimeOffset]::UtcNow.ToString('o')
$decision = [ordered]@{
    contract_version = '0.1.0'
    decision_type = 'AUTO_DECISION'
    decision_id = $decisionId
    project_id = $ProjectId
    binding = [ordered]@{ baseline_version=$null; definition_id=$DefinitionId; definition_version=$DefinitionVersion; execution_id=$null; revision=$null }
    target = [ordered]@{ target_type=$TargetType; item_key=$null; surface_id=if ([string]::IsNullOrWhiteSpace($SurfaceId)) {$null} else {$SurfaceId}; field=if ([string]::IsNullOrWhiteSpace($Field)) {$null} else {$Field} }
    chosen_value = $chosen
    alternatives_considered = @($alternatives)
    rationale = $Rationale
    assessment = $assessment
    decided_by = [ordered]@{ actor=$DecidedByActor; model=if ([string]::IsNullOrWhiteSpace($DecidedByModel)) {$null} else {$DecidedByModel}; session_id=if ([string]::IsNullOrWhiteSpace($SessionId)) {$null} else {$SessionId} }
    decided_at = $now
    supersedes_decision_id = if ([string]::IsNullOrWhiteSpace($SupersedesDecisionId)) {$null} else {$SupersedesDecisionId}
    superseded_by = $null
}

$decisionPath = Join-Path $decisionsRoot "$decisionId.json"
if ($PSCmdlet.ShouldProcess($decisionPath, 'Persist policy-valid Definition Auto Decision')) {
    if (-not (Test-Path -LiteralPath $decisionsRoot)) { New-Item -ItemType Directory -Path $decisionsRoot -Force | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($SupersedesDecisionId)) {
        $priorPath = Join-Path $decisionsRoot "$SupersedesDecisionId.json"
        if (-not (Test-Path -LiteralPath $priorPath -PathType Leaf)) { throw "Superseded Auto Decision not found: $priorPath" }
        $prior = Get-Content -LiteralPath $priorPath -Raw | ConvertFrom-Json -Depth 100
        if ($prior.project_id -ne $ProjectId -or $prior.binding.definition_id -ne $DefinitionId -or $prior.binding.definition_version -ne $DefinitionVersion) { throw 'Superseded Auto Decision binding mismatch.' }
        if ($null -ne $prior.superseded_by) { throw 'Superseded Auto Decision already has a replacement.' }
        $prior.superseded_by = $decisionId
        [System.IO.File]::WriteAllText($priorPath, ($prior | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
    [System.IO.File]::WriteAllText($decisionPath, ($decision | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Persisted Definition Auto Decision: .aidos/definitions/$DefinitionId/v$DefinitionVersion/decisions/$decisionId.json"
}

[pscustomobject]@{
    decision_id = $decisionId
    decision_ref = ".aidos/definitions/$DefinitionId/v$DefinitionVersion/decisions/$decisionId.json"
    decided_at = $now
}
