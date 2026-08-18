Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorAssignments.psm1') -DisableNameChecking

function Get-AidosDefinitionCanonicalPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$DefinitionId,[Parameter(Mandatory)][int]$DefinitionVersion)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/definitions/{0}/v{1}/DEFINITION.json' -f $DefinitionId,$DefinitionVersion)
}

function Get-AidosDefinitionFinalAcceptanceResumeRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $resumeRoot=Join-Path $root '.aidos/runtime/resume'
    if(-not(Test-Path -LiteralPath $resumeRoot -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $resumeRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $resume=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
            if([string]$resume.status-ne'PENDING' -or [string]$resume.phase-ne'DEFINITION'){return}
            $bindingPath=Join-Path $root ('.aidos/human-input-bindings/{0}.json' -f [string]$resume.request_id)
            if(-not(Test-Path -LiteralPath $bindingPath -PathType Leaf)){return}
            $binding=Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
            if([string]$binding.processor-eq'DEFINITION_FINAL_ACCEPTANCE'){$resume}
        }
    )
}

function New-AidosCanonicalDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$DefinitionId,[Parameter(Mandatory)][int]$DefinitionVersion)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $profile=Get-AidosProjectProfile $root
    $baseline=Read-AidosJson (Join-Path $root ([string]$profile.project_baseline))
    $progressRef=('.aidos/definitions/{0}/v{1}/PROGRESS.json' -f $DefinitionId,$DefinitionVersion)
    $applicabilityRef=('.aidos/definitions/{0}/v{1}/APPLICABILITY.json' -f $DefinitionId,$DefinitionVersion)
    $progress=Read-AidosJson (Join-Path $root $progressRef)

    $goalItem=$baseline.items.PSObject.Properties['purpose.desired_outcomes']
    $successItem=$baseline.items.PSObject.Properties['purpose.success_boundary']
    $outItem=$baseline.items.PSObject.Properties['scope.out_of_scope']
    $goal=if($goalItem -and -not[string]::IsNullOrWhiteSpace([string]$goalItem.Value.value)){[string]$goalItem.Value.value}else{"Implement the accepted Definition for $($Project.project_id)."}
    $success=if($successItem -and -not[string]::IsNullOrWhiteSpace([string]$successItem.Value.value)){[string]$successItem.Value.value}else{'All accepted Definition requirements and deterministic validators pass.'}
    $outOfScope=if($outItem){@($outItem.Value.value|ForEach-Object {[string]$_})}else{@()}

    $requirements=@($progress.surfaces|Where-Object {[string]$_.status -in @('COMPLETE','NOT_APPLICABLE')}|ForEach-Object {
        [ordered]@{
            surface_id=[string]$_.surface_id
            status=[string]$_.status
            summary=[string]$_.summary
            source_refs=@($_.source_refs|ForEach-Object {[string]$_})
            decision_refs=@($_.decision_refs|ForEach-Object {[string]$_})
        }
    })
    $decisionRefs=@($progress.surfaces|ForEach-Object {@($_.decision_refs)}|Where-Object {-not[string]::IsNullOrWhiteSpace([string]$_)}|ForEach-Object {[string]$_}|Select-Object -Unique)
    $autoDecisionRefs=@($decisionRefs|Where-Object {$_ -like '.aidos/definitions/*/decisions/*'})
    $humanRefs=@($decisionRefs|Where-Object {$_ -like '.aidos/human-input/*'})
    [ordered]@{
        schema_version='0.1'
        definition_id=$DefinitionId
        version=$DefinitionVersion
        project_id=[string]$Project.project_id
        status='USER_REVIEW'
        goal=$goal
        requirements=@($requirements)
        non_functional=@()
        acceptance=@([ordered]@{criterion=$success;source_ref='.aidos/documentation/PROJECT_BASELINE.json'},[ordered]@{criterion='All Definition progress/applicability/decision validators pass before execution.';source_ref='AIDOS/tools/Test-AidosDefinitionReady.ps1'})
        out_of_scope=@($outOfScope)
        open_questions=@()
        sources=@('.aidos/documentation/PROJECT_BASELINE.json',$progressRef,$applicabilityRef,'.aidos/profile/PROJECT_APPLICABILITY.json')
        decision_refs=@($decisionRefs)
        auto_decision_refs=@($autoDecisionRefs)
        human_input_request_refs=@($humanRefs)
        progress_ref=$progressRef
        applicability_ref=$applicabilityRef
        project_applicability_ref='.aidos/profile/PROJECT_APPLICABILITY.json'
        profile_refs=@('.aidos/profile/PROJECT_APPLICABILITY.json')
        accepted_at=$null
        accepted_by=$null
    }
}

