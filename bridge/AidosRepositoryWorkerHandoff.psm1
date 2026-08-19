Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosWorkerDispatchGuard.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffPersistence.psm1') -DisableNameChecking

function Get-AidosRepositoryWorkerBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Execution)
    $state=Get-AidosState -ProjectRoot $ProjectRoot
    [pscustomobject][ordered]@{
        project_state=[string]$state.state
        definition_id=[string]$Execution.definition.id
        definition_version=[int]$Execution.definition.version
        execution_id=[string]$Execution.execution_id
        revision=[int]$Execution.revision
        review_id=$null
    }
}

function Get-AidosRepositoryWorkerSourceRefs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionPath)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $refs=[Collections.Generic.List[string]]::new()
    $refs.Add([IO.Path]::GetRelativePath($root,$ExecutionPath).Replace('\','/'))
    foreach($relative in @('AGENTS.md','.aidos/AGENT_PROFILE.json','.aidos/PROJECT.json','.aidos/STATE.json')){
        if(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf){$refs.Add($relative)}
    }
    $refs.ToArray()
}

function New-AidosRepositoryWorkerAssignmentBody {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Execution,[Parameter(Mandatory)][string]$PayloadRef)
    @"
# AIDOS Worker handoff

AIDOS Core assigned this execution to the Codex Worker.

- Project: $([string]$Execution.project_id)
- Execution: $([string]$Execution.execution_id)
- Revision: $([int]$Execution.revision)
- Payload: $PayloadRef

Read the canonical HANDOFF.md and the exact execution payload. Work only inside the execution authority. Do not commit, push, create another actor assignment, or infer work from session history. AIDOS Core owns validation, review scheduling and the next handoff.
"@
}

function Get-AidosRepositoryWorkerChangedLifecyclePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    @(
        Get-AidosRepositoryHandoffChangedPaths -Project $Project |
        Where-Object {$_.path.StartsWith('.aidos/',[StringComparison]::Ordinal)} |
        ForEach-Object path
    )
}

function New-AidosRepositoryWorkerDeferredPersistence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Phase,[Parameter(Mandatory)][string[]]$Paths)
    [pscustomobject][ordered]@{
        status='DEFERRED_UNTIL_WORKER_GUARD'
        phase=$Phase
        reason='AIDOS must verify that Codex did not change Git HEAD before Core commits repository handoff lifecycle files.'
        paths=@($Paths)
        commit=$null
        pushed=$false
    }
}

function Publish-AidosRepositoryWorkerAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$ExecutionPath,
        [switch]$Push,
        [switch]$DeferPersistence
    )
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $executionPathResolved=[IO.Path]::GetFullPath($ExecutionPath)
    if(-not(Test-Path -LiteralPath $executionPathResolved -PathType Leaf)){throw 'Worker execution payload is missing.'}
    $execution=Read-AidosJson -Path $executionPathResolved
    if([string]$execution.project_id-ne[string]$Project.project_id){throw 'Worker execution project binding mismatch.'}
    $payloadRef=[IO.Path]::GetRelativePath($root,$executionPathResolved).Replace('\','/')
    $payloadSha=(Get-FileHash -LiteralPath $executionPathResolved -Algorithm SHA256).Hash.ToLowerInvariant()
    $existing=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($existing -and [string]$existing.metadata.kind-eq'ASSIGNMENT'){
        if([string]$existing.metadata.to_actor-eq'WORKER' -and [string]$existing.metadata.payload_ref-eq$payloadRef -and [string]$existing.metadata.payload_sha256-eq$payloadSha){
            return [pscustomobject][ordered]@{
                status='ALREADY_PUBLISHED'
                handoff=$existing
                execution=$execution
                persistence=[pscustomobject][ordered]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}
            }
        }
        throw 'Another repository actor assignment is already active.'
    }
    $binding=Get-AidosRepositoryWorkerBinding -ProjectRoot $root -Execution $execution
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1'
        envelope_type='AIDOS_REPOSITORY_HANDOFF'
        handoff_id=[guid]::NewGuid().ToString()
        project_id=[string]$Project.project_id
        kind='ASSIGNMENT'
        from_actor='CORE'
        to_actor='WORKER'
        status='READY'
        parent_handoff_id=if($existing){[string]$existing.metadata.handoff_id}else{$null}
        created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action='DISPATCH_EXECUTION'
        payload_ref=$payloadRef
        payload_sha256=$payloadSha
        binding=$binding
        source_refs=@(Get-AidosRepositoryWorkerSourceRefs -ProjectRoot $root -ExecutionPath $executionPathResolved)
    }
    if($existing){Test-AidosRepositoryHandoffTransition -Previous $existing -Next $metadata|Out-Null}
    $body=New-AidosRepositoryWorkerAssignmentBody -Execution $execution -PayloadRef $payloadRef
    $expectedParent=if($existing){[string]$existing.metadata.handoff_id}else{$null}
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId $expectedParent
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_WORKER_HANDOFF_PUBLISHED' -Actor SYSTEM -Payload @{
        handoff_id=[string]$metadata.handoff_id
        execution_id=[string]$execution.execution_id
        revision=[int]$execution.revision
        payload_ref=$payloadRef
        payload_sha256=$payloadSha
        persistence=if($DeferPersistence){'DEFERRED_UNTIL_WORKER_GUARD'}else{'IMMEDIATE'}
    }|Out-Null
    $changed=@(Get-AidosRepositoryWorkerChangedLifecyclePaths -Project $Project)
    $persistence=if($DeferPersistence){
        New-AidosRepositoryWorkerDeferredPersistence -Phase ASSIGNMENT -Paths $changed
    }else{
        Invoke-AidosRepositoryHandoffGitPersistence -Project $Project -Paths $changed -CommitMessage ("AIDOS publish Worker handoff $($execution.execution_id) r$($execution.revision)") -Push:$Push
    }
    [pscustomobject][ordered]@{status='PUBLISHED';handoff=$handoff;execution=$execution;persistence=$persistence}
}

