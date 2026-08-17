Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking

$script:OperatorCommands=@('RUN','PAUSE','RESUME','SAFE_STOP','QUERY_STATUS','SUBMIT_HUMAN_INPUT','REQUEST_RECOVERY')

function Get-AidosOptionalProperty {
    param($Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if($null -eq $Object){return $Default}
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){return $Default}
    $property.Value
}

function Read-AidosOptionalJson {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
}

function Get-AidosOperatorControlStatePath {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/runtime/operator-control.json'
}

function Get-AidosOperatorControlState {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path=Get-AidosOperatorControlStatePath $ProjectRoot
    $state=Read-AidosOptionalJson $path
    if($state){return $state}
    [pscustomobject][ordered]@{
        schema_version='0.1'
        mode='RUNNING'
        requested_by='SYSTEM_DEFAULT'
        control_id=$null
        updated_at=$null
    }
}

function Set-AidosOperatorControlState {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [ValidateSet('RUNNING','PAUSED','SAFE_STOPPED')][string]$Mode,
        [Parameter(Mandatory)][string]$RequestedBy,
        [Parameter(Mandatory)][string]$ControlId
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $value=[ordered]@{
        schema_version='0.1'
        mode=$Mode
        requested_by=$RequestedBy
        control_id=$ControlId
        updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-AidosJsonAtomic (Get-AidosOperatorControlStatePath $root) $value
    [pscustomobject]$value
}

function Get-AidosOpenHumanInputRequests {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/human-input'
    if(-not(Test-Path -LiteralPath $root -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $request=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
                $status=[string](Get-AidosOptionalProperty $request 'status' '')
                if($status -in @('WAITING','OPEN','PENDING')){$request}
            } catch {}
        }
    )
}

function Get-AidosProgressEstimateRef {
    param([Parameter(Mandatory)][string]$ProjectRoot,$Object)
    $direct=[string](Get-AidosOptionalProperty $Object 'progress_estimate_ref' '')
    if(-not[string]::IsNullOrWhiteSpace($direct)){return $direct}
    $progressRoot=Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/progress'
    if(-not(Test-Path -LiteralPath $progressRoot -PathType Container)){return $null}
    $latest=Get-ChildItem -LiteralPath $progressRoot -Filter '*.json' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
    if(-not$latest){return $null}
    [IO.Path]::GetRelativePath((Resolve-AidosFileSystemPath $ProjectRoot),$latest.FullName).Replace('\','/')
}

function Get-AidosRuntimeWorkstreamProjection {
    param([Parameter(Mandatory)][string]$ProjectRoot,[object[]]$OpenHumanInputRequests)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $workstreamRoot=Join-Path $root '.aidos/workstreams'
    if(-not(Test-Path -LiteralPath $workstreamRoot -PathType Container)){return @()}
    $items=@()
    foreach($file in @(Get-ChildItem -LiteralPath $workstreamRoot -Filter '*.json' -File -ErrorAction SilentlyContinue|Sort-Object Name)){
        try {$workstream=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}catch{continue}
        $id=[string](Get-AidosOptionalProperty $workstream 'workstream_id' $file.BaseName)
        $status=[string](Get-AidosOptionalProperty $workstream 'status' (Get-AidosOptionalProperty $workstream 'state' 'UNKNOWN'))
        $blockers=@(Get-AidosOptionalProperty $workstream 'blockers' @())
        $openBlockers=@($blockers|Where-Object { [string](Get-AidosOptionalProperty $_ 'status' 'OPEN') -eq 'OPEN' })
        $requestIds=@($OpenHumanInputRequests|Where-Object { [string](Get-AidosOptionalProperty $_ 'workstream_id' '') -eq $id }|ForEach-Object { [string](Get-AidosOptionalProperty $_ 'request_id' (Get-AidosOptionalProperty $_ 'human_input_request_id' '')) }|Where-Object { -not[string]::IsNullOrWhiteSpace($_) })
        $items += [pscustomobject][ordered]@{
            workstream_id=$id
            status=$status
            current_actor_role=Get-AidosOptionalProperty $workstream 'current_actor_role' $null
            blocker_count=$openBlockers.Count
            open_human_input_request_ids=@($requestIds)
            progress_estimate_ref=Get-AidosProgressEstimateRef -ProjectRoot $root -Object $workstream
        }
    }
    @($items)
}

function Get-AidosRuntimeStatusProjection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $profile=Get-AidosProjectProfile $root
    $state=Get-AidosState $root
    $requests=@(Get-AidosOpenHumanInputRequests $root)
    $workstreams=@(Get-AidosRuntimeWorkstreamProjection -ProjectRoot $root -OpenHumanInputRequests $requests)
    $requestIds=@($requests|ForEach-Object { [string](Get-AidosOptionalProperty $_ 'request_id' (Get-AidosOptionalProperty $_ 'human_input_request_id' '')) }|Where-Object { -not[string]::IsNullOrWhiteSpace($_) })
    $blockerCount=0
    foreach($workstream in $workstreams){$blockerCount += [int]$workstream.blocker_count}
    $project=[pscustomobject][ordered]@{
        project_id=[string]$profile.project_id
        state=[string]$state.state
        recovery_required=([string]$state.state -eq 'RECOVERY_REQUIRED')
        blocker_count=$blockerCount
        open_human_input_request_ids=@($requestIds)
        progress_estimate_ref=Get-AidosProgressEstimateRef -ProjectRoot $root -Object $state
        workstreams=@($workstreams)
    }
    [pscustomobject][ordered]@{
        schema_version='0.1'
        generated_at=[DateTimeOffset]::UtcNow.ToString('o')
        projects=@($project)
    }
}

