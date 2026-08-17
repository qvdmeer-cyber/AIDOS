[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DecisionPath,
    [Parameter(Mandatory)][string]$ContractsRoot,
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
    if ([int]$a.alternatives_count -ne @($decision.alternatives_considered).Count) { $errors.Add('alternatives_count does not match alternatives_considered.') }
    $contracts = [System.IO.Path]::GetFullPath($ContractsRoot)
    $policyTool = Join-Path $contracts 'tools\Test-AidosDecisionAssessment.ps1'
    if (-not (Test-Path -LiteralPath $policyTool -PathType Leaf)) { $errors.Add("Canonical Decision Assessment evaluator not found: $policyTool") }
    else {
        $assessmentJson = $a | ConvertTo-Json -Depth 100 -Compress
        $policy = & $policyTool -AssessmentJson $assessmentJson -ContractsRoot $contracts -NoExit
        if (-not $policy.pass -or -not $policy.decision_allowed) { foreach ($e in @($policy.errors)) { $errors.Add("Decision Governance: $e") } }
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
