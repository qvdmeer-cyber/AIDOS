Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousIntegration.psm1') -DisableNameChecking

function Get-AidosWorkerDispatchGuardPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/runtime/worker-dispatch/{0}-r{1}.json' -f $ExecutionId,$Revision)
}
function New-AidosWorkerDispatchGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$state=Get-AidosState $root
    if([string]$state.state-ne'TASK_READY' -or [string]::IsNullOrWhiteSpace([string]$state.execution_id)-or$null-eq$state.revision){throw 'Worker dispatch guard requires exact TASK_READY execution binding.'}
    $executionPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision);$execution=Read-AidosJson $executionPath
    $changed=@(Get-AidosIntegrationChangedPaths -ProjectRoot $root)
    $hasRepair=$execution.scope -and $execution.scope.PSObject.Properties['repair'] -and $null-ne$execution.scope.repair
    if(-not$hasRepair -and $changed.Count){throw "Initial Worker dispatch requires a clean worktree; found: $($changed -join ', ')"}
    foreach($path in $changed){if(-not(Test-AidosIntegrationPathAuthorized -Execution $execution -Path $path)){throw "Pre-dispatch changed path is outside Worker authority: $path"}}
    $headResult=Invoke-AidosGit $root @('rev-parse','HEAD');if($headResult.ExitCode-ne0){throw 'Unable to bind Worker dispatch to current Git HEAD.'};$head=[string]($headResult.Output|Select-Object -First 1)
    $guardPath=Get-AidosWorkerDispatchGuardPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision)
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
