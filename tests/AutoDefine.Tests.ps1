Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('aidos-autodefine-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $temp 'project'
$contracts = Join-Path $temp 'contracts'
New-Item -ItemType Directory -Path (Join-Path $contracts 'catalog') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $contracts 'tools') -Force | Out-Null
New-Item -ItemType Directory -Path $project -Force | Out-Null

try {
    $policy = [ordered]@{
        contract_version='0.1.0'
        authority_classifications=@('SYSTEM_INVARIANT','REPO_VERIFIABLE','AUTO_DECIDABLE','HUMAN_REQUIRED')
        confidence_levels=@('HIGH','MEDIUM','LOW','NOT_APPLICABLE')
        reversibility_levels=@('REVERSIBLE','CONDITIONALLY_REVERSIBLE','IRREVERSIBLE','NOT_APPLICABLE')
        impact_levels=@('NONE','LOW','MEDIUM','HIGH')
        auto_decision_policy=[ordered]@{}
    }
    $policy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $contracts 'catalog\decision-authority.catalog.json') -Encoding UTF8

    @'
param([Parameter(Mandatory)][string]$AssessmentJson,[string]$ContractsRoot,[switch]$NoExit)
$a = $AssessmentJson | ConvertFrom-Json -Depth 50
$errors = @()
if ($a.authority_classification -ne 'AUTO_DECIDABLE') { $errors += 'not auto decidable' }
if ($a.within_authority -ne $true) { $errors += 'outside authority' }
if ($a.materially_equivalent_alternatives -eq $true) { $errors += 'equivalent alternatives' }
if ($a.confidence -eq 'LOW' -or $a.confidence -eq 'NOT_APPLICABLE') { $errors += 'confidence blocked' }
if ($a.reversibility -eq 'IRREVERSIBLE') { $errors += 'irreversible' }
if ($a.confidence -eq 'MEDIUM' -and $a.reversibility -ne 'REVERSIBLE') { $errors += 'medium requires reversible' }
foreach ($name in @('product_business','security_privacy','destructive','external_cost_commitment','compatibility','blast_radius')) { if ([string]$a.impacts.$name -in @('MEDIUM','HIGH')) { $errors += "material $name" } }
if ([string]$a.missing_evidence -in @('MEDIUM','HIGH')) { $errors += 'missing evidence' }
[pscustomobject]@{pass=($errors.Count -eq 0);decision_allowed=($errors.Count -eq 0);errors=$errors}
'@ | Set-Content -LiteralPath (Join-Path $contracts 'tools\Test-AidosDecisionAssessment.ps1') -Encoding UTF8

    & (Join-Path $repoRoot 'tools\New-AidosDefinitionProgress.ps1') -ProjectRoot $project -ProjectId 'TEST' -DefinitionId 'DEF-1' -DefinitionVersion 1

    function New-AssessmentJson([string]$Confidence='HIGH',[string]$Reversibility='REVERSIBLE',[bool]$Equivalent=$false,[bool]$Within=$true,[string]$Impact='LOW',[string]$Missing='LOW') {
        [ordered]@{
            contract_version='0.1.0'; authority_classification='AUTO_DECIDABLE'; confidence=$Confidence; reversibility=$Reversibility;
            within_authority=$Within; materially_equivalent_alternatives=$Equivalent; alternatives_count=0;
            impacts=[ordered]@{product_business=$Impact;security_privacy='LOW';destructive='NONE';external_cost_commitment='NONE';compatibility='LOW';blast_radius='LOW'};
            missing_evidence=$Missing; rationale='Regression test assessment.'; evidence_refs=@('test:evidence'); source_refs=@('test:source');
            assessed_by=[ordered]@{actor='DEFINITION_AGENT';model='test-model';session_id='test'}; assessed_at=[DateTimeOffset]::UtcNow.ToString('o')
        } | ConvertTo-Json -Depth 20 -Compress
    }

    $create = Join-Path $repoRoot 'tools\New-AidosDefinitionAutoDecision.ps1'
    $validate = Join-Path $repoRoot 'tools\Test-AidosAutoDecision.ps1'
    $validateDefinition = Join-Path $repoRoot 'tools\Test-AidosDefinitionDecisions.ps1'
    $validateReady = Join-Path $repoRoot 'tools\Test-AidosDefinitionReady.ps1'
    $setSurface = Join-Path $repoRoot 'tools\Set-AidosDefinitionSurface.ps1'

    $first = & $create -ProjectRoot $project -ContractsRoot $contracts -ProjectId 'TEST' -DefinitionId 'DEF-1' -DefinitionVersion 1 -TargetType DEFINITION_SURFACE -SurfaceId goal_scope -ChosenValueJson '"bounded goal"' -Rationale 'High-confidence reversible choice.' -AssessmentJson (New-AssessmentJson) -DecidedByActor DEFINITION_AGENT -DecidedByModel test-model
    if ([string]::IsNullOrWhiteSpace($first.decision_id)) { throw 'Expected HIGH-confidence Auto Decision to be created.' }
    $firstPath = Join-Path $project ($first.decision_ref -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $validation = & $validate -DecisionPath $firstPath -ContractsRoot $contracts -NoExit
    if (-not $validation.pass) { throw 'Expected persisted HIGH-confidence Auto Decision to validate.' }
    & $setSurface -ProjectRoot $project -DefinitionId 'DEF-1' -DefinitionVersion 1 -SurfaceId goal_scope -Status COMPLETE -Summary 'Auto-defined goal.' -DecisionRef $first.decision_ref -AutoDecisionId $first.decision_id -AutoDecisionAt $first.decided_at

    $initialDefinitionValidation = & $validateDefinition -ProjectRoot $project -ContractsRoot $contracts -ProjectId 'TEST' -DefinitionId 'DEF-1' -DefinitionVersion 1 -NoExit
    if (-not $initialDefinitionValidation.pass -or $initialDefinitionValidation.auto_decisions_current -ne 1) { throw 'Expected Definition decision lineage to validate with one current Auto Decision.' }

    $blocked = 0
    foreach ($case in @(
        @{name='LOW confidence'; assessment=(New-AssessmentJson -Confidence LOW)},
        @{name='equivalent alternatives'; assessment=(New-AssessmentJson -Equivalent $true)},
        @{name='outside authority'; assessment=(New-AssessmentJson -Within $false)},
        @{name='material impact'; assessment=(New-AssessmentJson -Impact MEDIUM)},
        @{name='medium not fully reversible'; assessment=(New-AssessmentJson -Confidence MEDIUM -Reversibility CONDITIONALLY_REVERSIBLE)}
    )) {
        try {
            & $create -ProjectRoot $project -ContractsRoot $contracts -ProjectId 'TEST' -DefinitionId 'DEF-1' -DefinitionVersion 1 -TargetType DEFINITION_SURFACE -SurfaceId goal_scope -ChosenValueJson '"should-fail"' -Rationale $case.name -AssessmentJson $case.assessment -DecidedByActor DEFINITION_AGENT | Out-Null
            throw "Expected Auto Define to reject: $($case.name)"
        } catch {
            if ($_.Exception.Message -like 'Expected Auto Define to reject:*') { throw }
            $blocked++
        }
    }
    if ($blocked -ne 5) { throw "Expected 5 blocked cases, got $blocked." }

    $medium = & $create -ProjectRoot $project -ContractsRoot $contracts -ProjectId 'TEST' -DefinitionId 'DEF-1' -DefinitionVersion 1 -TargetType DEFINITION_SURFACE -SurfaceId goal_scope -ChosenValueJson '"medium-reversible"' -Rationale 'Medium but reversible.' -AssessmentJson (New-AssessmentJson -Confidence MEDIUM -Reversibility REVERSIBLE) -DecidedByActor DEFINITION_AGENT -SupersedesDecisionId $first.decision_id
    $prior = Get-Content -LiteralPath $firstPath -Raw | ConvertFrom-Json -Depth 50
    if ($prior.superseded_by -ne $medium.decision_id) { throw 'Supersession lineage was not persisted.' }
    & $setSurface -ProjectRoot $project -DefinitionId 'DEF-1' -DefinitionVersion 1 -SurfaceId goal_scope -Status COMPLETE -Summary 'Superseding Auto Decision.' -DecisionRef $medium.decision_ref -AutoDecisionId $medium.decision_id -AutoDecisionAt $medium.decided_at

    $lineage = & $validateDefinition -ProjectRoot $project -ContractsRoot $contracts -ProjectId 'TEST' -DefinitionId 'DEF-1' -DefinitionVersion 1 -NoExit
    if (-not $lineage.pass) { throw "Expected Definition decision lineage to validate after supersession: $($lineage.errors -join '; ')" }
    if ($lineage.auto_decisions_current -ne 1 -or $lineage.auto_decisions_superseded -ne 1) { throw 'Expected one current and one superseded Auto Decision.' }

    $progress = Get-Content -LiteralPath (Join-Path $project '.aidos\definitions\DEF-1\v1\PROGRESS.json') -Raw | ConvertFrom-Json -Depth 50
    foreach ($surface in @($progress.surfaces | Where-Object { $_.surface_id -ne 'goal_scope' })) {
        & $setSurface -ProjectRoot $project -DefinitionId 'DEF-1' -DefinitionVersion 1 -SurfaceId $surface.surface_id -Status COMPLETE -Summary 'Regression-test resolved.' -DecisionKind REPO_VERIFIED -DecisionId ('test-' + $surface.surface_id)
    }
    $ready = & $validateReady -ProjectRoot $project -ContractsRoot $contracts -DefinitionId 'DEF-1' -DefinitionVersion 1 -NoExit
    if (-not $ready.pass) { throw "Expected unified Definition readiness to pass: $($ready.errors -join '; ')" }

    Write-Host 'AIDOS Auto Define tests PASS.'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
