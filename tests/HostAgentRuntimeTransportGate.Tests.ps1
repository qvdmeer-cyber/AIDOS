[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPersistentLocalDesktopAgent.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Gate([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-host-transport-gate-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$registry=Join-Path $base 'registry'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects') -Force|Out-Null

    $global:AidosTransportCalls=0
    $deferred=Invoke-AidosPreparationDispatcherTick -RegistryRoot $registry -DeferActorTransport -RuntimeProjectManager {
        param($registryRoot,$maxItems,$push)
        [pscustomobject]@{status='IDLE';processed=0;results=@()}
    } -ActorTransportDispatcher {
        param($project,$assignment,$stateRoot)
        $global:AidosTransportCalls++
        [pscustomobject]@{status='SHOULD_NOT_RUN'}
    }
    Assert-Gate ($deferred.actor_transport_result.status -eq 'DEFERRED_INTERACTIVE_GATE') 'pre-gate dispatcher explicitly defers actor transport'
    Assert-Gate ($global:AidosTransportCalls -eq 0) 'pre-gate dispatcher never invokes desktop actor transport'

    $lockedSnapshot=[pscustomobject]@{
        observed_at='2026-08-18T00:00:00Z';session_id=1;process_session_id=1;active_console_session_id=1;
        connection_state='ACTIVE';lock_state='LOCKED';session_kind='RDP';protocol_type=2;input_desktop_available=$false;
        user_name='qvdm';domain_name='AIDOS';winstation_name='RDP-Tcp#0';observation_status='OK';error=''
    }
    $global:AidosTransportCalls=0
    $locked=Invoke-AidosHostAgentTick -ProjectRoot $projectRoot -AuthorizedUser 'AIDOS\qvdm' -PreparationRegistryRoot $registry `
        -PreparationDispatcher {[pscustomobject]@{status='IDLE'}} `
        -SnapshotProvider {$lockedSnapshot} `
        -ShellHealthProvider {param($processName,$sessionId);[pscustomobject]@{status='HEALTHY';session_id=$sessionId}} `
        -RuntimeActorTransportDispatcher {param($registryRoot,$stateRoot,$processName,$push);$global:AidosTransportCalls++;[pscustomobject]@{status='IDLE';processed=0;results=@()}} `
        -ReviewReconciler {param($root);[pscustomobject]@{status='CLEAN';review_id=$null}}
    Assert-Gate ($locked.status -eq 'WAITING_INFRASTRUCTURE') 'locked session remains fail-closed'
    Assert-Gate ($global:AidosTransportCalls -eq 0) 'locked session cannot invoke runtime actor transport'

    $authorizedSnapshot=[pscustomobject]@{
        observed_at='2026-08-18T00:00:01Z';session_id=1;process_session_id=1;active_console_session_id=1;
        connection_state='ACTIVE';lock_state='UNLOCKED';session_kind='RDP';protocol_type=2;input_desktop_available=$true;
        user_name='qvdm';domain_name='AIDOS';winstation_name='RDP-Tcp#0';observation_status='OK';error=''
    }
    $global:AidosTransportCalls=0
    $authorized=Invoke-AidosHostAgentTick -ProjectRoot $projectRoot -AuthorizedUser 'AIDOS\qvdm' -PreparationRegistryRoot $registry `
        -PreparationDispatcher {[pscustomobject]@{status='IDLE'}} `
        -SnapshotProvider {$authorizedSnapshot} `
        -ShellHealthProvider {param($processName,$sessionId);[pscustomobject]@{status='HEALTHY';session_id=$sessionId}} `
        -RuntimeActorTransportDispatcher {param($registryRoot,$stateRoot,$processName,$push);$global:AidosTransportCalls++;[pscustomobject]@{status='IDLE';processed=0;results=@()}} `
        -ReviewReconciler {param($root);[pscustomobject]@{status='CLEAN';review_id=$null}}
    Assert-Gate ($global:AidosTransportCalls -eq 1) 'authorized healthy shell invokes runtime actor transport exactly once'
    Assert-Gate ($authorized.runtime_actor_transport_result.status -eq 'IDLE') 'host tick exposes post-gate runtime actor transport result'
    Assert-Gate ($authorized.status -eq 'CLEAN') 'post-gate transport does not disturb unrelated clean review state'
} finally {
    Remove-Variable -Name AidosTransportCalls -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed host-agent runtime transport gate assertions"
