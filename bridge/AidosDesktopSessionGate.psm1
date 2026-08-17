Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosWindowsSession.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -Force -DisableNameChecking

function New-AidosDesktopSessionGateBackend {
    param(
        [Parameter(Mandatory)]$Backend,
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$Policy='SUPERVISED',
        [scriptblock]$SnapshotProvider,
        [Parameter(Mandatory)]$GateState
    )
    $assertUnderlying=$Backend.AssertInteractiveSession
    $provider=$SnapshotProvider
    $gate=$GateState
    $props=[ordered]@{}
    foreach($p in $Backend.PSObject.Properties){ $props[$p.Name]=$p.Value }
    $props['AssertInteractiveSession']=({
        param()
        $snapshot=if($provider){ & $provider }else{ Get-AidosInteractiveSessionSnapshot }
        $decision=Test-AidosInteractiveSessionPolicy -Snapshot $snapshot -Policy $Policy
        $gate.snapshot=$snapshot
        $gate.decision=$decision
        if(-not $decision.allowed){ throw "Interactive ChatGPT action blocked by session policy: $($decision.reason)." }
        if($assertUnderlying){
            try {
                & $assertUnderlying | Out-Null
            } catch {
                # The Windows backend's underlying interactive assertion is a second
                # OpenInputDesktop check immediately before UIA use. If that check
                # fails after the native policy snapshot was eligible, availability
                # changed inside the race window. Persist the stricter observation;
                # WAITING must never be paired with reason=NONE.
                $strict=[ordered]@{}
                foreach($p in $snapshot.PSObject.Properties){ $strict[$p.Name]=$p.Value }
                $strict.input_desktop_available=$false
                $strict.observation_status='OK'
                $strict.error="UNDERLYING_INTERACTIVE_ASSERTION_FAILED: $($_.Exception.Message)"
                $strict.observed_at=[DateTimeOffset]::UtcNow.ToString('o')
                $snapshot=[pscustomobject]$strict
                $decision=Test-AidosInteractiveSessionPolicy -Snapshot $snapshot -Policy $Policy
                $gate.snapshot=$snapshot
                $gate.decision=$decision
                throw "Interactive ChatGPT action blocked by session policy: $($decision.reason)."
            }
        }
        $true
    }).GetNewClosure()
    [pscustomobject]$props
}

function New-AidosDesktopInteractiveOverlay {
    param([Parameter(Mandatory)]$Decision,[ValidateSet('AVAILABLE','WAITING')][string]$Status)
    $s=$Decision.snapshot
    [ordered]@{
        status=$Status
        reason=if($Status -eq 'AVAILABLE'){'NONE'}else{[string]$Decision.reason}
        policy=[string]$Decision.policy
        observed_session_id=$s.session_id
        process_session_id=$s.process_session_id
        active_console_session_id=$s.active_console_session_id
        session_kind=[string]$s.session_kind
        connection_state=[string]$s.connection_state
        lock_state=[string]$s.lock_state
        input_desktop_available=[bool]$s.input_desktop_available
        user_name=[string]$s.user_name
        domain_name=[string]$s.domain_name
        winstation_name=[string]$s.winstation_name
        observation_status=[string]$s.observation_status
        observation_error=[string]$s.error
        observed_at=[string]$s.observed_at
    }
}

function ConvertTo-AidosDesktopWaitingState {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Decision
    )
    $phase=if([string]$State.delivery_status -in @('PREPARED','SENT')){[string]$State.delivery_status}elseif([string]$State.status -in @('PREPARED','SENT','RECEIVED','VALIDATED','HANDOFF_COMPLETE')){[string]$State.status}else{'PREPARED'}
    $o=[ordered]@{}
    foreach($p in $State.PSObject.Properties){
        if($p.Name -notin @('delivery_status','interactive_session')){ $o[$p.Name]=$p.Value }
    }
    $o.status=$phase
    $o.interactive_session=New-AidosDesktopInteractiveOverlay -Decision $Decision -Status WAITING
    $o.last_error=[string]$Decision.reason
    $o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    [pscustomobject]$o
}

