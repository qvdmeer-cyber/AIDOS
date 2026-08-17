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

function New-TestSessionSnapshot {
    param(
        [string]$Connection='ACTIVE',
        [string]$Lock='UNLOCKED',
        [string]$Kind='CONSOLE',
        [bool]$InputDesktop=$true,
        [string]$Observation='OK'
    )
    [pscustomobject]@{
        observed_at='2026-08-17T12:00:00Z'
        session_id=1
        process_session_id=1
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

# Deterministic policy assertions.
$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot)
Assert-SessionTest ($decision.allowed -and $decision.reason -eq 'NONE') 'active unlocked console is eligible'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Kind RDP)
Assert-SessionTest $decision.allowed 'active unlocked RDP session is eligible'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Lock LOCKED)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'SESSION_LOCKED') 'locked workstation fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'SESSION_DISCONNECTED') 'disconnected RDP session fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -InputDesktop:$false)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'INPUT_DESKTOP_UNAVAILABLE') 'missing input desktop fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Kind UNKNOWN)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'SESSION_STATE_UNKNOWN') 'unknown protocol/session kind fails closed'

$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Observation PARTIAL)
Assert-SessionTest (-not $decision.allowed -and $decision.reason -eq 'SESSION_STATE_UNKNOWN') 'partial native observation fails closed'

# A second desktop assertion can fail after an eligible WTS snapshot. The wrapper
# must convert that race into an explicit blocking decision, never WAITING/NONE.
$raceGate=[pscustomobject]@{snapshot=$null;decision=$null}
$raceBackend=[pscustomobject]@{
    AssertInteractiveSession={ throw 'Windows session is locked or unavailable.' }
}
$eligibleProvider={ New-TestSessionSnapshot -Kind RDP }
$gated=New-AidosDesktopSessionGateBackend -Backend $raceBackend -Policy SUPERVISED -SnapshotProvider $eligibleProvider -GateState $raceGate
try {
    & $gated.AssertInteractiveSession | Out-Null
    throw 'Expected transient input desktop assertion failure.'
} catch {
    Assert-SessionTest ($raceGate.decision -and -not $raceGate.decision.allowed) 'underlying desktop assertion failure becomes a blocking decision'
    Assert-SessionTest ($raceGate.decision.reason -eq 'INPUT_DESKTOP_UNAVAILABLE') 'desktop assertion race is classified as INPUT_DESKTOP_UNAVAILABLE'
    Assert-SessionTest (-not $raceGate.decision.snapshot.input_desktop_available) 'desktop assertion race records input desktop unavailable'
}

# Legacy waiting state normalization must preserve exact send phase.
$legacySent=[pscustomobject]@{
    schema_version='0.1';review_id='review-1';status='WAITING_INTERACTIVE_SESSION';delivery_status='SENT'
    sent_at='2026-08-17T12:00:00Z';updated_at='2026-08-17T12:00:01Z'
}
$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false)
$normalized=ConvertTo-AidosDesktopWaitingState $legacySent $decision
Assert-SessionTest ($normalized.status -eq 'SENT') 'legacy waiting state preserves SENT transport phase'
Assert-SessionTest (-not $normalized.PSObject.Properties['delivery_status']) 'legacy delivery_status is removed after normalization'
Assert-SessionTest ($normalized.interactive_session.status -eq 'WAITING' -and $normalized.interactive_session.reason -eq 'SESSION_DISCONNECTED') 'SENT wait is represented by the interactive overlay'
Assert-SessionTest ($normalized.sent_at -eq '2026-08-17T12:00:00Z') 'SENT timestamp survives normalization'

$legacyPrepared=[pscustomobject]@{
    schema_version='0.1';review_id='review-2';status='WAITING_INTERACTIVE_SESSION';delivery_status='PREPARED'
    updated_at='2026-08-17T12:00:01Z'
}
$decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Lock LOCKED)
$normalized=ConvertTo-AidosDesktopWaitingState $legacyPrepared $decision
Assert-SessionTest ($normalized.status -eq 'PREPARED') 'legacy waiting state preserves PREPARED transport phase'
Assert-SessionTest ($normalized.interactive_session.status -eq 'WAITING' -and $normalized.interactive_session.reason -eq 'SESSION_LOCKED') 'PREPARED wait is represented by the interactive overlay'

# Real-machine native observation. This does not require the session to be eligible,
# but it must produce a complete, internally coherent Windows snapshot.
$live=Get-AidosInteractiveSessionSnapshot
Assert-SessionTest ($live.observation_status -eq 'OK') "native WTS observation is complete (status=$($live.observation_status), error=$($live.error))"
Assert-SessionTest ($null -ne $live.session_id -and $live.session_id -eq $live.process_session_id) 'native snapshot binds the orchestrator process to its session'
Assert-SessionTest ($live.connection_state -ne 'UNKNOWN') 'native connection state is known'
Assert-SessionTest ($live.lock_state -ne 'UNKNOWN') 'native lock state is known'
Assert-SessionTest ($live.session_kind -in @('CONSOLE','RDP')) 'native protocol resolves to console or RDP'

Write-Output "PASS: $passed Windows interactive session assertions"
Write-Output ($live | ConvertTo-Json -Depth 20 -Compress)