function Get-AidosRecentProjectEvents {
    param([Parameter(Mandatory)][string]$ProjectRoot,[int]$Limit=25)
    $eventRoot=Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/events'
    if(-not(Test-Path -LiteralPath $eventRoot -PathType Container)){return @()}
    $files=@(Get-ChildItem -LiteralPath $eventRoot -Filter '*.jsonl' -File -ErrorAction SilentlyContinue|Sort-Object Name -Descending)
    $events=[System.Collections.Generic.List[object]]::new()
    foreach($file in $files){
        $lines=@(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
        for($i=$lines.Count-1;$i-ge0;$i--){
            if([string]::IsNullOrWhiteSpace($lines[$i])){continue}
            try{$events.Add(($lines[$i]|ConvertFrom-Json -Depth 100))}catch{}
            if($events.Count -ge $Limit){break}
        }
        if($events.Count -ge $Limit){break}
    }
    @($events)
}

function Get-AidosOperatorSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$HostAgentStateRoot,
        [int]$EventLimit=25
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $host=$null
    if(-not[string]::IsNullOrWhiteSpace($HostAgentStateRoot)){
        $host=Read-AidosOptionalJson (Join-Path $HostAgentStateRoot 'STATUS.json')
    }
    [pscustomobject][ordered]@{
        schema_version='0.1'
        generated_at=[DateTimeOffset]::UtcNow.ToString('o')
        project_root=$root
        runtime=Get-AidosRuntimeStatusProjection $root
        control=Get-AidosOperatorControlState $root
        host_agent=$host
        recent_events=@(Get-AidosRecentProjectEvents -ProjectRoot $root -Limit $EventLimit)
    }
}

function Get-AidosControlIntentRoot {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/control/intents'
}

function Write-AidosControlIntent {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Intent)
    $root=Get-AidosControlIntentRoot $ProjectRoot
    if(-not(Test-Path -LiteralPath $root -PathType Container)){New-Item -ItemType Directory -Path $root -Force|Out-Null}
    $path=Join-Path $root (([string]$Intent.control_id)+'.json')
    if(Test-Path -LiteralPath $path){throw "Control intent already exists: $($Intent.control_id)"}
    Write-AidosJsonAtomic $path $Intent
    $path
}

