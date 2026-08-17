[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){ throw 'WindowsSession.Tests.ps1 must run under Windows PowerShell 7.' }

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosDesktopChatGPT.psm1') -Force -DisableNameChecking
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosDesktopSessionGate.psm1') -Force -DisableNameChecking
# Import the session module last. The gate imports it as a nested dependency with
# -Force; importing it again here makes its public commands available to this
# standalone caller scope as well.
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosWindowsSession.psm1') -Force -DisableNameChecking

$passed=0
function Assert-SessionTest([bool]$Condition,[string]$Message){
    if(-not $Condition){ throw "ASSERTION FAILED: $Message" }
    $script:passed++
}

function Assert-SessionThrows([scriptblock]$Script,[string]$Pattern,[string]$Message){
    try { & $Script; throw "ASSERTION FAILED: $Message (no exception)" }
    catch {
        if($_.Exception.Message -like 'ASSERTION FAILED:*'){ throw }
        if($_.Exception.Message -notmatch $Pattern){ throw "ASSERTION FAILED: $Message (actual='$($_.Exception.Message)')" }
        $script:passed++
    }
}

function New-TestSessionSnapshot {
    param(
        [string]$Connection='ACTIVE',
        [string]$Lock='UNLOCKED',
        [string]$Kind='CONSOLE',
        [bool]$InputDesktop=$true,
        [string]$Observation='OK',
        [Nullable[int]]$SessionId=1,
        [Nullable[int]]$ProcessSessionId=1
    )
    [pscustomobject]@{
        observed_at='2026-08-17T12:00:00Z'
        session_id=$SessionId
        process_session_id=$ProcessSessionId
        active_console_session_id=1
        connection_state=$Connection
        lock_state=$Lock
        session_kind=$Kind
        protocol_type=if($Kind -eq 'RDP'){2}elseif($Kind -eq 'CONSOLE'){0}else{$null}
        input_desktop_available=$InputDesktop
        user_name='aidos'
        domain_name='AIDOS'
        winstation_name=if($Kind -eq 'RDP'){'RDP-Tcp#1'}else{'Console'}
        observation_status=$Observation
        error=$null
    }
}

# Deterministic machine/session policy assertions.
$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot)
Assert-SessionTest ($decision.allowed -and $decision.reason -eq 'NONE') 'active unlocked console is eligible'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Kind RDP)
Assert-SessionTest $decision.allowed 'active unlocked RDP session is eligible'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false)
Assert-SessionTest ($decision.allowed -and $decision.reason -eq 'NONE') 'disconnected unlocked RDP session remains eligible'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Kind RDP -InputDesktop:$false)
Assert-SessionTest ($decision.allowed -and $decision.reason -eq 'NONE') 'input desktop availability is transport readiness, not machine authorization'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Lock LOCKED)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'SESSION_LOCKED') 'locked workstation fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Connection DOWN)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'NO_INTERACTIVE_SESSION') 'down session fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Kind UNKNOWN)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'SESSION_STATE_UNKNOWN') 'unknown protocol/session kind fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Observation PARTIAL)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'SESSION_STATE_UNKNOWN') 'partial native observation fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -SessionId 1 -ProcessSessionId 2)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'NO_INTERACTIVE_SESSION') 'process/session identity mismatch fails closed'

# Legacy waiting state normalization must preserve exact send phase.
$legacySent=[pscustomobject]@{
    schema_version='0.1';review_id='review-1';status='WAITING_INTERACTIVE_SESSION';delivery_status='SENT'
    sent_at='2026-08-17T12:00:00Z';updated_at='2026-08-17T12:00:01Z'
}
$blocked=[pscustomobject]@{allowed=$false;policy='SUPERVISED';reason='SESSION_LOCKED';snapshot=(New-TestSessionSnapshot -Lock LOCKED)}
$normalized=ConvertTo-AidosDesktopWaitingState $legacySent $blocked
Assert-SessionTest ($normalized.status -eq 'SENT') 'legacy waiting state preserves SENT transport phase'
Assert-SessionTest (-not $normalized.PSObject.Properties['delivery_status']) 'legacy delivery_status is removed after normalization'
Assert-SessionTest ($normalized.interactive_session.status -eq 'WAITING' -and $normalized.interactive_session.reason -eq 'SESSION_LOCKED') 'SENT wait is represented by the interactive overlay'
Assert-SessionTest ($normalized.sent_at -eq '2026-08-17T12:00:00Z') 'SENT timestamp survives normalization'

