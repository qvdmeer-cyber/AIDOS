Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -DisableNameChecking

function Get-AidosRepositoryHandoffBridgeDefaultStateRoot {
    if([OperatingSystem]::IsWindows()){return (Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-bridge')}
    Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-repository-handoff-bridge'
}
function Get-AidosRepositoryThinkerBindingPath {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId)
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("bindings/$ProjectId.json")
}
function Get-AidosRepositoryThinkerTriggerPath {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$HandoffId)
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("triggers/$ProjectId/$HandoffId.json")
}
function Write-AidosRepositoryThinkerJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $dir=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Read-AidosRepositoryThinkerBinding {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId)
    $path=Get-AidosRepositoryThinkerBindingPath -StateRoot $StateRoot -ProjectId $ProjectId
    if(Test-Path -LiteralPath $path -PathType Leaf){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50}else{$null}
}

function Get-AidosRepositoryThinkerCurrentConversationFromRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RootElement)
    if(-not('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
    $condition=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty),([System.Windows.Automation.ControlType]::Document)
    $documents=@($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,$condition)|Where-Object {-not[bool]$_.Current.IsOffscreen})
    $candidates=[Collections.Generic.List[object]]::new()
    foreach($document in $documents){
        $url=''
        try{$value=$document.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern);if($value){$url=[string]$value.Current.Value}}catch{}
        if([string]::IsNullOrWhiteSpace($url)){continue}
        $score=0
        if($url.IndexOf('chatgpt.com',[StringComparison]::OrdinalIgnoreCase)-ge0){$score++}
        if($url.IndexOf('/c/',[StringComparison]::OrdinalIgnoreCase)-ge0){$score+=10}
        $candidates.Add([pscustomobject][ordered]@{element=$document;title=[string]$document.Current.Name;url=$url;score=$score})
    }
    if($candidates.Count-eq0){throw 'Active ChatGPT conversation document URL is unavailable.'}
    $ordered=@($candidates|Sort-Object score -Descending)
    $best=$ordered[0]
    if(@($ordered|Where-Object {[int]$_.score-eq[int]$best.score}).Count-ne1){throw 'Active ChatGPT conversation document remains ambiguous.'}
    [pscustomobject][ordered]@{title=[string]$best.title;url=[string]$best.url;document=$best.element}
}
function Get-AidosRepositoryThinkerLegacyAccessiblePattern {
    $legacyType='System.Windows.Automation.LegacyIAccessiblePattern' -as [type]
    if($null-eq$legacyType){return $null}
    $property=$legacyType.GetProperty('Pattern',[Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::Static)
    if($null-eq$property){return $null}
    $property.GetValue($null)
}
function Test-AidosRepositoryThinkerActionableElement {
    param([Parameter(Mandatory)]$Element)
    $patterns=[Collections.Generic.List[object]]::new()
    $patterns.Add([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $patterns.Add([System.Windows.Automation.InvokePattern]::Pattern)
    $legacyPattern=Get-AidosRepositoryThinkerLegacyAccessiblePattern
    if($null-ne$legacyPattern){$patterns.Add($legacyPattern)}
    foreach($pattern in $patterns){
        try{$null=$Element.GetCurrentPattern($pattern);return $true}catch{}
    }
    $false
}
function Invoke-AidosRepositoryThinkerActionableElement {
    param([Parameter(Mandatory)]$Element)
    try{$p=$Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern);$p.Select();return 'SELECTION_ITEM'}catch{}
    try{$p=$Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern);$p.Invoke();return 'INVOKE'}catch{}
    $legacyPattern=Get-AidosRepositoryThinkerLegacyAccessiblePattern
    if($null-ne$legacyPattern){
        try{$p=$Element.GetCurrentPattern($legacyPattern);$p.DoDefaultAction();return 'LEGACY_DEFAULT_ACTION'}catch{}
    }
    throw 'Bound ChatGPT conversation element exposes no actionable UIA pattern.'
}
function Find-AidosRepositoryThinkerConversationAction {
    param([Parameter(Mandatory)]$RootElement,[Parameter(Mandatory)][string]$ConversationTitle)
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
    $candidates=[Collections.Generic.List[object]]::new()
    foreach($element in @($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))){
        if([bool]$element.Current.IsOffscreen -or -not[string]::Equals([string]$element.Current.Name,$ConversationTitle,[StringComparison]::Ordinal)){continue}
        $current=$element
        for($level=0;$level-lt5 -and $current;$level++){
            if(Test-AidosRepositoryThinkerActionableElement -Element $current){
                $candidates.Add([pscustomobject][ordered]@{element=$current;level=$level;automation_id=[string]$current.Current.AutomationId;control_type=[string]$current.Current.ControlType.ProgrammaticName})
                break
            }
            try{$current=$walker.GetParent($current)}catch{$current=$null}
        }
    }
    if($candidates.Count-eq0){throw "Pinned ChatGPT conversation '$ConversationTitle' was not found as an actionable sidebar item."}
    $minimum=($candidates|Measure-Object level -Minimum).Minimum
    $best=@($candidates|Where-Object {[int]$_.level-eq[int]$minimum})
    $unique=@($best|Group-Object automation_id,control_type|ForEach-Object {$_.Group[0]})
    if($unique.Count-ne1){throw "Pinned ChatGPT conversation '$ConversationTitle' is ambiguous in the active app."}
    $unique[0].element
}

