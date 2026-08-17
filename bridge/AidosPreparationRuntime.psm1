Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -Force -DisableNameChecking

function Get-AidosHumanInputResolutionBindingPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RequestId)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/human-input-bindings/{0}.json' -f $RequestId)
}

function Get-AidosPreparationResumePath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RequestId)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/runtime/resume/{0}.json' -f $RequestId)
}

function Set-AidosPreparationResumeRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$Status,$Result)
    $Record.status=$Status
    $Record.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    if($Status -in @('APPLIED','FAILED')){$Record.applied_at=$Record.updated_at}
    $Record.result=$Result
    Write-AidosJsonAtomic $Path $Record
    $Record
}

function Invoke-AidosPreparationResume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RequestId,
        [string]$BuilderRoot,
        [string]$ContractsRoot,
        [scriptblock]$ApplyProcessor,
        [scriptblock]$Validator,
        [switch]$Push
    )
    $project=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    if([string]$project.stage -ne 'PREPARATION'){throw "Project '$ProjectId' is not in PREPARATION stage."}
    Test-AidosRegistryProjectBinding $project|Out-Null
    $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
    $requestPath=Join-Path $root ('.aidos/human-input/{0}.json' -f $RequestId)
    $resumePath=Get-AidosPreparationResumePath -ProjectRoot $root -RequestId $RequestId
    if(-not(Test-Path -LiteralPath $requestPath -PathType Leaf)){throw "Human Input Request not found: $RequestId"}
    if(-not(Test-Path -LiteralPath $resumePath -PathType Leaf)){throw "Resume intent not found: $RequestId"}
    $request=Read-AidosJson $requestPath
    $resume=Read-AidosJson $resumePath
    if([string]$request.status -ne 'RESOLVED'){throw 'Preparation resume requires a RESOLVED Human Input Request.'}
    if([string]$resume.status -eq 'APPLIED'){return [pscustomobject][ordered]@{status='ALREADY_APPLIED';request_id=$RequestId;result=$resume.result}}
    if([string]$resume.status -ne 'PENDING'){throw "Resume intent status '$($resume.status)' cannot be processed."}
    if([string]$request.project_id -ne $ProjectId -or [string]$resume.project_id -ne $ProjectId){throw 'Preparation resume project binding mismatch.'}

    $bindingPath=Get-AidosHumanInputResolutionBindingPath -ProjectRoot $root -RequestId $RequestId
    if(-not(Test-Path -LiteralPath $bindingPath -PathType Leaf)){
        return [pscustomobject][ordered]@{status='ACTOR_RESUME_REQUIRED';request_id=$RequestId;resume_actor_role=[string]$resume.resume_actor_role;reason='No deterministic Human Input resolution binding exists.'}
    }
    $binding=Read-AidosJson $bindingPath
    if([string]$binding.request_id -ne $RequestId -or [string]$binding.project_id -ne $ProjectId){throw 'Human Input resolution binding identity mismatch.'}
    if([string]$binding.phase -ne [string]$request.phase){throw 'Human Input resolution binding phase mismatch.'}

    try{
        $selected=[string]$request.response.selected_option_id
        if([string]::IsNullOrWhiteSpace($selected)){throw 'Deterministic resolution requires a selected option.'}
        $valueProperty=$binding.option_values.PSObject.Properties[$selected]
        if($null -eq $valueProperty){throw "Resolution binding has no value for selected option '$selected'."}
        $value=$valueProperty.Value

        if($ApplyProcessor){
            $applyResult=& $ApplyProcessor $project $request $binding $value
        } else {
            if([string]$binding.processor -ne 'BASELINE_ITEM_HUMAN_ACCEPTED'){throw "Unsupported deterministic preparation processor '$($binding.processor)'."}
            if([string]::IsNullOrWhiteSpace($BuilderRoot)){throw 'BuilderRoot is required for BASELINE_ITEM_HUMAN_ACCEPTED.'}
            $setTool=Join-Path ([IO.Path]::GetFullPath($BuilderRoot)) 'tools/Set-AidosBaselineItem.ps1'
            if(-not(Test-Path -LiteralPath $setTool -PathType Leaf)){throw "Builder baseline setter not found: $setTool"}
            $valueJson=$value|ConvertTo-Json -Depth 100 -Compress
            $rationale=('{0} {1} for Human Input Request {2}.' -f [string]$binding.rationale_prefix,$selected,$RequestId).Trim()
            & $setTool -ProjectRoot $root -ItemKey ([string]$binding.target.item_key) -HumanAccepted -AcceptedBy ([string]$request.response.responded_by) -Rationale $rationale -ValueJson $valueJson|Out-Null
            $applyResult=[pscustomobject]@{processor=[string]$binding.processor;item_key=[string]$binding.target.item_key;selected_option_id=$selected}
        }

        if($Validator){
            $validation=& $Validator $project $request $binding
        } else {
            if([string]::IsNullOrWhiteSpace($BuilderRoot)-or[string]::IsNullOrWhiteSpace($ContractsRoot)){throw 'BuilderRoot and ContractsRoot are required for Project Baseline validation.'}
            $validatorTool=Join-Path ([IO.Path]::GetFullPath($BuilderRoot)) 'tools/Test-AidosProjectBaseline.ps1'
            if(-not(Test-Path -LiteralPath $validatorTool -PathType Leaf)){throw "Builder baseline validator not found: $validatorTool"}
            $validation=& $validatorTool -ProjectRoot $root -ContractsRoot ([IO.Path]::GetFullPath($ContractsRoot)) -NoExit
        }
        if($null -eq $validation -or $null -eq $validation.PSObject.Properties['pass']){throw 'Preparation validator returned no canonical pass result.'}
        if(-not[bool]$validation.pass){throw "Preparation validation failed; next unresolved item: $($validation.next_item)"}

        $git=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage ("AIDOS consume Human Input $RequestId") -Push:$Push
        $result=[ordered]@{apply=$applyResult;validation=$validation;git=$git}
        Set-AidosPreparationResumeRecord -Path $resumePath -Record $resume -Status APPLIED -Result $result|Out-Null
        Set-AidosPreparationProjectPhase -RegistryRoot $RegistryRoot -ProjectId $ProjectId -Phase 'BASELINE_ACCEPTANCE' -Status WAITING_HUMAN|Out-Null
        [pscustomobject][ordered]@{status='APPLIED';request_id=$RequestId;validation=$validation;git=$git}
    }catch{
        $failure=[ordered]@{reason=$_.Exception.Message}
        Set-AidosPreparationResumeRecord -Path $resumePath -Record $resume -Status FAILED -Result $failure|Out-Null
        Set-AidosPreparationProjectPhase -RegistryRoot $RegistryRoot -ProjectId $ProjectId -Phase ([string]$project.preparation_phase) -Status BLOCKED|Out-Null
        throw
    }
}

Export-ModuleMember -Function Get-AidosHumanInputResolutionBindingPath,Get-AidosPreparationResumePath,Invoke-AidosPreparationResume
