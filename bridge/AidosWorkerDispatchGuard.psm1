Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousIntegration.psm1') -DisableNameChecking

function Get-AidosWorkerDispatchGuardPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/runtime/worker-dispatch/{0}-r{1}.json' -f $ExecutionId,$Revision)
}

function Assert-AidosWorkerDispatchRetryEventDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string[]]$EventPaths,
        [Parameter(Mandatory)]$Guard
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    if($EventPaths.Count-ne1){throw "Existing Worker dispatch guard retry requires exactly one dirty event log; found $($EventPaths.Count)."}
    $eventPath=[string]$EventPaths[0]
    if($eventPath-notmatch'^\.aidos/events/\d{4}-\d{2}\.jsonl$'){throw "Existing Worker dispatch guard retry has unexpected event path '$eventPath'."}
    $tracked=Invoke-AidosGit $root @('ls-files','--error-unmatch','--',$eventPath)
    $added=[Collections.Generic.List[string]]::new()
    if($tracked.ExitCode-eq0){
        $diff=Invoke-AidosGit $root @('diff','--no-ext-diff','--unified=0','--',$eventPath)
        if($diff.ExitCode-ne0){throw "Unable to inspect existing Worker dispatch guard event delta '$eventPath'."}
        foreach($lineRaw in @($diff.Output)){
            $line=[string]$lineRaw
            if($line.StartsWith('---',[StringComparison]::Ordinal)-or$line.StartsWith('+++',[StringComparison]::Ordinal)-or$line.StartsWith('@@',[StringComparison]::Ordinal)){continue}
            if($line.StartsWith('-',[StringComparison]::Ordinal)){throw 'Existing Worker dispatch guard retry event log contains a deletion or replacement.'}
            if($line.StartsWith('+',[StringComparison]::Ordinal)){$added.Add($line.Substring(1))}
        }
    }else{
        $full=Join-Path $root $eventPath
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "Existing Worker dispatch guard retry event log is missing: $eventPath"}
        foreach($line in @(Get-Content -LiteralPath $full -Encoding UTF8)){if(-not[string]::IsNullOrWhiteSpace([string]$line)){$added.Add([string]$line)}}
    }
    if($added.Count-ne1){throw "Existing Worker dispatch guard retry requires exactly one appended guard event; found $($added.Count)."}
    try{$event=$added[0]|ConvertFrom-Json -Depth 100}catch{throw 'Existing Worker dispatch guard retry event delta is not valid JSON.'}
    if([string]$event.event_type-ne'WORKER_DISPATCH_GUARD_BOUND' -or [string]$event.actor-ne'SYSTEM'){throw 'Existing Worker dispatch guard retry event is not the Core-owned guard-bound event.'}
    if([string]$event.project_id-ne[string]$Guard.project_id -or [string]$event.execution_id-ne[string]$Guard.execution_id -or [int]$event.revision-ne[int]$Guard.revision){throw 'Existing Worker dispatch guard retry event binding mismatch.'}
    if($null-eq$event.payload -or [string]$event.payload.execution_id-ne[string]$Guard.execution_id -or [int]$event.payload.revision-ne[int]$Guard.revision -or [string]$event.payload.git_head-ne[string]$Guard.git_head_before -or [bool]$event.payload.repair_dispatch){throw 'Existing Worker dispatch guard retry event payload mismatch.'}
    $true
}

function Resolve-AidosReusableInitialWorkerDispatchGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$GuardPath,
        [Parameter(Mandatory)][string[]]$ChangedPaths
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    if(-not(Test-Path -LiteralPath $GuardPath -PathType Leaf)){return $null}
    $guard=Read-AidosJson $GuardPath
    $projectId=[string](Get-AidosProjectProfile $root).project_id
    if([string]$guard.status-ne'BOUND'){throw "Existing Worker dispatch guard cannot be reused from status '$($guard.status)'."}
    if([string]$guard.project_id-ne$projectId -or [string]$guard.execution_id-ne[string]$State.execution_id -or [int]$guard.revision-ne[int]$State.revision){throw 'Existing Worker dispatch guard binding differs from the current TASK_READY execution.'}
    if([bool]$guard.repair_dispatch -or @($guard.preexisting_delta).Count-ne0){throw 'Existing Worker dispatch guard is not a clean initial-dispatch guard and cannot use automatic retry recovery.'}
    $headResult=Invoke-AidosGit $root @('rev-parse','HEAD')
    if($headResult.ExitCode-ne0){throw 'Unable to verify Git HEAD for existing Worker dispatch guard retry.'}
    $head=[string]($headResult.Output|Select-Object -First 1)
    if([string]$guard.git_head_before-ne$head){throw 'Existing Worker dispatch guard Git HEAD changed before retry.'}
    $guardRef=[IO.Path]::GetRelativePath($root,$GuardPath).Replace('\','/')
    if($guardRef-notin@($ChangedPaths)){throw 'Existing Worker dispatch guard retry evidence is not present in the current worktree delta.'}
    $eventPaths=@($ChangedPaths|Where-Object {$_.StartsWith('.aidos/events/',[StringComparison]::Ordinal)})
    $allowed=@($guardRef)+$eventPaths
    $unexpected=@($ChangedPaths|Where-Object {$_-notin$allowed})
    if($unexpected.Count){throw "Existing Worker dispatch guard retry has unrelated worktree changes: $($unexpected -join ', ')"}
    Assert-AidosWorkerDispatchRetryEventDelta -ProjectRoot $root -EventPaths $eventPaths -Guard $guard|Out-Null
    [pscustomobject]$guard
}

