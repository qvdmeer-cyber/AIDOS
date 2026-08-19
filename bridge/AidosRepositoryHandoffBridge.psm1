Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeProjectManager.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorAssignments.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryActorHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryWorkerHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryThinkerBinding.psm1') -DisableNameChecking

function Get-AidosRepositoryHandoffBridgePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[ValidateSet('config','status','stop','wake')][string]$Kind)
    $names=@{config='CONFIG.json';status='STATUS.json';stop='STOP';wake='WAKE.json'}
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) $names[$Kind]
}
function Write-AidosRepositoryHandoffBridgeJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $dir=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Initialize-AidosRepositoryHandoffBridge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [string]$ContractsRoot,
        [string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),
        [string]$StateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),
        [int]$RecoveryIntervalSeconds=30,
        [int]$MaxProjectsPerTick=6
    )
    if($RecoveryIntervalSeconds-lt5){throw 'Repository handoff bridge recovery interval must be at least 5 seconds.'}
    if($MaxProjectsPerTick-lt1){throw 'Repository handoff bridge MaxProjectsPerTick must be at least 1.'}
    $state=[IO.Path]::GetFullPath($StateRoot)
    $config=[pscustomobject][ordered]@{schema_version='0.1';registry_root=[IO.Path]::GetFullPath($RegistryRoot);contracts_root=if([string]::IsNullOrWhiteSpace($ContractsRoot)){$null}else{[IO.Path]::GetFullPath($ContractsRoot)};aidos_root=[IO.Path]::GetFullPath($AidosRoot);state_root=$state;recovery_interval_seconds=$RecoveryIntervalSeconds;max_projects_per_tick=$MaxProjectsPerTick;configured_at=[DateTimeOffset]::UtcNow.ToString('o')}
    Write-AidosRepositoryHandoffBridgeJsonAtomic -Path (Get-AidosRepositoryHandoffBridgePath -StateRoot $state -Kind config) -Value $config
    [pscustomobject][ordered]@{status='CONFIGURED';config=$config}
}
function Read-AidosRepositoryHandoffBridgeConfiguration {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot))
    $path=Get-AidosRepositoryHandoffBridgePath -StateRoot $StateRoot -Kind config
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Repository handoff bridge is not configured.'}
    Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
}
function Signal-AidosRepositoryHandoffBridge {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),[string]$Reason='EXTERNAL_RESULT',[string]$ProjectId,[string]$HandoffId)
    $value=[pscustomobject][ordered]@{schema_version='0.1';reason=$Reason;project_id=if([string]::IsNullOrWhiteSpace($ProjectId)){$null}else{$ProjectId};handoff_id=if([string]::IsNullOrWhiteSpace($HandoffId)){$null}else{$HandoffId};signaled_at=[DateTimeOffset]::UtcNow.ToString('o');nonce=[guid]::NewGuid().ToString()}
    Write-AidosRepositoryHandoffBridgeJsonAtomic -Path (Get-AidosRepositoryHandoffBridgePath -StateRoot $StateRoot -Kind wake) -Value $value
    $value
}

function Publish-AidosPendingRepositoryActorHandoffs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$StateRoot,[int]$MaxItems=20,[switch]$Push,[scriptblock]$ThinkerTrigger)
    $results=[Collections.Generic.List[object]]::new();$processed=0
    foreach($project in @(Get-AidosRuntimeRegistryProjects -RegistryRoot $RegistryRoot)){
        if($processed-ge$MaxItems){break}
        $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
        foreach($pending in @(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $root)){
            if($processed-ge$MaxItems){break}
            $assignment=$pending.assignment
            if([string]$assignment.actor_role-ne'THINKER'){continue}
            try{
                $published=Publish-AidosRuntimeActorRepositoryHandoff -Project $project -AssignmentId ([string]$assignment.assignment_id) -Push:$Push
                $handoff=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$project.project_id)
                $trigger=if($null-eq$handoff -or [string]$handoff.metadata.kind-ne'ASSIGNMENT' -or [string]$handoff.metadata.to_actor-ne'THINKER'){$null}elseif($ThinkerTrigger){&$ThinkerTrigger $StateRoot $handoff}else{Invoke-AidosRepositoryThinkerTrigger -StateRoot $StateRoot -Handoff $handoff}
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;assignment_id=[string]$assignment.assignment_id;status='PUBLISHED';publication=$published;trigger=$trigger})
            }catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;assignment_id=[string]$assignment.assignment_id;status='ERROR';error=$_.Exception.Message})}
            $processed++
        }
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object status -eq'ERROR').Count){'ERROR'}elseif($processed){'PROCESSED'}else{'IDLE'};processed=$processed;results=$results.ToArray()}
}

function Invoke-AidosCurrentRepositoryThinkerTriggers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$StateRoot,[int]$MaxItems=20,[scriptblock]$ThinkerTrigger)
    $results=[Collections.Generic.List[object]]::new();$processed=0
    foreach($project in @(Get-AidosRuntimeRegistryProjects -RegistryRoot $RegistryRoot)){
        if($processed-ge$MaxItems){break}
        try{
            $handoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId ([string]$project.project_id)
            if($null-eq$handoff -or [string]$handoff.metadata.kind-ne'ASSIGNMENT' -or [string]$handoff.metadata.to_actor-ne'THINKER'){continue}
            $trigger=if($ThinkerTrigger){&$ThinkerTrigger $StateRoot $handoff}else{Invoke-AidosRepositoryThinkerTrigger -StateRoot $StateRoot -Handoff $handoff}
            $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;handoff_id=[string]$handoff.metadata.handoff_id;status=[string]$trigger.status;trigger=$trigger});$processed++
        }catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='ERROR';error=$_.Exception.Message});$processed++}
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object status -eq'ERROR').Count){'ERROR'}elseif($processed){'PROCESSED'}else{'IDLE'};processed=$processed;results=$results.ToArray()}
}