$legacyPrepared=[pscustomobject]@{
    schema_version='0.1';review_id='review-2';status='WAITING_INTERACTIVE_SESSION';delivery_status='PREPARED'
    updated_at='2026-08-17T12:00:01Z'
}
$transition=[pscustomobject]@{allowed=$false;policy='SUPERVISED';reason='DESKTOP_TRANSITION_UNAVAILABLE';snapshot=(New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false)}
$normalized=ConvertTo-AidosDesktopWaitingState $legacyPrepared $transition
Assert-SessionTest ($normalized.status -eq 'PREPARED') 'transient desktop transition preserves PREPARED transport phase'
Assert-SessionTest ($normalized.interactive_session.status -eq 'WAITING' -and $normalized.interactive_session.reason -eq 'DESKTOP_TRANSITION_UNAVAILABLE') 'desktop transition gets an explicit transient reason'

$allowed=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false)
Assert-SessionThrows { ConvertTo-AidosDesktopWaitingState $legacyPrepared $allowed | Out-Null } 'requires a blocking or transient reason' 'WAITING plus reason NONE is impossible'

# Gate backend converts a transport-level desktop assertion race into a retryable
# transition only while the fresh WTS policy still authorizes the session.
$throwingBackend=[pscustomobject]@{
    AssertInteractiveSession={ throw 'Windows session is locked or unavailable.' }
    GetProcessContext={ param($n) $null }
}
$gateState=[pscustomobject]@{snapshot=$null;decision=$null}
$provider={ New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false }
$gated=New-AidosDesktopSessionGateBackend -Backend $throwingBackend -Policy SUPERVISED -SnapshotProvider $provider -GateState $gateState
Assert-SessionThrows { & $gated.AssertInteractiveSession | Out-Null } 'desktop is transitioning' 'transport desktop race is surfaced as retryable transition'
Assert-SessionTest (-not $gateState.decision.allowed -and $gateState.decision.reason -eq 'DESKTOP_TRANSITION_UNAVAILABLE') 'retryable transition has explicit non-NONE reason'
Assert-SessionTest ($gateState.decision.snapshot.connection_state -eq 'DISCONNECTED' -and $gateState.decision.snapshot.lock_state -eq 'UNLOCKED') 'retryable transition preserves disconnected/unlocked WTS evidence'

# If a fresh observation says LOCKED, the underlying transport failure must remain
# a real supervised stop rather than being converted to a retryable transition.
$gateState=[pscustomobject]@{snapshot=$null;decision=$null}
$lockedProvider={ New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -Lock LOCKED -InputDesktop:$false }
$gated=New-AidosDesktopSessionGateBackend -Backend $throwingBackend -Policy SUPERVISED -SnapshotProvider $lockedProvider -GateState $gateState
Assert-SessionThrows { & $gated.AssertInteractiveSession | Out-Null } 'SESSION_LOCKED' 'locked session remains a real policy stop'
Assert-SessionTest (-not $gateState.decision.allowed -and $gateState.decision.reason -eq 'SESSION_LOCKED') 'locked refresh is not downgraded to desktop transition'

# Real-machine native observation. The caller may currently be console, active RDP,
# or (when invoked by an external harness) a disconnected RDP session. The snapshot
# must still be complete and session-bound.
$live=Get-AidosInteractiveSessionSnapshot
Assert-SessionTest ($live.observation_status -eq 'OK') "native WTS observation is complete (status=$($live.observation_status), error=$($live.error))"
Assert-SessionTest ($null -ne $live.session_id -and $live.session_id -eq $live.process_session_id) 'native snapshot binds the orchestrator process to its session'
Assert-SessionTest ($live.connection_state -ne 'UNKNOWN') 'native connection state is known'
Assert-SessionTest ($live.lock_state -ne 'UNKNOWN') 'native lock state is known'
Assert-SessionTest ($live.session_kind -in @('CONSOLE','RDP')) 'native protocol resolves to console or RDP'

Write-Output "PASS: $passed Windows interactive session assertions"
Write-Output ($live | ConvertTo-Json -Depth 20 -Compress)
