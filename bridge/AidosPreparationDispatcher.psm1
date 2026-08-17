Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosPreparationRuntime.psm1') -Force -DisableNameChecking

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

function Invoke-AidosPreparationDispatcherTick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [string]$BuilderRoot,
        [string]$ContractsRoot,
        [int]$MaxItems=1,
        [switch]$Push,
        [scriptblock]$ResumeProcessor
    )
    if($MaxItems -lt 1){throw 'MaxItems must be at least 1.'}
    $projects=@(Get-AidosPreparationRegistryProjects -RegistryRoot $RegistryRoot)
    $results=[System.Collections.Generic.List[object]]::new()
    $processed=0
    foreach($project in $projects){
        if($processed -ge $MaxItems){break}
        if([string]$project.stage -ne 'PREPARATION'){continue}
        if([string]$project.status -in @('BLOCKED','PROMOTED')){continue}
        $requestIds=@(Get-AidosPendingPreparationResumeIds -Project $project)
        foreach($requestId in $requestIds){
            if($processed -ge $MaxItems){break}
            try{
                $outcome=if($ResumeProcessor){
                    & $ResumeProcessor $project $requestId
                }else{
                    Invoke-AidosPreparationResume -RegistryRoot $RegistryRoot -ProjectId ([string]$project.project_id) -RequestId $requestId -BuilderRoot $BuilderRoot -ContractsRoot $ContractsRoot -Push:$Push
                }
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=$requestId;status=[string]$outcome.status;outcome=$outcome})
            }catch{
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;request_id=$requestId;status='ERROR';error=$_.Exception.Message})
            }
            $processed++
        }
    }
    [pscustomobject][ordered]@{
        schema_version='0.1'
        registry_root=[IO.Path]::GetFullPath($RegistryRoot)
        observed_at=[DateTimeOffset]::UtcNow.ToString('o')
        project_count=$projects.Count
        processed=$processed
        results=@($results)
        status=if($processed -eq 0){'IDLE'}elseif(@($results|Where-Object {$_.status -eq 'ERROR'}).Count){'ERROR'}else{'PROCESSED'}
    }
}

Export-ModuleMember -Function Get-AidosPreparationRegistryProjects,Get-AidosPendingPreparationResumeIds,Invoke-AidosPreparationDispatcherTick