function Resolve-AidosRepositoryWorkerTerminalResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$WorkerOutcome)
    $terminal=if($WorkerOutcome.PSObject.Properties['result'] -and $null-ne$WorkerOutcome.result){$WorkerOutcome.result}else{$WorkerOutcome}
    foreach($name in @('project_id','execution_id','revision','terminal_type','validation_status')){
        if(-not$terminal.PSObject.Properties[$name]){throw "Worker outcome does not expose required terminal result field '$name'."}
    }
    [pscustomobject]$terminal
}

function Publish-AidosRepositoryWorkerResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)]$WorkerResult,
        [switch]$Push,
        [switch]$DeferPersistence
    )
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $terminal=Resolve-AidosRepositoryWorkerTerminalResult -WorkerOutcome $WorkerResult
    if([string]$terminal.project_id-ne[string]$Project.project_id){throw 'Worker result project binding mismatch.'}
    $assignment=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$assignment -or [string]$assignment.metadata.kind-ne'ASSIGNMENT' -or [string]$assignment.metadata.to_actor-ne'WORKER'){throw 'Worker result requires the current WORKER assignment handoff.'}
    if([string]$assignment.metadata.binding.execution_id-ne[string]$terminal.execution_id -or [int]$assignment.metadata.binding.revision-ne[int]$terminal.revision){throw 'Worker result execution/revision differs from the current repository assignment.'}
    $resultPath=Join-Path $root ('.aidos/executions/{0}/revision-{1}/RESULT.json' -f [string]$terminal.execution_id,[int]$terminal.revision)
    if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Canonical Worker RESULT.json is missing.'}
    $payloadRef=[IO.Path]::GetRelativePath($root,$resultPath).Replace('\','/')
    $payloadSha=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $state=Get-AidosState -ProjectRoot $root
    if([string]$state.execution_id-ne[string]$terminal.execution_id -or [int]$state.revision-ne[int]$terminal.revision){throw 'Worker result differs from current AIDOS state binding.'}
    $binding=[pscustomobject][ordered]@{
        project_state=[string]$state.state
        definition_id=[string]$state.definition_id
        definition_version=if($null-eq$state.definition_version){$null}else{[int]$state.definition_version}
        execution_id=[string]$terminal.execution_id
        revision=[int]$terminal.revision
        review_id=$null
    }
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1'
        envelope_type='AIDOS_REPOSITORY_HANDOFF'
        handoff_id=[guid]::NewGuid().ToString()
        project_id=[string]$Project.project_id
        kind='RESULT'
        from_actor='WORKER'
        to_actor='CORE'
        status='READY'
        parent_handoff_id=[string]$assignment.metadata.handoff_id
        created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action='DISPATCH_EXECUTION_RESULT'
        payload_ref=$payloadRef
        payload_sha256=$payloadSha
        binding=$binding
        source_refs=@()
    }
    Test-AidosRepositoryHandoffTransition -Previous $assignment -Next $metadata|Out-Null
    $body="# AIDOS Worker result`n`nExecution $([string]$terminal.execution_id) revision $([int]$terminal.revision) finished with terminal type $([string]$terminal.terminal_type) and validation $([string]$terminal.validation_status)."
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId ([string]$assignment.metadata.handoff_id)
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_WORKER_RESULT_PUBLISHED' -Actor EXECUTION_AGENT -Payload @{
        handoff_id=[string]$metadata.handoff_id
        parent_handoff_id=[string]$metadata.parent_handoff_id
        execution_id=[string]$terminal.execution_id
        revision=[int]$terminal.revision
        payload_ref=$payloadRef
        payload_sha256=$payloadSha
        persistence=if($DeferPersistence){'DEFERRED_UNTIL_WORKER_GUARD'}else{'IMMEDIATE'}
    }|Out-Null
    $changed=@(Get-AidosRepositoryWorkerChangedLifecyclePaths -Project $Project)
    $persistence=if($DeferPersistence){
        New-AidosRepositoryWorkerDeferredPersistence -Phase RESULT -Paths $changed
    }else{
        Invoke-AidosRepositoryHandoffGitPersistence -Project $Project -Paths $changed -CommitMessage ("AIDOS publish Worker result $($terminal.execution_id) r$($terminal.revision)") -Push:$Push
    }
    [pscustomobject][ordered]@{status='PUBLISHED';handoff=$handoff;worker_result=$terminal;persistence=$persistence}
}

