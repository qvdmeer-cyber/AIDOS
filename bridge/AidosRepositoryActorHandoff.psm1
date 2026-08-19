Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopThinkerTransport.psm1') -DisableNameChecking

function ConvertTo-AidosRepositoryActorName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ActorRole)
    switch($ActorRole){
        'THINKER' {'THINKER'}
        'WORKER' {'WORKER'}
        'HUMAN' {'HUMAN'}
        default {throw "Unsupported repository handoff actor role '$ActorRole'."}
    }
}
function Get-AidosRepositoryActorAssignmentRelativePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $path=(Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId $AssignmentId).path
    [IO.Path]::GetRelativePath($root,$path).Replace('\','/')
}
function Get-AidosRepositoryActorSourceRefs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$BoundAssignment)
    $assignment=$BoundAssignment.assignment
    if([string]$assignment.actor_role-eq'THINKER'){
        $documents=@(Get-AidosDesktopThinkerAuthorizedDocuments -ProjectRoot $ProjectRoot -BoundAssignment $BoundAssignment)
        return @($documents|ForEach-Object {[string]$_.path}|Where-Object {-not[string]::IsNullOrWhiteSpace($_)}|Select-Object -Unique)
    }
    $refs=[System.Collections.Generic.List[string]]::new()
    foreach($relative in @('.aidos/PROJECT.json','.aidos/STATE.json','AGENTS.md')){if(Test-Path -LiteralPath (Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) $relative) -PathType Leaf){$refs.Add($relative)}}
    $definitionId=[string]$assignment.binding.definition_id
    if(-not[string]::IsNullOrWhiteSpace($definitionId) -and $null-ne$assignment.binding.definition_version){
        $definitionRef=('.aidos/definitions/{0}/v{1}/DEFINITION.json' -f $definitionId,[int]$assignment.binding.definition_version)
        if(Test-Path -LiteralPath (Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) $definitionRef) -PathType Leaf){$refs.Add($definitionRef)}
    }
    @($refs|Select-Object -Unique)
}
function New-AidosRepositoryActorResultTemplate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$BoundAssignment)
    $assignment=$BoundAssignment.assignment
    $payload=if([string]$assignment.action-eq'RESOLVE_PROJECT_APPLICABILITY'){
        [ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='REQUIRED: concise evidence-based applicability rationale';proposed_artifacts=@([ordered]@{artifact_type='PROJECT_APPLICABILITY_PROPOSAL';authority_classification='REPO_VERIFIABLE';preset_ids='REQUIRED_NONEMPTY: exact preset_id values from AIDOS/catalog/profile-presets.catalog.json';selection_source='BASELINE_DERIVED';overrides=@();source_refs='REQUIRED_NONEMPTY: only paths from handoff source_refs'});human_input_request=$null}
    }elseif([string]$assignment.actor_role-eq'THINKER'){
        [ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='';applicability_resolutions=@();surface_resolutions=@();human_input_request=$null}
    }else{
        [ordered]@{result_type='WORKER_OUTPUT';summary='';evidence_refs=@();human_input_request=$null}
    }
    [pscustomobject][ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$assignment.assignment_id;assignment_sha256=[string]$BoundAssignment.sha256;project_id=[string]$assignment.project_id;actor_role=[string]$assignment.actor_role;actor_identity=[string]$assignment.actor_identity;action=[string]$assignment.action;binding=$assignment.binding;outcome='COMPLETED';result=[pscustomobject]$payload;responded_at='REQUIRED: ISO-8601 completion timestamp'}
}
function New-AidosRepositoryActorAssignmentBody {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$BoundAssignment,[Parameter(Mandatory)][string]$PayloadRef,[Parameter(Mandatory)][string[]]$SourceRefs)
    $assignment=$BoundAssignment.assignment
    $target=ConvertTo-AidosRepositoryActorName -ActorRole ([string]$assignment.actor_role)
    $template=New-AidosRepositoryActorResultTemplate -BoundAssignment $BoundAssignment
    $sourceLines=@($SourceRefs|ForEach-Object {"- $_"}) -join "`n"
    @"
# AIDOS $target handoff

AIDOS Core has assigned this handoff. The repository is the transport and canonical workflow state. Chat/session history is not authority.

- Project: $([string]$assignment.project_id)
- Assignment: $([string]$assignment.assignment_id)
- Assignment SHA-256: $([string]$BoundAssignment.sha256)
- Action: $([string]$assignment.action)
- Target actor: $target

## Actor protocol

1. Read the exact assignment at $PayloadRef through the handoff gateway or local repository.
2. Read only the authorized source_refs from the handoff metadata. AIDOS/... refs resolve against AIDOS Core; all other refs resolve against this project repository.
3. Perform the assigned work under the project and AIDOS actor instructions.
4. Return the exact result payload below to AIDOS Core. Do not directly assign or start another actor.
5. Complete by publishing one RESULT handoff whose parent is this handoff. The bridge will wake the next actor selected by Core.

## Required result envelope

BEGIN_RESULT_JSON
$($template|ConvertTo-Json -Depth 100)
END_RESULT_JSON

## Authorized source refs