function Set-AidosDesktopInteractiveOverlay {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ReviewId,
        [Parameter(Mandatory)]$Decision,
        [ValidateSet('AVAILABLE','WAITING')][string]$Status='AVAILABLE'
    )
    $state=Read-AidosDesktopChatGPTState $ProjectRoot $ReviewId
    if(-not $state){ return $null }
    $o=[ordered]@{}
    foreach($p in $state.PSObject.Properties){
        if($p.Name -ne 'interactive_session'){ $o[$p.Name]=$p.Value }
    }
    $o.interactive_session=New-AidosDesktopInteractiveOverlay -Decision $Decision -Status $Status
    if($Status -eq 'AVAILABLE' -and [string]$o.last_error -in @('SESSION_LOCKED','SESSION_DISCONNECTED','NO_INTERACTIVE_SESSION','INPUT_DESKTOP_UNAVAILABLE','SESSION_STATE_UNKNOWN')){
        [void]$o.Remove('last_error')
    }
    $o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $ReviewId $o
    [pscustomobject]$o
}

function Add-AidosDesktopInteractiveWaitEvent {
    param([string]$ProjectRoot,[string]$EventType,[string]$ReviewId,$State,$Decision)
    try {
        $record=Read-AidosReviewRecord $ProjectRoot $ReviewId
        Add-AidosEvent $ProjectRoot $EventType 'BRIDGE' @{
            review_id=$ReviewId
            project_id=$record.project_id
            execution_id=$record.execution_id
            revision=$record.revision
            transport_phase=[string]$State.status
            session_id=$Decision.snapshot.session_id
            session_kind=$Decision.snapshot.session_kind
            reason=$Decision.reason
        } | Out-Null
    } catch {
        # Availability persistence is authoritative for this gate. Telemetry/event
        # emission must not corrupt an otherwise safe wait transition.
    }
}

function Invoke-AidosDesktopChatGPTEnroll {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ConversationProofText,
        [string]$AccountProofText='',
        [string]$ProcessName='ChatGPT',
        [object]$Backend,
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$SessionPolicy='SUPERVISED',
        [scriptblock]$SessionSnapshotProvider
    )
    $realBackend=$Backend
    if(-not $realBackend){ $realBackend=AidosDesktopChatGPT\New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName }
    if($Backend -and -not $SessionSnapshotProvider){
        return AidosDesktopChatGPT\Invoke-AidosDesktopChatGPTEnroll -ProjectRoot $ProjectRoot -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -Backend $realBackend
    }
    $gateState=[pscustomobject]@{snapshot=$null;decision=$null}
    $gated=New-AidosDesktopSessionGateBackend -Backend $realBackend -Policy $SessionPolicy -SnapshotProvider $SessionSnapshotProvider -GateState $gateState
    AidosDesktopChatGPT\Invoke-AidosDesktopChatGPTEnroll -ProjectRoot $ProjectRoot -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -Backend $gated
}

function Invoke-AidosDesktopChatGPTReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$AssignmentPath,
        [string]$ConversationProofText='',
        [string]$AccountProofText='',
        [string]$ProcessName='ChatGPT',
        [int]$ResponseTimeoutSeconds=180,
        [object]$Backend,
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$SessionPolicy='SUPERVISED',
        [bool]$WaitForInteractiveSession=$true,
        [int]$InteractiveSessionPollSeconds=2,
        [int]$InteractiveSessionWaitTimeoutSeconds=0,
        [scriptblock]$SessionSnapshotProvider
    )
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $reviewId=[string](Split-Path -Leaf (Split-Path -Parent $AssignmentPath))
    $realBackend=$Backend
    if(-not $realBackend){ $realBackend=AidosDesktopChatGPT\New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName }
    $useNativeGate=(-not $Backend) -or $null -ne $SessionSnapshotProvider

    while($true){
        $before=if(-not [string]::IsNullOrWhiteSpace($reviewId)){ Read-AidosDesktopChatGPTState $ProjectRoot $reviewId }else{$null}
        $gateState=[pscustomobject]@{snapshot=$null;decision=$null}
        $effectiveBackend=if($useNativeGate){ New-AidosDesktopSessionGateBackend -Backend $realBackend -Policy $SessionPolicy -SnapshotProvider $SessionSnapshotProvider -GateState $gateState }else{$realBackend}
        $result=AidosDesktopChatGPT\Invoke-AidosDesktopChatGPTReview -ProjectRoot $ProjectRoot -AssignmentPath $AssignmentPath -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -ResponseTimeoutSeconds $ResponseTimeoutSeconds -Backend $effectiveBackend
        $reviewId=[string]$result.review_id

        if([string]$result.status -eq 'WAITING_INTERACTIVE_SESSION'){
            $decision=$gateState.decision
            if(-not $decision -or $decision.allowed){
                # A WAITING result must always have a blocking availability reason.
                # A still-allowed decision means the underlying desktop assertion
                # failed outside/between snapshots; refresh and, if still eligible,
                # fail closed as an input-desktop race rather than persisting NONE.
                $snapshot=if($SessionSnapshotProvider){ & $SessionSnapshotProvider }else{ Get-AidosInteractiveSessionSnapshot }
                $decision=Test-AidosInteractiveSessionPolicy -Snapshot $snapshot -Policy $SessionPolicy
                if($decision.allowed){
                    $strict=[ordered]@{}
                    foreach($p in $snapshot.PSObject.Properties){ $strict[$p.Name]=$p.Value }
                    $strict.input_desktop_available=$false
                    $strict.error='INTERACTIVE_ASSERTION_RACE'
                    $strict.observed_at=[DateTimeOffset]::UtcNow.ToString('o')
                    $snapshot=[pscustomobject]$strict
                    $decision=Test-AidosInteractiveSessionPolicy -Snapshot $snapshot -Policy $SessionPolicy
                }
            }
            $raw=Read-AidosDesktopChatGPTState $ProjectRoot $reviewId
            $normalized=ConvertTo-AidosDesktopWaitingState -State $raw -Decision $decision
            Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $normalized
            if(-not $before -or -not $before.PSObject.Properties['interactive_session'] -or [string]$before.interactive_session.status -ne 'WAITING'){
                Add-AidosDesktopInteractiveWaitEvent $ProjectRoot 'INTERACTIVE_SESSION_WAIT_STARTED' $reviewId $normalized $decision
            }
            if(-not $WaitForInteractiveSession){
                return [pscustomobject]@{review_id=$reviewId;status=[string]$normalized.status;waiting_interactive_session=$true;idempotent=$false;adapter_state=$normalized}
            }
            $ready=Wait-AidosInteractiveSession -Policy $SessionPolicy -PollSeconds $InteractiveSessionPollSeconds -TimeoutSeconds $InteractiveSessionWaitTimeoutSeconds -SnapshotProvider $SessionSnapshotProvider
            if(-not $ready.allowed){
                return [pscustomobject]@{review_id=$reviewId;status=[string]$normalized.status;waiting_interactive_session=$true;wait_timeout=$true;idempotent=$false;adapter_state=$normalized}
            }
            $available=Set-AidosDesktopInteractiveOverlay $ProjectRoot $reviewId $ready AVAILABLE
            Add-AidosDesktopInteractiveWaitEvent $ProjectRoot 'INTERACTIVE_SESSION_WAIT_ENDED' $reviewId $available $ready
            continue
        }

        if($useNativeGate -and $gateState.decision -and $gateState.decision.allowed){
            $updated=Set-AidosDesktopInteractiveOverlay $ProjectRoot $reviewId $gateState.decision AVAILABLE
            if($updated){ $result.adapter_state=$updated }
        }
        return $result
    }
}

Export-ModuleMember -Function New-AidosDesktopSessionGateBackend,New-AidosDesktopInteractiveOverlay,ConvertTo-AidosDesktopWaitingState,Set-AidosDesktopInteractiveOverlay,Invoke-AidosDesktopChatGPTEnroll,Invoke-AidosDesktopChatGPTReview
