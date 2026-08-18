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
        [ValidateSet('WAITING_TRANSPORT','ACTIVATED','COMPLETED','CONSUMED','FAILED','ABANDONED')][string]$Status,
        [string]$TransportType,
        [string]$LastError,
        [string]$ResultRef
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $state=Initialize-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId
    if([string]$state.status -in @('CONSUMED','FAILED','ABANDONED')){
        if([string]$state.status -eq $Status){return $state}
        throw "Runtime actor transport is terminal: $($state.status)"
    }
    $allowed=@{
        PENDING=@('WAITING_TRANSPORT','ACTIVATED','FAILED','ABANDONED')
        WAITING_TRANSPORT=@('WAITING_TRANSPORT','ACTIVATED','FAILED','ABANDONED')
        ACTIVATED=@('ACTIVATED','COMPLETED','FAILED','ABANDONED')
        COMPLETED=@('COMPLETED','CONSUMED','FAILED','ABANDONED')
    }
    if($Status -notin @($allowed[[string]$state.status])){throw "Illegal runtime actor transport transition: $($state.status) -> $Status"}
    $state.status=$Status
    if(-not[string]::IsNullOrWhiteSpace($TransportType)){$state.transport_type=$TransportType}
    if($Status -eq 'ACTIVATED' -and [string]::IsNullOrWhiteSpace([string]$state.activated_at)){$state.activated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    if($Status -in @('COMPLETED','CONSUMED','FAILED','ABANDONED') -and [string]::IsNullOrWhiteSpace([string]$state.completed_at)){$state.completed_at=[DateTimeOffset]::UtcNow.ToString('o')}
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
function ConvertTo-AidosCanonicalActorValue {
    param($Value)
    if($null -eq $Value){return $null}
    if($Value -is [string] -or $Value -is [char] -or $Value -is [bool] -or $Value -is [ValueType]){return $Value}
    if($Value -is [System.Collections.IDictionary]){
        $ordered=[ordered]@{}
        foreach($key in @($Value.Keys|ForEach-Object {[string]$_}|Sort-Object -CaseSensitive)){$ordered[$key]=ConvertTo-AidosCanonicalActorValue $Value[$key]}
        return $ordered
    }
    if($Value -is [System.Collections.IEnumerable] -and -not($Value -is [pscustomobject])){
        return @($Value|ForEach-Object {ConvertTo-AidosCanonicalActorValue $_})
    }
    $properties=@($Value.PSObject.Properties|Where-Object {$_.MemberType -in @('NoteProperty','Property')}|Sort-Object Name -CaseSensitive)
    if($properties.Count -gt 0){
        $ordered=[ordered]@{}
        foreach($property in $properties){$ordered[[string]$property.Name]=ConvertTo-AidosCanonicalActorValue $property.Value}
        return $ordered
    }
    $Value
}
function ConvertTo-AidosCanonicalActorJson {
    param([Parameter(Mandatory)]$Value)
    (ConvertTo-AidosCanonicalActorValue $Value)|ConvertTo-Json -Depth 100 -Compress
}
function Save-AidosRuntimeActorResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Result)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $binding=Test-AidosRuntimeActorResultBinding -ProjectRoot $root -Result $Result
    $path=Get-AidosRuntimeActorResultPath -ProjectRoot $root -AssignmentId ([string]$Result.assignment_id)
    if(Test-Path -LiteralPath $path -PathType Leaf){
        $existing=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
        if((ConvertTo-AidosCanonicalActorJson $existing) -cne (ConvertTo-AidosCanonicalActorJson $Result)){throw 'Conflicting runtime actor result already exists.'}
        return [pscustomobject][ordered]@{status='ALREADY_SAVED';path=$path;binding=$binding}
    }
    Write-AidosJsonAtomic $path $Result
    $relative=[IO.Path]::GetRelativePath($root,$path).Replace('\','/')
    Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId ([string]$Result.assignment_id) -Status COMPLETED -ResultRef $relative|Out-Null
    Add-AidosEvent -ProjectRoot $root -EventType 'ACTOR_RESULT_RECEIVED' -Actor SYSTEM -Payload @{assignment_id=[string]$Result.assignment_id;assignment_sha256=[string]$Result.assignment_sha256;outcome=[string]$Result.outcome}|Out-Null
    [pscustomobject][ordered]@{status='SAVED';path=$path;binding=$binding}
}

Export-ModuleMember -Function Get-AidosRuntimeActorResultRoot,Get-AidosRuntimeActorResultPath,Read-AidosRuntimeActorAssignment,Read-AidosRuntimeActorTransportState,Initialize-AidosRuntimeActorTransportState,Set-AidosRuntimeActorTransportState,Test-AidosRuntimeActorResultBinding,ConvertTo-AidosCanonicalActorValue,ConvertTo-AidosCanonicalActorJson,Save-AidosRuntimeActorResult
