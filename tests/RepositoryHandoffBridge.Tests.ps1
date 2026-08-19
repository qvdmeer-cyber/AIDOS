[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Bridge([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-repository-bridge-'+[guid]::NewGuid().ToString('N'))
$registry=Join-Path $temp 'registry'
$state=Join-Path $temp 'state'
New-Item -ItemType Directory -Path (Join-Path $registry 'projects'),$state -Force|Out-Null
try{
    $configured=Initialize-AidosRepositoryHandoffBridge -RegistryRoot $registry -BuilderRoot (Join-Path $temp 'builder') -ContractsRoot (Join-Path $temp 'contracts') -AidosRoot $root -StateRoot $state -ProcessName 'ChatGPT Classic Test' -RecoveryIntervalSeconds 10 -MaxProjectsPerTick 4
    Assert-Bridge ([string]$configured.status-eq'CONFIGURED') 'bridge configuration is persisted'
    Assert-Bridge ([string]$configured.config.schema_version-eq'0.4') 'bridge configuration records Human Input transport version'
    Assert-Bridge ([string]$configured.config.builder_root-eq[IO.Path]::GetFullPath((Join-Path $temp 'builder'))) 'bridge configuration binds Builder root'
    Assert-Bridge ([string]$configured.config.process_name-eq'ChatGPT Classic Test') 'bridge configuration binds exact ChatGPT process name'
    $loaded=Read-AidosRepositoryHandoffBridgeConfiguration -StateRoot $state
    Assert-Bridge ([int]$loaded.max_projects_per_tick-eq4) 'bridge configuration round-trips'

    $calls=[pscustomobject]@{preparation=0;runtime=0;worker_adapter=$null;review_adapter=$null}
    $runtimeManager=({
        param($RuntimeRegistryRoot,$RuntimeMaxProjects,$RuntimePush,$WorkerInvoker,$ReviewPublisher)
        $calls.runtime++
        $calls.worker_adapter=$WorkerInvoker
        $calls.review_adapter=$ReviewPublisher
        [pscustomobject][ordered]@{status='IDLE';processed=0;runtime_project_count=0;registry_root=$RuntimeRegistryRoot;max_projects=$RuntimeMaxProjects;push=[bool]$RuntimePush;results=@()}
    }).GetNewClosure()
    $preparationDispatcher=({
        param($RegistryRoot,$BuilderRoot,$ContractsRoot,$MaxItems,$Push,$RuntimeAdapter)
        $calls.preparation++
        $runtime=& $RuntimeAdapter $RegistryRoot $MaxItems $Push
        [pscustomobject][ordered]@{status='IDLE';processed=0;registry_root=$RegistryRoot;builder_root=$BuilderRoot;contracts_root=$ContractsRoot;runtime_result=$runtime;actor_transport_result=[pscustomobject]@{status='DEFERRED_INTERACTIVE_GATE';processed=0}}
    }).GetNewClosure()

    $tick=Invoke-AidosRepositoryHandoffBridgeTick -RegistryRoot $registry -StateRoot $state -BuilderRoot (Join-Path $temp 'builder') -ContractsRoot (Join-Path $temp 'contracts') -AidosRoot $root -ProcessName 'ChatGPT Classic Test' -MaxProjects 4 -PreparationDispatcher $preparationDispatcher -RuntimeManager $runtimeManager
    Assert-Bridge ($calls.preparation-eq1) 'one bridge tick invokes preparation exactly once'
    Assert-Bridge ($calls.runtime-eq1) 'preparation delegates to the repository-aware runtime manager exactly once'
    Assert-Bridge ($null-ne$calls.worker_adapter -and $null-ne$calls.review_adapter) 'runtime manager receives repository Worker and review adapters'
    Assert-Bridge ([string]$tick.preparation.actor_transport_result.status-eq'DEFERRED_INTERACTIVE_GATE') 'legacy Desktop Thinker transport remains deferred'
    Assert-Bridge ([string]$tick.manager.repository_worker_finalization.status-eq'IDLE') 'empty runtime manager has no deferred Worker lifecycle to finalize'
    Assert-Bridge ([string]$tick.human_input_triggers.status-eq'IDLE' -and [int]$tick.human_input_triggers.processed-eq0) 'empty portfolio has no Human Input ChatGPT transport work'
    Assert-Bridge ([string]$tick.status-eq'IDLE') 'empty portfolio remains idle'

    $wake=Signal-AidosRepositoryHandoffBridge -StateRoot $state -Reason TEST -ProjectId P1 -HandoffId ([guid]::NewGuid().ToString())
    Assert-Bridge ([string]$wake.reason-eq'TEST') 'bridge wake signal preserves reason'
    Assert-Bridge (Test-Path -LiteralPath (Get-AidosRepositoryHandoffBridgePath -StateRoot $state -Kind wake) -PathType Leaf) 'bridge wake signal is durable'
    $stop=Stop-AidosRepositoryHandoffBridge -StateRoot $state
    Assert-Bridge ([string]$stop.status-eq'STOP_REQUESTED') 'bridge stop request is durable'

    Write-Output "PASS: $passed repository handoff bridge assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
