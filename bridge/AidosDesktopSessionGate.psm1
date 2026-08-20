Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosWindowsSession.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -Force -DisableNameChecking
$script:DesktopChatGPTWindowDiscoveryModule=Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPTWindowDiscovery.psm1') -DisableNameChecking -PassThru
$script:ResilientDesktopChatGPTBackendCommand=$script:DesktopChatGPTWindowDiscoveryModule.ExportedCommands['New-AidosDesktopChatGPTResilientWindowsBackend']
if($null-eq$script:ResilientDesktopChatGPTBackendCommand){throw 'Resilient Desktop ChatGPT backend factory is unavailable.'}

function Test-AidosDesktopReviewResponseValueResolved {
    param($Value)
    if($null-eq$Value){return $true}
    if($Value -is [string]){
        $text=([string]$Value).Trim()
        if($text -match '^(?i:REQUIRED|REQUIRED_NONEMPTY)\s*:'){return $false}
        if([string]::Equals($text,'Replace with the evidence-based review reason.',[StringComparison]::Ordinal)){return $false}
        return $true
    }
    if($Value -is [char] -or $Value -is [bool] -or $Value -is [ValueType]){return $true}
    if($Value -is [Collections.IDictionary]){
        foreach($key in @($Value.Keys)){if(-not(Test-AidosDesktopReviewResponseValueResolved -Value $Value[$key])){return $false}}
        return $true
    }
    if($Value -is [Collections.IEnumerable] -and -not($Value -is [pscustomobject])){
        foreach($item in @($Value)){if(-not(Test-AidosDesktopReviewResponseValueResolved -Value $item)){return $false}}
        return $true
    }
    $properties=@($Value.PSObject.Properties|Where-Object {$_.MemberType -in @('NoteProperty','Property')})
    foreach($property in $properties){if(-not(Test-AidosDesktopReviewResponseValueResolved -Value $property.Value)){return $false}}
    $true
}

function Resolve-AidosDesktopReviewMessageDirection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Texts)
    $assistant=$false
    $user=$false
    foreach($text in @($Texts)){
        if([string]::IsNullOrWhiteSpace([string]$text)){continue}
        $normalized=([string]$text).Replace("`r`n","`n").Replace("`r","`n")
        foreach($line in @($normalized -split "`n")){
            $label=([string]$line).Trim()
            if([string]::IsNullOrWhiteSpace($label)){continue}
            if([string]::Equals($label,'You said:',[StringComparison]::OrdinalIgnoreCase) -or
               [string]::Equals($label,'Jij zei:',[StringComparison]::OrdinalIgnoreCase)){
                $user=$true
                continue
            }
            if([string]::Equals($label,'ChatGPT said:',[StringComparison]::OrdinalIgnoreCase) -or
               [string]::Equals($label,'ChatGPT zei:',[StringComparison]::OrdinalIgnoreCase) -or
               ($label -match '^(?i)(?!You said:$)(?!Jij zei:$).+\s+(?:said|zei):$')){
                $assistant=$true
            }
        }
    }
    if($assistant -and -not$user){return 'ASSISTANT'}
    if($user -and -not$assistant){return 'USER'}
    'UNKNOWN'
}

function Select-AidosDesktopStrictReviewResponseText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Texts,
        [Parameter(Mandatory)]$Assignment
    )
    if($Texts.Count-eq0 -or -not$Assignment){return $null}
    $reviewId=[string]$Assignment.review_id
    $manifestSha=[string]$Assignment.package_manifest_sha256
    if([string]::IsNullOrWhiteSpace($reviewId)-or[string]::IsNullOrWhiteSpace($manifestSha)){return $null}
    $responses=[Collections.Generic.List[string]]::new()
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($text in @($Texts)){
        if([string]::IsNullOrWhiteSpace([string]$text)){continue}
        $trim=([string]$text).Trim()
        $body=$trim
        if($trim.StartsWith('```')){
            if($trim -notmatch '^```(?:json)?\s*(?<body>[\s\S]*?)\s*```$'){continue}
            $body=[string]$Matches.body.Trim()
        }elseif($trim -notmatch '^\{[\s\S]*\}$'){
            continue
        }
        if($body -notmatch '^\{[\s\S]*\}$'){continue}
        try{$parsed=$body|ConvertFrom-Json -Depth 100}catch{continue}
        if([string]$parsed.envelope_type-ne'REVIEW_RESPONSE'){continue}
        if([string]$parsed.review_id-ne$reviewId){continue}
        if([string]$parsed.package_manifest_sha256-ne$manifestSha){continue}
        if([string]$parsed.outcome-notin@('PASS','REPAIR','BLOCKER','DISCOVERY_REFRESH_REQUIRED','WAITING_INTERACTIVE_SESSION')){continue}
        if([string]::IsNullOrWhiteSpace([string]$parsed.reason)){continue}
        if([string]::IsNullOrWhiteSpace([string]$parsed.responded_at)){continue}
        $respondedAt=[DateTimeOffset]::MinValue
        if(-not[DateTimeOffset]::TryParse([string]$parsed.responded_at,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$respondedAt)){continue}
        if(-not(Test-AidosDesktopReviewResponseValueResolved -Value $parsed)){continue}
        if($seen.Add($body)){$responses.Add($body)}
    }
    if($responses.Count-eq0){return $null}
    $responses[$responses.Count-1]
}

