Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../bridge/AidosBridge.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $PSScriptRoot '../bridge/AidosDesktopChatGPT.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $PSScriptRoot '../bridge/AidosWindowsSession.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $PSScriptRoot '../bridge/AidosDesktopSessionGate.psm1') -Force -DisableNameChecking

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
            protocol_type=if($Kind -eq 'RDP'){2}else{0}
            input_desktop_available=$InputDesktop
            user_name='aidos'
            domain_name='AIDOS'
            winstation_name=if($Kind -eq 'RDP'){'RDP-Tcp#1'}else{'Console'}
            observation_status=$Observation
            error=$null
        }
    }
}

Describe 'AIDOS native interactive session policy' {
    It 'allows an active unlocked console with an input desktop' {
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot)
        $decision.allowed | Should -BeTrue
        $decision.reason | Should -Be 'NONE'
    }

    It 'allows an active unlocked RDP session with an input desktop' {
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Kind RDP)
        $decision.allowed | Should -BeTrue
    }

    It 'fails closed when the workstation is locked' {
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Lock LOCKED)
        $decision.allowed | Should -BeFalse
        $decision.reason | Should -Be 'SESSION_LOCKED'
    }

    It 'fails closed when an RDP session is disconnected' {
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false)
        $decision.allowed | Should -BeFalse
        $decision.reason | Should -Be 'SESSION_DISCONNECTED'
    }

    It 'fails closed when the input desktop is unavailable' {
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -InputDesktop:$false)
        $decision.allowed | Should -BeFalse
        $decision.reason | Should -Be 'INPUT_DESKTOP_UNAVAILABLE'
    }

    It 'fails closed for unknown protocol/session kind' {
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Kind UNKNOWN)
        $decision.allowed | Should -BeFalse
        $decision.reason | Should -Be 'SESSION_STATE_UNKNOWN'
    }
}

Describe 'Desktop adapter waiting overlay' {
    It 'preserves SENT as the transport phase instead of replacing it with WAITING_INTERACTIVE_SESSION' {
        $state=[pscustomobject]@{
            schema_version='0.1'
            review_id='review-1'
            status='WAITING_INTERACTIVE_SESSION'
            delivery_status='SENT'
            sent_at='2026-08-17T12:00:00Z'
            updated_at='2026-08-17T12:00:01Z'
        }
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Connection DISCONNECTED -Kind RDP -InputDesktop:$false)
        $normalized=ConvertTo-AidosDesktopWaitingState $state $decision
        $normalized.status | Should -Be 'SENT'
        $normalized.PSObject.Properties['delivery_status'] | Should -BeNullOrEmpty
        $normalized.interactive_session.status | Should -Be 'WAITING'
        $normalized.interactive_session.reason | Should -Be 'SESSION_DISCONNECTED'
        $normalized.sent_at | Should -Be '2026-08-17T12:00:00Z'
    }

    It 'preserves PREPARED before the first desktop send' {
        $state=[pscustomobject]@{
            schema_version='0.1'
            review_id='review-2'
            status='WAITING_INTERACTIVE_SESSION'
            delivery_status='PREPARED'
            updated_at='2026-08-17T12:00:01Z'
        }
        $decision=Test-AidosInteractiveSessionPolicy (New-TestSessionSnapshot -Lock LOCKED)
        $normalized=ConvertTo-AidosDesktopWaitingState $state $decision
        $normalized.status | Should -Be 'PREPARED'
        $normalized.interactive_session.status | Should -Be 'WAITING'
        $normalized.interactive_session.reason | Should -Be 'SESSION_LOCKED'
    }
}
