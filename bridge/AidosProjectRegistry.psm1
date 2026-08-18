Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking

function ConvertTo-AidosRegistryRepositoryIdentity {
    param([Parameter(Mandatory)][string]$Repository)
    $v=$Repository.Trim().TrimEnd('/')
    if($v-match'^https?://[^/]+/(.+)$'){$v=$Matches[1]}
    elseif($v-match'^ssh://[^/]+/(.+)$'){$v=$Matches[1]}
    elseif($v-match'^[^@]+@[^:]+:(.+)$'){$v=$Matches[1]}
    if($v.EndsWith('.git',[StringComparison]::OrdinalIgnoreCase)){$v=$v.Substring(0,$v.Length-4)}
    $v.ToLowerInvariant()
}

function Get-AidosRegistryProjectPath {
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    Join-Path $RegistryRoot ('projects/{0}.json' -f $ProjectId)
}

function Register-AidosPreparationProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$LocalRoot,
        [ValidateSet('NEW_PROJECT','EXISTING_PROJECT')][string]$ProjectMode='EXISTING_PROJECT',
        [string]$DefaultBranch='main',
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$RunnerPolicy='SUPERVISED',
        [ValidateSet('NATIVE','WINDOWS_WSL')][string]$GitRuntimeKind='NATIVE',
        [string]$WslDistribution,
        [string]$WslProjectRoot,
        [string]$GitPath='git',
        [string[]]$AllowedPersistencePaths=@('.aidos')
    )
    $registry=[IO.Path]::GetFullPath($RegistryRoot)
    $path=Get-AidosRegistryProjectPath $registry $ProjectId
    if(Test-Path -LiteralPath $path){throw "Project '$ProjectId' is already registered."}
    $local=(Resolve-AidosFileSystemPath $LocalRoot)
    $gitRuntime=if($GitRuntimeKind -eq 'NATIVE'){
        [ordered]@{kind='NATIVE';project_root=$local;git_path=$GitPath}
    }else{
        if([string]::IsNullOrWhiteSpace($WslDistribution)-or[string]::IsNullOrWhiteSpace($WslProjectRoot)){throw 'WINDOWS_WSL requires distribution and WSL project root.'}
        [ordered]@{kind='WINDOWS_WSL';distribution=$WslDistribution;project_root=$WslProjectRoot;git_path=$GitPath}
    }
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $record=[ordered]@{
        schema_version='0.2';project_id=$ProjectId;repository=$Repository;local_root=$local;stage='PREPARATION';
        preparation_phase='PROJECT_BASELINE';status='ACTIVE';project_mode=$ProjectMode;default_branch=$DefaultBranch;runner_policy=$RunnerPolicy;git_runtime=$gitRuntime;
        allowed_persistence_paths=@($AllowedPersistencePaths);registered_at=$now;updated_at=$now;promoted_at=$null
    }
    Write-AidosJsonAtomic $path $record
    [pscustomobject]$record
}

function Get-AidosRegisteredProject {
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    $path=Get-AidosRegistryProjectPath ([IO.Path]::GetFullPath($RegistryRoot)) $ProjectId
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Registered project not found: $ProjectId"}
    Read-AidosJson $path
}

function Get-AidosRegisteredGitCommand {
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string[]]$Arguments)
    $runtime=$Project.git_runtime
    if([string]$runtime.kind -eq 'NATIVE'){
        $gitPath=if($runtime.git_path){[string]$runtime.git_path}else{'git'}
        return [pscustomobject]@{FileName=$gitPath;Arguments=@('-C',[string]$runtime.project_root)+$Arguments}
    }
    if([string]$runtime.kind -eq 'WINDOWS_WSL'){
        $gitPath=if($runtime.git_path){[string]$runtime.git_path}else{'git'}
        return [pscustomobject]@{FileName='wsl.exe';Arguments=@('--distribution',[string]$runtime.distribution,'--cd',[string]$runtime.project_root,'--exec',$gitPath,'-C',[string]$runtime.project_root)+$Arguments}
    }
    throw "Unsupported registry Git runtime '$($runtime.kind)'."
}

function Invoke-AidosRegisteredGit {
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string[]]$Arguments)
    $cmd=Get-AidosRegisteredGitCommand $Project $Arguments
    $output=@(&$cmd.FileName @($cmd.Arguments) 2>&1);$code=$LASTEXITCODE
    [pscustomobject]@{ExitCode=$code;Output=$output;Command=$cmd}
}

function Test-AidosRegistryProjectBinding {
    param([Parameter(Mandatory)]$Project)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $origin=Invoke-AidosRegisteredGit $Project @('remote','get-url','origin')
    if($origin.ExitCode-ne0-or$origin.Output.Count-eq0){throw 'Registered project Git origin is unavailable.'}
    if((ConvertTo-AidosRegistryRepositoryIdentity ([string]$origin.Output[0]))-ne(ConvertTo-AidosRegistryRepositoryIdentity ([string]$Project.repository))){throw 'Registered project origin does not match registry repository.'}
    [pscustomobject]@{project_id=[string]$Project.project_id;root=$root;repository=[string]$Project.repository;valid=$true}
}