function Publish-AidosDefinitionFinalAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$AidosRoot,[Parameter(Mandatory)][string]$ContractsRoot,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $state=Get-AidosState $root
    if([string]$state.state-ne'WAITING_DEFINITION'){throw 'Final Definition acceptance publication requires WAITING_DEFINITION.'}
    $definitionId=[string]$state.definition_id;$definitionVersion=[int]$state.definition_version
    if([string]::IsNullOrWhiteSpace($definitionId)-or$definitionVersion-lt1){throw 'Final Definition acceptance requires exact Definition binding.'}
    if(@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $root|Where-Object {[string]$_.binding.definition_id-eq$definitionId -and [int]$_.binding.definition_version-eq$definitionVersion}).Count-gt0){return [pscustomobject][ordered]@{status='ACTOR_PENDING';definition_id=$definitionId;definition_version=$definitionVersion}}

    $readyTool=Join-Path ([IO.Path]::GetFullPath($AidosRoot)) 'tools/Test-AidosDefinitionReady.ps1'
    $ready=& $readyTool -ProjectRoot $root -ContractsRoot $ContractsRoot -DefinitionId $definitionId -DefinitionVersion $definitionVersion -NoExit
    if(-not[bool]$ready.pass){return [pscustomobject][ordered]@{status='NOT_READY';definition_id=$definitionId;definition_version=$definitionVersion;ready=$ready}}

    $requestRoot=Join-Path $root '.aidos/human-input'
    if(Test-Path -LiteralPath $requestRoot -PathType Container){
        $existing=@(Get-ChildItem -LiteralPath $requestRoot -Filter '*.json' -File|ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}|Where-Object {[string]$_.status-eq'WAITING' -and [string]$_.phase-eq'DEFINITION' -and [string]$_.context_summary -like 'FORMAL_DEFINITION_ACCEPTANCE:*' -and [string]$_.binding.definition_id-eq$definitionId -and [int]$_.binding.definition_version-eq$definitionVersion})
        if($existing.Count-gt0){return [pscustomobject][ordered]@{status='ALREADY_WAITING';request_id=[string]$existing[0].request_id;definition_id=$definitionId;definition_version=$definitionVersion}}
    }else{New-Item -ItemType Directory -Path $requestRoot -Force|Out-Null}

    $definition=New-AidosCanonicalDefinition -Project $Project -DefinitionId $definitionId -DefinitionVersion $definitionVersion
    $definitionPath=Get-AidosDefinitionCanonicalPath -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion
    Write-AidosJsonAtomic $definitionPath $definition

    $requestId=[guid]::NewGuid().ToString();$now=[DateTimeOffset]::UtcNow.ToString('o')
    $request=[ordered]@{
        contract_version='0.1.0';request_id=$requestId;project_id=[string]$Project.project_id;workstream_id=$null;phase='DEFINITION';request_type='AUTHORITY';status='WAITING';
        context_summary=("FORMAL_DEFINITION_ACCEPTANCE: Definition {0} v{1} has converged and passed deterministic readiness validation." -f $definitionId,$definitionVersion)
        question=("Accept Definition {0} v{1} as the authoritative implementation contract?" -f $definitionId,$definitionVersion)
        options=@(
            [ordered]@{option_id='ACCEPT';label='Accept Definition';description='Authorize AIDOS to create execution work from this Definition.'},
            [ordered]@{option_id='REOPEN';label='Reopen Definition';description='Return the Definition to Thinker resolution before execution.'}
        )
        authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason='Final explicit Definition acceptance is a mandatory AIDOS execution gate.'
        binding=[ordered]@{baseline_version=$null;definition_id=$definitionId;definition_version=$definitionVersion;execution_id=$null;revision=$null;review_id=$null}
        requested_by=[ordered]@{actor='AIDOS_CORE';model=$null;session_id=$null};resume_actor_role='THINKER';response=$null;evidence_refs=@();source_refs=@([IO.Path]::GetRelativePath($root,$definitionPath).Replace('\','/'));created_at=$now;updated_at=$now
    }
    $requestPath=Join-Path $requestRoot ($requestId+'.json');Write-AidosJsonAtomic $requestPath $request
    $bindingRoot=Join-Path $root '.aidos/human-input-bindings';if(-not(Test-Path -LiteralPath $bindingRoot)){New-Item -ItemType Directory -Path $bindingRoot -Force|Out-Null}
    $resolution=[ordered]@{schema_version='0.1';request_id=$requestId;project_id=[string]$Project.project_id;phase='DEFINITION';processor='DEFINITION_FINAL_ACCEPTANCE';target=[ordered]@{definition_id=$definitionId;definition_version=$definitionVersion};option_values=[ordered]@{ACCEPT='ACCEPT';REOPEN='REOPEN'};allow_text=$true;created_at=$now}
    Write-AidosJsonAtomic (Join-Path $bindingRoot ($requestId+'.json')) $resolution
    Set-AidosState -ProjectRoot $root -NewState WAITING_USER -Actor SYSTEM -Patch @{}|Out-Null
    Add-AidosEvent -ProjectRoot $root -EventType 'DEFINITION_FINAL_ACCEPTANCE_REQUIRED' -Actor SYSTEM -Payload @{request_id=$requestId;definition_id=$definitionId;definition_version=$definitionVersion;definition_ref=[IO.Path]::GetRelativePath($root,$definitionPath).Replace('\','/')}|Out-Null
    $persist=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS publish final Definition acceptance $definitionId v$definitionVersion") -Push:$Push
    [pscustomobject][ordered]@{status='WAITING_HUMAN';request_id=$requestId;definition_ref=[IO.Path]::GetRelativePath($root,$definitionPath).Replace('\','/');ready=$ready;persistence=$persist}
}

function Invoke-AidosDefinitionFinalAcceptanceResume {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$RequestId,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $requestPath=Join-Path $root ('.aidos/human-input/{0}.json' -f $RequestId)
    $bindingPath=Join-Path $root ('.aidos/human-input-bindings/{0}.json' -f $RequestId)
    $resumePath=Join-Path $root ('.aidos/runtime/resume/{0}.json' -f $RequestId)
    foreach($path in @($requestPath,$bindingPath,$resumePath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Final Definition acceptance artifact missing: $path"}}
    $request=Read-AidosJson $requestPath;$binding=Read-AidosJson $bindingPath;$resume=Read-AidosJson $resumePath
    if([string]$binding.processor-ne'DEFINITION_FINAL_ACCEPTANCE'){throw 'Final Definition acceptance processor mismatch.'}
    if([string]$request.status-ne'RESOLVED'){throw 'Final Definition acceptance requires a resolved Human Input Request.'}
    if([string]$resume.status-eq'APPLIED'){return [pscustomobject][ordered]@{status='ALREADY_APPLIED';request_id=$RequestId;result=$resume.result}}
    if([string]$resume.status-ne'PENDING'){throw "Final Definition acceptance resume status '$($resume.status)' is not applicable."}
    $state=Get-AidosState $root;$definitionId=[string]$binding.target.definition_id;$definitionVersion=[int]$binding.target.definition_version
    if([string]$state.definition_id-ne$definitionId -or [int]$state.definition_version-ne$definitionVersion){throw 'Final Definition acceptance state binding mismatch.'}
    $definitionPath=Get-AidosDefinitionCanonicalPath -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion
    $definition=Read-AidosJson $definitionPath;$selected=[string]$request.response.selected_option_id;$now=[DateTimeOffset]::UtcNow.ToString('o')
    switch($selected){
        'ACCEPT' {
            if([string]$definition.status-ne'USER_REVIEW'){throw "Definition acceptance requires USER_REVIEW, found '$($definition.status)'."}
            $definition.status='ACCEPTED';$definition.accepted_at=$now;$definition.accepted_by=[string]$request.response.responded_by
            $definition.human_input_request_refs=@($definition.human_input_request_refs)+('.aidos/human-input/'+$RequestId+'.json')
            Write-AidosJsonAtomic $definitionPath $definition
            Set-AidosState -ProjectRoot $root -NewState TASK_READY -Actor SYSTEM -Patch @{}|Out-Null
            $result=[ordered]@{processor='DEFINITION_FINAL_ACCEPTANCE';outcome='ACCEPTED';definition_ref=[IO.Path]::GetRelativePath($root,$definitionPath).Replace('\','/')}
            Add-AidosEvent -ProjectRoot $root -EventType 'DEFINITION_ACCEPTED' -Actor SYSTEM -Payload @{request_id=$RequestId;definition_id=$definitionId;definition_version=$definitionVersion}|Out-Null
        }
        'REOPEN' {
            $definition.status='REOPENED';$definition.accepted_at=$null;$definition.accepted_by=$null
            $definition.open_questions=@([ordered]@{question=if([string]::IsNullOrWhiteSpace([string]$request.response.text)){'Human reopened final Definition; determine the requested correction before re-proposal.'}else{[string]$request.response.text};request_ref=('.aidos/human-input/'+$RequestId+'.json')})
            Write-AidosJsonAtomic $definitionPath $definition
            $setSurface=Join-Path ([IO.Path]::GetFullPath($AidosRoot)) 'tools/Set-AidosDefinitionSurface.ps1'
            & $setSurface -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -SurfaceId 'unresolved_assumptions' -Status DECISION_REQUIRED -Summary 'Final Definition was reopened by the human.' -DecisionRef ('.aidos/human-input/'+$RequestId+'.json') -OpenQuestionCount 1 -HumanDecisionId $RequestId -HumanDecisionAt ([string]$request.response.responded_at)|Out-Null
            Set-AidosState -ProjectRoot $root -NewState WAITING_DEFINITION -Actor SYSTEM -Patch @{}|Out-Null
            $result=[ordered]@{processor='DEFINITION_FINAL_ACCEPTANCE';outcome='REOPENED';definition_ref=[IO.Path]::GetRelativePath($root,$definitionPath).Replace('\','/')}
            Add-AidosEvent -ProjectRoot $root -EventType 'DEFINITION_REOPENED' -Actor SYSTEM -Payload @{request_id=$RequestId;definition_id=$definitionId;definition_version=$definitionVersion}|Out-Null
        }
        default {throw "Unsupported final Definition acceptance option '$selected'."}
    }
    $resume.status='APPLIED';$resume.updated_at=$now;$resume.applied_at=$now;$resume.result=$result;Write-AidosJsonAtomic $resumePath $resume
    $persist=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS apply final Definition decision $RequestId") -Push:$Push
    [pscustomobject][ordered]@{status='APPLIED';request_id=$RequestId;outcome=[string]$result.outcome;persistence=$persist}
}

function Invoke-AidosDefinitionFinalAcceptanceResumeTick {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[int]$MaxItems=1,[switch]$Push)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects';$results=[Collections.Generic.List[object]]::new();$processed=0
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return [pscustomobject][ordered]@{status='IDLE';processed=0;results=@()}}
    foreach($file in @(Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File|Sort-Object Name)){
        if($processed-ge$MaxItems){break};$project=Read-AidosJson $file.FullName
        if([string]$project.stage-ne'RUNTIME' -or [string]$project.status-ne'PROMOTED'){continue}
        foreach($resume in @(Get-AidosDefinitionFinalAcceptanceResumeRecords -ProjectRoot ([string]$project.local_root))){
            if($processed-ge$MaxItems){break}
            try{$outcome=Invoke-AidosDefinitionFinalAcceptanceResume -Project $project -RequestId ([string]$resume.request_id) -AidosRoot $AidosRoot -Push:$Push;$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=[string]$resume.request_id;status=[string]$outcome.status;outcome=$outcome})}
            catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=[string]$resume.request_id;status='RESUME_ERROR';error=$_.Exception.Message})}
            $processed++
        }
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object {$_.status-eq'RESUME_ERROR'}).Count){'ERROR'}elseif($processed-gt0){'PROCESSED'}else{'IDLE'};processed=$processed;results=@($results)}
}

function Invoke-AidosDefinitionClosureTick {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ContractsRoot,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[int]$MaxItems=1,[switch]$Push)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects';$results=[Collections.Generic.List[object]]::new();$processed=0
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return [pscustomobject][ordered]@{status='IDLE';processed=0;results=@()}}
    foreach($file in @(Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File|Sort-Object Name)){
        if($processed-ge$MaxItems){break};$project=Read-AidosJson $file.FullName
        if([string]$project.stage-ne'RUNTIME' -or [string]$project.status-ne'PROMOTED'){continue}
        $state=Get-AidosState ([string]$project.local_root);if([string]$state.state-ne'WAITING_DEFINITION'){continue}
        try{$outcome=Publish-AidosDefinitionFinalAcceptance -Project $project -AidosRoot $AidosRoot -ContractsRoot $ContractsRoot -Push:$Push;$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status=[string]$outcome.status;outcome=$outcome})}
        catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='CLOSURE_ERROR';error=$_.Exception.Message})}
        $processed++
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object {$_.status-eq'CLOSURE_ERROR'}).Count){'ERROR'}elseif(@($results|Where-Object {$_.status-eq'WAITING_HUMAN'}).Count){'PROCESSED'}else{'IDLE'};processed=$processed;results=@($results)}
}

Export-ModuleMember -Function Get-AidosDefinitionCanonicalPath,Get-AidosDefinitionFinalAcceptanceResumeRecords,New-AidosCanonicalDefinition,Publish-AidosDefinitionFinalAcceptance,Invoke-AidosDefinitionFinalAcceptanceResume,Invoke-AidosDefinitionFinalAcceptanceResumeTick,Invoke-AidosDefinitionClosureTick