$sourceLines
"@
}
function Publish-AidosRuntimeActorRepositoryHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$AssignmentId,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $bound=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId $AssignmentId
    $assignment=$bound.assignment
    if([string]$assignment.project_id-ne[string]$Project.project_id){throw 'Repository handoff project/assignment binding mismatch.'}
    $target=ConvertTo-AidosRepositoryActorName -ActorRole ([string]$assignment.actor_role)
    $payloadRef=[IO.Path]::GetRelativePath($root,$bound.path).Replace('\','/')
    $existing=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($existing -and [string]$existing.metadata.kind-eq'ASSIGNMENT'){
        if([string]$existing.metadata.payload_ref-eq$payloadRef -and [string]$existing.metadata.payload_sha256-eq[string]$bound.sha256 -and [string]$existing.metadata.to_actor-eq$target){
            $transport=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status ACTIVATED -TransportType REPOSITORY_HANDOFF -LastError $null
            return [pscustomobject][ordered]@{status='ALREADY_PUBLISHED';handoff=$existing;transport=$transport;persistence=[pscustomobject]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}}
        }
        return [pscustomobject][ordered]@{status='BLOCKED_ACTIVE_HANDOFF';active_handoff=$existing;assignment_id=$AssignmentId}
    }
    $sourceRefs=@(Get-AidosRepositoryActorSourceRefs -ProjectRoot $root -BoundAssignment $bound)
    $metadata=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id=[string]$assignment.project_id;kind='ASSIGNMENT';from_actor='CORE';to_actor=$target;status='READY';parent_handoff_id=if($existing){[string]$existing.metadata.handoff_id}else{$null};created_at=[DateTimeOffset]::UtcNow.ToString('o');action=[string]$assignment.action;payload_ref=$payloadRef;payload_sha256=[string]$bound.sha256;binding=$assignment.binding;source_refs=@($sourceRefs)}
    if($existing){$null=Test-AidosRepositoryHandoffTransition -Previous $existing -Next $metadata}
    $body=New-AidosRepositoryActorAssignmentBody -BoundAssignment $bound -PayloadRef $payloadRef -SourceRefs $sourceRefs
    $expectedParent=if($existing){[string]$existing.metadata.handoff_id}else{$null}
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId $expectedParent
    $transport=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status ACTIVATED -TransportType REPOSITORY_HANDOFF -LastError $null
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_HANDOFF_PUBLISHED' -Actor SYSTEM -Payload @{handoff_id=[string]$metadata.handoff_id;assignment_id=$AssignmentId;assignment_sha256=[string]$bound.sha256;to_actor=$target}|Out-Null
    $persistence=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS publish $target handoff $AssignmentId") -Push:$Push
    [pscustomobject][ordered]@{status='PUBLISHED';handoff=$handoff;transport=$transport;persistence=$persistence}
}
function Resolve-AidosRepositoryHandoffPayloadPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RelativePath)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $relative=Test-AidosRepositoryRelativePath -Path $RelativePath -FieldName 'payload_ref'
    $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
    $comparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    $prefix=$root.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not$path.StartsWith($prefix,$comparison)){throw 'Repository handoff payload escapes project root.'}
    $path
}
function Import-AidosRepositoryActorResultHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$handoff -or [string]$handoff.metadata.kind-ne'RESULT'){return [pscustomobject][ordered]@{status='NO_RESULT_HANDOFF'}}
    $path=Resolve-AidosRepositoryHandoffPayloadPath -ProjectRoot $root -RelativePath ([string]$handoff.metadata.payload_ref)
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Repository result handoff payload is missing.'}
    $sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]$handoff.metadata.payload_sha256-ne$sha){throw 'Repository result handoff payload SHA-256 mismatch.'}
    try{$result=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}catch{throw "Repository result payload is invalid JSON: $($_.Exception.Message)"}
    if([string]$result.envelope_type-ne'RUNTIME_ACTOR_RESULT'){throw "Unsupported repository result payload envelope '$($result.envelope_type)'."}
    $assignment=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId ([string]$result.assignment_id)
    $assignmentRef=[IO.Path]::GetRelativePath($root,$assignment.path).Replace('\','/')
    $previousId=[string]$handoff.metadata.parent_handoff_id
    if([string]::IsNullOrWhiteSpace($previousId)){throw 'Repository result handoff has no parent assignment handoff.'}
    $expectedActor=ConvertTo-AidosRepositoryActorName -ActorRole ([string]$assignment.assignment.actor_role)
    if([string]$handoff.metadata.from_actor-ne$expectedActor){throw 'Repository result actor does not match runtime assignment.'}
    $expectedAction=[string]$assignment.assignment.action+'_RESULT'
    if([string]$handoff.metadata.action-ne$expectedAction){throw 'Repository result handoff action does not match runtime assignment.'}
    $saved=Save-AidosRuntimeActorResult -ProjectRoot $root -Result $result
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_HANDOFF_RESULT_IMPORTED' -Actor SYSTEM -Payload @{handoff_id=[string]$handoff.metadata.handoff_id;parent_handoff_id=$previousId;assignment_id=[string]$result.assignment_id;payload_ref=[string]$handoff.metadata.payload_ref;assignment_ref=$assignmentRef}|Out-Null
    $persistence=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS import repository result $($result.assignment_id)") -Push:$Push
    [pscustomobject][ordered]@{status='IMPORTED';handoff=$handoff;saved=$saved;result=$result;persistence=$persistence}
}

Export-ModuleMember -Function ConvertTo-AidosRepositoryActorName,Get-AidosRepositoryActorAssignmentRelativePath,Get-AidosRepositoryActorSourceRefs,New-AidosRepositoryActorResultTemplate,New-AidosRepositoryActorAssignmentBody,Publish-AidosRuntimeActorRepositoryHandoff,Resolve-AidosRepositoryHandoffPayloadPath,Import-AidosRepositoryActorResultHandoff