function Select-AidosDesktopStrictReviewResponseSurface {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Surfaces,
        [Parameter(Mandatory)]$Assignment
    )
    $assistantTexts=[Collections.Generic.List[string]]::new()
    foreach($surface in @($Surfaces)){
        if($null-eq$surface -or [string]$surface.direction-ne'ASSISTANT'){continue}
        foreach($text in @($surface.texts)){
            if(-not[string]::IsNullOrWhiteSpace([string]$text)){$assistantTexts.Add([string]$text)}
        }
    }
    Select-AidosDesktopStrictReviewResponseText -Texts $assistantTexts.ToArray() -Assignment $Assignment
}

function Get-AidosDesktopReviewMessageSurface {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Element)
    $candidateTexts=[Collections.Generic.List[string]]::new()
    $candidateSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $values=@()
    try{
        $textPattern=$Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if($textPattern){$values+=[string]$textPattern.DocumentRange.GetText(-1)}
    }catch{}
    try{
        $valuePattern=$Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if($valuePattern){$values+=[string]$valuePattern.Current.Value}
    }catch{}
    try{$values+=[string]$Element.Current.Name}catch{}
    foreach($value in @($values)){
        if([string]::IsNullOrWhiteSpace([string]$value)){continue}
        if($candidateSeen.Add([string]$value)){$candidateTexts.Add([string]$value)}
    }

    $direction='UNKNOWN'
    $proofTexts=@()
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
    $current=$Element
    for($depth=0;$depth-lt16-and$current;$depth++){
        $controlType=''
        try{$controlType=[string]$current.Current.ControlType.ProgrammaticName}catch{}
        if($controlType -match 'Document$'){break}
        $metadata=[Collections.Generic.List[string]]::new()
        $metadataSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $raw=@()
        try{$raw+=[string]$current.Current.Name}catch{}
        try{$raw+=[string]$current.Current.HelpText}catch{}
        try{$raw+=[string]$current.Current.AutomationId}catch{}
        try{
            $text=Get-AidosDesktopChatGPTElementText $current
            if(-not[string]::IsNullOrWhiteSpace([string]$text)){$raw+=[string]$text}
        }catch{}
        foreach($value in @($raw)){
            if([string]::IsNullOrWhiteSpace([string]$value)){continue}
            if($metadataSeen.Add([string]$value)){$metadata.Add([string]$value)}
        }
        $nodeDirection=Resolve-AidosDesktopReviewMessageDirection -Texts $metadata.ToArray()
        if([string]$nodeDirection-ne'UNKNOWN'){
            $direction=[string]$nodeDirection
            $proofTexts=$metadata.ToArray()
            break
        }
        try{$current=$walker.GetParent($current)}catch{$current=$null}
    }
    [pscustomobject][ordered]@{
        direction=$direction
        texts=$candidateTexts.ToArray()
        direction_proof_texts=@($proofTexts)
    }
}

function Get-AidosDesktopStrictReviewResponseText {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Assignment
    )
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){ return $null }
    if(-not ('System.Windows.Automation.AutomationElement' -as [type])){
        Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
    }
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not $root){ return $null }
    $surfaces=[Collections.Generic.List[object]]::new()
    foreach($element in @($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))){
        try{if([string]$element.Current.AutomationId-eq'prompt-textarea'){continue}}catch{}
        $surface=Get-AidosDesktopReviewMessageSurface -Element $element
        if([string]$surface.direction-eq'ASSISTANT' -and @($surface.texts).Count){$surfaces.Add($surface)}
    }
    Select-AidosDesktopStrictReviewResponseSurface -Surfaces $surfaces.ToArray() -Assignment $Assignment
}

function New-AidosDesktopSessionGateDefaultBackend {
    param([string]$ProcessName='ChatGPT Classic')
    & $script:ResilientDesktopChatGPTBackendCommand -ProcessName $ProcessName
}