function Complete-AidosRepositoryWorkerHandoffPersistence {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$handoff -or [string]$handoff.metadata.kind-ne'RESULT' -or [string]$handoff.metadata.from_actor-ne'WORKER' -or [string]$handoff.metadata.to_actor-ne'CORE' -or [string]$handoff.metadata.action-ne'DISPATCH_EXECUTION_RESULT'){
        return [pscustomobject][ordered]@{status='NO_WORKER_RESULT_HANDOFF';persistence=$null}
    }
    $executionId=[string]$handoff.metadata.binding.execution_id
    $revision=[int]$handoff.metadata.binding.revision
    $guardPath=Get-AidosWorkerDispatchGuardPath -ProjectRoot $root -ExecutionId $executionId -Revision $revision
    if(-not(Test-Path -LiteralPath $guardPath -PathType Leaf)){throw 'Repository Worker handoff finalization requires dispatch guard evidence.'}
    $guard=Read-AidosJson -Path $guardPath
    if([string]$guard.status-ne'PASS'){throw "Repository Worker handoff finalization requires PASS dispatch guard, found '$($guard.status)'."}
    $changedBefore=@(Get-AidosRepositoryWorkerChangedLifecyclePaths -Project $Project)
    if($changedBefore.Count-eq0){
        return [pscustomobject][ordered]@{
            status='ALREADY_FINALIZED'
            execution_id=$executionId
            revision=$revision
            handoff_id=[string]$handoff.metadata.handoff_id
            persistence=[pscustomobject][ordered]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}
        }
    }
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_WORKER_HANDOFF_FINALIZED' -Actor SYSTEM -Payload @{
        handoff_id=[string]$handoff.metadata.handoff_id
        execution_id=$executionId
        revision=$revision
        guard_path=[IO.Path]::GetRelativePath($root,$guardPath).Replace('\','/')
        guard_status='PASS'
    }|Out-Null
    $changed=@(Get-AidosRepositoryWorkerChangedLifecyclePaths -Project $Project)
    $persistence=Invoke-AidosRepositoryHandoffGitPersistence -Project $Project -Paths $changed -CommitMessage ("AIDOS finalize Worker handoff $executionId r$revision") -Push:$Push
    [pscustomobject][ordered]@{
        status='FINALIZED'
        execution_id=$executionId
        revision=$revision
        handoff_id=[string]$handoff.metadata.handoff_id
        persistence=$persistence
    }
}

