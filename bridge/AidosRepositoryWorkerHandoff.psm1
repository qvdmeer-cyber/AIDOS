Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosWorkerDispatchGuard.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking

function Resolve-AidosRepositoryWorkerHandoffModulePath {
    [CmdletBinding()]
    param(
        [string]$ModuleRoot=$PSScriptRoot,
        [object[]]$LoadedModules=@(Get-Module -All)
    )
    $root=[IO.Path]::GetFullPath($ModuleRoot)
    $comparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    $candidates=[Collections.Generic.List[string]]::new()
    foreach($module in @($LoadedModules)){
        if($null-eq$module -or -not$module.PSObject.Properties['Path']){continue}
        $path=[string]$module.Path
        if([string]::IsNullOrWhiteSpace($path)){continue}
        try{$full=[IO.Path]::GetFullPath($path)}catch{continue}
        $directory=[IO.Path]::GetDirectoryName($full)
        $name=[IO.Path]::GetFileName($full)
        if(-not[string]::Equals($directory,$root,$comparison)){continue}
        if($name-notmatch'^AidosRepositoryHandoff\.runtime\.[0-9a-fA-F]{32}\.psm1$'){continue}
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){continue}
        $candidates.Add($full)|Out-Null
    }
    $runtimePaths=@($candidates|Sort-Object -Unique)
    if($runtimePaths.Count-gt1){throw "Worker handoff runtime has $($runtimePaths.Count) loaded repository handoff modules; refusing ambiguous WSL routing."}
    if($runtimePaths.Count-eq1){return [string]$runtimePaths[0]}
    Join-Path $root 'AidosRepositoryHandoff.psm1'
}

$canonicalRepositoryHandoffModulePath=Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1'
$repositoryHandoffModulePath=Resolve-AidosRepositoryWorkerHandoffModulePath
$modulePathComparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
if([string]::Equals([IO.Path]::GetFullPath($repositoryHandoffModulePath),[IO.Path]::GetFullPath($canonicalRepositoryHandoffModulePath),$modulePathComparison)){
    Import-Module $repositoryHandoffModulePath -DisableNameChecking
}else{
    Import-Module $repositoryHandoffModulePath -Force -DisableNameChecking
}
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

function Resolve-AidosRepositoryWorkerStaleConsumedThinkerAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)]$Handoff
    )
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $state=Get-AidosState -ProjectRoot $root
    if([string]$state.state-ne'TASK_READY'){throw 'Another repository actor assignment is already active.'}
    if($null-eq$Handoff -or [string]$Handoff.metadata.kind-ne'ASSIGNMENT' -or [string]$Handoff.metadata.from_actor-ne'CORE' -or [string]$Handoff.metadata.to_actor-ne'THINKER'){
        throw 'Another repository actor assignment is already active.'
    }
    $payloadRef=[string]$Handoff.metadata.payload_ref
    $prefix='.aidos/runtime/actor-assignments/'
    if(-not$payloadRef.StartsWith($prefix,[StringComparison]::Ordinal) -or -not$payloadRef.EndsWith('.json',[StringComparison]::Ordinal)){
        throw 'Another repository actor assignment is already active.'
    }
    $assignmentId=$payloadRef.Substring($prefix.Length,$payloadRef.Length-$prefix.Length-5)
    $parsedAssignmentId=[guid]::Empty
    if(-not[guid]::TryParse($assignmentId,[ref]$parsedAssignmentId)){throw 'Another repository actor assignment is already active.'}

    $bound=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId $assignmentId
    $assignment=$bound.assignment
    $assignmentRef=[IO.Path]::GetRelativePath($root,$bound.path).Replace('\','/')
    if([string]$assignment.project_id-ne[string]$Project.project_id -or [string]$assignment.actor_role-ne'THINKER' -or [string]$Handoff.metadata.payload_ref-ne$assignmentRef -or [string]$Handoff.metadata.payload_sha256-ne[string]$bound.sha256 -or [string]$Handoff.metadata.action-ne[string]$assignment.action){
        throw 'Another repository actor assignment is already active.'
    }
    foreach($name in @('project_state','definition_id','definition_version','execution_id','revision','review_id')){
        if([string]$Handoff.metadata.binding.$name-ne[string]$assignment.binding.$name){throw 'Another repository actor assignment is already active.'}
    }

    $transport=Read-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $assignmentId
    if($null-eq$transport -or [string]$transport.status-ne'CONSUMED'){throw 'Another repository actor assignment is already active.'}
    $resultPath=Get-AidosRuntimeActorResultPath -ProjectRoot $root -AssignmentId $assignmentId
    if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Consumed runtime actor assignment has no durable result to reconcile.'}
    $result=Read-AidosJson -Path $resultPath
    Test-AidosRuntimeActorResultBinding -ProjectRoot $root -Result $result|Out-Null
    if([string]$result.outcome-ne'COMPLETED'){throw 'Consumed runtime actor result is not COMPLETED and cannot close a stale repository assignment.'}
    $resultRef=[IO.Path]::GetRelativePath($root,$resultPath).Replace('\','/')
    if([string]$transport.result_ref-ne$resultRef){throw 'Consumed runtime actor transport result_ref does not match the durable result.'}
    $resultSha=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1'
        envelope_type='AIDOS_REPOSITORY_HANDOFF'
        handoff_id=[guid]::NewGuid().ToString()
        project_id=[string]$Project.project_id
        kind='RESULT'
        from_actor='THINKER'
        to_actor='CORE'
        status='READY'
        parent_handoff_id=[string]$Handoff.metadata.handoff_id
        created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action=([string]$assignment.action+'_RESULT')
        payload_ref=$resultRef
        payload_sha256=$resultSha
        binding=$assignment.binding
        source_refs=@()
    }
    Test-AidosRepositoryHandoffTransition -Previous $Handoff -Next $metadata|Out-Null
    $body="# AIDOS reconciled Thinker result`n`nThe current repository assignment referenced runtime assignment $assignmentId, which AIDOS Core has already consumed. This RESULT handoff restores the repository transport chain from the exact durable runtime actor result."
    $reconciled=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId ([string]$Handoff.metadata.handoff_id)
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_STALE_ASSIGNMENT_RECONCILED' -Actor SYSTEM -Payload @{
        stale_handoff_id=[string]$Handoff.metadata.handoff_id
        result_handoff_id=[string]$metadata.handoff_id
        assignment_id=$assignmentId
        assignment_sha256=[string]$bound.sha256
        transport_status=[string]$transport.status
        result_ref=$resultRef
        result_sha256=$resultSha
    }|Out-Null
    $reconciled
}

