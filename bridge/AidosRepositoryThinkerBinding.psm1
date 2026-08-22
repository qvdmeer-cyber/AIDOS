Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Foreground/UIA operations in ChatGPT Classic are asynchronous WebView
# transitions. A short settle window prevents rapid focus churn from racing
# the composer's React input surface while keeping the transport automatic.

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
function Test-AidosRepositoryThinkerConversationTitleMatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ObservedTitle,[Parameter(Mandatory)][string]$ExpectedTitle)
    if([string]::Equals($ObservedTitle,$ExpectedTitle,[StringComparison]::Ordinal)){return $true}
    # ChatGPT Classic decorates pinned sidebar hyperlinks with a localized
    # accessibility suffix while preserving the conversation title itself.
    # The suffix is presentation metadata, not a different conversation.
    foreach($suffix in @(', vastgezet gesprek', ', pinned conversation', ', conversation pinned')){
        if($ObservedTitle.EndsWith($suffix,[StringComparison]::OrdinalIgnoreCase)){
            $base=$ObservedTitle.Substring(0,$ObservedTitle.Length-$suffix.Length).TrimEnd()
            if([string]::Equals($base,$ExpectedTitle,[StringComparison]::Ordinal)){return $true}
        }
    }
    $false
}
function Test-AidosRepositoryThinkerConversationUrlMatch {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$ObservedUrl,[AllowEmptyString()][string]$ExpectedUrl)
    if([string]::Equals($ObservedUrl,$ExpectedUrl,[StringComparison]::Ordinal)){return $true}
    $observedMatch=[regex]::Match($ObservedUrl,'/c/([A-Za-z0-9-]+)(?:[/?#]|$)')
    $expectedMatch=[regex]::Match($ExpectedUrl,'/c/([A-Za-z0-9-]+)(?:[/?#]|$)')
    $observedMatch.Success -and $expectedMatch.Success -and [string]::Equals($observedMatch.Groups[1].Value,$expectedMatch.Groups[1].Value,[StringComparison]::OrdinalIgnoreCase)
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
        if([bool]$element.Current.IsOffscreen -or -not(Test-AidosRepositoryThinkerConversationTitleMatch -ObservedTitle ([string]$element.Current.Name) -ExpectedTitle $ConversationTitle)){continue}
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
function Wait-AidosRepositoryThinkerComposerElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RootElement,
        [ValidateRange(1,600)][int]$MaxAttempts=120,
        [ValidateRange(0,5000)][int]$PollMilliseconds=500,
        [scriptblock]$ComposerResolver
    )
    if($null-eq$ComposerResolver){$ComposerResolver={param($Root) Get-AidosRepositoryThinkerComposerElement -RootElement $Root}}
    for($attempt=1;$attempt-le$MaxAttempts;$attempt++){
        try{return & $ComposerResolver $RootElement}
        catch{
            # A temporarily absent composer is expected while an already-active
            # conversation restores or finishes rendering. Ambiguity and every
            # other UIA contract failure remain immediate fail-closed errors.
            if($_.Exception.Message-ne'Expected exactly one ChatGPT composer control, found 0.'){throw}
            if($attempt-eq$MaxAttempts){throw "ChatGPT composer did not become uniquely ready after $MaxAttempts bounded observations."}
        }
        if($PollMilliseconds-gt0){Start-Sleep -Milliseconds $PollMilliseconds}
    }
}
function Test-AidosRepositoryThinkerComposerFocusProof {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Composer)
    try{if([bool]$Composer.Current.HasKeyboardFocus){return $true}}catch{}
    $focused=$null
    try{$focused=[System.Windows.Automation.AutomationElement]::FocusedElement}catch{}
    if(-not$focused){return $false}
    $composerProcess=$null
    try{$composerProcess=[int]$Composer.Current.ProcessId}catch{return $false}
    $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker
    $current=$focused
    for($level=0;$level-lt20 -and $current;$level++){
        try{
            if(
                [int]$current.Current.ProcessId -eq $composerProcess -and
                [string]$current.Current.AutomationId -eq 'prompt-textarea'
            ){return $true}
            $current=$walker.GetParent($current)
        }catch{return $false}
    }
    $false
}