function New-AidosDesktopSessionGateBackend {
    param(
        [Parameter(Mandatory)]$Backend,
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$Policy='SUPERVISED',
        [scriptblock]$SnapshotProvider,
        [Parameter(Mandatory)]$GateState,
        [bool]$UseStrictUiResponseReader=$false
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
                $fresh=if($provider){ & $provider }else{ Get-AidosInteractiveSessionSnapshot }
                $freshDecision=Test-AidosInteractiveSessionPolicy -Snapshot $fresh -Policy $Policy
                if(-not $freshDecision.allowed){
                    $gate.snapshot=$fresh
                    $gate.decision=$freshDecision
                    throw "Interactive ChatGPT action blocked by session policy: $($freshDecision.reason)."
                }
                $transition=[ordered]@{}
                foreach($p in $fresh.PSObject.Properties){$transition[$p.Name]=$p.Value}
                $transition.input_desktop_available=$false
                $transition.error="DESKTOP_TRANSITION_UNAVAILABLE: $($_.Exception.Message)"
                $transition.observed_at=[DateTimeOffset]::UtcNow.ToString('o')
                $transitionDecision=[pscustomobject]@{
                    allowed=$false
                    policy=$Policy
                    reason='DESKTOP_TRANSITION_UNAVAILABLE'
                    snapshot=[pscustomobject]$transition
                }
                $gate.snapshot=$transitionDecision.snapshot
                $gate.decision=$transitionDecision
                throw 'Interactive desktop is transitioning; retry without changing project or transport authority.'
            }
        }
        $true
    }).GetNewClosure()
    if($UseStrictUiResponseReader){
        $strictReviewResponseReader=${function:Get-AidosDesktopStrictReviewResponseText}
        if($null-eq$strictReviewResponseReader){throw 'Strict Desktop ChatGPT review response reader is unavailable.'}
        $props['ReadLatestResponseText']=({
            param($Context,$Enrollment,[int]$Attempt,$Assignment)
            & $strictReviewResponseReader -Context $Context -Assignment $Assignment
        }).GetNewClosure()
    }
    [pscustomobject]$props
}