function New-AidosWorkerDispatchGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$state=Get-AidosState $root
    if([string]$state.state-ne'TASK_READY' -or [string]::IsNullOrWhiteSpace([string]$state.execution_id)-or$null-eq$state.revision){throw 'Worker dispatch guard requires exact TASK_READY execution binding.'}
    $executionPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision);$execution=Read-AidosJson $executionPath
    $guardPath=Get-AidosWorkerDispatchGuardPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision)
    $changed=@(Get-AidosIntegrationChangedPaths -ProjectRoot $root)
    $hasRepair=$execution.scope -and $execution.scope.PSObject.Properties['repair'] -and $null-ne$execution.scope.repair
    if(-not$hasRepair -and (Test-Path -LiteralPath $guardPath -PathType Leaf)){
        $reusable=Resolve-AidosReusableInitialWorkerDispatchGuard -ProjectRoot $root -State $state -GuardPath $guardPath -ChangedPaths $changed
        if($null-ne$reusable){return $reusable}
    }
    if(-not$hasRepair -and $changed.Count){throw "Initial Worker dispatch requires a clean worktree; found: $($changed -join ', ')"}
    foreach($path in $changed){if(-not(Test-AidosIntegrationPathAuthorized -Execution $execution -Path $path)){throw "Pre-dispatch changed path is outside Worker authority: $path"}}
    $headResult=Invoke-AidosGit $root @('rev-parse','HEAD');if($headResult.ExitCode-ne0){throw 'Unable to bind Worker dispatch to current Git HEAD.'};$head=[string]($headResult.Output|Select-Object -First 1)
    $guard=[ordered]@{schema_version='0.1';project_id=[string](Get-AidosProjectProfile $root).project_id;execution_id=[string]$state.execution_id;revision=[int]$state.revision;git_head_before=$head;preexisting_delta=@($changed);repair_dispatch=[bool]$hasRepair;status='BOUND';created_at=[DateTimeOffset]::UtcNow.ToString('o');checked_at=$null;git_head_after=$null}
    Write-AidosJsonAtomic $guardPath $guard
    Add-AidosEvent -ProjectRoot $root -EventType 'WORKER_DISPATCH_GUARD_BOUND' -Actor SYSTEM -Payload @{execution_id=[string]$state.execution_id;revision=[int]$state.revision;git_head=$head;repair_dispatch=[bool]$hasRepair}|Out-Null
    [pscustomobject]$guard
}
function Test-AidosWorkerDispatchGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$guardPath=Get-AidosWorkerDispatchGuardPath -ProjectRoot $root -ExecutionId $ExecutionId -Revision $Revision
    if(-not(Test-Path -LiteralPath $guardPath -PathType Leaf)){throw 'Worker dispatch guard evidence is missing.'}
    $guard=Read-AidosJson $guardPath;$headResult=Invoke-AidosGit $root @('rev-parse','HEAD');if($headResult.ExitCode-ne0){throw 'Unable to verify post-Worker Git HEAD.'};$head=[string]($headResult.Output|Select-Object -First 1)
    $guard.git_head_after=$head;$guard.checked_at=[DateTimeOffset]::UtcNow.ToString('o')
    if([string]$guard.git_head_before-ne$head){
        $guard.status='AUTHORITY_VIOLATION';Write-AidosJsonAtomic $guardPath $guard
        $state=Get-AidosState $root
        if([string]$state.state-ne'RECOVERY_REQUIRED'){Set-AidosState -ProjectRoot $root -NewState RECOVERY_REQUIRED -Actor SYSTEM -Patch @{}|Out-Null}
        Add-AidosEvent -ProjectRoot $root -EventType 'WORKER_GIT_AUTHORITY_VIOLATION' -Actor SYSTEM -Payload @{execution_id=$ExecutionId;revision=$Revision;git_head_before=[string]$guard.git_head_before;git_head_after=$head}|Out-Null
        return [pscustomobject][ordered]@{status='AUTHORITY_VIOLATION';git_head_before=[string]$guard.git_head_before;git_head_after=$head}
    }
    $guard.status='PASS';Write-AidosJsonAtomic $guardPath $guard
    [pscustomobject][ordered]@{status='PASS';git_head_before=[string]$guard.git_head_before;git_head_after=$head}
}

Export-ModuleMember -Function Get-AidosWorkerDispatchGuardPath,New-AidosWorkerDispatchGuard,Test-AidosWorkerDispatchGuard
