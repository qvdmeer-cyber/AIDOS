[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DecisionPath,
    [string]$ContractsRoot,
    [switch]$Json,
    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
if (-not (Test-Path -LiteralPath $DecisionPath -PathType Leaf)) { throw "Auto Decision not found: $DecisionPath" }
$decision = Get-Content -LiteralPath $DecisionPath -Raw | ConvertFrom-Json -Depth 100

if ($decision.contract_version -ne '0.1.0') { $errors.Add('Unsupported Auto Decision contract version.') }
if ($decision.decision_type -ne 'AUTO_DECISION') { $errors.Add('decision_type must be AUTO_DECISION.') }
if ([string]::IsNullOrWhiteSpace([string]$decision.decision_id)) { $errors.Add('decision_id is required.') }
if ([string]::IsNullOrWhiteSpace([string]$decision.project_id)) { $errors.Add('project_id is required.') }
if ($null -ne $decision.superseded_by) { $errors.Add('Decision is superseded and may not remain authoritative current decision.') }

$a = $decision.assessment
if ($null -eq $a) { $errors.Add('Decision assessment is required.') }
else {
    if ($a.contract_version -ne '0.1.0') { $errors.Add('Unsupported Decision Assessment contract.') }
    if ($a.authority_classification -ne 'AUTO_DECIDABLE') { $errors.Add('Only AUTO_DECIDABLE may be persisted as AUTO_DECISION.') }
    if ($a.within_authority -ne $true) { $errors.Add('Decision is outside authority.') }
    if ($a.materially_equivalent_alternatives -eq $true) { $errors.Add('Materially equivalent alternatives require human input.') }
    if ($a.confidence -in @('LOW','NOT_APPLICABLE')) { $errors.Add("Confidence '$($a.confidence)' does not permit autonomous decision.") }
    if ($a.reversibility -eq 'IRREVERSIBLE') { $errors.Add('Irreversible decision requires human input.') }
    foreach ($name in @('product_business','security_privacy','destructive','external_cost_commitment','compatibility','blast_radius')) {
        if ([string]$a.impacts.$name -in @('MEDIUM','HIGH')) { $errors.Add("Material $name impact requires human input.") }
    }
    if ([string]$a.missing_evidence -in @('MEDIUM','HIGH')) { $errors.Add('Material missing evidence requires human input.') }
    if ($a.confidence -eq 'MEDIUM' -and $a.reversibility -ne 'REVERSIBLE') { $errors.Add('MEDIUM-confidence decision must be fully REVERSIBLE.') }
    if ([int]$a.alternatives_count -ne @($decision.alternatives_considered).Count) { $errors.Add('alternatives_count does not match alternatives_considered.') }
}

if (-not [string]::IsNullOrWhiteSpace($ContractsRoot)) {
    $catalogPath = Join-Path ([System.IO.Path]::GetFullPath($ContractsRoot)) 'catalog\decision-authority.catalog.json'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { $errors.Add("Decision Governance catalog not found: $catalogPath") }
    else {
        $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 100
        if ($catalog.contract_version -ne '0.1.0') { $errors.Add('Decision Governance catalog version mismatch.') }
    }
}

$result = [pscustomobject][ordered]@{
    pass = ($errors.Count -eq 0)
    decision_id = $decision.decision_id
    project_id = $decision.project_id
    confidence = if ($null -eq $a) {$null} else {$a.confidence}
    reversibility = if ($null -eq $a) {$null} else {$a.reversibility}
    errors = @($errors)
}

if ($Json) { $result | ConvertTo-Json -Depth 50 }
elseif ($NoExit) { $result }
else {
    Write-Host "AIDOS Auto Decision: $(if ($result.pass) {'PASS'} else {'FAIL'})"
    foreach ($error in $errors) { Write-Host "ERROR: $error" }
}
if (-not $NoExit -and -not $result.pass) { exit 1 }