function Invoke-AidosRepositoryHandoffBridgeTick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$StateRoot,
        [string]$ContractsRoot,
        [string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),
        [int]$MaxProjects=6,
        [switch]$Push,
        [scriptblock]$CodexInvoker,
        [scriptblock]$ThinkerTrigger
    )
    $workerInvoker={param($Project,$ExecutionPath) Invoke-AidosRepositoryWorkerHandoff -Project $Project -ExecutionPath $ExecutionPath -Push:$Push -CodexInvoker $CodexInvoker}.GetNewClosure()
    $reviewPublisher={param($Project) Publish-AidosRepositoryReviewHandoff -Project $Project -Push:$Push}.GetNewClosure()
    $manager=Invoke-AidosRuntimeProjectManagerTick -RegistryRoot $RegistryRoot -MaxProjects $MaxProjects -Push:$Push -ContractsRoot $ContractsRoot -AidosRoot $AidosRoot -WorkerInvoker $workerInvoker -ReviewPublisher $reviewPublisher
    $published=Publish-AidosPendingRepositoryActorHandoffs -RegistryRoot $RegistryRoot -StateRoot $StateRoot -MaxItems ($MaxProjects*4) -Push:$Push -ThinkerTrigger $ThinkerTrigger
    $triggers=Invoke-AidosCurrentRepositoryThinkerTriggers -RegistryRoot $RegistryRoot -StateRoot $StateRoot -MaxItems ($MaxProjects*2) -ThinkerTrigger $ThinkerTrigger
    [pscustomobject][ordered]@{
        schema_version='0.1';observed_at=[DateTimeOffset]::UtcNow.ToString('o');manager=$manager;pending_actor_handoffs=$published;thinker_triggers=$triggers;status=if([string]$manager.status-eq'ERROR' -or [string]$published.status-eq'ERROR' -or [string]$triggers.status-eq'ERROR'){'ERROR'}elseif([string]$manager.status-eq'ACTIONABLE' -or [int]$published.processed-gt0 -or [int]$triggers.processed-gt0){'ACTIONABLE'}else{'IDLE'}
    }
}

function Start-AidosRepositoryHandoffBridge {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),[switch]$Push)
    $config=Read-AidosRepositoryHandoffBridgeConfiguration -StateRoot $StateRoot
    $statusPath=Get-AidosRepositoryHandoffBridgePath -StateRoot $StateRoot -Kind status
    $stopPath=Get-AidosRepositoryHandoffBridgePath -StateRoot $StateRoot -Kind stop
    $wakePath=Get-AidosRepositoryHandoffBridgePath -StateRoot $StateRoot -Kind wake
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    $lastWake=''
    try{
        while(-not(Test-Path -LiteralPath $stopPath -PathType Leaf)){
            $started=[DateTimeOffset]::UtcNow
            $tick=Invoke-AidosRepositoryHandoffBridgeTick -RegistryRoot ([string]$config.registry_root) -StateRoot ([string]$config.state_root) -ContractsRoot ([string]$config.contracts_root) -AidosRoot ([string]$config.aidos_root) -MaxProjects ([int]$config.max_projects_per_tick) -Push:$Push
            Write-AidosRepositoryHandoffBridgeJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='RUNNING';pid=$PID;heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o');last_tick=$tick})
            $deadline=$started.AddSeconds([int]$config.recovery_interval_seconds)
            while([DateTimeOffset]::UtcNow-lt$deadline -and -not(Test-Path -LiteralPath $stopPath -PathType Leaf)){
                Start-Sleep -Milliseconds 250
                if(Test-Path -LiteralPath $wakePath -PathType Leaf){$current=(Get-FileHash -LiteralPath $wakePath -Algorithm SHA256).Hash;if($current-ne$lastWake){$lastWake=$current;break}}
            }
        }
        Write-AidosRepositoryHandoffBridgeJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='STOPPED';pid=$PID;stopped_at=[DateTimeOffset]::UtcNow.ToString('o')})
    }catch{Write-AidosRepositoryHandoffBridgeJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='ERROR';pid=$PID;observed_at=[DateTimeOffset]::UtcNow.ToString('o');error=$_.Exception.Message});throw}
}
function Stop-AidosRepositoryHandoffBridge {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot))
    $path=Get-AidosRepositoryHandoffBridgePath -StateRoot $StateRoot -Kind stop
    $dir=Split-Path -Parent $path;if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Set-Content -LiteralPath $path -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
    [pscustomobject][ordered]@{status='STOP_REQUESTED';state_root=[IO.Path]::GetFullPath($StateRoot)}
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffBridgePath,Write-AidosRepositoryHandoffBridgeJsonAtomic,Initialize-AidosRepositoryHandoffBridge,Read-AidosRepositoryHandoffBridgeConfiguration,Signal-AidosRepositoryHandoffBridge,Publish-AidosPendingRepositoryActorHandoffs,Invoke-AidosCurrentRepositoryThinkerTriggers,Invoke-AidosRepositoryHandoffBridgeTick,Start-AidosRepositoryHandoffBridge,Stop-AidosRepositoryHandoffBridge
