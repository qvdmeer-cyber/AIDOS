Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking

function ConvertTo-AidosRepositoryHandoffGitPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $value=$Path.Replace('\','/').Trim()
    if($value.StartsWith('./',[StringComparison]::Ordinal)){$value=$value.Substring(2)}
    if([string]::IsNullOrWhiteSpace($value) -or [IO.Path]::IsPathRooted($value) -or $value.StartsWith('../',[StringComparison]::Ordinal) -or $value.Contains('/../',[StringComparison]::Ordinal)){throw "Invalid handoff persistence path '$Path'."}
    $value
}

function Get-AidosRepositoryHandoffChangedPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    $status=Invoke-AidosRegisteredGit -Project $Project -Arguments @('status','--porcelain=v1')
    if($status.ExitCode-ne0){throw 'Unable to inspect repository handoff worktree.'}
    $items=[Collections.Generic.List[object]]::new()
    foreach($line in @($status.Output)){
        $text=[string]$line
        if([string]::IsNullOrWhiteSpace($text) -or $text.Length-lt4){continue}
        $path=$text.Substring(3).Trim()
        if($path -match ' -> '){$path=($path -split ' -> ')[-1]}
        $items.Add([pscustomobject][ordered]@{index=$text.Substring(0,1);worktree=$text.Substring(1,1);path=(ConvertTo-AidosRepositoryHandoffGitPath -Path $path);raw=$text})
    }
    $items.ToArray()
}

function Invoke-AidosRepositoryHandoffGitPersistence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter(Mandatory)][string]$CommitMessage,
        [switch]$Push
    )
    Test-AidosRegistryProjectBinding -Project $Project|Out-Null
    $requested=@($Paths|ForEach-Object {ConvertTo-AidosRepositoryHandoffGitPath -Path $_}|Select-Object -Unique)
    if($requested.Count-eq0){throw 'Handoff persistence requires at least one path.'}
    foreach($path in $requested){if(-not(Test-AidosAllowedPersistencePath -Project $Project -Path $path)){throw "Unauthorized handoff persistence path: $path"}}

    $changed=@(Get-AidosRepositoryHandoffChangedPaths -Project $Project)
    $changedByPath=@{};foreach($item in $changed){$changedByPath[[string]$item.path]=$item}
    $effective=@($requested|Where-Object {$changedByPath.ContainsKey($_)})
    if($effective.Count-eq0){return [pscustomobject][ordered]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@();uncommitted_paths=@($changed|ForEach-Object path)}}

    $staged=Invoke-AidosRegisteredGit -Project $Project -Arguments @('diff','--cached','--name-only')
    if($staged.ExitCode-ne0){throw 'Unable to inspect staged repository paths.'}
    $requestedSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($path in $effective){[void]$requestedSet.Add($path)}
    foreach($line in @($staged.Output)){
        $path=ConvertTo-AidosRepositoryHandoffGitPath -Path ([string]$line)
        if(-not$requestedSet.Contains($path)){throw "Pre-staged non-handoff path blocks scoped persistence: $path"}
    }

    foreach($path in $effective){
        $add=Invoke-AidosRegisteredGit -Project $Project -Arguments @('add','--',$path)
        if($add.ExitCode-ne0){throw "git add failed for handoff path '$path'."}
    }
    $commitArguments=@('commit','-m',$CommitMessage,'--')+$effective
    $commit=Invoke-AidosRegisteredGit -Project $Project -Arguments $commitArguments
    if($commit.ExitCode-ne0){throw "Scoped handoff git commit failed: $($commit.Output -join '; ')"}
    $head=Invoke-AidosRegisteredGit -Project $Project -Arguments @('rev-parse','HEAD')
    if($head.ExitCode-ne0-or$head.Output.Count-eq0){throw 'Unable to read scoped handoff commit.'}
    $sha=[string]$head.Output[0]
    $committed=Invoke-AidosRegisteredGit -Project $Project -Arguments @('show','--pretty=format:','--name-only',$sha)
    if($committed.ExitCode-ne0){throw 'Unable to verify scoped handoff commit.'}
    $committedPaths=@($committed.Output|Where-Object {-not[string]::IsNullOrWhiteSpace([string]$_)}|ForEach-Object {ConvertTo-AidosRepositoryHandoffGitPath -Path ([string]$_)})
    foreach($path in $committedPaths){if(-not$requestedSet.Contains($path)){throw "Scoped handoff commit unexpectedly contains '$path'."}}
    $pushed=$false
    if($Push){$pushResult=Invoke-AidosRegisteredGit -Project $Project -Arguments @('push');if($pushResult.ExitCode-ne0){throw 'git push failed after scoped handoff commit.'};$pushed=$true}
    $remaining=@(Get-AidosRepositoryHandoffChangedPaths -Project $Project|ForEach-Object path)
    [pscustomobject][ordered]@{status='PERSISTED';commit=$sha;pushed=$pushed;paths=$committedPaths;uncommitted_paths=$remaining}
}

Export-ModuleMember -Function ConvertTo-AidosRepositoryHandoffGitPath,Get-AidosRepositoryHandoffChangedPaths,Invoke-AidosRepositoryHandoffGitPersistence
