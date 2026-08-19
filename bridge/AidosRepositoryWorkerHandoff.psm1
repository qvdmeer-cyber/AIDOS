Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking
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
    foreach($relative in @('AGENTS.md','.aidos/AGENT_PROFILE.json','.aidos/PROJECT.json','.aidos/STATE.json')){if(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf){$refs.Add($relative)}}
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

function Publish-AidosRepositoryWorkerAssignment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$ExecutionPath,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $executionPathResolved=[IO.Path]::GetFullPath($ExecutionPath)
    if(-not(Test-Path -LiteralPath $executionPathResolved -PathType Leaf)){throw 'Worker execution payload is missing.'}
    $execution=Read-AidosJson -Path $executionPathResolved
    if([string]$execution.project_id-ne[string]$Project.project_id){throw 'Worker execution project binding mismatch.'}
    $payloadRef=[IO.Path]::GetRelativePath($root,$executionPathResolved).Replace('\','/')
    $payloadSha=(Get-FileHash -LiteralPath $executionPathResolved -Algorithm SHA256).Hash.ToLowerInvariant()
    $existing=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($existing -and [string]$existing.metadata.kind-eq'ASSIGNMENT'){
        if([string]$existing.metadata.to_actor-eq'WORKER' -and [string]$existing.metadata.payload_ref-eq$payloadRef -and [string]$existing.metadata.payload_sha256-eq$payloadSha){return [pscustomobject][ordered]@{status='ALREADY_PUBLISHED';handoff=$existing;persistence=[pscustomobject]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}}}
        throw 'Another repository actor assignment is already active.'
    }
    $binding=Get-AidosRepositoryWorkerBinding -ProjectRoot $root -Execution $execution
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id=[string]$Project.project_id;kind='ASSIGNMENT';from_actor='CORE';to_actor='WORKER';status='READY';parent_handoff_id=if($existing){[string]$existing.metadata.handoff_id}else{$null};created_at=[DateTimeOffset]::UtcNow.ToString('o');action='DISPATCH_EXECUTION';payload_ref=$payloadRef;payload_sha256=$payloadSha;binding=$binding;source_refs=@(Get-AidosRepositoryWorkerSourceRefs -ProjectRoot $root -ExecutionPath $executionPathResolved)
    }
    if($existing){Test-AidosRepositoryHandoffTransition -Previous $existing -Next $metadata|Out-Null}
    $body=New-AidosRepositoryWorkerAssignmentBody -Execution $execution -PayloadRef $payloadRef
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId $(if($existing){[string]$existing.metadata.handoff_id}else{$null})
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_WORKER_HANDOFF_PUBLISHED' -Actor SYSTEM -Payload @{handoff_id=[string]$metadata.handoff_id;execution_id=[string]$execution.execution_id;revision=[int]$execution.revision;payload_ref=$payloadRef;payload_sha256=$payloadSha}|Out-Null
    $changed=@(Get-AidosRepositoryHandoffChangedPaths -Project $Project|Where-Object {$_.path.StartsWith('.aidos/',[StringComparison]::Ordinal)}|ForEach-Object path)
    $persistence=Invoke-AidosRepositoryHandoffGitPersistence -Project $Project -Paths $changed -CommitMessage ("AIDOS publish Worker handoff $($execution.execution_id) r$($execution.revision)") -Push:$Push
    [pscustomobject][ordered]@{status='PUBLISHED';handoff=$handoff;execution=$execution;persistence=$persistence}
}

function Publish-AidosRepositoryWorkerResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$WorkerResult,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $assignment=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$assignment -or [string]$assignment.metadata.kind-ne'ASSIGNMENT' -or [string]$assignment.metadata.to_actor-ne'WORKER'){throw 'Worker result requires the current WORKER assignment handoff.'}
    $resultPath=Join-Path $root ('.aidos/executions/{0}/revision-{1}/RESULT.json' -f [string]$WorkerResult.execution_id,[int]$WorkerResult.revision)
    if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Canonical Worker RESULT.json is missing.'}
    $payloadRef=[IO.Path]::GetRelativePath($root,$resultPath).Replace('\','/')
    $payloadSha=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $state=Get-AidosState -ProjectRoot $root
    $binding=[pscustomobject][ordered]@{project_state=[string]$state.state;definition_id=[string]$state.definition_id;definition_version=if($null-eq$state.definition_version){$null}else{[int]$state.definition_version};execution_id=[string]$WorkerResult.execution_id;revision=[int]$WorkerResult.revision;review_id=$null}
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id=[string]$Project.project_id;kind='RESULT';from_actor='WORKER';to_actor='CORE';status='READY';parent_handoff_id=[string]$assignment.metadata.handoff_id;created_at=[DateTimeOffset]::UtcNow.ToString('o');action='DISPATCH_EXECUTION_RESULT';payload_ref=$payloadRef;payload_sha256=$payloadSha;binding=$binding;source_refs=@()
    }
    Test-AidosRepositoryHandoffTransition -Previous $assignment -Next $metadata|Out-Null
    $body="# AIDOS Worker result`n`nExecution $([string]$WorkerResult.execution_id) revision $([int]$WorkerResult.revision) finished with terminal type $([string]$WorkerResult.terminal_type) and validation $([string]$WorkerResult.validation_status)."
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId ([string]$assignment.metadata.handoff_id)
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_WORKER_RESULT_PUBLISHED' -Actor EXECUTION_AGENT -Payload @{handoff_id=[string]$metadata.handoff_id;parent_handoff_id=[string]$metadata.parent_handoff_id;execution_id=[string]$WorkerResult.execution_id;revision=[int]$WorkerResult.revision;payload_ref=$payloadRef;payload_sha256=$payloadSha}|Out-Null
    $changed=@(Get-AidosRepositoryHandoffChangedPaths -Project $Project|Where-Object {$_.path.StartsWith('.aidos/',[StringComparison]::Ordinal)}|ForEach-Object path)
    $persistence=Invoke-AidosRepositoryHandoffGitPersistence -Project $Project -Paths $changed -CommitMessage ("AIDOS publish Worker result $($WorkerResult.execution_id) r$($WorkerResult.revision)") -Push:$Push
    [pscustomobject][ordered]@{status='PUBLISHED';handoff=$handoff;worker_result=$WorkerResult;persistence=$persistence}
}

function Invoke-AidosRepositoryWorkerHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$ExecutionPath,[switch]$Push,[scriptblock]$CodexInvoker)
    $assignment=Publish-AidosRepositoryWorkerAssignment -Project $Project -ExecutionPath $ExecutionPath -Push:$Push
    $prompt='Read .aidos/HANDOFF.md and execute the exact bound Worker assignment. Use the repository as transport. Do not commit or push. Do not create the next actor handoff; AIDOS Core owns validation and scheduling.'
    $worker=if($CodexInvoker){& $CodexInvoker $Project $ExecutionPath $prompt}else{Invoke-AidosAutonomousCodexExecution -Project $Project -ExecutionPath $ExecutionPath -Prompt $prompt}
    $result=Publish-AidosRepositoryWorkerResult -Project $Project -WorkerResult $worker -Push:$Push
    [pscustomobject][ordered]@{status='WORKER_COMPLETED';assignment_handoff=$assignment;worker=$worker;result_handoff=$result}
}

Export-ModuleMember -Function Get-AidosRepositoryWorkerBinding,Get-AidosRepositoryWorkerSourceRefs,New-AidosRepositoryWorkerAssignmentBody,Publish-AidosRepositoryWorkerAssignment,Publish-AidosRepositoryWorkerResult,Invoke-AidosRepositoryWorkerHandoff
