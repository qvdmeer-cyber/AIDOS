Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorAssignments.psm1') -DisableNameChecking

function Get-AidosRuntimeActorResultRoot {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/runtime/actor-results'
}
function Get-AidosRuntimeActorResultPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    Join-Path (Get-AidosRuntimeActorResultRoot -ProjectRoot $ProjectRoot) ($AssignmentId+'.json')
}
function Read-AidosRuntimeActorAssignment {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    $path=Get-AidosRuntimeActorAssignmentPath -ProjectRoot $ProjectRoot -AssignmentId $AssignmentId
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Runtime actor assignment not found: $AssignmentId"}
    $assignment=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    [pscustomobject][ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();assignment=$assignment}
}
function Read-AidosRuntimeActorTransportState {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    $path=Get-AidosRuntimeActorTransportStatePath -ProjectRoot $ProjectRoot -AssignmentId $AssignmentId
    if(Test-Path -LiteralPath $path -PathType Leaf){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50}else{$null}
}
function Initialize-AidosRuntimeActorTransportState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $bound=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId $AssignmentId
    $assignment=$bound.assignment
    $statePath=Get-AidosRuntimeActorTransportStatePath -ProjectRoot $root -AssignmentId $AssignmentId
    if(Test-Path -LiteralPath $statePath -PathType Leaf){
        $existing=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
        if([string]$existing.assignment_sha256 -ne [string]$bound.sha256){throw 'Runtime actor transport assignment hash mismatch.'}
        return $existing
    }
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $state=[ordered]@{schema_version='0.1';assignment_id=$AssignmentId;assignment_sha256=$bound.sha256;project_id=[string]$assignment.project_id;status='PENDING';transport_type=$null;created_at=$now;updated_at=$now;activated_at=$null;completed_at=$null;last_error=$null;result_ref=$null}
    Write-AidosJsonAtomic $statePath $state
    [pscustomobject]$state
}
function Set-AidosRuntimeActorTransportState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$AssignmentId,
        [ValidateSet('WAITING_TRANSPORT','ACTIVATED','COMPLETED','FAILED','ABANDONED')][string]$Status,
        [string]$TransportType,
        [string]$LastError,
        [string]$ResultRef
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $state=Initialize-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId
    if([string]$state.status -in @('COMPLETED','FAILED','ABANDONED')){
        if([string]$state.status -eq $Status){return $state}
        throw "Runtime actor transport is terminal: $($state.status)"
    }
    $allowed=@{PENDING=@('WAITING_TRANSPORT','ACTIVATED','FAILED','ABANDONED');WAITING_TRANSPORT=@('WAITING_TRANSPORT','ACTIVATED','FAILED','ABANDONED');ACTIVATED=@('ACTIVATED','COMPLETED','FAILED','ABANDONED')}
    if($Status -notin @($allowed[[string]$state.status])){throw "Illegal runtime actor transport transition: $($state.status) -> $Status"}
    $state.status=$Status
    if(-not[string]::IsNullOrWhiteSpace($TransportType)){$state.transport_type=$TransportType}
    if($Status -eq 'ACTIVATED' -and [string]::IsNullOrWhiteSpace([string]$state.activated_at)){$state.activated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    if($Status -in @('COMPLETED','FAILED','ABANDONED')){$state.completed_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $state.last_error=if([string]::IsNullOrWhiteSpace($LastError)){$null}else{$LastError}
    $state.result_ref=if([string]::IsNullOrWhiteSpace($ResultRef)){$state.result_ref}else{$ResultRef}
    $state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    Write-AidosJsonAtomic (Get-AidosRuntimeActorTransportStatePath -ProjectRoot $root -AssignmentId $AssignmentId) $state
    $state
}
function Test-AidosRuntimeActorResultBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Result)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $bound=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId ([string]$Result.assignment_id)
    $a=$bound.assignment
    if([string]$Result.envelope_type -ne 'RUNTIME_ACTOR_RESULT'){throw 'Runtime actor result envelope_type mismatch.'}
    if([string]$Result.assignment_sha256 -ne [string]$bound.sha256){throw 'Runtime actor result assignment hash mismatch.'}
    foreach($name in @('project_id','actor_role','actor_identity','action')){if([string]$Result.$name -ne [string]$a.$name){throw "Runtime actor result binding mismatch for '$name'."}}
    foreach($name in @('project_state','definition_id','definition_version','execution_id','revision','review_id')){
        if([string]$Result.binding.$name -ne [string]$a.binding.$name){throw "Runtime actor result binding mismatch for '$name'."}
    }
    [pscustomobject][ordered]@{valid=$true;assignment_id=[string]$a.assignment_id;assignment_sha256=$bound.sha256;project_id=[string]$a.project_id}
}
function Save-AidosRuntimeActorResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Result)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $binding=Test-AidosRuntimeActorResultBinding -ProjectRoot $root -Result $Result
    $path=Get-AidosRuntimeActorResultPath -ProjectRoot $root -AssignmentId ([string]$Result.assignment_id)
    if(Test-Path -LiteralPath $path -PathType Leaf){
        $existing=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
        if((ConvertTo-Json $existing -Depth 100 -Compress) -ne (ConvertTo-Json $Result -Depth 100 -Compress)){throw 'Conflicting runtime actor result already exists.'}
        return [pscustomobject][ordered]@{status='ALREADY_SAVED';path=$path;binding=$binding}
    }
    Write-AidosJsonAtomic $path $Result
    $relative=[IO.Path]::GetRelativePath($root,$path).Replace('\','/')
    Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId ([string]$Result.assignment_id) -Status COMPLETED -ResultRef $relative|Out-Null
    Add-AidosEvent -ProjectRoot $root -EventType 'ACTOR_RESULT_RECEIVED' -Actor SYSTEM -Payload @{assignment_id=[string]$Result.assignment_id;assignment_sha256=[string]$Result.assignment_sha256;outcome=[string]$Result.outcome}|Out-Null
    [pscustomobject][ordered]@{status='SAVED';path=$path;binding=$binding}
}

Export-ModuleMember -Function Get-AidosRuntimeActorResultRoot,Get-AidosRuntimeActorResultPath,Read-AidosRuntimeActorAssignment,Read-AidosRuntimeActorTransportState,Initialize-AidosRuntimeActorTransportState,Set-AidosRuntimeActorTransportState,Test-AidosRuntimeActorResultBinding,Save-AidosRuntimeActorResult