function Get-AidosRepositoryThinkerComposerElement {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RootElement)
    $matches=@($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition)|Where-Object {
        $_.Current.AutomationId -eq 'prompt-textarea' -and
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
        $_.Current.IsKeyboardFocusable
    })
    if($matches.Count-ne1){throw "Expected exactly one ChatGPT composer control, found $($matches.Count)."}
    $matches[0]
}
function Find-AidosRepositoryThinkerSubmitElement {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RootElement)
    $buttons=@($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition)|Where-Object {
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $_.Current.IsEnabled -and -not $_.Current.IsOffscreen
    })
    foreach($ids in @(
        @('composer-submit-button'),
        @('send-button','composer-send-button')
    )){
        $matches=@($buttons|Where-Object { [string]$_.Current.AutomationId -in $ids })
        if($matches.Count-eq1){return $matches[0]}
        if($matches.Count-gt1){throw 'ChatGPT composer submit control is ambiguous.'}
    }
    $names=@('Send prompt','Send message','Send')
    $matches=@($buttons|Where-Object { [string]$_.Current.Name -in $names })
    if($matches.Count-eq1){return $matches[0]}
    if($matches.Count-gt1){throw 'ChatGPT composer submit control is ambiguous.'}
    $null
}
function Invoke-AidosRepositoryThinkerPromptSend {
    [CmdletBinding()]
    param($Context,$Binding,[Parameter(Mandatory)][string]$PromptText,$Assignment)
    if(-not('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
    if(-not('System.Windows.Forms.SendKeys' -as [type])){Add-Type -AssemblyName System.Windows.Forms}
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw 'ChatGPT window is not present.'}
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not$root){throw 'ChatGPT window is not accessible through UI Automation.'}
    $composer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
    $before=Get-AidosDesktopChatGPTElementText $composer
    $mutationOccurred=([string]$before-ne[string]$PromptText)
    $composer.SetFocus()
    Start-Sleep -Milliseconds 100
    if(-not[bool]$composer.Current.HasKeyboardFocus){throw 'ChatGPT composer keyboard focus proof is required before send.'}

    # Always hydrate through actual keyboard/clipboard input, even when a prior
    # failed attempt left matching visible text. Chromium/React may expose
    # ValuePattern text without updating the application's send-enabled state.
    Set-Clipboard -Value $PromptText
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 50
    [System.Windows.Forms.SendKeys]::SendWait('^v')

    $composerExact=$false
    for($attempt=0;$attempt-lt30;$attempt++){
        Start-Sleep -Milliseconds 100
        $current=[string](Get-AidosDesktopChatGPTElementText $composer)
        if([string]::Equals($current,$PromptText,[StringComparison]::Ordinal)){$composerExact=$true;break}
    }
    if(-not$composerExact){throw 'ChatGPT composer did not contain the exact outbound payload after keyboard hydration.'}

    $submit=$null
    for($attempt=0;$attempt-lt20;$attempt++){
        $submit=Find-AidosRepositoryThinkerSubmitElement -RootElement $root
        if($submit){break}
        Start-Sleep -Milliseconds 100
    }
    $sendMethod=$null
    if($submit){
        try{$invoke=$submit.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern);$invoke.Invoke();$sendMethod='UIA_INVOKE'}
        catch{throw "ChatGPT composer submit control cannot be invoked through UI Automation: $($_.Exception.Message)"}
    }else{
        # Enter is bounded fallback only after exact composer text and focus are
        # proven. If it inserts a newline, post-send proof below fails closed.
        $composer.SetFocus()
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        $sendMethod='KEYBOARD_ENTER'
    }

    $cleared=$false
    $remaining=$null
    for($attempt=0;$attempt-lt50;$attempt++){
        Start-Sleep -Milliseconds 100
        $remaining=[string](Get-AidosDesktopChatGPTElementText $composer)
        if([string]::IsNullOrWhiteSpace($remaining) -or $remaining.IndexOf($PromptText,[StringComparison]::Ordinal)-lt0){$cleared=$true;break}
    }
    if(-not$cleared){throw 'ChatGPT composer still contains the exact outbound payload after submit; committed-send proof is absent.'}
    [pscustomobject]@{
        schema_version='0.1'
        assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}else{$null}
        assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['payload_sha256']){[string]$Assignment.payload_sha256}else{$null}
        conversation_fingerprint_sha256=$null
        composer_state='COMMITTED'
        composer_result=if([string]::IsNullOrWhiteSpace([string]$before)){'EMPTY'}elseif([string]$before-eq$PromptText){'MATCHING_EXACT'}else{'MISMATCH'}
        mutation_occurred=$mutationOccurred
        send_invocation_state=$sendMethod
        committed_message_proof_state='PROVEN'
        failure_reason=$null
        committed=$true
    }
}

