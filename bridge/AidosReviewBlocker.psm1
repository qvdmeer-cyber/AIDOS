Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousRepair.psm1') -DisableNameChecking

function New-AidosReviewBlockerHumanInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$ReviewId)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$review=Read-AidosReviewRecord -ProjectRoot $root -ReviewId $ReviewId
    if(-not$review.decision -or [string]$review.decision.outcome-ne'BLOCKER'){throw 'Review blocker Human Input requires a BLOCKER review decision.'}
    $state=Get-AidosState $root
    if([string]$state.state-ne'WAITING_USER'){throw "Review blocker Human Input requires WAITING_USER, found '$($state.state)'."}
    $requestRoot=Join-Path $root '.aidos/human-input';if(-not(Test-Path -LiteralPath $requestRoot -PathType Container)){New-Item -ItemType Directory -Path $requestRoot -Force|Out-Null}
    $existing=@(Get-ChildItem -LiteralPath $requestRoot -Filter '*.json' -File|ForEach-Object {Read-AidosJson $_.FullName}|Where-Object {[string]$_.status-eq'WAITING' -and [string]$_.phase-eq'REVIEW' -and [string]$_.context_summary -like "REVIEW_BLOCKER:$ReviewId*"})
    if($existing.Count){return [pscustomobject][ordered]@{status='ALREADY_WAITING';request_id=[string]$existing[0].request_id}}
    $requestId=[guid]::NewGuid().ToString();$now=[DateTimeOffset]::UtcNow.ToString('o')
    $request=[ordered]@{
        contract_version='0.1.0';request_id=$requestId;project_id=[string]$Project.project_id;workstream_id=$null;phase='REVIEW';request_type='AUTHORITY';status='WAITING'
        context_summary=("REVIEW_BLOCKER:{0} — {1}" -f $ReviewId,[string]$review.decision.reason)
        question='How should AIDOS continue from this review blocker?'
        options=@(
            [ordered]@{option_id='REPAIR_WITHIN_DEFINITION';label='Repair within accepted Definition';description='Authorize a new repair revision without changing product intent.'},
            [ordered]@{option_id='REOPEN_DEFINITION';label='Reopen Definition';description='Return to Definition because the accepted product contract needs reconsideration.'},
            [ordered]@{option_id='STOP';label='Stop this execution';description='Preserve the blocker evidence and do not continue this execution.'}
        )
        authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason='Thinker review reported a blocker that cannot be resolved safely without human authority.'
        binding=[ordered]@{baseline_version=$null;definition_id=[string]$review.definition_id;definition_version=[int]$review.definition_version;execution_id=[string]$review.execution_id;revision=[int]$review.revision;review_id=$null}
        requested_by=[ordered]@{actor='WORKER_AGENT';model=$null;session_id=$null};resume_actor_role='SYSTEM';response=$null;evidence_refs=@([string]$review.package_manifest_path);source_refs=@([string]$review.assignment_path);created_at=$now;updated_at=$now
    }
    $requestPath=Join-Path $requestRoot ($requestId+'.json');Write-AidosJsonAtomic $requestPath $request
    $bindingRoot=Join-Path $root '.aidos/human-input-bindings';if(-not(Test-Path -LiteralPath $bindingRoot -PathType Container)){New-Item -ItemType Directory -Path $bindingRoot -Force|Out-Null}
    $resolution=[ordered]@{schema_version='0.1';request_id=$requestId;project_id=[string]$Project.project_id;phase='REVIEW';processor='REVIEW_BLOCKER_RESOLUTION';target=[ordered]@{review_id=$ReviewId;execution_id=[string]$review.execution_id;revision=[int]$review.revision;definition_id=[string]$review.definition_id;definition_version=[int]$review.definition_version};option_values=[ordered]@{REPAIR_WITHIN_DEFINITION='REPAIR_WITHIN_DEFINITION';REOPEN_DEFINITION='REOPEN_DEFINITION';STOP='STOP'};allow_text=$true;created_at=$now}
    Write-AidosJsonAtomic (Join-Path $bindingRoot ($requestId+'.json')) $resolution
    Add-AidosEvent -ProjectRoot $root -EventType 'REVIEW_BLOCKER_HUMAN_INPUT_REQUIRED' -Actor SYSTEM -Payload @{request_id=$requestId;review_id=$ReviewId;execution_id=[string]$review.execution_id;revision=[int]$review.revision}|Out-Null
    [pscustomobject][ordered]@{status='WAITING_HUMAN';request_id=$requestId;request_ref=[IO.Path]::GetRelativePath($root,$requestPath).Replace('\','/')}
}

function Get-AidosPendingReviewBlockerResumes {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$resumeRoot=Join-Path $root '.aidos/runtime/resume'
    if(-not(Test-Path -LiteralPath $resumeRoot -PathType Container)){return @()}
    @(Get-ChildItem -LiteralPath $resumeRoot -Filter '*.json' -File|Sort-Object Name|ForEach-Object {
        $resume=Read-AidosJson $_.FullName;if([string]$resume.status-ne'PENDING' -or [string]$resume.phase-ne'REVIEW'){return}
        $bindingPath=Join-Path $root ('.aidos/human-input-bindings/{0}.json' -f [string]$resume.request_id)
        if(Test-Path -LiteralPath $bindingPath -PathType Leaf){$binding=Read-AidosJson $bindingPath;if([string]$binding.processor-eq'REVIEW_BLOCKER_RESOLUTION'){$resume}}
    })
}
function Invoke-AidosReviewBlockerResume {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$RequestId,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent))
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$requestPath=Join-Path $root ('.aidos/human-input/{0}.json' -f $RequestId);$bindingPath=Join-Path $root ('.aidos/human-input-bindings/{0}.json' -f $RequestId);$resumePath=Join-Path $root ('.aidos/runtime/resume/{0}.json' -f $RequestId)
    foreach($path in @($requestPath,$bindingPath,$resumePath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Review blocker resume artifact missing: $path"}}
    $request=Read-AidosJson $requestPath;$binding=Read-AidosJson $bindingPath;$resume=Read-AidosJson $resumePath
    if([string]$request.status-ne'RESOLVED' -or [string]$binding.processor-ne'REVIEW_BLOCKER_RESOLUTION' -or [string]$resume.status-ne'PENDING'){throw 'Review blocker response is not pending and resolved.'}
    $state=Get-AidosState $root
    if([string]$state.state-ne'WAITING_USER' -or [string]$state.execution_id-ne[string]$binding.target.execution_id -or [int]$state.revision-ne[int]$binding.target.revision){throw 'Review blocker resume state binding mismatch.'}
    $selected=[string]$request.response.selected_option_id;$text=[string]$request.response.text;$result=$null
    switch($selected){
        'REPAIR_WITHIN_DEFINITION' {
            $executionPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$binding.target.execution_id) -Revision ([int]$binding.target.revision);$execution=Read-AidosJson $executionPath
            $guidance=@("Human authorized repair after review blocker $($binding.target.review_id).")
            if(-not[string]::IsNullOrWhiteSpace($text)){$guidance+= $text}
            $repair=Write-AidosRepairRevision -Project $Project -CurrentExecution $execution -RepairKind 'HUMAN_BLOCKER_RESOLUTION' -Guidance $guidance -EvidenceRefs @('.aidos/human-input/'+$RequestId+'.json','.aidos/reviews/'+[string]$binding.target.review_id+'/REVIEW.json')
            $result=[ordered]@{outcome='REPAIR_WITHIN_DEFINITION';repair=$repair}
        }
        'REOPEN_DEFINITION' {
            $definitionId=[string]$binding.target.definition_id;$definitionVersion=[int]$binding.target.definition_version
            $definitionPath=Join-Path $root ('.aidos/definitions/{0}/v{1}/DEFINITION.json' -f $definitionId,$definitionVersion)
            if(Test-Path -LiteralPath $definitionPath -PathType Leaf){$definition=Read-AidosJson $definitionPath;$definition.status='REOPENED';$definition.accepted_at=$null;$definition.accepted_by=$null;$definition.open_questions=@([ordered]@{question=if([string]::IsNullOrWhiteSpace($text)){'Review blocker requires Definition reconsideration.'}else{$text};request_ref=('.aidos/human-input/'+$RequestId+'.json')});Write-AidosJsonAtomic $definitionPath $definition}
            $setSurface=Join-Path ([IO.Path]::GetFullPath($AidosRoot)) 'tools/Set-AidosDefinitionSurface.ps1'
            & $setSurface -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -SurfaceId 'unresolved_assumptions' -Status DECISION_REQUIRED -Summary 'Definition reopened from review blocker Human Input.' -DecisionRef ('.aidos/human-input/'+$RequestId+'.json') -OpenQuestionCount 1 -HumanDecisionId $RequestId -HumanDecisionAt ([string]$request.response.responded_at)|Out-Null
            Set-AidosState -ProjectRoot $root -NewState WAITING_DEFINITION -Actor SYSTEM -Patch @{execution_id=$null;revision=$null;review_id=$null;terminal_result=$null;validation_result=$null;codex_session_id=$null;lease_id=$null}|Out-Null
            $result=[ordered]@{outcome='REOPEN_DEFINITION'}
        }
        'STOP' {
            Set-AidosState -ProjectRoot $root -NewState IDLE -Actor SYSTEM -Patch @{execution_id=$null;revision=$null;review_id=$null;terminal_result=$null;validation_result=$null;codex_session_id=$null;lease_id=$null}|Out-Null
            $result=[ordered]@{outcome='STOPPED'}
        }
        default {throw "Unsupported review blocker resolution '$selected'."}
    }
    $now=[DateTimeOffset]::UtcNow.ToString('o');$resume.status='APPLIED';$resume.applied_at=$now;$resume.updated_at=$now;$resume.result=$result;Write-AidosJsonAtomic $resumePath $resume
    Add-AidosEvent -ProjectRoot $root -EventType 'REVIEW_BLOCKER_HUMAN_INPUT_APPLIED' -Actor SYSTEM -Payload @{request_id=$RequestId;selected_option_id=$selected;outcome=[string]$result.outcome}|Out-Null
    [pscustomobject][ordered]@{status='APPLIED';request_id=$RequestId;outcome=[string]$result.outcome;result=$result}
}
function Invoke-AidosReviewBlockerResumeTick {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[int]$MaxItems=1)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects';$results=[Collections.Generic.List[object]]::new();$processed=0
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return [pscustomobject][ordered]@{status='IDLE';processed=0;results=@()}}
    foreach($file in @(Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File|Sort-Object Name)){
        if($processed-ge$MaxItems){break};$project=Read-AidosJson $file.FullName;if([string]$project.stage-ne'RUNTIME' -or [string]$project.status-ne'PROMOTED'){continue}
        foreach($resume in @(Get-AidosPendingReviewBlockerResumes -ProjectRoot ([string]$project.local_root))){if($processed-ge$MaxItems){break};try{$outcome=Invoke-AidosReviewBlockerResume -Project $project -RequestId ([string]$resume.request_id) -AidosRoot $AidosRoot;$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=[string]$resume.request_id;status=[string]$outcome.status;outcome=$outcome})}catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=[string]$resume.request_id;status='RESUME_ERROR';error=$_.Exception.Message})};$processed++}
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object {$_.status-eq'RESUME_ERROR'}).Count){'ERROR'}elseif($processed-gt0){'PROCESSED'}else{'IDLE'};processed=$processed;results=@($results)}
}

Export-ModuleMember -Function New-AidosReviewBlockerHumanInput,Get-AidosPendingReviewBlockerResumes,Invoke-AidosReviewBlockerResume,Invoke-AidosReviewBlockerResumeTick
