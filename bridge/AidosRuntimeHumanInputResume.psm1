Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking

function Get-AidosPendingRuntimeHumanInputResumeRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $resumeRoot=Join-Path $root '.aidos/runtime/resume'
    if(-not(Test-Path -LiteralPath $resumeRoot -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $resumeRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $record=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
            if([string]$record.status -eq 'PENDING' -and [string]$record.phase -eq 'DEFINITION'){$record}
        }
    )
}

function Test-AidosDefinitionHumanDecisionApplied {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$DefinitionId,[Parameter(Mandatory)][int]$DefinitionVersion,[Parameter(Mandatory)][string]$SurfaceId,[Parameter(Mandatory)][string]$RequestRef)
    $progressPath=Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/definitions/{0}/v{1}/PROGRESS.json' -f $DefinitionId,$DefinitionVersion)
    if(-not(Test-Path -LiteralPath $progressPath -PathType Leaf)){return $false}
    $progress=Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    $surface=@($progress.surfaces|Where-Object {[string]$_.surface_id -eq $SurfaceId})
    if($surface.Count-ne1){return $false}
    ([string]$surface[0].status -eq 'COMPLETE' -and @($surface[0].decision_refs) -contains $RequestRef)
}

function Invoke-AidosDefinitionHumanInputResume {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$RequestId,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    Test-AidosRegistryProjectBinding $Project|Out-Null
    if([string]$Project.stage-ne'RUNTIME' -or [string]$Project.status-ne'PROMOTED'){throw 'Definition Human Input resume requires a promoted runtime project.'}
    $requestPath=Join-Path $root ('.aidos/human-input/{0}.json' -f $RequestId)
    $bindingPath=Join-Path $root ('.aidos/human-input-bindings/{0}.json' -f $RequestId)
    $resumePath=Join-Path $root ('.aidos/runtime/resume/{0}.json' -f $RequestId)
    foreach($path in @($requestPath,$bindingPath,$resumePath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Definition Human Input resume artifact missing: $path"}}
    $request=Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    $binding=Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    $resume=Get-Content -LiteralPath $resumePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    if([string]$request.status-ne'RESOLVED' -or [string]$request.phase-ne'DEFINITION'){throw 'Runtime Definition resume requires a resolved DEFINITION Human Input Request.'}
    if([string]$resume.status-eq'APPLIED'){return [pscustomobject][ordered]@{status='ALREADY_APPLIED';request_id=$RequestId;result=$resume.result}}
    if([string]$resume.status-ne'PENDING'){throw "Runtime resume status '$($resume.status)' cannot be applied."}
    if([string]$binding.processor-ne'DEFINITION_SURFACE_HUMAN_ACCEPTED'){throw "Unsupported runtime Human Input processor '$($binding.processor)'."}
    if([string]$binding.request_id-ne$RequestId -or [string]$binding.project_id-ne[string]$Project.project_id -or [string]$resume.project_id-ne[string]$Project.project_id){throw 'Runtime Human Input resume identity mismatch.'}
    $state=Get-AidosState $root
    $definitionId=[string]$request.binding.definition_id;$definitionVersion=[int]$request.binding.definition_version
    if([string]$state.definition_id-ne$definitionId -or [int]$state.definition_version-ne$definitionVersion){throw 'Runtime Human Input resume Definition binding mismatch.'}
    if([string]$state.state -notin @('WAITING_USER','WAITING_DEFINITION')){throw "Runtime Human Input resume cannot apply from state '$($state.state)'."}
    $surfaceId=[string]$binding.target.surface_id;if([string]::IsNullOrWhiteSpace($surfaceId)){throw 'Definition Human Input resolution binding has no surface_id.'}
    $selected=[string]$request.response.selected_option_id;$text=[string]$request.response.text
    $label=$null
    if(-not[string]::IsNullOrWhiteSpace($selected)){
        $property=$binding.option_values.PSObject.Properties[$selected]
        if($null-eq$property){throw "Definition Human Input binding has no option '$selected'."}
        $label=[string]$property.Value.label
    }elseif([string]::IsNullOrWhiteSpace($text)){throw 'Resolved Definition Human Input has neither selected option nor text.'}
    $requestRef=('.aidos/human-input/{0}.json' -f $RequestId)
    $already=Test-AidosDefinitionHumanDecisionApplied -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -SurfaceId $surfaceId -RequestRef $requestRef
    if(-not$already){
        $setSurface=Join-Path ([IO.Path]::GetFullPath($AidosRoot)) 'tools/Set-AidosDefinitionSurface.ps1'
        $testProgress=Join-Path ([IO.Path]::GetFullPath($AidosRoot)) 'tools/Test-AidosDefinitionProgress.ps1'
        foreach($tool in @($setSurface,$testProgress)){if(-not(Test-Path -LiteralPath $tool -PathType Leaf)){throw "Definition Human Input resume tool unavailable: $tool"}}
        $summary=if(-not[string]::IsNullOrWhiteSpace($label)){"Human decision: $label"}else{"Human decision: $text"}
        & $setSurface -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -SurfaceId $surfaceId -Status ([string]$binding.target.completion_status) -Summary $summary -DecisionRef $requestRef -OpenQuestionCount 0 -HumanDecisionId $RequestId -HumanDecisionAt ([string]$request.response.responded_at)|Out-Null
        $check=& $testProgress -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -NoExit
        if(-not[bool]$check.pass){throw "Definition progress invalid after Human Input resume: $(@($check.errors)-join'; ')"}
    }
    if([string]$state.state-ne'WAITING_DEFINITION'){Set-AidosState -ProjectRoot $root -NewState WAITING_DEFINITION -Actor SYSTEM -Patch @{}|Out-Null}
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $result=[ordered]@{processor='DEFINITION_SURFACE_HUMAN_ACCEPTED';surface_id=$surfaceId;selected_option_id=if([string]::IsNullOrWhiteSpace($selected)){$null}else{$selected};response_ref=$requestRef}
    $resume.status='APPLIED';$resume.updated_at=$now;$resume.applied_at=$now;$resume.result=$result;Write-AidosJsonAtomic $resumePath $resume
    Add-AidosEvent -ProjectRoot $root -EventType 'DEFINITION_HUMAN_INPUT_APPLIED' -Actor SYSTEM -Payload @{request_id=$RequestId;surface_id=$surfaceId;definition_id=$definitionId;definition_version=$definitionVersion}|Out-Null
    $persist=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS resume Definition after Human Input $RequestId") -Push:$Push
    [pscustomobject][ordered]@{status='APPLIED';request_id=$RequestId;surface_id=$surfaceId;persistence=$persist}
}

function Invoke-AidosRuntimeHumanInputResumeTick {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[int]$MaxItems=1,[switch]$Push)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects';$results=[Collections.Generic.List[object]]::new();$processed=0
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return [pscustomobject][ordered]@{status='IDLE';processed=0;results=@()}}
    foreach($file in @(Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File|Sort-Object Name)){
        if($processed-ge$MaxItems){break};$project=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
        if([string]$project.stage-ne'RUNTIME' -or [string]$project.status-ne'PROMOTED'){continue}
        foreach($resume in @(Get-AidosPendingRuntimeHumanInputResumeRecords -ProjectRoot ([string]$project.local_root))){
            if($processed-ge$MaxItems){break}
            try{$outcome=Invoke-AidosDefinitionHumanInputResume -Project $project -RequestId ([string]$resume.request_id) -AidosRoot $AidosRoot -Push:$Push;$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=[string]$resume.request_id;status=[string]$outcome.status;outcome=$outcome})}
            catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=[string]$resume.request_id;status='RESUME_ERROR';error=$_.Exception.Message})}
            $processed++
        }
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object {$_.status-eq'RESUME_ERROR'}).Count){'ERROR'}elseif($processed-gt0){'PROCESSED'}else{'IDLE'};processed=$processed;results=@($results)}
}

Export-ModuleMember -Function Get-AidosPendingRuntimeHumanInputResumeRecords,Test-AidosDefinitionHumanDecisionApplied,Invoke-AidosDefinitionHumanInputResume,Invoke-AidosRuntimeHumanInputResumeTick
