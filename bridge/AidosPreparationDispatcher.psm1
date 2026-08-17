Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosPreparationRuntime.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosPreparationOnboarding.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosHumanInput.psm1') -DisableNameChecking

function Get-AidosPreparationRegistryProjects {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects'
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            try { Read-AidosJson $_.FullName } catch { throw "Invalid registered project record '$($_.FullName)': $($_.Exception.Message)" }
        }
    )
}

function Get-AidosPendingPreparationResumeIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $resumeRoot=Join-Path $root '.aidos/runtime/resume'
    if(-not(Test-Path -LiteralPath $resumeRoot -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $resumeRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $record=Read-AidosJson $_.FullName
            if([string]$record.status -eq 'PENDING'){
                if([string]::IsNullOrWhiteSpace([string]$record.request_id)){throw "Pending resume record '$($_.FullName)' has no request_id."}
                [string]$record.request_id
            }
        }
    )
}

function Invoke-AidosPreparationControlInbox {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[int]$MaxItems=1)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $intentRoot=Join-Path $root '.aidos/control/intents'
    if(-not(Test-Path -LiteralPath $intentRoot -PathType Container)){return @()}
    $results=[System.Collections.Generic.List[object]]::new();$count=0
    foreach($file in @(Get-ChildItem -LiteralPath $intentRoot -Filter '*.json' -File|Sort-Object Name)){
        if($count-ge$MaxItems){break}
        $intent=Read-AidosJson $file.FullName
        if([string]$intent.status -ne 'RECEIVED'){continue}
        if([string]$intent.project_id -ne [string]$Project.project_id){throw "Control intent '$($intent.control_id)' project binding mismatch."}
        if([string]$intent.command -ne 'SUBMIT_HUMAN_INPUT'){continue}
        $intent.status='ACCEPTED';Write-AidosJsonAtomic $file.FullName $intent
        try{
            $payload=$intent.payload
            $requestId=[string]$payload.request_id
            if([string]::IsNullOrWhiteSpace($requestId)){throw 'SUBMIT_HUMAN_INPUT intent payload requires request_id.'}
            $response=Submit-AidosHumanInputResponse -ProjectRoot $root -RequestId $requestId -RespondedBy ([string]$intent.requested_by) -SelectedOptionId ([string]$payload.selected_option_id) -Text ([string]$payload.text)
            $intent.status='APPLIED';$intent.result=[ordered]@{human_input=$response};$intent.applied_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosJsonAtomic $file.FullName $intent
            $results.Add([pscustomobject][ordered]@{control_id=[string]$intent.control_id;request_id=$requestId;status='APPLIED';response=$response})
        }catch{
            $intent.status='REJECTED';$intent.result=[ordered]@{reason=$_.Exception.Message};$intent.applied_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic $file.FullName $intent
            $results.Add([pscustomobject][ordered]@{control_id=[string]$intent.control_id;request_id=[string]$intent.payload.request_id;status='REJECTED';error=$_.Exception.Message})
        }
        $count++
    }
    @($results)
}

function Invoke-AidosPreparationDispatcherTick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [string]$BuilderRoot,
        [string]$ContractsRoot,
        [int]$MaxItems=1,
        [switch]$Push,
        [scriptblock]$ResumeProcessor,
        [scriptblock]$SyncProcessor,
        [scriptblock]$OnboardingProcessor
    )
    if($MaxItems -lt 1){throw 'MaxItems must be at least 1.'}
    $projects=@(Get-AidosPreparationRegistryProjects -RegistryRoot $RegistryRoot)
    $results=[System.Collections.Generic.List[object]]::new();$processed=0
    foreach($project in $projects){
        if($processed -ge $MaxItems){break}
        if([string]$project.stage -ne 'PREPARATION'){continue}
        if([string]$project.status -in @('BLOCKED','PROMOTED')){continue}
        try{
            $sync=if($SyncProcessor){& $SyncProcessor $project}else{Sync-AidosRegisteredPreparationProject $project}
        }catch{
            $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='SYNC_ERROR';error=$_.Exception.Message});continue
        }
        $project=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId ([string]$project.project_id)
        if([string]$project.status -eq 'READY_FOR_ONBOARDING'){
            try{
                $onboarding=if($OnboardingProcessor){& $OnboardingProcessor $project}else{Invoke-AidosPreparationRuntimeOnboarding -RegistryRoot $RegistryRoot -ProjectId ([string]$project.project_id) -Push:$Push}
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status=[string]$onboarding.status;sync=$sync;onboarding=$onboarding})
            }catch{
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='ONBOARDING_ERROR';sync=$sync;error=$_.Exception.Message})
            }
            $processed++;continue
        }
        $inbox=@(Invoke-AidosPreparationControlInbox -Project $project -MaxItems $MaxItems)
        $requestIds=@(Get-AidosPendingPreparationResumeIds -Project $project)
        if($requestIds.Count-eq0 -and $inbox.Count-gt0){
            try{$persist=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage 'AIDOS persist preparation control intent outcome' -Push:$Push}catch{$persist=[pscustomobject]@{status='ERROR';error=$_.Exception.Message}}
            $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='CONTROL_ONLY';sync=$sync;control=@($inbox);persistence=$persist});$processed++;continue
        }
        foreach($requestId in $requestIds){
            if($processed -ge $MaxItems){break}
            try{
                $outcome=if($ResumeProcessor){& $ResumeProcessor $project $requestId}else{Invoke-AidosPreparationResume -RegistryRoot $RegistryRoot -ProjectId ([string]$project.project_id) -RequestId $requestId -BuilderRoot $BuilderRoot -ContractsRoot $ContractsRoot -Push:$Push}
                $fallbackPersistence=$null
                if([string]$outcome.status -eq 'ACTOR_RESUME_REQUIRED'){$fallbackPersistence=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage ("AIDOS record Human Input $requestId") -Push:$Push}
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=$requestId;status=[string]$outcome.status;sync=$sync;control=@($inbox);outcome=$outcome;persistence=$fallbackPersistence})
            }catch{
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=$requestId;status='ERROR';sync=$sync;control=@($inbox);error=$_.Exception.Message})
            }
            $processed++
        }
    }
    [pscustomobject][ordered]@{
        schema_version='0.1';registry_root=[IO.Path]::GetFullPath($RegistryRoot);observed_at=[DateTimeOffset]::UtcNow.ToString('o');project_count=$projects.Count;processed=$processed;results=@($results);
        status=if($processed-eq0-and$results.Count-eq0){'IDLE'}elseif(@($results|Where-Object {$_.status -in @('ERROR','SYNC_ERROR','ONBOARDING_ERROR')}).Count){'ERROR'}else{'PROCESSED'}
    }
}

Export-ModuleMember -Function Get-AidosPreparationRegistryProjects,Get-AidosPendingPreparationResumeIds,Invoke-AidosPreparationControlInbox,Invoke-AidosPreparationDispatcherTick
