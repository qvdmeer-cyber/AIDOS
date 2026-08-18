Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking

function Get-AidosIntegrationIntentRoot {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/runtime/integration'
}
function Get-AidosIntegrationIntentPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId)
    Join-Path (Get-AidosIntegrationIntentRoot $ProjectRoot) ($ReviewId+'.json')
}
function New-AidosPassIntegrationIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$path=Get-AidosIntegrationIntentPath -ProjectRoot $root -ReviewId $ReviewId
    if(Test-Path -LiteralPath $path -PathType Leaf){
        $existing=Read-AidosJson $path
        if([string]$existing.review_id-ne$ReviewId -or [string]$existing.execution_id-ne$ExecutionId -or [int]$existing.revision-ne$Revision){throw 'Existing integration intent binding mismatch.'}
        return [pscustomobject]$existing
    }
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $intent=[ordered]@{schema_version='0.1';project_id=[string](Get-AidosProjectProfile $root).project_id;review_id=$ReviewId;execution_id=$ExecutionId;revision=$Revision;status='PENDING';integration_commit=$null;created_at=$now;updated_at=$now;applied_at=$null;error=$null}
    Write-AidosJsonAtomic $path $intent
    Add-AidosEvent -ProjectRoot $root -EventType 'EXECUTION_INTEGRATION_REQUIRED' -Actor SYSTEM -Payload @{review_id=$ReviewId;execution_id=$ExecutionId;revision=$Revision}|Out-Null
    [pscustomobject]$intent
}
function Get-AidosPendingIntegrationIntents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $dir=Get-AidosIntegrationIntentRoot $ProjectRoot
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){return @()}
    @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File|Sort-Object Name|ForEach-Object {$x=Read-AidosJson $_.FullName;if([string]$x.status-ne'APPLIED'){$x}})
}
function Test-AidosIntegrationPathAuthorized {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Execution,[Parameter(Mandatory)][string]$Path)
    $relative=$Path.Replace('\','/').TrimStart('./')
    if($relative -eq '.aidos' -or $relative.StartsWith('.aidos/',[StringComparison]::Ordinal)){return $true}
    foreach($allowedRaw in @($Execution.authority.filesystem_write)){
        $allowed=([string]$allowedRaw).Replace('\','/').Trim()
        if($allowed -in @('.','./','')){return $true}
        $allowed=$allowed.TrimStart('./').TrimEnd('/')
        if($relative-eq$allowed -or $relative.StartsWith($allowed+'/',[StringComparison]::Ordinal)){return $true}
    }
    $false
}
function Get-AidosIntegrationChangedPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$status=Invoke-AidosGit $root @('status','--porcelain=v1','--untracked-files=all')
    if($status.ExitCode-ne0){throw 'Unable to inspect Worker integration worktree.'}
    $paths=[Collections.Generic.List[string]]::new()
    foreach($line in @($status.Output)){
        if([string]::IsNullOrWhiteSpace([string]$line)){continue}
        $path=([string]$line).Substring(3).Trim();if($path-match' -> '){$path=($path-split' -> ')[-1]};$paths.Add($path.Replace('\','/'))
    }
    @($paths)
}
function Invoke-AidosPassIntegration {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$ReviewId,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$intentPath=Get-AidosIntegrationIntentPath -ProjectRoot $root -ReviewId $ReviewId
    if(-not(Test-Path -LiteralPath $intentPath -PathType Leaf)){throw 'PASS integration intent is missing.'}
    $intent=Read-AidosJson $intentPath
    if([string]$intent.status-eq'APPLIED'){return [pscustomobject][ordered]@{status='ALREADY_APPLIED';review_id=$ReviewId;commit=[string]$intent.integration_commit}}
    $review=Read-AidosReviewRecord -ProjectRoot $root -ReviewId $ReviewId
    if(-not$review.decision -or [string]$review.decision.outcome-ne'PASS'){throw 'Integration requires an accepted PASS review decision.'}
    if([string]$review.execution_id-ne[string]$intent.execution_id -or [int]$review.revision-ne[int]$intent.revision){throw 'Integration review/intent binding mismatch.'}
    $executionPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$intent.execution_id) -Revision ([int]$intent.revision)
    if(-not(Test-Path -LiteralPath $executionPath -PathType Leaf)){throw 'Integration Execution artifact is missing.'}
    $execution=Read-AidosJson $executionPath;Assert-AidosExecutionBinding -ProjectRoot $root -Execution $execution|Out-Null
    $validationPath=Join-Path (Split-Path -Parent $executionPath) 'VALIDATION.json'
    if(-not(Test-Path -LiteralPath $validationPath -PathType Leaf) -or [string](Read-AidosJson $validationPath).status-ne'PASS'){throw 'Integration requires PASS deterministic validation evidence.'}

    $integrationMessage="AIDOS accept execution $($intent.execution_id) revision $($intent.revision) review $ReviewId"
    $headMessage=(Invoke-AidosGit $root @('log','-1','--format=%s')).Output|Select-Object -First 1
    $integrationCommit=$null
    if([string]$headMessage-eq$integrationMessage){
        $integrationCommit=(Invoke-AidosGit $root @('rev-parse','HEAD')).Output|Select-Object -First 1
    }else{
        $paths=@(Get-AidosIntegrationChangedPaths -ProjectRoot $root)
        if($paths.Count-eq0){throw 'PASS review has no Worker/integration delta to persist.'}
        foreach($path in $paths){if(-not(Test-AidosIntegrationPathAuthorized -Execution $execution -Path $path)){throw "Unauthorized Worker/integration path blocks PASS: $path"}}
        foreach($path in $paths){$added=Invoke-AidosGit $root @('add','--',$path);if($added.ExitCode-ne0){throw "git add failed for integration path '$path'."}}
        $commit=Invoke-AidosGit $root @('commit','-m',$integrationMessage);if($commit.ExitCode-ne0){throw 'AIDOS integration commit failed.'}
        $integrationCommit=(Invoke-AidosGit $root @('rev-parse','HEAD')).Output|Select-Object -First 1
    }
    if($Push){$pushed=Invoke-AidosGit $root @('push');if($pushed.ExitCode-ne0){throw 'AIDOS integration push failed; integration intent remains pending for retry.'}}

    $intent=Read-AidosJson $intentPath;$intent.status='APPLIED';$intent.integration_commit=[string]$integrationCommit;$intent.updated_at=[DateTimeOffset]::UtcNow.ToString('o');$intent.applied_at=$intent.updated_at;$intent.error=$null;Write-AidosJsonAtomic $intentPath $intent
    Add-AidosEvent -ProjectRoot $root -EventType 'EXECUTION_INTEGRATED' -Actor SYSTEM -Payload @{review_id=$ReviewId;execution_id=[string]$intent.execution_id;revision=[int]$intent.revision;commit=[string]$integrationCommit;pushed=[bool]$Push}|Out-Null
    $closePaths=@(Get-AidosIntegrationChangedPaths -ProjectRoot $root)
    foreach($path in $closePaths){if(-not(Test-AidosIntegrationPathAuthorized -Execution $execution -Path $path)){throw "Unauthorized path appeared while closing integration: $path"}}
    if($closePaths.Count){
        foreach($path in $closePaths){$added=Invoke-AidosGit $root @('add','--',$path);if($added.ExitCode-ne0){throw "git add failed while closing integration '$path'."}}
        $closeMessage="AIDOS close integration $ReviewId"
        $closed=Invoke-AidosGit $root @('commit','-m',$closeMessage);if($closed.ExitCode-ne0){throw 'AIDOS integration closure commit failed.'}
        if($Push){$p=Invoke-AidosGit $root @('push');if($p.ExitCode-ne0){throw 'AIDOS integration closure push failed.'}}
    }
    [pscustomobject][ordered]@{status='APPLIED';review_id=$ReviewId;execution_id=[string]$intent.execution_id;revision=[int]$intent.revision;commit=[string]$integrationCommit;pushed=[bool]$Push}
}
function Invoke-AidosReviewIntegrationTick {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[int]$MaxItems=1,[switch]$Push)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects';$results=[Collections.Generic.List[object]]::new();$processed=0
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return [pscustomobject][ordered]@{status='IDLE';processed=0;results=@()}}
    foreach($file in @(Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File|Sort-Object Name)){
        if($processed-ge$MaxItems){break};$project=Read-AidosJson $file.FullName
        if([string]$project.stage-ne'RUNTIME' -or [string]$project.status-ne'PROMOTED'){continue}
        foreach($intent in @(Get-AidosPendingIntegrationIntents -ProjectRoot ([string]$project.local_root))){
            if($processed-ge$MaxItems){break}
            try{$outcome=Invoke-AidosPassIntegration -Project $project -ReviewId ([string]$intent.review_id) -Push:$Push;$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;review_id=[string]$intent.review_id;status=[string]$outcome.status;outcome=$outcome})}
            catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;review_id=[string]$intent.review_id;status='INTEGRATION_ERROR';error=$_.Exception.Message})}
            $processed++
        }
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object {$_.status-eq'INTEGRATION_ERROR'}).Count){'ERROR'}elseif($processed-gt0){'PROCESSED'}else{'IDLE'};processed=$processed;results=@($results)}
}

Export-ModuleMember -Function Get-AidosIntegrationIntentRoot,Get-AidosIntegrationIntentPath,New-AidosPassIntegrationIntent,Get-AidosPendingIntegrationIntents,Test-AidosIntegrationPathAuthorized,Get-AidosIntegrationChangedPaths,Invoke-AidosPassIntegration,Invoke-AidosReviewIntegrationTick