function ConvertTo-AidosRepositoryThinkerComposerComparableText {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if($null-eq$Text){return $null}
    $normalized=$Text.Replace("`r`n","`n").Replace("`r","`n")
    $normalized.TrimEnd([char[]]"`r`n")
}
function Test-AidosRepositoryThinkerComposerTextMatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Expected,[AllowNull()][string]$Observed)
    $expectedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $Expected
    $observedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $Observed
    [string]::Equals($observedComparable,$expectedComparable,[StringComparison]::Ordinal)
}
function Get-AidosRepositoryThinkerComposerPayloadProof {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Expected,[AllowNull()][string]$Observed)
    $expectedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $Expected
    $observedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $Observed
    if([string]::Equals($observedComparable,$expectedComparable,[StringComparison]::Ordinal)){
        return [pscustomobject][ordered]@{proven=$true;mode='EXACT'}
    }
    $matches=[regex]::Matches($expectedComparable,'(?m)^repository=https://github\.com/([^\r\n]+)$')
    if($matches.Count-eq1){
        $line=[string]$matches[0].Value
        $path=[string]$matches[0].Groups[1].Value
        $projected=$expectedComparable.Replace("$line`n`n","repository=`n`n$path`n")
        if([string]::Equals($observedComparable,$projected,[StringComparison]::Ordinal)){
            return [pscustomobject][ordered]@{proven=$true;mode='CHATGPT_UIA_GITHUB_AUTOLINK_PROJECTION'}
        }
    }
    [pscustomobject][ordered]@{proven=$false;mode='NONE'}
}
function Set-AidosRepositoryThinkerComposerValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Composer,[Parameter(Mandatory)][string]$Value)
    try{$pattern=$Composer.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)}
    catch{throw "ChatGPT composer does not expose the required UI Automation ValuePattern compatibility surface: $($_.Exception.Message)"}
    if($null-eq$pattern -or [bool]$pattern.Current.IsReadOnly){throw 'ChatGPT composer UI Automation ValuePattern compatibility surface is read-only.'}
    $pattern.SetValue($Value)
    'UIA_VALUE_PATTERN_ZERO_FALLBACK'
}