function Sync-AidosRegisteredPreparationProject {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    Test-AidosRegistryProjectBinding $Project|Out-Null
    $status=Invoke-AidosRegisteredGit $Project @('status','--porcelain=v1')
    if($status.ExitCode-ne0){throw 'Unable to inspect registered project before synchronization.'}
    if(@($status.Output|Where-Object {-not[string]::IsNullOrWhiteSpace([string]$_)}).Count -gt 0){throw 'Preparation project synchronization requires a clean worktree.'}
    $pull=Invoke-AidosRegisteredGit $Project @('pull','--ff-only')
    if($pull.ExitCode-ne0){throw "Preparation project fast-forward synchronization failed: $($pull.Output -join '; ')"}
    $head=Invoke-AidosRegisteredGit $Project @('rev-parse','HEAD')
    [pscustomobject]@{status='SYNCED';project_id=[string]$Project.project_id;head=if($head.ExitCode-eq0-and$head.Output.Count){[string]$head.Output[0]}else{$null};output=@($pull.Output)}
}

function Test-AidosAllowedPersistencePath {
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$Path)
    $normalized=$Path.Replace('\\','/').TrimStart('./')
    foreach($allowed in @($Project.allowed_persistence_paths)){
        $a=([string]$allowed).Replace('\\','/').Trim('/','.')
        if($normalized -eq $a -or $normalized.StartsWith($a+'/',[StringComparison]::Ordinal)){return $true}
    }
    $false
}

function Invoke-AidosPreparationGitPersistence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$CommitMessage,
        [switch]$Push
    )
    Test-AidosRegistryProjectBinding $Project|Out-Null
    $status=Invoke-AidosRegisteredGit $Project @('status','--porcelain=v1')
    if($status.ExitCode-ne0){throw 'Unable to inspect registered project worktree.'}
    $changed=@()
    foreach($line in @($status.Output)){
        if([string]::IsNullOrWhiteSpace([string]$line)){continue}
        $path=([string]$line).Substring(3).Trim()
        if($path -match ' -> '){$path=($path -split ' -> ')[-1]}
        if(-not(Test-AidosAllowedPersistencePath -Project $Project -Path $path)){throw "Unauthorized changed path blocks persistence: $path"}
        $changed += $path
    }
    if($changed.Count-eq0){return [pscustomobject]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}}
    foreach($path in $changed){$r=Invoke-AidosRegisteredGit $Project @('add','--',$path);if($r.ExitCode-ne0){throw "git add failed for '$path'."}}
    $commit=Invoke-AidosRegisteredGit $Project @('commit','-m',$CommitMessage)
    if($commit.ExitCode-ne0){throw 'git commit failed.'}
    $head=Invoke-AidosRegisteredGit $Project @('rev-parse','HEAD');if($head.ExitCode-ne0){throw 'Unable to read created commit.'}
    $sha=[string]$head.Output[0]
    $pushed=$false
    if($Push){$p=Invoke-AidosRegisteredGit $Project @('push');if($p.ExitCode-ne0){throw 'git push failed after commit.'};$pushed=$true}
    [pscustomobject]@{status='PERSISTED';commit=$sha;pushed=$pushed;paths=@($changed)}
}

function Set-AidosPreparationProjectPhase {
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$Phase,[ValidateSet('ACTIVE','WAITING_HUMAN','BLOCKED','READY_FOR_ONBOARDING','PROMOTED')][string]$Status='ACTIVE')
    $path=Get-AidosRegistryProjectPath ([IO.Path]::GetFullPath($RegistryRoot)) $ProjectId
    $record=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    if([string]$record.stage -eq 'RUNTIME' -and $Status -ne 'PROMOTED'){
        throw "Runtime project '$ProjectId' may not be downgraded to preparation status '$Status'."
    }
    $record.preparation_phase=$Phase;$record.status=$Status;$record.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    if($Status-eq'PROMOTED'){
        $record.stage='RUNTIME'
        $record.preparation_phase='RUNTIME'
        if([string]::IsNullOrWhiteSpace([string]$record.promoted_at)){$record.promoted_at=$record.updated_at}
    }
    Write-AidosJsonAtomic $path $record
    $record
}

Export-ModuleMember -Function ConvertTo-AidosRegistryRepositoryIdentity,Get-AidosRegistryProjectPath,Register-AidosPreparationProject,Get-AidosRegisteredProject,Get-AidosRegisteredGitCommand,Invoke-AidosRegisteredGit,Test-AidosRegistryProjectBinding,Sync-AidosRegisteredPreparationProject,Test-AidosAllowedPersistencePath,Invoke-AidosPreparationGitPersistence,Set-AidosPreparationProjectPhase
