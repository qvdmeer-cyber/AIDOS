[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){ throw 'PersistentLocalDesktopAgent.Tests.ps1 must run under Windows PowerShell 7.' }
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosWindowsSession.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDesktopChatGPT.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPersistentLocalDesktopAgent.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Agent([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-AgentThrows([scriptblock]$Block,[string]$Pattern){try{& $Block;throw 'expected throw'}catch{if($_.Exception.Message -eq 'expected throw'){throw};Assert-Agent ($_.Exception.Message -match $Pattern) "unexpected error: $($_.Exception.Message)"}}
function New-AgentSnapshot([string]$Kind='CONSOLE',[string]$Lock='UNLOCKED',[string]$Connection='ACTIVE',[int]$Id=8){[pscustomobject]@{observed_at='2026-08-17T12:00:00Z';session_id=$Id;process_session_id=$Id;active_console_session_id=if($Kind -eq 'CONSOLE'){$Id}else{1};connection_state=$Connection;lock_state=$Lock;session_kind=$Kind;protocol_type=if($Kind -eq 'RDP'){2}else{0};input_desktop_available=$true;user_name='qvdm';domain_name='AIDOS';winstation_name='Console';observation_status='OK';error=$null}}

$stateRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-host-agent-test-'+[guid]::NewGuid().ToString('N'))
try {
    $lease=Acquire-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'owner-one'
    Assert-Agent ($lease.owner_id -eq 'owner-one') 'first host agent obtains singleton lease'
    Assert-AgentThrows {Acquire-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'owner-two'} 'already exists'
    Assert-AgentThrows {Release-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'owner-two'} 'owner mismatch'
    Release-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'owner-one'
    Assert-Agent ((Acquire-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'owner-three').owner_id -eq 'owner-three') 'lease can be acquired after orderly stop'
    Release-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'owner-three'
    @{schema_version='0.1';owner_id='dead-owner';pid=999999;started_at='2026-08-17T12:00:00Z';process_started_at='2026-08-17T12:00:00Z'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $stateRoot 'LEASE.json') -Encoding utf8NoBOM
    Assert-Agent ((Acquire-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'reclaimed').owner_id -eq 'reclaimed') 'a provably dead host lease is reclaimed during restart reconciliation'
    Release-AidosHostAgentLease -StateRoot $stateRoot -OwnerId 'reclaimed'

    $disconnected=Test-AidosAuthorizedInteractiveSession -Snapshot (New-AgentSnapshot -Kind RDP -Connection DISCONNECTED) -AuthorizedUser 'AIDOS\qvdm'
    Assert-Agent ($disconnected.allowed) 'disconnected unlocked authorized RDP session remains eligible'
    $locked=Test-AidosAuthorizedInteractiveSession -Snapshot (New-AgentSnapshot -Lock LOCKED) -AuthorizedUser 'AIDOS\qvdm'
    Assert-Agent (-not $locked.allowed -and $locked.reason -eq 'SESSION_LOCKED') 'locked session blocks desktop agent action'
    $lockedTick=Invoke-AidosHostAgentTick -ProjectRoot (Join-Path $stateRoot 'must-not-touch') -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-AgentSnapshot -Lock LOCKED}
    Assert-Agent ($lockedTick.status -eq 'WAITING_INFRASTRUCTURE' -and $lockedTick.reason -eq 'SESSION_LOCKED') 'lock prevents reconciliation and every desktop action'
    $wrong=Test-AidosAuthorizedInteractiveSession -Snapshot (New-AgentSnapshot) -AuthorizedUser 'AIDOS\other'
    Assert-Agent (-not $wrong.allowed -and $wrong.reason -eq 'AUTHORIZED_USER_MISMATCH') 'mismatched user fails closed'
    $global:AidosHostAgentTestReconciled=$false
    $unknownTick=Invoke-AidosHostAgentTick -ProjectRoot (Join-Path $stateRoot 'must-not-touch-unknown') -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-AgentSnapshot -Lock UNKNOWN} -ReviewReconciler {$global:AidosHostAgentTestReconciled=$true;throw 'must not reconcile'}
    Assert-Agent ($unknownTick.status -eq 'WAITING_INFRASTRUCTURE' -and $unknownTick.reason -eq 'SESSION_STATE_UNKNOWN' -and -not $global:AidosHostAgentTestReconciled) 'unknown session identity fails closed before durable review or desktop work'
    Remove-Variable -Name AidosHostAgentTestReconciled -Scope Global -ErrorAction SilentlyContinue

    # The host agent composes the durable adapter and consumer.  These injected
    # seams keep the orchestration test deterministic while the adapter's own
    # binding/hash validation remains covered by Bridge.Tests.ps1.
    $reviewId='agent-review-1'
    $reviewDir=Join-Path $stateRoot ".aidos/reviews/$reviewId"
    New-Item -ItemType Directory -Path $reviewDir -Force|Out-Null
    @{review_id=$reviewId;assignment_path=".aidos/reviews/$reviewId/REVIEW_ASSIGNMENT.json"}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $reviewDir 'REVIEW.json') -Encoding utf8NoBOM
    $adapterDir=Get-AidosDesktopChatGPTReviewPath $stateRoot $reviewId
    New-Item -ItemType Directory -Path $adapterDir -Force|Out-Null
    @{review_id=$reviewId;status='HANDOFF_COMPLETE'}|ConvertTo-Json|Set-Content -LiteralPath (Get-AidosDesktopChatGPTStatePath $stateRoot $reviewId) -Encoding utf8NoBOM
    '{}'|Set-Content -LiteralPath (Get-AidosDesktopChatGPTResponsePath $stateRoot $reviewId) -Encoding utf8NoBOM
    $global:AidosHostAgentTestConsumeCount=0
    $completeTick=Invoke-AidosHostAgentTick -ProjectRoot $stateRoot -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-AgentSnapshot} -ShellHealthProvider {[pscustomobject]@{status='HEALTHY'}} -ReviewReconciler {[pscustomobject]@{status='PUBLISHED';review_id=$reviewId}} -ReviewConsumer {param($root,$responsePath) $global:AidosHostAgentTestConsumeCount++;[pscustomobject]@{status='CLEANED'}} -DesktopReviewInvoker {throw 'completed response must never be re-sent'}
    Assert-Agent ($completeTick.status -eq 'CONSUMED' -and $global:AidosHostAgentTestConsumeCount -eq 1) 'validated HANDOFF_COMPLETE response is consumed without desktop resend'
    $alreadyCleanTick=Invoke-AidosHostAgentTick -ProjectRoot $stateRoot -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-AgentSnapshot} -ShellHealthProvider {[pscustomobject]@{status='HEALTHY'}} -ReviewReconciler {[pscustomobject]@{status='CLEANED';review_id=$reviewId}} -ReviewConsumer {throw 'a cleaned response must not be consumed twice'} -DesktopReviewInvoker {throw 'a cleaned response must not be re-sent'}
    Assert-Agent ($alreadyCleanTick.status -eq 'CLEANED' -and $global:AidosHostAgentTestConsumeCount -eq 1) 'cleanup reconciliation makes validated response consumption exactly once'

    $failedConsumeTick=Invoke-AidosHostAgentTick -ProjectRoot $stateRoot -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-AgentSnapshot} -ShellHealthProvider {[pscustomobject]@{status='HEALTHY'}} -ReviewReconciler {[pscustomobject]@{status='PUBLISHED';review_id=$reviewId}} -ReviewConsumer {throw 'response binding mismatch'} -DesktopReviewInvoker {throw 'a failed consume must never trigger desktop resend'}
    Assert-Agent ($failedConsumeTick.status -eq 'RECOVERY_REQUIRED' -and $failedConsumeTick.reason -match 'REVIEW_CONSUME_FAILED') 'a handoff consumer validation failure fails closed without a desktop resend'

    Remove-Item -LiteralPath (Get-AidosDesktopChatGPTResponsePath $stateRoot $reviewId) -Force
    $global:AidosHostAgentTestDesktopCalls=0
    foreach($phase in @('PREPARED','SENT','RECEIVED')){
        @{review_id=$reviewId;status=$phase}|ConvertTo-Json|Set-Content -LiteralPath (Get-AidosDesktopChatGPTStatePath $stateRoot $reviewId) -Encoding utf8NoBOM
        $restartedTick=Invoke-AidosHostAgentTick -ProjectRoot $stateRoot -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-AgentSnapshot -Kind CONSOLE} -ShellHealthProvider {[pscustomobject]@{status='HEALTHY'}} -ReviewReconciler {[pscustomobject]@{status='PUBLISHED';review_id=$reviewId}} -DesktopReviewInvoker {param($root,$assignmentPath) $global:AidosHostAgentTestDesktopCalls++;[pscustomobject]@{status=$phase;review_id=$reviewId;idempotent=$true}}
        Assert-Agent ($restartedTick.status -eq $phase) "restart reconciliation preserves $phase adapter phase"
    }
    Assert-Agent ($global:AidosHostAgentTestDesktopCalls -eq 3) 'PREPARED/SENT/RECEIVED each enter only the existing adapter recovery path, never a fresh publish'
    Remove-Variable -Name AidosHostAgentTestConsumeCount -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name AidosHostAgentTestDesktopCalls -Scope Global -ErrorAction SilentlyContinue

    $script:handoffPhase=0
    $provider={if($script:handoffPhase -eq 0){New-AgentSnapshot -Kind RDP -Id 12}else{New-AgentSnapshot -Kind CONSOLE -Id 12}}
    $handoff=Invoke-AidosAuthorizedSessionHandoffToConsole -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider $provider -TsconInvoker {param($sid) Assert-Agent ($sid -eq 12) 'handoff invokes only observed authorized session id';$script:handoffPhase=1}
    Assert-Agent ($handoff.status -eq 'HANDOFF_COMPLETE' -and $handoff.before.session_id -eq $handoff.after.session_id) 'handoff preserves session id and proves console topology'
    $already=Invoke-AidosAuthorizedSessionHandoffToConsole -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-AgentSnapshot -Kind CONSOLE -Id 12} -TsconInvoker {throw 'must not invoke'}
    Assert-Agent ($already.status -eq 'ALREADY_CONSOLE') 'console handoff is idempotent'
    $script:sourceChanged=0
    $changedBeforeHandoff=Invoke-AidosAuthorizedSessionHandoffToConsole -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {if($script:sourceChanged++ -eq 0){New-AgentSnapshot -Kind RDP -Id 12}else{New-AgentSnapshot -Kind CONSOLE -Id 12}} -TsconInvoker {throw 'must not invoke after topology changed'}
    Assert-Agent ($changedBeforeHandoff.status -eq 'ALREADY_CONSOLE') 'a console transition during handoff re-query does not invoke tscon'
} finally {if(Test-Path $stateRoot){Remove-Item -LiteralPath $stateRoot -Recurse -Force}}
Write-Output "PASS: $passed persistent local desktop agent assertions"