function New-AidosRepositoryThinkerWindowsBackend {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic')
    $desktop=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName
    $desktopFocus=$desktop.FocusConversation
    [pscustomobject]@{
        GetProcessContext=$desktop.GetProcessContext
        GetCurrentConversation={
            param($Context)
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not$root){throw 'ChatGPT window is unavailable through UI Automation.'}
            Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
        }
        ResolveConversationByTitle={
            param($Context,$ConversationTitle)
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not$root){throw 'ChatGPT window is unavailable through UI Automation.'}
            $element=Find-AidosRepositoryThinkerConversationAction -RootElement $root -ConversationTitle ([string]$ConversationTitle)
            $method=Invoke-AidosRepositoryThinkerActionableElement -Element $element
            for($attempt=0;$attempt-lt50;$attempt++){
                Start-Sleep -Milliseconds 100
                $observed=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
                if(-not[string]::IsNullOrWhiteSpace([string]$observed.url) -and $observed.url.IndexOf('/c/',[StringComparison]::OrdinalIgnoreCase)-ge0){
                    $conversation=[pscustomobject][ordered]@{title=[string]$ConversationTitle;document_title=[string]$observed.title;url=[string]$observed.url;document=$observed.document}
                    return [pscustomobject][ordered]@{status='RESOLVED';method=$method;conversation=$conversation;context=$Context}
                }
            }
            throw "ChatGPT conversation '$ConversationTitle' was invoked but no conversation URL became active."
        }
        ActivateConversation={
            param($Context,$Binding)
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not$root){throw 'ChatGPT window is unavailable through UI Automation.'}
            $current=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
            if([string]::Equals([string]$current.url,[string]$Binding.conversation_url,[StringComparison]::Ordinal)){return [pscustomobject][ordered]@{status='ALREADY_ACTIVE';conversation=$current;context=$Context}}
            $element=Find-AidosRepositoryThinkerConversationAction -RootElement $root -ConversationTitle ([string]$Binding.conversation_title)
            $method=Invoke-AidosRepositoryThinkerActionableElement -Element $element
            for($attempt=0;$attempt-lt50;$attempt++){
                Start-Sleep -Milliseconds 100
                $observed=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
                if([string]::Equals([string]$observed.url,[string]$Binding.conversation_url,[StringComparison]::Ordinal)){return [pscustomobject][ordered]@{status='ACTIVATED';method=$method;conversation=$observed;context=$Context}}
            }
            throw "ChatGPT conversation '$($Binding.conversation_title)' was invoked but its bound URL did not become active."
        }
        FocusConversation=({
            param($Context,$Binding)
            if($Context -and $Context.PSObject.Properties['process_id'] -and -not[string]::IsNullOrWhiteSpace([string]$Context.process_id)){
                $shell=$null
                try{
                    $shell=New-Object -ComObject WScript.Shell
                    for($attempt=0;$attempt-lt5;$attempt++){
                        if([bool]$shell.AppActivate([int]$Context.process_id)){break}
                        Start-Sleep -Milliseconds 100
                    }
                }catch{}finally{
                    if($shell){try{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}catch{}}
                }
            }
            & $desktopFocus $Context $Binding
        }).GetNewClosure()
        SendPrompt={param($Context,$Binding,$PromptText,$Assignment);Invoke-AidosRepositoryThinkerPromptSend -Context $Context -Binding $Binding -PromptText $PromptText -Assignment $Assignment}
    }
}