function Invoke-AidosRepositoryWorkerFinalizationFromManagerResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)]$ManagerResult,
        [switch]$Push
    )
    $results=[Collections.Generic.List[object]]::new()
    foreach($item in @($ManagerResult.results)){
        if([string]$item.status-ne'WORKER_DISPATCHED'){continue}
        $projectId=[string]$item.project_id
        try{
            $project=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId $projectId
            $finalized=Complete-AidosRepositoryWorkerHandoffPersistence -Project $project -Push:$Push
            if($item.activation){$item.activation|Add-Member -NotePropertyName repository_handoff_finalization -NotePropertyValue $finalized -Force}
            $results.Add([pscustomobject][ordered]@{project_id=$projectId;status=[string]$finalized.status;finalization=$finalized})
        }catch{
            try{
                $project=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId $projectId
                $state=Get-AidosState -ProjectRoot ([string]$project.local_root)
                if([string]$state.state-ne'RECOVERY_REQUIRED'){Set-AidosState -ProjectRoot ([string]$project.local_root) -NewState RECOVERY_REQUIRED -Actor SYSTEM -Patch @{}|Out-Null}
            }catch{}
            $item.status='ACTIVATION_ERROR'
            $errorResult=[pscustomobject][ordered]@{status='ERROR';error=$_.Exception.Message}
            if($item.activation){$item.activation|Add-Member -NotePropertyName repository_handoff_finalization -NotePropertyValue $errorResult -Force}
            $results.Add([pscustomobject][ordered]@{project_id=$projectId;status='ERROR';error=$_.Exception.Message})
        }
    }
    $status=if(@($results|Where-Object status -eq'ERROR').Count){'ERROR'}elseif($results.Count){'PROCESSED'}else{'IDLE'}
    if($status-eq'ERROR' -and $ManagerResult.PSObject.Properties['status']){$ManagerResult.status='ERROR'}
    [pscustomobject][ordered]@{status=$status;processed=$results.Count;results=$results.ToArray()}
}

function Invoke-AidosRepositoryWorkerHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$ExecutionPath,
        [switch]$Push,
        [scriptblock]$CodexInvoker
    )
    # Core-owned lifecycle commits are deliberately deferred until the existing
    # Worker dispatch guard proves that Codex did not change Git HEAD.
    $assignment=Publish-AidosRepositoryWorkerAssignment -Project $Project -ExecutionPath $ExecutionPath -Push:$Push -DeferPersistence
    $prompt='Read .aidos/HANDOFF.md and execute the exact bound Worker assignment. Use the repository as transport. Do not commit or push. Do not create the next actor handoff; AIDOS Core owns validation and scheduling.'
    $worker=if($CodexInvoker){
        & $CodexInvoker $Project $ExecutionPath $prompt
    }else{
        Invoke-AidosAutonomousCodexExecution -ProjectRoot ([string]$Project.local_root) -ExecutionPath $ExecutionPath -Prompt $prompt
    }
    $terminal=Resolve-AidosRepositoryWorkerTerminalResult -WorkerOutcome $worker
    $result=Publish-AidosRepositoryWorkerResult -Project $Project -WorkerResult $terminal -Push:$Push -DeferPersistence
    $status=if($worker.PSObject.Properties['status'] -and -not[string]::IsNullOrWhiteSpace([string]$worker.status)){[string]$worker.status}else{[string](Get-AidosState -ProjectRoot ([string]$Project.local_root)).state}
    [pscustomobject][ordered]@{
        status=$status
        assignment_handoff=$assignment
        worker=$worker
        terminal_result=$terminal
        result_handoff=$result
        persistence=[pscustomobject][ordered]@{
            status='DEFERRED_UNTIL_WORKER_GUARD'
            reason='The repository bridge finalizes all .aidos lifecycle files only after Test-AidosWorkerDispatchGuard returns PASS.'
        }
    }
}

Export-ModuleMember -Function Get-AidosRepositoryWorkerBinding,Get-AidosRepositoryWorkerSourceRefs,New-AidosRepositoryWorkerAssignmentBody,Get-AidosRepositoryWorkerChangedLifecyclePaths,New-AidosRepositoryWorkerDeferredPersistence,Publish-AidosRepositoryWorkerAssignment,Resolve-AidosRepositoryWorkerTerminalResult,Publish-AidosRepositoryWorkerResult,Complete-AidosRepositoryWorkerHandoffPersistence,Invoke-AidosRepositoryWorkerFinalizationFromManagerResult,Invoke-AidosRepositoryWorkerHandoff
