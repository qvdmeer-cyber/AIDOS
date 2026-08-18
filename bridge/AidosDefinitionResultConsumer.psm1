Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosHumanInput.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDefinitionRuntime.psm1') -DisableNameChecking

function Resolve-AidosDefinitionActorSourceRef {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AidosRoot,[Parameter(Mandatory)][string]$SourceRef,[Parameter(Mandatory)][string]$DefinitionId,[Parameter(Mandatory)][int]$DefinitionVersion)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $relative=$SourceRef.Replace('\','/')
    if([string]::IsNullOrWhiteSpace($relative)){throw 'Definition source_ref is empty.'}
    if($relative.StartsWith('AIDOS/',[StringComparison]::Ordinal)){
        $systemRelative=$relative.Substring(6)
        if($systemRelative -notmatch '^(docs|protocols|catalog|agents|schemas)/'){throw "AIDOS source_ref is outside authorized system source set: $relative"}
        $path=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath($AidosRoot)) $systemRelative))
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "AIDOS source_ref does not exist: $relative"}
        return [pscustomobject][ordered]@{ref=$relative;scope='AIDOS';path=$path}
    }
    if([IO.Path]::IsPathRooted($relative)){throw 'Definition source_ref must be project-relative or AIDOS/-scoped.'}
    $definitionPrefix=(".aidos/definitions/{0}/v{1}/" -f $DefinitionId,$DefinitionVersion)
    $allowed=($relative -eq '.aidos/documentation/PROJECT_BASELINE.json' -or $relative -eq '.aidos/documentation/PROJECT_ACCESS.json' -or $relative -eq '.aidos/evidence/EVIDENCE_INVENTORY.json' -or $relative -eq '.aidos/profile/PROJECT_APPLICABILITY.json' -or $relative -eq 'AGENTS.md' -or $relative.StartsWith('docs/',[StringComparison]::Ordinal) -or $relative.StartsWith($definitionPrefix,[StringComparison]::Ordinal))
    if(-not$allowed){throw "Definition source_ref is outside authorized project source set: $relative"}
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative));$prefix=$root+[IO.Path]::DirectorySeparatorChar
    $cmp=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not$path.StartsWith($prefix,$cmp)){throw "Definition source_ref escapes project root: $relative"}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Definition source_ref does not exist: $relative"}
    [pscustomobject][ordered]@{ref=$relative;scope='PROJECT';path=$path}
}

function Get-AidosDefinitionValidatedSourceRefs {
    [CmdletBinding()]
    param([string]$ProjectRoot,[string]$AidosRoot,[object[]]$SourceRefs,[string]$DefinitionId,[int]$DefinitionVersion,[switch]$RequireAny)
    $refs=@($SourceRefs|ForEach-Object {[string]$_}|Where-Object {-not[string]::IsNullOrWhiteSpace($_)}|Select-Object -Unique)
    if($RequireAny -and $refs.Count-eq0){throw 'Definition resolution requires source refs.'}
    foreach($ref in $refs){Resolve-AidosDefinitionActorSourceRef -ProjectRoot $ProjectRoot -AidosRoot $AidosRoot -SourceRef $ref -DefinitionId $DefinitionId -DefinitionVersion $DefinitionVersion|Out-Null}
    foreach($ref in $refs){Write-Output ([string]$ref)}
}

function New-AidosDefinitionHumanInputRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$Assignment,[Parameter(Mandatory)]$Proposal,[Parameter(Mandatory)][string]$AidosRoot)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$definitionId=[string]$Assignment.binding.definition_id;$definitionVersion=[int]$Assignment.binding.definition_version
    if([string]$Proposal.authority_classification -notin @('HUMAN_REQUIRED','AUTO_DECIDABLE')){throw 'Definition Human Input authority classification is invalid.'}
    $surfaceId=[string]$Proposal.surface_id;if([string]::IsNullOrWhiteSpace($surfaceId)){throw 'Definition Human Input requires surface_id.'}
    $options=@($Proposal.options);$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($option in $options){if([string]::IsNullOrWhiteSpace([string]$option.option_id)-or[string]::IsNullOrWhiteSpace([string]$option.label)){throw 'Human Input options require option_id and label.'};if(-not$seen.Add([string]$option.option_id)){throw 'Human Input option ids must be unique.'}}
    $sourceRefs=@(Get-AidosDefinitionValidatedSourceRefs -ProjectRoot $root -AidosRoot $AidosRoot -SourceRefs @($Proposal.source_refs) -DefinitionId $definitionId -DefinitionVersion $definitionVersion)
    $requestRoot=Join-Path $root '.aidos/human-input';if(-not(Test-Path -LiteralPath $requestRoot -PathType Container)){New-Item -ItemType Directory -Path $requestRoot -Force|Out-Null}
    $existing=@(Get-ChildItem -LiteralPath $requestRoot -Filter '*.json' -File -ErrorAction SilentlyContinue|ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}|Where-Object {[string]$_.status-eq'WAITING' -and [string]$_.phase-eq'DEFINITION' -and [string]$_.binding.definition_id-eq$definitionId -and [int]$_.binding.definition_version-eq$definitionVersion})
    if($existing.Count-gt0){throw 'A Definition Human Input Request is already waiting for this Definition binding.'}
    if([string]::IsNullOrWhiteSpace([string]$Proposal.context_summary)-or[string]::IsNullOrWhiteSpace([string]$Proposal.question)-or[string]::IsNullOrWhiteSpace([string]$Proposal.auto_define_stop_reason)){throw 'Definition Human Input request text fields are incomplete.'}
    $requestId=[guid]::NewGuid().ToString();$now=[DateTimeOffset]::UtcNow.ToString('o')
    $request=[ordered]@{contract_version='0.1.0';request_id=$requestId;project_id=[string]$Project.project_id;workstream_id=$null;phase='DEFINITION';request_type=[string]$Proposal.request_type;status='WAITING';context_summary=[string]$Proposal.context_summary;question=[string]$Proposal.question;options=@($options|ForEach-Object {[ordered]@{option_id=[string]$_.option_id;label=[string]$_.label;description=if($null-eq$_.description){$null}else{[string]$_.description}}});authority_classification=[string]$Proposal.authority_classification;decision_assessment_ref=if([string]::IsNullOrWhiteSpace([string]$Proposal.decision_assessment_ref)){$null}else{[string]$Proposal.decision_assessment_ref};auto_define_stop_reason=[string]$Proposal.auto_define_stop_reason;binding=[ordered]@{baseline_version=$null;definition_id=$definitionId;definition_version=$definitionVersion;execution_id=$null;revision=$null;review_id=$null};requested_by=[ordered]@{actor='DEFINITION_AGENT';model=$null;session_id=$null};resume_actor_role='THINKER';response=$null;evidence_refs=@($Proposal.evidence_refs|ForEach-Object {[string]$_});source_refs=@($sourceRefs);created_at=$now;updated_at=$now}
    $path=Join-Path $requestRoot ($requestId+'.json');Write-AidosJsonAtomic $path $request

    $bindingRoot=Join-Path $root '.aidos/human-input-bindings';if(-not(Test-Path -LiteralPath $bindingRoot -PathType Container)){New-Item -ItemType Directory -Path $bindingRoot -Force|Out-Null}
    $optionValues=[ordered]@{}
    foreach($option in $options){$optionValues[[string]$option.option_id]=[ordered]@{label=[string]$option.label;description=if($null-eq$option.description){$null}else{[string]$option.description}}}
    $resolutionBinding=[ordered]@{schema_version='0.1';request_id=$requestId;project_id=[string]$Project.project_id;phase='DEFINITION';processor='DEFINITION_SURFACE_HUMAN_ACCEPTED';target=[ordered]@{surface_id=$surfaceId;completion_status='COMPLETE'};option_values=$optionValues;allow_text=$true;created_at=$now}
    $bindingPath=Join-Path $bindingRoot ($requestId+'.json');Write-AidosJsonAtomic $bindingPath $resolutionBinding
    Add-AidosEvent -ProjectRoot $root -EventType 'HUMAN_INPUT_REQUIRED' -Actor DEFINITION_AGENT -Payload @{request_id=$requestId;phase='DEFINITION';surface_id=$surfaceId;authority_classification=[string]$Proposal.authority_classification}|Out-Null
    [pscustomobject][ordered]@{request_id=$requestId;request_ref=[IO.Path]::GetRelativePath($root,$path).Replace('\','/');resolution_binding_ref=[IO.Path]::GetRelativePath($root,$bindingPath).Replace('\','/');request=[pscustomobject]$request}
}

function Invoke-AidosDefinitionThinkerResultConsumer {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$ActorResult,[Parameter(Mandatory)][string]$ContractsRoot,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$binding=Test-AidosRuntimeActorResultBinding -ProjectRoot $root -Result $ActorResult
    $assignment=(Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId ([string]$ActorResult.assignment_id)).assignment
    if([string]$assignment.action -notin @('START_DEFINITION','RESUME_DEFINITION')){throw 'Definition Thinker consumer received the wrong actor action.'}
    if([string]$ActorResult.outcome-ne'COMPLETED'){throw "Definition Thinker outcome '$($ActorResult.outcome)' requires a different consumer path."}
    $state=Get-AidosState $root
    if([string]$state.state-ne'WAITING_DEFINITION' -or [string]$state.definition_id-ne[string]$assignment.binding.definition_id -or [int]$state.definition_version-ne[int]$assignment.binding.definition_version){throw 'Definition Thinker result no longer matches active Definition state.'}
    Ensure-AidosDefinitionWorkspace -ProjectRoot $root -AidosRoot $AidosRoot|Out-Null
    $output=$ActorResult.result;if($null-eq$output -or [string]$output.result_type-ne'DEFINITION_THINKER_OUTPUT'){throw 'Definition Thinker result_type mismatch.'}
    $definitionId=[string]$state.definition_id;$definitionVersion=[int]$state.definition_version;$aidos=[IO.Path]::GetFullPath($AidosRoot)
    $setApplicability=Join-Path $aidos 'tools/Set-AidosDefinitionApplicabilitySurface.ps1';$setSurface=Join-Path $aidos 'tools/Set-AidosDefinitionSurface.ps1';$newAutoDecision=Join-Path $aidos 'tools/New-AidosDefinitionAutoDecision.ps1';$testAutoDecision=Join-Path $aidos 'tools/Test-AidosAutoDecision.ps1';$testApplicability=Join-Path $aidos 'tools/Test-AidosDefinitionApplicability.ps1';$testProgress=Join-Path $aidos 'tools/Test-AidosDefinitionProgress.ps1'
    foreach($tool in @($setApplicability,$setSurface,$newAutoDecision,$testAutoDecision,$testApplicability,$testProgress)){if(-not(Test-Path -LiteralPath $tool -PathType Leaf)){throw "Definition result consumer tool unavailable: $tool"}}
    $applied=[Collections.Generic.List[object]]::new();$appSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($resolution in @($output.applicability_resolutions)){
        $surfaceId=[string]$resolution.surface_id;if(-not$appSeen.Add($surfaceId)){throw "Duplicate Definition applicability resolution '$surfaceId'."};if([string]$resolution.authority_classification -notin @('SYSTEM_INVARIANT','REPO_VERIFIABLE')){throw 'Definition applicability resolution must be SYSTEM_INVARIANT or REPO_VERIFIABLE.'}
        $refs=@(Get-AidosDefinitionValidatedSourceRefs -ProjectRoot $root -AidosRoot $AidosRoot -SourceRefs @($resolution.source_refs) -DefinitionId $definitionId -DefinitionVersion $definitionVersion -RequireAny)
        & $setApplicability -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -SurfaceId $surfaceId -DefinitionState ([string]$resolution.definition_state) -Reason ([string]$resolution.reason) -SourceRefs $refs|Out-Null
        $applied.Add([pscustomobject]@{kind='APPLICABILITY';surface_id=$surfaceId;authority=[string]$resolution.authority_classification})
    }
    $humanResolutions=@($output.surface_resolutions|Where-Object {[string]$_.authority_classification-eq'HUMAN_REQUIRED'})
    if($humanResolutions.Count-gt1){throw 'Definition Thinker may surface at most one HUMAN_REQUIRED decision per result.'};if($humanResolutions.Count-eq1 -and $null-eq$output.human_input_request){throw 'HUMAN_REQUIRED surface requires human_input_request.'};if($humanResolutions.Count-eq0 -and $null-ne$output.human_input_request){throw 'human_input_request requires a matching HUMAN_REQUIRED surface.'}
    $surfaceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$humanRequest=$null
    foreach($resolution in @($output.surface_resolutions)){
        $surfaceId=[string]$resolution.surface_id;if(-not$surfaceSeen.Add($surfaceId)){throw "Duplicate Definition surface resolution '$surfaceId'."};$authority=[string]$resolution.authority_classification;$status=[string]$resolution.status
        $refs=@(Get-AidosDefinitionValidatedSourceRefs -ProjectRoot $root -AidosRoot $AidosRoot -SourceRefs @($resolution.source_refs) -DefinitionId $definitionId -DefinitionVersion $definitionVersion -RequireAny:($authority -in @('SYSTEM_INVARIANT','REPO_VERIFIABLE','AUTO_DECIDABLE')));$decisionRef=$null
        switch($authority){
            'SYSTEM_INVARIANT' {if($null-ne$resolution.auto_decision){throw 'SYSTEM_INVARIANT must not create an Auto Decision.'};if($status-notin@('COMPLETE','NOT_APPLICABLE')){throw 'SYSTEM_INVARIANT surface must close deterministically.'}}
            'REPO_VERIFIABLE' {if($null-ne$resolution.auto_decision){throw 'REPO_VERIFIABLE must not create an Auto Decision.'};if($status-notin@('COMPLETE','NOT_APPLICABLE')){throw 'REPO_VERIFIABLE surface must close deterministically.'}}
            'AUTO_DECIDABLE' {if($null-eq$resolution.auto_decision){throw 'AUTO_DECIDABLE surface requires auto_decision payload.'};if($status-ne'COMPLETE'){throw 'Policy-valid AUTO_DECIDABLE surface must close COMPLETE.'};$auto=$resolution.auto_decision;$decision=& $newAutoDecision -ProjectRoot $root -ContractsRoot $ContractsRoot -ProjectId ([string]$Project.project_id) -DefinitionId $definitionId -DefinitionVersion $definitionVersion -TargetType DEFINITION_SURFACE -SurfaceId $surfaceId -ChosenValueJson ($auto.chosen_value|ConvertTo-Json -Depth 100 -Compress) -AlternativesJson (@($auto.alternatives_considered)|ConvertTo-Json -Depth 100 -Compress) -Rationale ([string]$auto.rationale) -AssessmentJson ($auto.assessment|ConvertTo-Json -Depth 100 -Compress) -DecidedByActor DEFINITION_AGENT;$decisionRef=[string]$decision.decision_ref;$decisionCheck=& $testAutoDecision -ProjectRoot $root -ContractsRoot $ContractsRoot -DecisionPath (Join-Path $root $decisionRef) -NoExit;if(-not[bool]$decisionCheck.pass){throw "Persisted Auto Decision failed validation: $(@($decisionCheck.errors)-join'; ')"}}
            'HUMAN_REQUIRED' {if($null-ne$resolution.auto_decision){throw 'HUMAN_REQUIRED surface must not persist an Auto Decision.'};if($status-ne'DECISION_REQUIRED'){throw 'HUMAN_REQUIRED surface must remain DECISION_REQUIRED.'};if([string]$output.human_input_request.surface_id-ne$surfaceId){throw 'Human Input request surface binding mismatch.'};$humanRequest=New-AidosDefinitionHumanInputRequest -Project $Project -Assignment $assignment -Proposal $output.human_input_request -AidosRoot $AidosRoot}
            default {throw "Unsupported Definition authority classification '$authority'."}
        }
        $sourceRef=if($refs.Count-gt0){[string]$refs[0]}else{$null}
        & $setSurface -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -SurfaceId $surfaceId -Status $status -Summary ([string]$resolution.summary) -DecisionRef $decisionRef -SourceRef $sourceRef -OpenQuestionCount ([int]$resolution.open_question_count)|Out-Null
        foreach($extraRef in @($refs|Select-Object -Skip 1)){& $setSurface -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -SurfaceId $surfaceId -Status $status -Summary ([string]$resolution.summary) -DecisionRef $decisionRef -SourceRef ([string]$extraRef) -OpenQuestionCount ([int]$resolution.open_question_count)|Out-Null}
        $applied.Add([pscustomobject]@{kind='SURFACE';surface_id=$surfaceId;authority=$authority;decision_ref=$decisionRef})
    }
    $appCheck=& $testApplicability -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -NoExit;if(-not[bool]$appCheck.pass){throw "Definition Applicability validation failed after actor result: $(@($appCheck.errors)-join'; ')"}
    $progressCheck=& $testProgress -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -NoExit;if(-not[bool]$progressCheck.pass){throw "Definition Progress validation failed after actor result: $(@($progressCheck.errors)-join'; ')"}
    if($humanRequest){Set-AidosState -ProjectRoot $root -NewState WAITING_USER -Actor SYSTEM -Patch @{}|Out-Null}
    Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId ([string]$ActorResult.assignment_id) -Status CONSUMED|Out-Null
    Add-AidosEvent -ProjectRoot $root -EventType 'DEFINITION_THINKER_RESULT_CONSUMED' -Actor SYSTEM -Payload @{assignment_id=[string]$ActorResult.assignment_id;applied_count=$applied.Count;human_input_request_id=if($humanRequest){$humanRequest.request_id}else{$null};complete_count=[int]$progressCheck.complete_count;incomplete_count=[int]$progressCheck.incomplete_count;applicability_unresolved=[int]$appCheck.unresolved_count}|Out-Null
    [pscustomobject][ordered]@{status=if($humanRequest){'WAITING_HUMAN'}else{'APPLIED'};assignment_id=[string]$ActorResult.assignment_id;applied=@($applied);human_input=$humanRequest;applicability=$appCheck;progress=$progressCheck;binding=$binding}
}

Export-ModuleMember -Function Resolve-AidosDefinitionActorSourceRef,Get-AidosDefinitionValidatedSourceRefs,New-AidosDefinitionHumanInputRequest,Invoke-AidosDefinitionThinkerResultConsumer
