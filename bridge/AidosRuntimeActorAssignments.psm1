Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDefinitionRuntime.psm1') -DisableNameChecking

function Get-AidosRuntimeActorAssignmentRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/runtime/actor-assignments'
}
function Get-AidosRuntimeActorTransportRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/runtime/actor-transport'
}
function Get-AidosRuntimeActorAssignmentPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    Join-Path (Get-AidosRuntimeActorAssignmentRoot -ProjectRoot $ProjectRoot) ($AssignmentId+'.json')
}
function Get-AidosRuntimeActorTransportStatePath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    Join-Path (Get-AidosRuntimeActorTransportRoot -ProjectRoot $ProjectRoot) ($AssignmentId+'.json')
}
function Get-AidosPendingRuntimeActorAssignments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Get-AidosRuntimeActorAssignmentRoot -ProjectRoot $ProjectRoot
    if(-not(Test-Path -LiteralPath $root -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $record=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
            $transportPath=Get-AidosRuntimeActorTransportStatePath -ProjectRoot $ProjectRoot -AssignmentId ([string]$record.assignment_id)
            $terminal=$false
            if(Test-Path -LiteralPath $transportPath -PathType Leaf){
                $transport=Get-Content -LiteralPath $transportPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
                $terminal=[string]$transport.status -in @('CONSUMED','FAILED','ABANDONED')
            }
            if(-not$terminal){$record}
        }
    )
}

function New-AidosRuntimeActorAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)]$Selection
    )
    if(-not[bool]$Selection.activatable){throw 'Runtime actor assignment requires an activatable selection.'}
    if([string]::IsNullOrWhiteSpace([string]$Selection.actor_identity)){throw 'Runtime actor assignment requires actor_identity.'}
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $binding=Test-AidosProjectBinding $root
    if([string]$binding.ProjectId -ne [string]$Project.project_id){throw 'Runtime actor assignment project binding mismatch.'}
    $state=Get-AidosState $root

    $definitionAction=([string]$Selection.action -in @('START_DEFINITION','RESUME_DEFINITION'))
    $existing=@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $root | Where-Object {
        $sameAction=if($definitionAction){[string]$_.action -in @('START_DEFINITION','RESUME_DEFINITION')}else{[string]$_.action -eq [string]$Selection.action}
        [string]$_.project_id -eq [string]$Project.project_id -and
        $sameAction -and
        [string]$_.actor_identity -eq [string]$Selection.actor_identity -and
        [string]$_.binding.definition_id -eq [string]$state.definition_id -and
        [string]$_.binding.definition_version -eq [string]$state.definition_version
    })
    if($existing.Count -gt 1){throw 'Multiple pending actor assignments exist for the same runtime binding.'}
    if($existing.Count -eq 1){
        $path=Get-AidosRuntimeActorAssignmentPath -ProjectRoot $root -AssignmentId ([string]$existing[0].assignment_id)
        return [pscustomobject][ordered]@{status='ALREADY_PENDING';assignment_ref=[IO.Path]::GetRelativePath($root,$path).Replace('\','/');assignment_sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();assignment=$existing[0]}
    }

    if([string]$Selection.action -eq 'RESOLVE_PROJECT_APPLICABILITY'){
        if([string]$state.state -ne 'IDLE' -or -not[string]::IsNullOrWhiteSpace([string]$state.definition_id)){throw 'RESOLVE_PROJECT_APPLICABILITY requires new-project IDLE state without Definition lineage.'}
        if(Test-Path -LiteralPath (Join-Path $root '.aidos/profile/PROJECT_APPLICABILITY.json') -PathType Leaf){throw 'Project Applicability already exists.'}
    } elseif([string]$Selection.action -eq 'START_DEFINITION'){
        if([string]$state.state -ne 'IDLE' -or -not[string]::IsNullOrWhiteSpace([string]$state.definition_id)){throw 'START_DEFINITION requires new-project IDLE state without Definition lineage.'}
        if(-not(Test-Path -LiteralPath (Join-Path $root '.aidos/profile/PROJECT_APPLICABILITY.json') -PathType Leaf)){throw 'START_DEFINITION requires resolved Project Applicability.'}
        $definitionId=('DEF-'+[guid]::NewGuid().ToString())
        $state=Set-AidosState -ProjectRoot $root -NewState WAITING_DEFINITION -Actor SYSTEM -Patch @{definition_id=$definitionId;definition_version=1}
        Ensure-AidosDefinitionWorkspace -ProjectRoot $root|Out-Null
    } elseif([string]$Selection.action -eq 'RESUME_DEFINITION'){
        if([string]$state.state -ne 'WAITING_DEFINITION'){throw 'RESUME_DEFINITION requires WAITING_DEFINITION state.'}
        if([string]::IsNullOrWhiteSpace([string]$state.definition_id) -or $null -eq $state.definition_version){throw 'RESUME_DEFINITION requires exact Definition binding.'}
        Ensure-AidosDefinitionWorkspace -ProjectRoot $root|Out-Null
    } else {
        throw "Runtime actor assignment adapter does not yet support action '$($Selection.action)'."
    }

    $assignment=[ordered]@{
        schema_version='0.1'
        envelope_type='RUNTIME_ACTOR_ASSIGNMENT'
        assignment_id=[guid]::NewGuid().ToString()
        project_id=[string]$Project.project_id
        actor_role=[string]$Selection.actor_role
        actor_identity=[string]$Selection.actor_identity
        action=[string]$Selection.action
        binding=[ordered]@{
            project_state=[string]$state.state
            definition_id=if([string]::IsNullOrWhiteSpace([string]$state.definition_id)){$null}else{[string]$state.definition_id}
            definition_version=if($null -eq $state.definition_version){$null}else{[int]$state.definition_version}
            execution_id=$state.execution_id
            revision=$state.revision
            review_id=$state.review_id
        }
        requested_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    $assignmentRoot=Get-AidosRuntimeActorAssignmentRoot -ProjectRoot $root
    if(-not(Test-Path -LiteralPath $assignmentRoot -PathType Container)){New-Item -ItemType Directory -Path $assignmentRoot -Force|Out-Null}
    $path=Join-Path $assignmentRoot ($assignment.assignment_id+'.json')
    Write-AidosJsonAtomic $path $assignment
    $sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Add-AidosEvent -ProjectRoot $root -EventType 'ACTOR_ASSIGNMENT_CREATED' -Actor SYSTEM -Payload @{assignment_id=$assignment.assignment_id;assignment_sha256=$sha;actor_role=$assignment.actor_role;actor_identity=$assignment.actor_identity;action=$assignment.action}|Out-Null
    [pscustomobject][ordered]@{status='PENDING';assignment_ref=[IO.Path]::GetRelativePath($root,$path).Replace('\','/');assignment_sha256=$sha;assignment=[pscustomobject]$assignment}
}

Export-ModuleMember -Function Get-AidosRuntimeActorAssignmentRoot,Get-AidosRuntimeActorTransportRoot,Get-AidosRuntimeActorAssignmentPath,Get-AidosRuntimeActorTransportStatePath,Get-AidosPendingRuntimeActorAssignments,New-AidosRuntimeActorAssignment