function Update-AidosControlIntent {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Intent)
    Write-AidosJsonAtomic $Path $Intent
    [pscustomobject]$Intent
}

function Submit-AidosControlIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][ValidateSet('RUN','PAUSE','RESUME','SAFE_STOP','QUERY_STATUS','SUBMIT_HUMAN_INPUT','REQUEST_RECOVERY')][string]$Command,
        [Parameter(Mandatory)][string]$RequestedBy,
        [string]$WorkstreamId,
        [hashtable]$Payload=@{}
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $profile=Get-AidosProjectProfile $root
    $controlId=[guid]::NewGuid().ToString()
    $intent=[ordered]@{
        schema_version='0.1'
        control_id=$controlId
        command=$Command
        project_id=[string]$profile.project_id
        workstream_id=if([string]::IsNullOrWhiteSpace($WorkstreamId)){$null}else{$WorkstreamId}
        requested_by=$RequestedBy
        status='RECEIVED'
        payload=$Payload
        submitted_at=[DateTimeOffset]::UtcNow.ToString('o')
        applied_at=$null
        result=$null
    }
    $path=Write-AidosControlIntent -ProjectRoot $root -Intent $intent
    try {
        $intent.status='ACCEPTED'
        Update-AidosControlIntent -Path $path -Intent $intent|Out-Null
        switch($Command){
            'QUERY_STATUS' {
                $intent.result=[ordered]@{runtime_status=Get-AidosRuntimeStatusProjection $root}
                $intent.status='APPLIED'
            }
            'PAUSE' {
                $intent.result=[ordered]@{control=Set-AidosOperatorControlState -ProjectRoot $root -Mode PAUSED -RequestedBy $RequestedBy -ControlId $controlId;semantics='No new persistent desktop Worker activation after the next host-agent tick. Running bounded execution is not killed.'}
                $intent.status='APPLIED'
            }
            'SAFE_STOP' {
                $intent.result=[ordered]@{control=Set-AidosOperatorControlState -ProjectRoot $root -Mode SAFE_STOPPED -RequestedBy $RequestedBy -ControlId $controlId;semantics='No new persistent desktop Worker activation. Running bounded execution is not killed.'}
                $intent.status='APPLIED'
            }
            {$_ -in @('RUN','RESUME')} {
                $state=Get-AidosState $root
                if([string]$state.state -eq 'RECOVERY_REQUIRED'){throw 'RUN/RESUME rejected while project state is RECOVERY_REQUIRED.'}
                $intent.result=[ordered]@{control=Set-AidosOperatorControlState -ProjectRoot $root -Mode RUNNING -RequestedBy $RequestedBy -ControlId $controlId}
                $intent.status='APPLIED'
            }
            'SUBMIT_HUMAN_INPUT' {throw 'SUBMIT_HUMAN_INPUT runtime processor is not implemented; use the canonical Human Input Request resolver.'}
            'REQUEST_RECOVERY' {throw 'REQUEST_RECOVERY runtime processor is not implemented; recovery remains an explicit AIDOS Core reconciliation action.'}
        }
        $intent.applied_at=[DateTimeOffset]::UtcNow.ToString('o')
    } catch {
        $intent.status='REJECTED'
        $intent.result=[ordered]@{reason=$_.Exception.Message}
        $intent.applied_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Update-AidosControlIntent -Path $path -Intent $intent|Out-Null
    [pscustomobject][ordered]@{intent=[pscustomobject]$intent;path=[IO.Path]::GetRelativePath($root,$path).Replace('\','/')}
}

Export-ModuleMember -Function Get-AidosOperatorControlStatePath,Get-AidosOperatorControlState,Set-AidosOperatorControlState,Get-AidosRuntimeStatusProjection,Get-AidosOperatorSnapshot,Submit-AidosControlIntent
