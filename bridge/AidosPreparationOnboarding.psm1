Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -Force -DisableNameChecking

function Invoke-AidosPreparationRuntimeOnboarding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [switch]$Push
    )
    $project=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    if([string]$project.stage -eq 'RUNTIME' -and [string]$project.status -eq 'PROMOTED'){
        return [pscustomobject][ordered]@{status='ALREADY_PROMOTED';project_id=$ProjectId}
    }
    if([string]$project.stage -ne 'PREPARATION' -or [string]$project.status -ne 'READY_FOR_ONBOARDING'){
        throw "Project '$ProjectId' is not READY_FOR_ONBOARDING."
    }
    Test-AidosRegistryProjectBinding $project|Out-Null
    $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
    $projectPath=Join-Path $root '.aidos/PROJECT.json'
    $aidosRoot=Split-Path $PSScriptRoot -Parent
    $newProjectTool=Join-Path $aidosRoot 'tools/New-AidosProject.ps1'
    if(-not(Test-Path -LiteralPath $newProjectTool -PathType Leaf)){throw "AIDOS runtime onboarding tool not found: $newProjectTool"}

    try{
        if(Test-Path -LiteralPath $projectPath -PathType Leaf){
            $existing=Read-AidosJson $projectPath
            if([string]$existing.project_id -ne $ProjectId){throw 'Existing PROJECT.json project_id differs from registry binding.'}
            if((ConvertTo-AidosRegistryRepositoryIdentity ([string]$existing.repository)) -ne (ConvertTo-AidosRegistryRepositoryIdentity ([string]$project.repository))){throw 'Existing PROJECT.json repository differs from registry binding.'}
            $initialized='ALREADY_INITIALIZED'
        }else{
            $runtime=$project.git_runtime
            $args=@{
                ProjectRoot=$root
                ProjectId=$ProjectId
                Repository=[string]$project.repository
                ProjectMode=[string]$project.project_mode
                DefaultBranch=[string]$project.default_branch
                RunnerPolicy=[string]$project.runner_policy
                GitRuntimeKind=[string]$runtime.kind
                GitPath=if($runtime.git_path){[string]$runtime.git_path}else{'git'}
            }
            if([string]$runtime.kind -eq 'WINDOWS_WSL'){
                $args.WslDistribution=[string]$runtime.distribution
                $args.WslProjectRoot=[string]$runtime.project_root
            }
            & $newProjectTool @args|Out-Null
            $initialized='INITIALIZED'
        }
        $binding=Test-AidosProjectBinding $root
        $git=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage 'AIDOS promote accepted preparation to runtime' -Push:$Push
        Set-AidosPreparationProjectPhase -RegistryRoot $RegistryRoot -ProjectId $ProjectId -Phase 'RUNTIME' -Status PROMOTED|Out-Null
        [pscustomobject][ordered]@{status='PROMOTED';project_id=$ProjectId;initialization=$initialized;binding=$binding;git=$git}
    }catch{
        Set-AidosPreparationProjectPhase -RegistryRoot $RegistryRoot -ProjectId $ProjectId -Phase 'RUNTIME_ONBOARDING' -Status BLOCKED|Out-Null
        throw
    }
}

Export-ModuleMember -Function Invoke-AidosPreparationRuntimeOnboarding
