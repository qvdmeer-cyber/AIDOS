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
function Test-AidosRepositoryThinkerActionableElement {
    param([Parameter(Mandatory)]$Element)
    foreach($pattern in @([System.Windows.Automation.SelectionItemPattern]::Pattern,[System.Windows.Automation.InvokePattern]::Pattern,[System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)){
        try{$null=$Element.GetCurrentPattern($pattern);return $true}catch{}
    }
    $false
}
function Invoke-AidosRepositoryThinkerActionableElement {
    param([Parameter(Mandatory)]$Element)
    try{$p=$Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern);$p.Select();return 'SELECTION_ITEM'}catch{}
    try{$p=$Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern);$p.Invoke();return 'INVOKE'}catch{}
    try{$p=$Element.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern);$p.DoDefaultAction();return 'LEGACY_DEFAULT_ACTION'}catch{}
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

function New-AidosRepositoryThinkerWindowsBackend {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic')
    $desktop=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName
    [pscustomobject]@{
        GetProcessContext=$desktop.GetProcessContext
        GetCurrentConversation={
            param($Context)
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not$root){throw 'ChatGPT window is unavailable through UI Automation.'}
            Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
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
        FocusConversation=$desktop.FocusConversation
        SendPrompt=$desktop.SendPrompt
    }
}

function Bind-AidosRepositoryThinkerConversation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$ExpectedConversationTitle,[string]$ProcessName='ChatGPT Classic',[object]$Backend)
    if($null-eq$Backend){$Backend=New-AidosRepositoryThinkerWindowsBackend -ProcessName $ProcessName}
    $context=& $Backend.GetProcessContext $ProcessName
    $conversation=& $Backend.GetCurrentConversation $context
    if(-not[string]::Equals([string]$conversation.title,$ExpectedConversationTitle,[StringComparison]::Ordinal)){throw "Active ChatGPT conversation title '$($conversation.title)' does not equal required project title '$ExpectedConversationTitle'. Rename and pin the conversation before binding."}
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
    if($existing -and [string]$existing.status-eq'FAILED' -and $existing.retry_after){$retry=[DateTimeOffset]::Parse([string]$existing.retry_after);if([DateTimeOffset]::UtcNow-lt$retry){return [pscustomobject][ordered]@{status='BACKOFF';retry_after=$retry.ToString('o');state=$existing}}}
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

Export-ModuleMember -Function Get-AidosRepositoryHandoffBridgeDefaultStateRoot,Get-AidosRepositoryThinkerBindingPath,Get-AidosRepositoryThinkerTriggerPath,Write-AidosRepositoryThinkerJsonAtomic,Read-AidosRepositoryThinkerBinding,Get-AidosRepositoryThinkerCurrentConversationFromRoot,Test-AidosRepositoryThinkerActionableElement,Invoke-AidosRepositoryThinkerActionableElement,Find-AidosRepositoryThinkerConversationAction,New-AidosRepositoryThinkerWindowsBackend,Bind-AidosRepositoryThinkerConversation,Remove-AidosRepositoryThinkerBinding,Get-AidosRepositoryThinkerTriggerState,New-AidosRepositoryThinkerTriggerText,Invoke-AidosRepositoryThinkerTrigger,Reset-AidosRepositoryThinkerTrigger