function Bind-AidosRepositoryThinkerConversation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$ExpectedConversationTitle,[string]$ProcessName='ChatGPT Classic',[object]$Backend)
    if($null-eq$Backend){$Backend=New-AidosRepositoryThinkerWindowsBackend -ProcessName $ProcessName}
    $context=& $Backend.GetProcessContext $ProcessName
    $resolver=$Backend.PSObject.Properties['ResolveConversationByTitle']
    if($resolver){
        $resolved=& $Backend.ResolveConversationByTitle $context $ExpectedConversationTitle
        if($null-eq$resolved -or [string]$resolved.status-ne'RESOLVED' -or $null-eq$resolved.conversation){throw "Pinned ChatGPT conversation '$ExpectedConversationTitle' could not be resolved for binding."}
        $conversation=$resolved.conversation
    }else{
        $conversation=& $Backend.GetCurrentConversation $context
        if(-not[string]::Equals([string]$conversation.title,$ExpectedConversationTitle,[StringComparison]::Ordinal)){throw "Active ChatGPT conversation title '$($conversation.title)' does not equal required project title '$ExpectedConversationTitle'. Rename and pin the conversation before binding."}
    }
    if([string]::IsNullOrWhiteSpace([string]$conversation.url)){throw 'Active ChatGPT conversation URL is unavailable.'}
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $binding=[pscustomobject][ordered]@{schema_version='0.1';binding_type='MANUAL_PROJECT_CHATGPT_CONVERSATION';project_id=$ProjectId;repository=$Repository;process_name=$ProcessName;conversation_title=$ExpectedConversationTitle;conversation_url=[string]$conversation.url;status='BOUND';bound_at=$now;updated_at=$now}
    Write-AidosRepositoryThinkerJsonAtomic -Path (Get-AidosRepositoryThinkerBindingPath -StateRoot $StateRoot -ProjectId $ProjectId) -Value $binding
    $binding
}
function Remove-AidosRepositoryThinkerBinding {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId)
    $path=Get-AidosRepositoryThinkerBindingPath -StateRoot $StateRoot -ProjectId $ProjectId
    if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
    [pscustomobject][ordered]@{status='UNBOUND';project_id=$ProjectId}
}
function Get-AidosRepositoryThinkerTriggerState {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$HandoffId)
    $path=Get-AidosRepositoryThinkerTriggerPath -StateRoot $StateRoot -ProjectId $ProjectId -HandoffId $HandoffId
    if(Test-Path -LiteralPath $path -PathType Leaf){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50}else{$null}
}
function ConvertTo-AidosRepositoryThinkerRetryAfter {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Value)
    if($Value -is [DateTimeOffset]){return ([DateTimeOffset]$Value)}
    if($Value -is [DateTime]){return [DateTimeOffset]::new([DateTime]$Value)}
    $text=[string]$Value
    $parsed=[DateTimeOffset]::MinValue
    if([DateTimeOffset]::TryParseExact($text,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)){return $parsed}
    if([DateTimeOffset]::TryParse($text,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AllowWhiteSpaces,[ref]$parsed)){return $parsed}
    throw "Thinker retry_after is not a valid timestamp: $text"
}
function New-AidosRepositoryThinkerTriggerText {
    param([Parameter(Mandatory)]$Binding,[Parameter(Mandatory)]$Handoff)
    @"
AIDOS_HANDOFF_READY
project_id=$([string]$Handoff.metadata.project_id)
handoff_id=$([string]$Handoff.metadata.handoff_id)
handoff_sha256=$([string]$Handoff.text_sha256)
repository=$([string]$Binding.repository)

Process the current repository handoff through your configured AIDOS handoff actions. Read only its authorized sources. Submit the bound result to Core through the gateway. Do not place the work product in this chat and do not start another actor.
"@.Trim()
}
function Invoke-AidosRepositoryThinkerTrigger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$Handoff,[string]$ProcessName='ChatGPT Classic',[object]$Backend)
    if([string]$Handoff.metadata.kind-ne'ASSIGNMENT' -or [string]$Handoff.metadata.to_actor-ne'THINKER'){throw 'Thinker trigger requires a READY THINKER assignment handoff.'}
    $projectId=[string]$Handoff.metadata.project_id;$handoffId=[string]$Handoff.metadata.handoff_id
    $binding=Read-AidosRepositoryThinkerBinding -StateRoot $StateRoot -ProjectId $projectId
    if($null-eq$binding -or [string]$binding.status-ne'BOUND'){return [pscustomobject][ordered]@{status='UNBOUND';project_id=$projectId;handoff_id=$handoffId}}
    $existing=Get-AidosRepositoryThinkerTriggerState -StateRoot $StateRoot -ProjectId $projectId -HandoffId $handoffId
    if($existing -and [string]$existing.status-eq'COMMITTED'){return [pscustomobject][ordered]@{status='ALREADY_TRIGGERED';state=$existing}}
    if($existing -and [string]$existing.status-eq'FAILED' -and $existing.retry_after){$retry=ConvertTo-AidosRepositoryThinkerRetryAfter -Value $existing.retry_after;if([DateTimeOffset]::UtcNow-lt$retry){return [pscustomobject][ordered]@{status='BACKOFF';retry_after=$retry.ToString('o');state=$existing}}}
    if($null-eq$Backend){$Backend=New-AidosRepositoryThinkerWindowsBackend -ProcessName $ProcessName}
    $attempt=if($existing){[int]$existing.attempt+1}else{1}
    $path=Get-AidosRepositoryThinkerTriggerPath -StateRoot $StateRoot -ProjectId $projectId -HandoffId $handoffId
    $state=[pscustomobject][ordered]@{schema_version='0.1';project_id=$projectId;handoff_id=$handoffId;handoff_sha256=[string]$Handoff.text_sha256;status='PENDING';attempt=$attempt;triggered_at=$null;retry_after=$null;last_error=$null;updated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
    try{
        $context=& $Backend.GetProcessContext ([string]$binding.process_name)
        $activation=& $Backend.ActivateConversation $context $binding
        $context=& $Backend.FocusConversation $activation.context $binding
        $prompt=New-AidosRepositoryThinkerTriggerText -Binding $binding -Handoff $Handoff
        $send=& $Backend.SendPrompt $context $binding $prompt $Handoff.metadata
        if($null-eq$send -or -not [bool]$send.committed){throw 'ChatGPT trigger has no committed-send proof.'}
        $state.status='COMMITTED';$state.triggered_at=[DateTimeOffset]::UtcNow.ToString('o');$state.updated_at=$state.triggered_at
        Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
        [pscustomobject][ordered]@{status='TRIGGERED';project_id=$projectId;handoff_id=$handoffId;activation=$activation;send=$send;state=$state}
    }catch{
        $delays=@(60,300,900,1800);$delay=$delays[[Math]::Min(($attempt-1),($delays.Count-1))]
        $state.status='FAILED';$state.last_error=$_.Exception.Message;$state.retry_after=[DateTimeOffset]::UtcNow.AddSeconds($delay).ToString('o');$state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
        [pscustomobject][ordered]@{status='FAILED';project_id=$projectId;handoff_id=$handoffId;error=$state.last_error;retry_after=$state.retry_after;state=$state}
    }
}
function Reset-AidosRepositoryThinkerTrigger {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$HandoffId)
    $path=Get-AidosRepositoryThinkerTriggerPath -StateRoot $StateRoot -ProjectId $ProjectId -HandoffId $HandoffId
    if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
    [pscustomobject][ordered]@{status='RESET';project_id=$ProjectId;handoff_id=$HandoffId}
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffBridgeDefaultStateRoot,Get-AidosRepositoryThinkerBindingPath,Get-AidosRepositoryThinkerTriggerPath,Write-AidosRepositoryThinkerJsonAtomic,Read-AidosRepositoryThinkerBinding,Get-AidosRepositoryThinkerCurrentConversationFromRoot,Get-AidosRepositoryThinkerLegacyAccessiblePattern,Test-AidosRepositoryThinkerActionableElement,Invoke-AidosRepositoryThinkerActionableElement,Find-AidosRepositoryThinkerConversationAction,New-AidosRepositoryThinkerWindowsBackend,Bind-AidosRepositoryThinkerConversation,Remove-AidosRepositoryThinkerBinding,Get-AidosRepositoryThinkerTriggerState,ConvertTo-AidosRepositoryThinkerRetryAfter,New-AidosRepositoryThinkerTriggerText,Invoke-AidosRepositoryThinkerTrigger,Reset-AidosRepositoryThinkerTrigger