function Resolve-AidosRepositoryWorkerStaleConsumedReviewAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)]$Handoff
    )
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $state=Get-AidosState -ProjectRoot $root
    if([string]$state.state-ne'TASK_READY' -or $null-eq$Handoff -or [string]$Handoff.metadata.kind-ne'ASSIGNMENT' -or [string]$Handoff.metadata.from_actor-ne'CORE' -or [string]$Handoff.metadata.to_actor-ne'THINKER' -or [string]$Handoff.metadata.action-ne'REVIEW'){
        throw 'Another repository actor assignment is already active.'
    }
    $reviewId=[string]$Handoff.metadata.binding.review_id
    if([string]::IsNullOrWhiteSpace($reviewId)){throw 'Another repository actor assignment is already active.'}
    $record=Read-AidosReviewRecord -ProjectRoot $root -ReviewId $reviewId
    if($null-eq$record -or [string]$record.project_id-ne[string]$Project.project_id -or [string]$record.review_id-ne$reviewId){throw 'Another repository actor assignment is already active.'}
    if([string]$record.transport_state-ne'CLEANED' -or -not$record.response_accepted_at -or -not$record.response_sha256 -or -not$record.decision -or -not$record.consumed_at -or -not$record.consume_ack -or -not$record.cleaned_at){
        throw 'Another repository actor assignment is already active.'
    }
    if([string]$record.decision.outcome-ne'REPAIR' -or [string]$record.decision.target_state-ne'TASK_READY'){throw 'Cleaned review does not authorize a Worker repair revision.'}
    foreach($name in @('definition_id','definition_version','execution_id','revision','review_id')){
        if([string]$Handoff.metadata.binding.$name-ne[string]$record.$name){throw "Stale review handoff binding '$name' differs from the durable review record."}
    }
    if([string]$Handoff.metadata.payload_sha256-ne[string]$record.assignment_sha256){throw 'Stale review handoff assignment hash differs from the durable review record.'}
    $recordPath=Get-AidosReviewRecordPath -ProjectRoot $root -ReviewId $reviewId
    if(-not(Test-Path -LiteralPath $recordPath -PathType Leaf)){throw 'Cleaned review has no durable review record.'}
    $recordRef=[IO.Path]::GetRelativePath($root,$recordPath).Replace('\','/')
    $recordSha=(Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id=[string]$Project.project_id
        kind='RESULT';from_actor='THINKER';to_actor='CORE';status='READY';parent_handoff_id=[string]$Handoff.metadata.handoff_id;created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action='REVIEW_RESULT';payload_ref=$recordRef;payload_sha256=$recordSha;binding=$Handoff.metadata.binding;source_refs=@()
    }
    Test-AidosRepositoryHandoffTransition -Previous $Handoff -Next $metadata|Out-Null
    $body="# AIDOS reconciled Thinker review result`n`nReview $reviewId was already accepted, decided, consumed and cleaned by AIDOS Core. This RESULT handoff restores the repository transport chain from the exact durable review record."
    $reconciled=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId ([string]$Handoff.metadata.handoff_id)
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_STALE_REVIEW_ASSIGNMENT_RECONCILED' -Actor SYSTEM -Payload @{
        stale_handoff_id=[string]$Handoff.metadata.handoff_id;result_handoff_id=[string]$metadata.handoff_id;review_id=$reviewId
        assignment_sha256=[string]$record.assignment_sha256;response_sha256=[string]$record.response_sha256;review_record_ref=$recordRef;review_record_sha256=$recordSha
    }|Out-Null
    $reconciled
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
        $existing=if([string]$existing.metadata.action-eq'REVIEW'){
            Resolve-AidosRepositoryWorkerStaleConsumedReviewAssignment -Project $Project -Handoff $existing
        }else{
            Resolve-AidosRepositoryWorkerStaleConsumedThinkerAssignment -Project $Project -Handoff $existing
        }
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

function Repair-AidosRepositoryWorkerResultRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $state=Get-AidosState -ProjectRoot $root
    if([string]$state.state-ne'RECOVERY_REQUIRED'){
        return [pscustomobject][ordered]@{status='NOT_REQUIRED';project_id=[string]$Project.project_id}
    }
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$handoff -or [string]$handoff.metadata.kind-ne'RESULT' -or [string]$handoff.metadata.action-ne'DISPATCH_EXECUTION_RESULT'){
        return [pscustomobject][ordered]@{status='NO_RECOVERABLE_RESULT_HANDOFF';project_id=[string]$Project.project_id}
    }
    if([string]$handoff.metadata.binding.execution_id-ne[string]$state.execution_id -or [int]$handoff.metadata.binding.revision-ne[int]$state.revision -or [string]$handoff.metadata.binding.definition_id-ne[string]$state.definition_id -or [int]$handoff.metadata.binding.definition_version-ne[int]$state.definition_version){
        throw 'Recoverable Worker result handoff binding differs from canonical state.'
    }
    $resultPath=Join-Path $root ([string]$handoff.metadata.payload_ref)
    if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Recoverable Worker result handoff payload is missing.'}
    $result=Read-AidosJson -Path $resultPath
    $guardPath=Get-AidosWorkerDispatchGuardPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision)
    if(-not(Test-Path -LiteralPath $guardPath -PathType Leaf)){throw 'Recoverable Worker result requires dispatch guard evidence.'}
    $guard=Read-AidosJson -Path $guardPath
    if([string]$result.validation_status-ne'PASS' -or [string]$guard.status-ne'PASS'){throw 'Recoverable Worker result lacks PASS validation or dispatch-guard evidence.'}
    Set-AidosState -ProjectRoot $root -NewState REVIEW_READY -Actor BRIDGE -Patch @{validation_result=[string]$state.validation_result}|Out-Null
    Add-AidosEvent -ProjectRoot $root -EventType 'RECOVERY_RECONCILED_RESULT_HANDOFF' -Actor BRIDGE -Payload @{execution_id=[string]$state.execution_id;revision=[int]$state.revision;handoff_id=[string]$handoff.metadata.handoff_id;validation_status=[string]$result.validation_status;dispatch_guard=[string]$guard.status}|Out-Null
    [pscustomobject][ordered]@{status='RECONCILED';project_id=[string]$Project.project_id;execution_id=[string]$state.execution_id;revision=[int]$state.revision;handoff_id=[string]$handoff.metadata.handoff_id}
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

function Resume-AidosRepositoryWorkerHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$ExecutionPath,[Parameter(Mandatory)][string]$SessionId,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $assignment=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$assignment -or [string]$assignment.metadata.kind-ne'ASSIGNMENT' -or [string]$assignment.metadata.to_actor-ne'WORKER'){throw 'Codex resume requires the current WORKER assignment handoff.'}
    $prompt='Resume the interrupted exact bound Worker assignment from .aidos/HANDOFF.md. Continue autonomously inside the existing authority. Run every registered validator. Do not commit or push; AIDOS Core owns validation and scheduling.'
    $worker=Invoke-AidosAutonomousCodexExecution -ProjectRoot $root -ExecutionPath $ExecutionPath -Prompt $prompt -ResumeSessionId $SessionId
    $terminal=Resolve-AidosRepositoryWorkerTerminalResult -WorkerOutcome $worker
    $result=Publish-AidosRepositoryWorkerResult -Project $Project -WorkerResult $terminal -Push:$Push -DeferPersistence
    [pscustomobject][ordered]@{status=[string]$worker.status;assignment_handoff=$assignment;worker=$worker;terminal_result=$terminal;result_handoff=$result}
}

Export-ModuleMember -Function Resolve-AidosRepositoryWorkerHandoffModulePath,Get-AidosRepositoryWorkerBinding,Get-AidosRepositoryWorkerSourceRefs,New-AidosRepositoryWorkerAssignmentBody,Get-AidosRepositoryWorkerChangedLifecyclePaths,New-AidosRepositoryWorkerDeferredPersistence,Resolve-AidosRepositoryWorkerStaleConsumedThinkerAssignment,Resolve-AidosRepositoryWorkerStaleConsumedReviewAssignment,Publish-AidosRepositoryWorkerAssignment,Resolve-AidosRepositoryWorkerTerminalResult,Publish-AidosRepositoryWorkerResult,Complete-AidosRepositoryWorkerHandoffPersistence,Repair-AidosRepositoryWorkerResultRecovery,Invoke-AidosRepositoryWorkerFinalizationFromManagerResult,Invoke-AidosRepositoryWorkerHandoff,Resume-AidosRepositoryWorkerHandoff