function New-AidosDesktopInteractiveOverlay {
    param([Parameter(Mandatory)]$Decision,[ValidateSet('AVAILABLE','WAITING')][string]$Status)
    $s=$Decision.snapshot
    [ordered]@{
        status=$Status
        reason=if($Status-eq'AVAILABLE'){'NONE'}else{[string]$Decision.reason}
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
    if([string]$Decision.reason-eq'NONE'){throw 'WAITING interactive overlay requires a blocking or transient reason.'}
    $phase=if([string]$State.delivery_status-in@('PREPARED','SENT')){[string]$State.delivery_status}elseif([string]$State.status-in@('PREPARED','SENT','RECEIVED','VALIDATED','HANDOFF_COMPLETE')){[string]$State.status}else{'PREPARED'}
    $o=[ordered]@{}
    foreach($p in $State.PSObject.Properties){
        if($p.Name-notin@('delivery_status','interactive_session')){$o[$p.Name]=$p.Value}
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
    if(-not$state){return $null}
    $o=[ordered]@{}
    foreach($p in $state.PSObject.Properties){
        if($p.Name-ne'interactive_session'){$o[$p.Name]=$p.Value}
    }
    $o.interactive_session=New-AidosDesktopInteractiveOverlay -Decision $Decision -Status $Status
    $lastError=if($o.Contains('last_error')){[string]$o['last_error']}else{''}
    if($Status-eq'AVAILABLE' -and $lastError-in@('SESSION_LOCKED','SESSION_DISCONNECTED','NO_INTERACTIVE_SESSION','INPUT_DESKTOP_UNAVAILABLE','SESSION_STATE_UNKNOWN','DESKTOP_TRANSITION_UNAVAILABLE')){
        [void]$o.Remove('last_error')
    }
    $o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $ReviewId $o
    [pscustomobject]$o
}

function Add-AidosDesktopInteractiveWaitEvent {
    param([string]$ProjectRoot,[string]$EventType,[string]$ReviewId,$State,$Decision)
    try{
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
        }|Out-Null
    }catch{}
}

function Invoke-AidosDesktopChatGPTEnroll {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ConversationProofText,
        [string]$AccountProofText='',
        [string]$ProcessName='ChatGPT Classic',
        [object]$Backend,
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$SessionPolicy='SUPERVISED',
        [scriptblock]$SessionSnapshotProvider
    )
    $realBackend=$Backend
    if(-not$realBackend){$realBackend=New-AidosDesktopSessionGateDefaultBackend -ProcessName $ProcessName}
    if($Backend -and -not$SessionSnapshotProvider){
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
        [string]$ProcessName='ChatGPT Classic',
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
    $useStrictUiResponseReader=(-not$Backend)
    if(-not$realBackend){$realBackend=New-AidosDesktopSessionGateDefaultBackend -ProcessName $ProcessName}
    $useNativeGate=(-not$Backend)-or$null-ne$SessionSnapshotProvider
    $waitStarted=[DateTimeOffset]::UtcNow

    while($true){
        $before=if(-not[string]::IsNullOrWhiteSpace($reviewId)){Read-AidosDesktopChatGPTState $ProjectRoot $reviewId}else{$null}
        $gateState=[pscustomobject]@{snapshot=$null;decision=$null}
        $effectiveBackend=if($useNativeGate){New-AidosDesktopSessionGateBackend -Backend $realBackend -Policy $SessionPolicy -SnapshotProvider $SessionSnapshotProvider -GateState $gateState -UseStrictUiResponseReader:$useStrictUiResponseReader}else{$realBackend}
        $result=AidosDesktopChatGPT\Invoke-AidosDesktopChatGPTReview -ProjectRoot $ProjectRoot -AssignmentPath $AssignmentPath -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -ResponseTimeoutSeconds $ResponseTimeoutSeconds -Backend $effectiveBackend
        $reviewId=[string]$result.review_id

        if([string]$result.status-eq'WAITING_INTERACTIVE_SESSION'){
            $decision=$gateState.decision
            if(-not$decision){
                $snapshot=if($SessionSnapshotProvider){&$SessionSnapshotProvider}else{Get-AidosInteractiveSessionSnapshot}
                $decision=Test-AidosInteractiveSessionPolicy -Snapshot $snapshot -Policy $SessionPolicy
            }
            if(-not$decision -or [string]$decision.reason-eq'NONE'){
                throw 'Interactive wait was requested without a blocking or transient session reason.'
            }
            $raw=Read-AidosDesktopChatGPTState $ProjectRoot $reviewId
            $normalized=ConvertTo-AidosDesktopWaitingState -State $raw -Decision $decision
            Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $normalized
            if(-not$before -or -not$before.PSObject.Properties['interactive_session'] -or [string]$before.interactive_session.status-ne'WAITING'){
                Add-AidosDesktopInteractiveWaitEvent $ProjectRoot 'INTERACTIVE_SESSION_WAIT_STARTED' $reviewId $normalized $decision
            }
            if(-not$WaitForInteractiveSession){
                return [pscustomobject]@{review_id=$reviewId;status=[string]$normalized.status;waiting_interactive_session=$true;idempotent=$false;adapter_state=$normalized}
            }
            if([string]$decision.reason-eq'DESKTOP_TRANSITION_UNAVAILABLE'){
                if($InteractiveSessionWaitTimeoutSeconds-gt0 -and ([DateTimeOffset]::UtcNow-$waitStarted).TotalSeconds-ge$InteractiveSessionWaitTimeoutSeconds){
                    return [pscustomobject]@{review_id=$reviewId;status=[string]$normalized.status;waiting_interactive_session=$true;wait_timeout=$true;transient_desktop_transition=$true;idempotent=$false;adapter_state=$normalized}
                }
                Start-Sleep -Seconds ([Math]::Max(1,$InteractiveSessionPollSeconds))
                continue
            }
            $ready=Wait-AidosInteractiveSession -Policy $SessionPolicy -PollSeconds $InteractiveSessionPollSeconds -TimeoutSeconds $InteractiveSessionWaitTimeoutSeconds -SnapshotProvider $SessionSnapshotProvider
            if(-not$ready.allowed){
                return [pscustomobject]@{review_id=$reviewId;status=[string]$normalized.status;waiting_interactive_session=$true;wait_timeout=$true;idempotent=$false;adapter_state=$normalized}
            }
            $available=Set-AidosDesktopInteractiveOverlay $ProjectRoot $reviewId $ready AVAILABLE
            Add-AidosDesktopInteractiveWaitEvent $ProjectRoot 'INTERACTIVE_SESSION_WAIT_ENDED' $reviewId $available $ready
            continue
        }

        if($useNativeGate -and $gateState.decision -and $gateState.decision.allowed){
            $updated=Set-AidosDesktopInteractiveOverlay $ProjectRoot $reviewId $gateState.decision AVAILABLE
            if($updated){$result.adapter_state=$updated}
        }
        return $result
    }
}

Export-ModuleMember -Function Test-AidosDesktopReviewResponseValueResolved,Resolve-AidosDesktopReviewMessageDirection,Select-AidosDesktopStrictReviewResponseText,Select-AidosDesktopStrictReviewResponseSurface,Get-AidosDesktopReviewMessageSurface,Get-AidosDesktopStrictReviewResponseText,New-AidosDesktopSessionGateDefaultBackend,New-AidosDesktopSessionGateBackend,New-AidosDesktopInteractiveOverlay,ConvertTo-AidosDesktopWaitingState,Set-AidosDesktopInteractiveOverlay,Invoke-AidosDesktopChatGPTEnroll,Invoke-AidosDesktopChatGPTReview