function Initialize-AidosRepositoryThinkerNativeInput {
    [CmdletBinding()]
    param()
    if('AidosRepositoryThinkerNativeInputV2' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AidosRepositoryThinkerNativeInputV2 {
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint MAPVK_VK_TO_VSC = 0;

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT {
        public uint type;
        public INPUTUNION U;
    }

    [DllImport("user32.dll", SetLastError=true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint uCode, uint uMapType);

    [DllImport("kernel32.dll")]
    private static extern void SetLastError(uint dwErrCode);

    private static INPUT Keyboard(ushort vk, uint flags) {
        return new INPUT {
            type = INPUT_KEYBOARD,
            U = new INPUTUNION {
                ki = new KEYBDINPUT {
                    wVk = vk,
                    wScan = 0,
                    dwFlags = flags,
                    time = 0,
                    dwExtraInfo = UIntPtr.Zero
                }
            }
        };
    }

    private static uint Send(INPUT[] inputs, out int error, out int inputSize) {
        inputSize = Marshal.SizeOf(typeof(INPUT));
        SetLastError(0);
        uint sent = SendInput((uint)inputs.Length, inputs, inputSize);
        error = Marshal.GetLastWin32Error();
        return sent;
    }

    private static byte VirtualKey(ushort key) {
        if(key == 0 || key > 0xFE) {
            throw new ArgumentOutOfRangeException("key", "Native keyboard transport requires a virtual-key value from 1 through 254.");
        }
        return (byte)key;
    }

    private static byte ScanCode(byte key) {
        return (byte)(MapVirtualKey(key, MAPVK_VK_TO_VSC) & 0xFF);
    }

    private static void LegacyKey(byte key, uint flags) {
        keybd_event(key, ScanCode(key), flags, UIntPtr.Zero);
    }

    private static void ReleaseChord(byte modifier, byte key) {
        LegacyKey(key, KEYEVENTF_KEYUP);
        LegacyKey(modifier, KEYEVENTF_KEYUP);
    }

    private static void LegacyChord(byte modifier, byte key) {
        try {
            LegacyKey(modifier, 0);
            try {
                LegacyKey(key, 0);
            } finally {
                LegacyKey(key, KEYEVENTF_KEYUP);
            }
        } finally {
            LegacyKey(modifier, KEYEVENTF_KEYUP);
        }
    }

    private static void LegacySingleKey(byte key) {
        try {
            LegacyKey(key, 0);
        } finally {
            LegacyKey(key, KEYEVENTF_KEYUP);
        }
    }

    private static string FallbackDescription(int error, int inputSize) {
        return "KEYBD_EVENT_ZERO_FALLBACK(sendinput_error=" + error +
            ",input_size=" + inputSize +
            ",pointer_size=" + IntPtr.Size + ")";
    }

    public static string SendChord(ushort modifierValue, ushort keyValue) {
        byte modifier = VirtualKey(modifierValue);
        byte key = VirtualKey(keyValue);
        INPUT[] inputs = new INPUT[] {
            Keyboard(modifier, 0),
            Keyboard(key, 0),
            Keyboard(key, KEYEVENTF_KEYUP),
            Keyboard(modifier, KEYEVENTF_KEYUP)
        };
        int error;
        int inputSize;
        uint sent = Send(inputs, out error, out inputSize);
        if(sent == (uint)inputs.Length) {
            return "SENDINPUT";
        }
        if(sent != 0) {
            ReleaseChord(modifier, key);
            throw new InvalidOperationException(
                "SendInput partially accepted " + sent + " of " + inputs.Length +
                " keyboard events; key-up cleanup was issued and fallback is forbidden" +
                " (win32_error=" + error + ",input_size=" + inputSize +
                ",pointer_size=" + IntPtr.Size + ").");
        }
        LegacyChord(modifier, key);
        return FallbackDescription(error, inputSize);
    }

    public static string SendKey(ushort keyValue) {
        byte key = VirtualKey(keyValue);
        INPUT[] inputs = new INPUT[] {
            Keyboard(key, 0),
            Keyboard(key, KEYEVENTF_KEYUP)
        };
        int error;
        int inputSize;
        uint sent = Send(inputs, out error, out inputSize);
        if(sent == (uint)inputs.Length) {
            return "SENDINPUT";
        }
        if(sent != 0) {
            LegacyKey(key, KEYEVENTF_KEYUP);
            throw new InvalidOperationException(
                "SendInput partially accepted " + sent + " of " + inputs.Length +
                " keyboard events; key-up cleanup was issued and fallback is forbidden" +
                " (win32_error=" + error + ",input_size=" + inputSize +
                ",pointer_size=" + IntPtr.Size + ").");
        }
        LegacySingleKey(key);
        return FallbackDescription(error, inputSize);
    }
}
'@
}
function Invoke-AidosRepositoryThinkerNativeChord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][UInt16]$Modifier,[Parameter(Mandatory)][UInt16]$Key)
    Initialize-AidosRepositoryThinkerNativeInput
    [AidosRepositoryThinkerNativeInputV2]::SendChord($Modifier,$Key)
}
function Invoke-AidosRepositoryThinkerNativeKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][UInt16]$Key)
    Initialize-AidosRepositoryThinkerNativeInput
    [AidosRepositoryThinkerNativeInputV2]::SendKey($Key)
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
function Test-AidosRepositoryThinkerVisibleHandoffMarker {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RootElement,[Parameter(Mandatory)][string]$PromptText)
    $handoffMatch=[regex]::Match($PromptText,'(?m)^handoff_id=([^\r\n]+)$')
    if(-not$handoffMatch.Success){return $false}
    $handoffId=$handoffMatch.Groups[1].Value
    $elements=@($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))
    $texts=[Collections.Generic.List[string]]::new()
    foreach($element in $elements){
        try{$value=[string](Get-AidosDesktopChatGPTElementText $element);if(-not[string]::IsNullOrWhiteSpace($value)){$texts.Add($value)}}catch{}
    }
    $joined=($texts -join "`n")
    $joined.IndexOf('AIDOS_HANDOFF_READY',[StringComparison]::Ordinal) -ge 0 -and $joined.IndexOf($handoffId,[StringComparison]::Ordinal) -ge 0
}
function Invoke-AidosRepositoryThinkerPromptSend {
    [CmdletBinding()]
    param($Context,$Binding,[Parameter(Mandatory)][string]$PromptText,$Assignment)
    if(-not('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw 'ChatGPT window is not present.'}
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not$root){throw 'ChatGPT window is not accessible through UI Automation.'}
    $composer=Wait-AidosRepositoryThinkerComposerElement -RootElement $root
    $before=Get-AidosDesktopChatGPTElementText $composer
    $mutationOccurred=([string]$before-ne[string]$PromptText)
    $composer.SetFocus()
    $focusProven=$false
    for($attempt=0;$attempt-lt10;$attempt++){
        Start-Sleep -Milliseconds 100
        if(Test-AidosRepositoryThinkerComposerFocusProof -Composer $composer){$focusProven=$true;break}
        try{$composer.SetFocus()}catch{}
    }
    if(-not$focusProven){throw 'ChatGPT composer keyboard focus proof is required before send.'}

    # A zero-result SendInput call is reproducible on the authorized interactive
    # host. Its keybd_event compatibility fallback has no API acknowledgement,
    # so first prove a unique sentinel mutation before hydrating the real prompt.
    # This prevents stale matching ValuePattern text from masquerading as an
    # accepted keyboard/React input event.
    $inputSentinel="AIDOS_INPUT_PROBE::$([guid]::NewGuid().ToString('N'))"
    Set-Clipboard -Value $inputSentinel
    $sentinelSelectTransport=Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x41
    Start-Sleep -Milliseconds 50
    $sentinelPasteTransport=Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x56

    $sentinelProven=$false
    for($attempt=0;$attempt-lt30;$attempt++){
        Start-Sleep -Milliseconds 100
        $sentinelComposer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
        $sentinelObserved=[string](Get-AidosDesktopChatGPTElementText $sentinelComposer)
        if(Test-AidosRepositoryThinkerComposerTextMatch -Expected $inputSentinel -Observed $sentinelObserved){$composer=$sentinelComposer;$sentinelProven=$true;break}
    }
    $uiaValueFallback=$false
    if(-not$sentinelProven -and
       $sentinelSelectTransport.StartsWith('KEYBD_EVENT_ZERO_FALLBACK(',[StringComparison]::Ordinal) -and
       $sentinelPasteTransport.StartsWith('KEYBD_EVENT_ZERO_FALLBACK(',[StringComparison]::Ordinal)){
        $composer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
        $sentinelSelectTransport=Set-AidosRepositoryThinkerComposerValue -Composer $composer -Value $inputSentinel
        $sentinelPasteTransport=$sentinelSelectTransport
        for($attempt=0;$attempt-lt30;$attempt++){
            Start-Sleep -Milliseconds 100
            $sentinelComposer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
            $sentinelObserved=[string](Get-AidosDesktopChatGPTElementText $sentinelComposer)
            if(Test-AidosRepositoryThinkerComposerTextMatch -Expected $inputSentinel -Observed $sentinelObserved){$composer=$sentinelComposer;$sentinelProven=$true;$uiaValueFallback=$true;break}
        }
    }
    if(-not$sentinelProven){throw 'ChatGPT composer did not prove the unique native keyboard input sentinel; payload hydration was not attempted.'}

    if($uiaValueFallback){
        $composer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
        $payloadSelectTransport=Set-AidosRepositoryThinkerComposerValue -Composer $composer -Value $PromptText
        $payloadPasteTransport=$payloadSelectTransport
    }else{
        Set-Clipboard -Value $PromptText
        $payloadSelectTransport=Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x41
        Start-Sleep -Milliseconds 50
        $payloadPasteTransport=Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x56
    }

    $composerExact=$false
    $payloadProofMode='NONE'
    $current=$null
    for($attempt=0;$attempt-lt30;$attempt++){
        Start-Sleep -Milliseconds 100
        $currentComposer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
        $current=[string](Get-AidosDesktopChatGPTElementText $currentComposer)
        $payloadProof=Get-AidosRepositoryThinkerComposerPayloadProof -Expected $PromptText -Observed $current
        if([bool]$payloadProof.proven){$composer=$currentComposer;$composerExact=$true;$payloadProofMode=[string]$payloadProof.mode;break}
    }
    if(-not$composerExact){
        $expectedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $PromptText
        $observedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $current
        throw "ChatGPT composer did not contain the outbound payload after fresh keyboard hydration proof (expected_length=$($expectedComparable.Length); observed_length=$(if($null-eq$observedComparable){0}else{$observedComparable.Length}))."
    }

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
        $composer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
        $composer.SetFocus()
        Start-Sleep -Milliseconds 100
        if(-not(Test-AidosRepositoryThinkerComposerFocusProof -Composer $composer)){throw 'ChatGPT composer keyboard focus proof is required before Enter fallback.'}
        $enterTransport=Invoke-AidosRepositoryThinkerNativeKey -Key 0x0D
        $sendMethod="NATIVE_ENTER::$enterTransport"
    }

    $cleared=$false
    $remaining=$null
    for($attempt=0;$attempt-lt50;$attempt++){
        Start-Sleep -Milliseconds 100
        $remaining=[string](Get-AidosDesktopChatGPTElementText $composer)
        if([string]::IsNullOrWhiteSpace($remaining) -or $remaining.IndexOf($PromptText,[StringComparison]::Ordinal)-lt0){$cleared=$true;break}
    }
    if(-not$cleared){throw 'ChatGPT composer still contains the exact outbound payload after submit; committed-send proof is absent.'}
    $visibleMarker=$false
    for($attempt=0;$attempt-lt60;$attempt++){
        Start-Sleep -Milliseconds 250
        if(Test-AidosRepositoryThinkerVisibleHandoffMarker -RootElement $root -PromptText $PromptText){$visibleMarker=$true;break}
    }
    if(-not$visibleMarker){throw 'ChatGPT conversation did not visibly expose the exact AIDOS_HANDOFF_READY marker after submit; durable delivery proof is absent.'}
    [pscustomobject]@{
        schema_version='0.1'
        assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}else{$null}
        assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['payload_sha256']){[string]$Assignment.payload_sha256}else{$null}
        conversation_fingerprint_sha256=$null
        composer_state='COMMITTED'
        composer_result=if([string]::IsNullOrWhiteSpace([string]$before)){'EMPTY'}elseif([string]$before-eq$PromptText){'MATCHING_EXACT'}else{'MISMATCH'}
        mutation_occurred=$mutationOccurred
        input_transport_state=[ordered]@{
            sentinel_select=[string]$sentinelSelectTransport
            sentinel_paste=[string]$sentinelPasteTransport
            payload_select=[string]$payloadSelectTransport
            payload_paste=[string]$payloadPasteTransport
            sentinel_proof='PROVEN'
            payload_proof=[string]$payloadProofMode
        }
        send_invocation_state=$sendMethod
        committed_message_proof_state='PROVEN'
        visible_handoff_marker_proof_state='PROVEN'
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
        TestTransportHealth={
            param($Context)
            $process=Get-Process -Id ([int]$Context.process_id) -ErrorAction Stop
            if(-not $process.Responding){throw 'CHATGPT_TRANSPORT_CIRCUIT_OPEN::process_not_responding'}
            if($process.Handles -gt 5000){throw "CHATGPT_TRANSPORT_CIRCUIT_OPEN::handle_count_$($process.Handles)"}
            if($process.WorkingSet64 -gt 1610612736){throw 'CHATGPT_TRANSPORT_CIRCUIT_OPEN::working_set_exceeds_1_5GB'}
            if(-not('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
            $sw=[Diagnostics.Stopwatch]::StartNew();$root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle));if(-not$root){throw 'CHATGPT_TRANSPORT_CIRCUIT_OPEN::uia_root_unavailable'}
            $condition=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty),'prompt-textarea'
            $null=$root.FindFirst([System.Windows.Automation.TreeScope]::Subtree,$condition);$sw.Stop()
            if($sw.ElapsedMilliseconds -gt 2000){throw "CHATGPT_TRANSPORT_CIRCUIT_OPEN::uia_latency_$($sw.ElapsedMilliseconds)ms"}
            [pscustomobject][ordered]@{status='HEALTHY';uia_latency_ms=$sw.ElapsedMilliseconds;working_set_bytes=$process.WorkingSet64;handles=$process.Handles}
        }.GetNewClosure()
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
                # ChatGPT Classic can briefly expose the WebView without its
                # document URL while the selected conversation is loading.
                # Treat that as transient readiness failure and keep the
                # bounded activation poll alive; do not send until the URL is
                # durably observed.
                try{
                    $observed=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
                    if(-not[string]::IsNullOrWhiteSpace([string]$observed.url) -and $observed.url.IndexOf('/c/',[StringComparison]::OrdinalIgnoreCase)-ge0){
                        $conversation=[pscustomobject][ordered]@{title=[string]$ConversationTitle;document_title=[string]$observed.title;url=[string]$observed.url;document=$observed.document}
                        return [pscustomobject][ordered]@{status='RESOLVED';method=$method;conversation=$conversation;context=$Context}
                    }
                }catch{ continue }
            }
            throw "ChatGPT conversation '$ConversationTitle' was invoked but no conversation URL became active."
        }
        ActivateConversation={
            param($Context,$Binding)
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not$root){throw 'ChatGPT window is unavailable through UI Automation.'}
            $current=$null
            try{$current=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root}catch{}
            if($current -and (Test-AidosRepositoryThinkerConversationUrlMatch -ObservedUrl ([string]$current.url) -ExpectedUrl ([string]$Binding.conversation_url))){return [pscustomobject][ordered]@{status='ALREADY_ACTIVE';conversation=$current;context=$Context}}
            $element=Find-AidosRepositoryThinkerConversationAction -RootElement $root -ConversationTitle ([string]$Binding.conversation_title)
            $method=Invoke-AidosRepositoryThinkerActionableElement -Element $element
            for($attempt=0;$attempt-lt50;$attempt++){
                Start-Sleep -Milliseconds 100
                try{
                    $observed=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
                    if(Test-AidosRepositoryThinkerConversationUrlMatch -ObservedUrl ([string]$observed.url) -ExpectedUrl ([string]$Binding.conversation_url)){return [pscustomobject][ordered]@{status='ACTIVATED';method=$method;conversation=$observed;context=$Context}}
                }catch{ continue }
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
            Start-Sleep -Milliseconds 750
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
    if($existing -and [string]$existing.status-eq'FAILED'){return [pscustomobject][ordered]@{status='FAILED_REQUIRES_RESET';state=$existing}}
    if($existing -and [string]$existing.status-eq'PENDING'){return [pscustomobject][ordered]@{status='PENDING_REQUIRES_RECOVERY';state=$existing}}
    if($null-eq$Backend){$Backend=New-AidosRepositoryThinkerWindowsBackend -ProcessName $ProcessName}
    $attempt=if($existing){[int]$existing.attempt+1}else{1}
    $path=Get-AidosRepositoryThinkerTriggerPath -StateRoot $StateRoot -ProjectId $projectId -HandoffId $handoffId
    $state=[pscustomobject][ordered]@{schema_version='0.1';project_id=$projectId;handoff_id=$handoffId;handoff_sha256=[string]$Handoff.text_sha256;status='PENDING';attempt=$attempt;triggered_at=$null;retry_after=$null;last_error=$null;send_proof=$null;updated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
    try{
        $context=& $Backend.GetProcessContext ([string]$binding.process_name)
        if($Backend.PSObject.Properties['TestTransportHealth']){& $Backend.TestTransportHealth $context|Out-Null}
        $activation=& $Backend.ActivateConversation $context $binding
        $context=& $Backend.FocusConversation $activation.context $binding
        $prompt=New-AidosRepositoryThinkerTriggerText -Binding $binding -Handoff $Handoff
        $send=& $Backend.SendPrompt $context $binding $prompt $Handoff.metadata
        if($null-eq$send -or -not [bool]$send.committed){throw 'ChatGPT trigger has no committed-send proof.'}
        $state.status='COMMITTED';$state.triggered_at=[DateTimeOffset]::UtcNow.ToString('o');$state.send_proof=$send;$state.updated_at=$state.triggered_at
        Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
        [pscustomobject][ordered]@{status='TRIGGERED';project_id=$projectId;handoff_id=$handoffId;activation=$activation;send=$send;state=$state}
    }catch{
        $delays=@(60,300,900,1800);$delay=$delays[[Math]::Min(($attempt-1),($delays.Count-1))]
        $state.status='FAILED';$state.last_error=$_.Exception.Message;$state.retry_after=[DateTimeOffset]::UtcNow.AddSeconds($delay).ToString('o');$state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
        [pscustomobject][ordered]@{status='FAILED';project_id=$projectId;handoff_id=$handoffId;error=$state.last_error;retry_after=$state.retry_after;state=$state}
    }
}
function Recover-AidosRepositoryThinkerInterruptedTrigger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$HandoffId)
    $path=Get-AidosRepositoryThinkerTriggerPath -StateRoot $StateRoot -ProjectId $ProjectId -HandoffId $HandoffId
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Interrupted Thinker trigger recovery requires an existing trigger state.'}
    $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    if([string]$state.status-ne'PENDING' -or $null-ne$state.triggered_at -or $null-ne$state.send_proof){throw 'Only a proofless PENDING Thinker trigger can be recovered as interrupted.'}
    $state.status='FAILED'
    $state.retry_after=$null
    $state.last_error='INTERRUPTED_BEFORE_COMMIT: host stopped while trigger attempt was PENDING; explicit reset is required.'
    $state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
    [pscustomobject][ordered]@{status='RECOVERED_INTERRUPTED';project_id=$ProjectId;handoff_id=$HandoffId;state=$state}
}
function Recover-AidosRepositoryThinkerUnprovenCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$Handoff,[string]$ProcessName='ChatGPT Classic')
    $projectId=[string]$Handoff.metadata.project_id;$handoffId=[string]$Handoff.metadata.handoff_id
    $path=Get-AidosRepositoryThinkerTriggerPath -StateRoot $StateRoot -ProjectId $projectId -HandoffId $handoffId
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Unproven Thinker commit recovery requires an existing trigger state.'}
    $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    if([string]$state.status-ne'COMMITTED'){throw "Unproven Thinker commit recovery requires COMMITTED state, found '$($state.status)'."}
    $proofProperty=$state.send_proof.PSObject.Properties['visible_handoff_marker_proof_state']
    if($null -eq $proofProperty){
        $state.status='FAILED';$state.triggered_at=$null;$state.retry_after=$null;$state.last_error='COMMITTED_WITHOUT_VISIBLE_HANDOFF_MARKER_PROOF: trigger predates fail-closed visible-marker evidence.';$state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
        return [pscustomobject][ordered]@{status='RECOVERED_UNPROVEN_COMMIT';project_id=$projectId;handoff_id=$handoffId;state=$state}
    }
    $binding=Read-AidosRepositoryThinkerBinding -StateRoot $StateRoot -ProjectId $projectId
    if($null-eq$binding -or [string]$binding.status-ne'BOUND'){throw 'Unproven Thinker commit recovery requires a bound conversation.'}
    if(-not('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
    $context=Get-AidosDesktopChatGPTProcessContext -ProcessName ([string]$binding.process_name)
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$context.window_handle))
    $conversation=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root
    if(-not(Test-AidosRepositoryThinkerConversationUrlMatch -ObservedUrl ([string]$conversation.url) -ExpectedUrl ([string]$binding.conversation_url))){throw 'Unproven Thinker commit recovery refused because the bound conversation is not active.'}
    $prompt=New-AidosRepositoryThinkerTriggerText -Binding $binding -Handoff $Handoff
    if(Test-AidosRepositoryThinkerVisibleHandoffMarker -RootElement $root -PromptText $prompt){return [pscustomobject][ordered]@{status='VISIBLE_PROOF_PRESENT';project_id=$projectId;handoff_id=$handoffId}}
    $state.status='FAILED';$state.triggered_at=$null;$state.retry_after=$null;$state.last_error='COMMITTED_WITHOUT_VISIBLE_HANDOFF_MARKER: composer cleared but the exact handoff marker was not visible in the bound conversation.';$state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
    [pscustomobject][ordered]@{status='RECOVERED_UNPROVEN_COMMIT';project_id=$projectId;handoff_id=$handoffId;state=$state}
}
function Reset-AidosRepositoryThinkerTrigger {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$HandoffId)
    $path=Get-AidosRepositoryThinkerTriggerPath -StateRoot $StateRoot -ProjectId $ProjectId -HandoffId $HandoffId
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Thinker trigger reset requires an existing FAILED trigger state.'}
    $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    if([string]$state.status-ne'FAILED' -or $null-ne$state.triggered_at){throw 'Only an uncommitted FAILED Thinker trigger can be reset.'}
    Remove-Item -LiteralPath $path -Force
    [pscustomobject][ordered]@{status='RESET';project_id=$ProjectId;handoff_id=$HandoffId}
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffBridgeDefaultStateRoot,Get-AidosRepositoryThinkerBindingPath,Get-AidosRepositoryThinkerTriggerPath,Write-AidosRepositoryThinkerJsonAtomic,Read-AidosRepositoryThinkerBinding,Get-AidosRepositoryThinkerCurrentConversationFromRoot,Get-AidosRepositoryThinkerLegacyAccessiblePattern,Test-AidosRepositoryThinkerActionableElement,Test-AidosRepositoryThinkerConversationTitleMatch,Test-AidosRepositoryThinkerConversationUrlMatch,Invoke-AidosRepositoryThinkerActionableElement,Find-AidosRepositoryThinkerConversationAction,New-AidosRepositoryThinkerWindowsBackend,Bind-AidosRepositoryThinkerConversation,Remove-AidosRepositoryThinkerBinding,Get-AidosRepositoryThinkerTriggerState,ConvertTo-AidosRepositoryThinkerRetryAfter,New-AidosRepositoryThinkerTriggerText,Invoke-AidosRepositoryThinkerTrigger,Recover-AidosRepositoryThinkerInterruptedTrigger,Recover-AidosRepositoryThinkerUnprovenCommit,Reset-AidosRepositoryThinkerTrigger
