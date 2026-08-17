[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosHumanInput.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-HumanInput([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-Throws([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $thrown=$false
    try{&$Action}catch{$thrown=$true;Assert-HumanInput ($_.Exception.Message -match $Pattern) $Message}
    if(-not$thrown){throw "ASSERTION FAILED: $Message (no exception)"}
}

$projectRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-human-input-test-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/human-input') -Force|Out-Null

    [ordered]@{
        contract_version='0.3.0';catalog_version='0.2.0';project_id='HIR-SMOKE';baseline_version=3;
        accepted_at=$null;accepted_by=$null;accepted_commit=$null;items=[ordered]@{}
    }|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM

    $request=[ordered]@{
        contract_version='0.1.0';request_id='hir-1';project_id='HIR-SMOKE';workstream_id=$null;phase='PROJECT_BASELINE';request_type='PRODUCT_DECISION';status='WAITING';
        context_summary='Choose one';question='Choose';options=@(
            [ordered]@{option_id='A';label='Alpha';description='Alpha option'},
            [ordered]@{option_id='B';label='Beta';description='Beta option'}
        );authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason=$null;
        binding=[ordered]@{baseline_version=3;definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;review_id=$null};
        requested_by=[ordered]@{actor='BUILDER';model=$null;session_id=$null};resume_actor_role='BUILDER';response=$null;evidence_refs=@();source_refs=@();created_at='2026-08-17T21:00:00Z';updated_at='2026-08-17T21:00:00Z'
    }
    $request|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/human-input/hir-1.json') -Encoding utf8NoBOM

    Assert-HumanInput ((Get-AidosHumanInputProjectId $projectRoot) -eq 'HIR-SMOKE') 'pre-onboarding project identity resolves from Project Baseline'

    $result=Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId 'hir-1' -RespondedBy 'TEST_OPERATOR' -SelectedOptionId 'A'
    Assert-HumanInput ($result.status -eq 'RESOLVED') 'waiting request resolves'
    Assert-HumanInput ($result.request.status -eq 'RESOLVED' -and $result.request.response.selected_option_id -eq 'A') 'response is durably attached to request'
    Assert-HumanInput (-not[string]::IsNullOrWhiteSpace([string]$result.resume_ref)) 'resolution creates durable resume intent'
    Assert-HumanInput ((Test-Path -LiteralPath (Join-Path $projectRoot $result.resume_ref))) 'resume intent exists on disk'
    Assert-HumanInput ($result.resume.status -eq 'PENDING' -and $result.resume.resume_actor_role -eq 'BUILDER') 'resume intent preserves actor role'
    Assert-HumanInput ([int]$result.resume.binding.baseline_version -eq 3) 'resume intent preserves exact binding'

    $again=Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId 'hir-1' -RespondedBy 'TEST_OPERATOR' -SelectedOptionId 'A'
    Assert-HumanInput ($again.status -eq 'ALREADY_RESOLVED') 'same response is idempotent'
    Assert-Throws {Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId 'hir-1' -RespondedBy 'TEST_OPERATOR' -SelectedOptionId 'B'|Out-Null} 'different response' 'different duplicate response fails closed'

    $bad=$request.PSObject.Copy()
    $bad.request_id='hir-bad-option';$bad.status='WAITING';$bad.response=$null;$bad.binding.baseline_version=3
    $bad|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/human-input/hir-bad-option.json') -Encoding utf8NoBOM
    Assert-Throws {Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId 'hir-bad-option' -RespondedBy TEST -SelectedOptionId 'Z'|Out-Null} 'not permitted' 'unknown option fails closed'

    $mismatch=$request.PSObject.Copy()
    $mismatch.request_id='hir-mismatch';$mismatch.status='WAITING';$mismatch.response=$null;$mismatch.binding.baseline_version=99
    $mismatch|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/human-input/hir-mismatch.json') -Encoding utf8NoBOM
    Assert-Throws {Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId 'hir-mismatch' -RespondedBy TEST -SelectedOptionId 'A'|Out-Null} 'baseline binding mismatch' 'stale baseline binding fails closed'

    $runtimeRequest=$request.PSObject.Copy()
    $runtimeRequest.request_id='hir-runtime';$runtimeRequest.status='WAITING';$runtimeRequest.response=$null;$runtimeRequest.binding.baseline_version=3;$runtimeRequest.binding.definition_id='DEF-1'
    $runtimeRequest|ConvertTo-Json -Depth 50|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/human-input/hir-runtime.json') -Encoding utf8NoBOM
    Assert-Throws {Submit-AidosHumanInputResponse -ProjectRoot $projectRoot -RequestId 'hir-runtime' -RespondedBy TEST -SelectedOptionId 'A'|Out-Null} 'runtime state is unavailable' 'runtime-bound request cannot resolve before runtime state exists'
} finally {
    if(Test-Path -LiteralPath $projectRoot){Remove-Item -LiteralPath $projectRoot -Recurse -Force}
}

Write-Output "PASS: $passed human input assertions"
