[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorTransport.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDefinitionResultConsumer.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-DefinitionConsumer([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-definition-consumer-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project';$contracts=Join-Path $base 'contracts'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'docs') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $contracts 'catalog') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $contracts 'tools') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/definition-consumer.git'
    [ordered]@{schema_version='0.1';project_id='DEF-CONSUMER';project_mode='NEW_PROJECT';repository='https://example.invalid/definition-consumer.git';official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='DEF-CONSUMER';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    '# Product`nInteractive browser operator application.'|Set-Content -LiteralPath (Join-Path $projectRoot 'docs/PRODUCT.md') -Encoding utf8NoBOM
    & git -C $projectRoot add .; & git -C $projectRoot commit -q -m init

    [ordered]@{contract_version='0.1.0';authority_classifications=@('SYSTEM_INVARIANT','REPO_VERIFIABLE','AUTO_DECIDABLE','HUMAN_REQUIRED');confidence_levels=@('HIGH','MEDIUM','LOW','NOT_APPLICABLE');reversibility_levels=@('REVERSIBLE','CONDITIONALLY_REVERSIBLE','IRREVERSIBLE','NOT_APPLICABLE');impact_levels=@('NONE','LOW','MEDIUM','HIGH');auto_decision_policy=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $contracts 'catalog/decision-authority.catalog.json') -Encoding utf8NoBOM
    @'
param([Parameter(Mandatory)][string]$AssessmentJson,[string]$ContractsRoot,[switch]$NoExit)
$a=$AssessmentJson|ConvertFrom-Json -Depth 100;$errors=@()
if($a.authority_classification-ne'AUTO_DECIDABLE'){$errors+='not auto decidable'}
if($a.within_authority-ne$true){$errors+='outside authority'}
if($a.materially_equivalent_alternatives-eq$true){$errors+='equivalent alternatives'}
if($a.confidence-ne'HIGH'){$errors+='confidence blocked'}
foreach($n in @('product_business','security_privacy','destructive','external_cost_commitment','compatibility','blast_radius')){if([string]$a.impacts.$n -in @('MEDIUM','HIGH')){$errors+="material $n"}}
if([string]$a.missing_evidence -in @('MEDIUM','HIGH')){$errors+='missing evidence'}
[pscustomobject]@{pass=($errors.Count-eq0);decision_allowed=($errors.Count-eq0);errors=$errors}
'@|Set-Content -LiteralPath (Join-Path $contracts 'tools/Test-AidosDecisionAssessment.ps1') -Encoding utf8NoBOM

    $projectProfile=& (Join-Path $root 'tools/Resolve-AidosProjectApplicability.ps1') -ProjectRoot $projectRoot -ProjectId 'DEF-CONSUMER' -PresetIds @('WEB_APPLICATION') -SelectionSource BASELINE_DERIVED -OverridesJson '[]' -AidosRoot $root
    $projectOverrides=@($projectProfile.resolved_surfaces|Where-Object {[string]$_.state-eq'UNRESOLVED'}|ForEach-Object {
        [ordered]@{surface_id=[string]$_.surface_id;state='APPLICABLE';reason='Definition result consumer fixture explicitly resolves project applicability before Definition.';source_ref='docs/PRODUCT.md'}
    })
    if($projectOverrides.Count){
        & (Join-Path $root 'tools/Resolve-AidosProjectApplicability.ps1') -ProjectRoot $projectRoot -ProjectId 'DEF-CONSUMER' -PresetIds @('WEB_APPLICATION') -SelectionSource BASELINE_DERIVED -OverridesJson ($projectOverrides|ConvertTo-Json -Depth 20 -Compress) -AidosRoot $root|Out-Null
    }
    $project=[pscustomobject]@{project_id='DEF-CONSUMER';local_root=$projectRoot;project_mode='NEW_PROJECT'}
    $start=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    Assert-DefinitionConsumer ([string]$start.action-eq'START_DEFINITION') 'fully resolved project applicability unlocks START_DEFINITION'
    $created=New-AidosRuntimeActorAssignment -Project $project -Selection $start;$a=$created.assignment
    $profile=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/profile/PROJECT_APPLICABILITY.json') -Raw|ConvertFrom-Json -Depth 100
    $appSurface=@($profile.resolved_surfaces|Where-Object {[string]$_.state -in @('APPLICABLE','CONDITIONAL')}|Select-Object -First 1)[0]
    Assert-DefinitionConsumer ($null-ne$appSurface) 'test profile provides at least one classifiable development surface'

    $assessment=[ordered]@{contract_version='0.1.0';authority_classification='AUTO_DECIDABLE';confidence='HIGH';reversibility='REVERSIBLE';within_authority=$true;materially_equivalent_alternatives=$false;alternatives_count=0;impacts=[ordered]@{product_business='LOW';security_privacy='NONE';destructive='NONE';external_cost_commitment='NONE';compatibility='LOW';blast_radius='LOW'};missing_evidence='LOW';rationale='Low-impact reversible Definition detail.';evidence_refs=@();source_refs=@('docs/PRODUCT.md');assessed_by=[ordered]@{actor='DEFINITION_AGENT';model=$null;session_id=$null};assessed_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $output=[ordered]@{
        result_type='DEFINITION_THINKER_OUTPUT';summary='Definition fixed-point pass.';
        applicability_resolutions=@([ordered]@{surface_id=[string]$appSurface.surface_id;definition_state='AFFECTED';authority_classification='REPO_VERIFIABLE';reason='Canonical product documentation shows this development surface is part of the desired product.';source_refs=@('docs/PRODUCT.md')});
        surface_resolutions=@(
            [ordered]@{surface_id='goal_scope';authority_classification='REPO_VERIFIABLE';status='COMPLETE';summary='The accepted product documentation defines the bounded AIDOS Interface goal.';source_refs=@('docs/PRODUCT.md');open_question_count=0;auto_decision=$null},
            [ordered]@{surface_id='current_state_delta';authority_classification='AUTO_DECIDABLE';status='COMPLETE';summary='For this new product the current-state delta is the initial product implementation.';source_refs=@('docs/PRODUCT.md');open_question_count=0;auto_decision=[ordered]@{chosen_value='initial implementation';alternatives_considered=@();rationale='This is a low-impact reversible framing detail.';assessment=$assessment}},
            [ordered]@{surface_id='functional_behavior';authority_classification='HUMAN_REQUIRED';status='DECISION_REQUIRED';summary='A material behavior choice remains unresolved.';source_refs=@('docs/PRODUCT.md');open_question_count=1;auto_decision=$null}
        );
        human_input_request=[ordered]@{surface_id='functional_behavior';request_type='PRODUCT_DECISION';context_summary='One material interaction behavior remains ambiguous.';question='Which interaction behavior should V1 use?';options=@([ordered]@{option_id='A';label='Option A';description='First material behavior.'},[ordered]@{option_id='B';label='Option B';description='Second material behavior.'});authority_classification='HUMAN_REQUIRED';auto_define_stop_reason='Material product behavior requires owner choice.';decision_assessment_ref=$null;evidence_refs=@();source_refs=@('docs/PRODUCT.md')}
    }
    $output=$output|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $result=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$a.assignment_id;assignment_sha256=[string]$created.assignment_sha256;project_id=[string]$a.project_id;actor_role=[string]$a.actor_role;actor_identity=[string]$a.actor_identity;action=[string]$a.action;binding=$a.binding;outcome='COMPLETED';result=$output;responded_at=[DateTimeOffset]::UtcNow.ToString('o')}
    Set-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$a.assignment_id) -Status ACTIVATED -TransportType TEST|Out-Null
    Save-AidosRuntimeActorResult -ProjectRoot $projectRoot -Result $result|Out-Null
    $consumed=Invoke-AidosDefinitionThinkerResultConsumer -Project $project -ActorResult $result -ContractsRoot $contracts -AidosRoot $root
    Assert-DefinitionConsumer ($consumed.status -eq 'WAITING_HUMAN') 'mixed Definition result converges to waiting human when one material choice remains'
    Assert-DefinitionConsumer ((Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json).state -eq 'WAITING_USER') 'Human Input transitions project to WAITING_USER'
    Assert-DefinitionConsumer ((Read-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$a.assignment_id)).status -eq 'CONSUMED') 'Definition actor result is consumed after Core transaction'
    $progress=Get-Content -LiteralPath (Join-Path $projectRoot ('.aidos/definitions/{0}/v1/PROGRESS.json' -f $a.binding.definition_id)) -Raw|ConvertFrom-Json -Depth 100
    Assert-DefinitionConsumer ((@($progress.surfaces|Where-Object {$_.surface_id-eq'goal_scope'})[0].status) -eq 'COMPLETE') 'repo-verifiable Definition surface closes COMPLETE'
    Assert-DefinitionConsumer ((@($progress.surfaces|Where-Object {$_.surface_id-eq'current_state_delta'})[0].status) -eq 'COMPLETE') 'auto-decidable Definition surface closes COMPLETE'
    Assert-DefinitionConsumer ((@($progress.surfaces|Where-Object {$_.surface_id-eq'functional_behavior'})[0].status) -eq 'DECISION_REQUIRED') 'human-required Definition surface remains DECISION_REQUIRED'
    Assert-DefinitionConsumer (@(Get-ChildItem -LiteralPath (Join-Path $projectRoot ('.aidos/definitions/{0}/v1/decisions' -f $a.binding.definition_id)) -Filter '*.json' -File).Count -eq 1) 'policy-valid AUTO_DECIDABLE creates one durable Auto Decision'
    $hir=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot '.aidos/human-input') -Filter '*.json' -File)
    Assert-DefinitionConsumer ($hir.Count-eq1) 'exactly one durable Human Input Request is created'
    $hirRecord=Get-Content -LiteralPath $hir[0].FullName -Raw|ConvertFrom-Json -Depth 100
    Assert-DefinitionConsumer ($hirRecord.status-eq'WAITING' -and $hirRecord.binding.definition_id-eq$a.binding.definition_id -and $hirRecord.resume_actor_role-eq'THINKER') 'Human Input Request has exact Definition binding and Thinker resume role'
    $app=Get-Content -LiteralPath (Join-Path $projectRoot ('.aidos/definitions/{0}/v1/APPLICABILITY.json' -f $a.binding.definition_id)) -Raw|ConvertFrom-Json -Depth 100
    Assert-DefinitionConsumer ((@($app.development_surfaces|Where-Object {$_.surface_id-eq$appSurface.surface_id})[0].definition_state) -eq 'AFFECTED') 'development applicability resolution is persisted through deterministic updater'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed Definition result consumer assertions"
