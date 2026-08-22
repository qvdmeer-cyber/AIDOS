Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Nested reloads can evict the caller's public AidosBridge module instance.
Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking

function Get-AidosDesktopChatGPTAdapterRoot {
    param([string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/runtime/chatgpt'
}

function Get-AidosDesktopChatGPTReviewRoot {
    param([string]$ProjectRoot)
    Join-Path (Get-AidosDesktopChatGPTAdapterRoot $ProjectRoot) 'reviews'
}

function Get-AidosDesktopChatGPTEnrollmentPath {
    param([string]$ProjectRoot)
    Join-Path (Get-AidosDesktopChatGPTAdapterRoot $ProjectRoot) 'ENROLLMENT.json'
}

function Get-AidosDesktopChatGPTReviewPath {
    param([string]$ProjectRoot,[string]$ReviewId)
    Join-Path (Get-AidosDesktopChatGPTReviewRoot $ProjectRoot) $ReviewId
}

function Get-AidosDesktopChatGPTStatePath {
    param([string]$ProjectRoot,[string]$ReviewId)
    Join-Path (Get-AidosDesktopChatGPTReviewPath $ProjectRoot $ReviewId) 'ADAPTER_STATE.json'
}

function Get-AidosDesktopChatGPTResponsePath {
    param([string]$ProjectRoot,[string]$ReviewId)
    Join-Path (Get-AidosDesktopChatGPTReviewPath $ProjectRoot $ReviewId) 'REVIEW_RESPONSE.json'
}

function Get-AidosDesktopChatGPTTextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Write-AidosDesktopChatGPTJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    Write-AidosJsonAtomic $Path $Value
}

function Read-AidosDesktopChatGPTJson {
    param([Parameter(Mandatory)][string]$Path)
    Read-AidosJson $Path
}

function Initialize-AidosDesktopChatGPTWindowsAutomation {
    if(-not $IsWindows){ throw 'Desktop ChatGPT adapter is Windows-only.' }
    # Native helper types cannot be redefined in a long-lived PowerShell process.
    # Version the type whenever its P/Invoke contract changes so a fresh adapter
    # import cannot silently retain an incompatible declaration.
    if(-not ('AidosNativeDesktopV3' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AidosNativeDesktopV3 {
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    // The explicit W entry points write UTF-16.  CharSet.Unicode is required for
    // StringBuilder output marshalling; otherwise PowerShell sees only the first
    // byte before the UTF-16 NUL (for example "C" rather than "ChatGPT Classic").
    [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)] public static extern int GetWindowTextW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)] public static extern int GetClassNameW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenInputDesktop(UInt32 dwFlags, bool fInherit, UInt32 dwDesiredAccess);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool CloseDesktop(IntPtr hDesktop);
}
'@
    }
    if(-not ('System.Windows.Automation.AutomationElement' -as [type])){
        Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
    }
    if(-not ('System.Windows.Forms.SendKeys' -as [type])){
        Add-Type -AssemblyName System.Windows.Forms
    }
}

function Test-AidosDesktopChatGPTInteractiveSession {
    if(-not $IsWindows){ return $false }
    Initialize-AidosDesktopChatGPTWindowsAutomation
    $desktop=[AidosNativeDesktopV3]::OpenInputDesktop(0,$false,0x0101)
    if($desktop -eq [IntPtr]::Zero){ return $false }
    [void][AidosNativeDesktopV3]::CloseDesktop($desktop)
    return $true
}

function Get-AidosDesktopChatGPTWindowText {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)
    $sb=New-Object System.Text.StringBuilder 2048
    [void][AidosNativeDesktopV3]::GetWindowTextW($WindowHandle,$sb,$sb.Capacity)
    $sb.ToString()
}

function Get-AidosDesktopChatGPTWindowClass {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)
    $sb=New-Object System.Text.StringBuilder 256
    [void][AidosNativeDesktopV3]::GetClassNameW($WindowHandle,$sb,$sb.Capacity)
    $sb.ToString()
}

function Test-AidosDesktopChatGPTShellProof {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][IntPtr]$WindowHandle,
        [string]$WindowText,
        [string]$WindowClassName,
        [string]$WindowSource='MainWindowHandle'
    )
    if($WindowHandle -eq [IntPtr]::Zero){
        return [pscustomobject]@{
            usable_application_window=$false
            proof_reason='Window handle is zero.'
        }
    }
    $root=[System.Windows.Automation.AutomationElement]::FromHandle($WindowHandle)
    if(-not $root){
        return [pscustomobject]@{
            usable_application_window=$false
            proof_reason='UI Automation root element is unavailable.'
        }
    }
    $uiaProcessId=[int]$root.Current.ProcessId
    $uiaNativeHandle=[int64]$root.Current.NativeWindowHandle
    $uiaControlType=[string]$root.Current.ControlType.ProgrammaticName
    $uiaClassName=[string]$root.Current.ClassName
    $uiaName=[string]$root.Current.Name
    $isVisible=[AidosNativeDesktopV3]::IsWindowVisible($WindowHandle)
    $isMinimized=[AidosNativeDesktopV3]::IsIconic($WindowHandle)
    $expectedMainTitle=[string]$Process.MainWindowTitle
    $titleMatch=(
        -not [string]::IsNullOrWhiteSpace([string]$WindowText) -and
        -not [string]::IsNullOrWhiteSpace($expectedMainTitle) -and
        [string]$WindowText -eq $expectedMainTitle
    )
    $classMatch=([string]$WindowClassName -eq 'Chrome_WidgetWin_1' -and [string]$uiaClassName -eq [string]$WindowClassName)
    $uiaWindowTypeMatch=($uiaControlType -match '(^|\.|:)Window$' -or $uiaControlType -match 'Window$')
    $uiaMatch=(
        $uiaProcessId -eq [int]$Process.Id -and
        $uiaNativeHandle -eq [int64]$WindowHandle.ToInt64() -and
        $uiaWindowTypeMatch -and
        -not [string]::IsNullOrWhiteSpace([string]$uiaName)
    )
    $usable=([int]$Process.SessionId -eq [int]([System.Diagnostics.Process]::GetCurrentProcess().SessionId) -and
        $isVisible -and
        $titleMatch -and
        $classMatch -and
        $uiaMatch)
    $proofFailures=[System.Collections.Generic.List[string]]::new()
    if([int]$Process.SessionId -ne [int]([System.Diagnostics.Process]::GetCurrentProcess().SessionId)){ $null=$proofFailures.Add('session mismatch') }
    if(-not $isVisible){ $null=$proofFailures.Add('window not visible') }
    if(-not $titleMatch){ $null=$proofFailures.Add('window title mismatch') }
    if(-not $classMatch){ $null=$proofFailures.Add('shell class/name mismatch') }
    if($uiaProcessId -ne [int]$Process.Id){ $null=$proofFailures.Add('UIA ProcessId mismatch') }
    if($uiaNativeHandle -ne [int64]$WindowHandle.ToInt64()){ $null=$proofFailures.Add('UIA NativeWindowHandle mismatch') }
    if(-not $uiaWindowTypeMatch){ $null=$proofFailures.Add('UIA ControlType is not Window') }
    if([string]::IsNullOrWhiteSpace([string]$uiaName)){ $null=$proofFailures.Add('UIA Name missing') }
    [pscustomobject]@{
        present=$true
        process_id=$Process.Id
        process_name=$Process.ProcessName
        session_id=$Process.SessionId
        main_window_handle=[string](([IntPtr]$Process.MainWindowHandle).ToInt64())
        window_handle=[string]([Int64]$WindowHandle.ToInt64())
        window_title=[string]$WindowText
        window_class_name=[string]$WindowClassName
        window_is_minimized=$isMinimized
        window_is_foreground=([AidosNativeDesktopV3]::GetForegroundWindow() -eq $WindowHandle)
        window_is_visible=$isVisible
        window_source=$WindowSource
        uia_process_id=$uiaProcessId
        uia_native_window_handle=[string]$uiaNativeHandle
        uia_class_name=$uiaClassName
        uia_control_type=$uiaControlType
        uia_name=$uiaName
        usable_application_window=$usable
        proof_reason=if($usable){ 'Accepted application shell candidate.' } else { "Rejected non-shell window: $([string]::Join('; ', @($proofFailures)))" }
        proof_failures=@($proofFailures)
    }
}

function Get-AidosDesktopChatGPTProcessContextCandidates {
    param([string]$ProcessName='ChatGPT')
    Initialize-AidosDesktopChatGPTWindowsAutomation
    $sessionId=[System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $processes=@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })
    if(-not $processes){ return @() }
    $candidates=[System.Collections.Generic.List[object]]::new()
    foreach($process in $processes){
        $mainHandle=[IntPtr]$process.MainWindowHandle
        if($mainHandle -ne [IntPtr]::Zero){
            $windowText=Get-AidosDesktopChatGPTWindowText $mainHandle
            $windowClassName=Get-AidosDesktopChatGPTWindowClass $mainHandle
            $candidate=Test-AidosDesktopChatGPTShellProof -Process $process -WindowHandle $mainHandle -WindowText $windowText -WindowClassName $windowClassName -WindowSource 'MainWindowHandle'
            $null=$candidates.Add($candidate)
        }
    }
    @($candidates)
}

function Select-AidosDesktopChatGPTProcessContext {
    param(
        [Parameter(Mandatory)]$ProcessContexts,
        [int]$CurrentSessionId=([System.Diagnostics.Process]::GetCurrentProcess().SessionId)
    )
    $usable=@($ProcessContexts | Where-Object {
        $_ -and [int]$_.session_id -eq $CurrentSessionId -and
        -not [string]::IsNullOrWhiteSpace([string]$_.window_handle) -and
        [Int64]::Parse([string]$_.window_handle) -ne 0 -and
        $_.usable_application_window
    })
    if(-not $usable){
        if(-not $ProcessContexts){ return $null }
        $details=($ProcessContexts | ForEach-Object {
            "pid=$($_.process_id);handle=$($_.window_handle);title=$($_.window_title);class=$($_.window_class_name);usable=$($_.usable_application_window);reason=$($_.proof_reason)"
        }) -join ' | '
        throw "No usable ChatGPT application shell window was discovered in session $CurrentSessionId. Candidate proof details: $details"
    }
    $unique=@()
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($candidate in $usable){
        $key=[string]$candidate.window_handle
        if($seen.Add($key)){ $unique += $candidate }
    }
    if($unique.Count -gt 1){
        $details=($unique | ForEach-Object { "pid=$($_.process_id);handle=$($_.window_handle);title=$($_.window_title);class=$($_.window_class_name);minimized=$($_.window_is_minimized)" }) -join ' | '
        throw "Multiple usable ChatGPT top-level windows are present in session ${CurrentSessionId}: $details"
    }
    $unique[0]
}

function Get-AidosDesktopChatGPTProcessContext {
    param([string]$ProcessName='ChatGPT')
    $candidates=Get-AidosDesktopChatGPTProcessContextCandidates $ProcessName
    if(-not $candidates){
        $sessionId=[System.Diagnostics.Process]::GetCurrentProcess().SessionId
        throw "No ChatGPT application shell window was discovered in session $sessionId for process name '$ProcessName'. The visible shell must expose a non-zero MainWindowHandle, visible Win32 top-level window, matching UI Automation root, and matching shell class/name."
    }
    $selected=Select-AidosDesktopChatGPTProcessContext $candidates
    $selected
}

function Get-AidosDesktopChatGPTElementText {
    param($Element)
    if(-not $Element){ return $null }
    try {
        $valuePattern=$Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if($valuePattern){ return [string]$valuePattern.Current.Value }
    } catch {}
    try {
        $textPattern=$Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if($textPattern){ return [string]$textPattern.DocumentRange.GetText(-1) }
    } catch {}
    foreach($prop in @($Element.Current.Name,$Element.Current.HelpText,$Element.Current.AutomationId,$Element.Current.ClassName)){
        if(-not [string]::IsNullOrWhiteSpace([string]$prop)){ return [string]$prop }
    }
    $null
}

function Get-AidosDesktopChatGPTElementSearchText {
    <#
    UIA exposes a Chromium/WebView conversation in more than one form.  In
    particular, the RootWebArea's ValuePattern is its URL while its TextPattern
    is the rendered document; an individual message can also be split across
    adjacent Text controls.  Search every independently exposed representation
    without changing the stable locator text used for the enrollment fingerprint.
    #>
    param($Element)
    if(-not $Element){ return @() }
    $values=[System.Collections.Generic.List[string]]::new()
    try {
        $textPattern=$Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if($textPattern){
            $text=[string]$textPattern.DocumentRange.GetText(-1)
            if(-not [string]::IsNullOrWhiteSpace($text)){ $null=$values.Add($text) }
        }
    } catch {}
    try {
        $valuePattern=$Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if($valuePattern){
            $text=[string]$valuePattern.Current.Value
            if(-not [string]::IsNullOrWhiteSpace($text)){ $null=$values.Add($text) }
        }
    } catch {}
    foreach($text in @($Element.Current.Name,$Element.Current.HelpText,$Element.Current.AutomationId,$Element.Current.ClassName)){
        if(-not [string]::IsNullOrWhiteSpace([string]$text)){ $null=$values.Add([string]$text) }
    }
    @($values | Select-Object -Unique)
}

function Get-AidosDesktopChatGPTComposerElement {
    param([Parameter(Mandatory)]$RootElement)
    $matches=@($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object {
        $_.Current.AutomationId -eq 'prompt-textarea' -and
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
        $_.Current.IsKeyboardFocusable
    })
    if($matches.Count -ne 1){ throw "Expected exactly one ChatGPT composer control, found $($matches.Count)." }
    $matches[0]
}

function Test-AidosDesktopChatGPTWindowFocusProof {
    param($Context)
    [bool]$Context.window_is_foreground -or
    ($Context.PSObject.Properties['window_uia_focus_proven'] -and [bool]$Context.window_uia_focus_proven)
}

function Get-AidosDesktopChatGPTElementFingerprint {
    param($Element)
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
    $chain=[System.Collections.Generic.List[object]]::new()
    $current=$Element
    while($current){
        $chain.Insert(0,[ordered]@{
            name=[string]$current.Current.Name
            automation_id=[string]$current.Current.AutomationId
            class_name=[string]$current.Current.ClassName
            localized_control_type=[string]$current.Current.LocalizedControlType
            control_type=[string]$current.Current.ControlType.ProgrammaticName
        })
        $current=$walker.GetParent($current)
    }
    [ordered]@{
        path=@($chain)
        text=(Get-AidosDesktopChatGPTElementText $Element)
    }
}

function Get-AidosDesktopChatGPTFingerprintHash {
    param([Parameter(Mandatory)]$Fingerprint)
    Get-AidosDesktopChatGPTTextSha256 (($Fingerprint | ConvertTo-Json -Depth 100 -Compress))
}

function Find-AidosDesktopChatGPTConversationElement {
    param(
        [Parameter(Mandatory)]$RootElement,
        [Parameter(Mandatory)][string]$ProofText
    )
    $all=@($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))
    $matches=@()
    foreach($element in $all){
        $text=@(Get-AidosDesktopChatGPTElementSearchText $element | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_) -and
            ([string]$_).IndexOf($ProofText,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if($text){
            $matches += $element
        }
    }
    if(-not $matches){ throw "Conversation proof text '$ProofText' was not found in the active ChatGPT window." }
    if($matches.Count -gt 1){ throw "Conversation proof text '$ProofText' is ambiguous in the active ChatGPT window." }
    $matches[0]
}

function Test-AidosDesktopChatGPTFingerprintMatch {
    param($Expected,$Actual)
    if([string]$Expected.process_name -ne [string]$Actual.process_name){ throw 'ChatGPT process identity is stale or mismatched.' }
    if([string]$Expected.process_id -ne [string]$Actual.process_id){ throw 'ChatGPT process id is stale or mismatched.' }
    if([string]$Expected.session_id -ne [string]$Actual.session_id){ throw 'Windows session identity is stale or mismatched.' }
    if($Expected.PSObject.Properties['main_window_handle'] -and [string]$Expected.main_window_handle -and [string]$Expected.main_window_handle -ne [string]$Actual.main_window_handle){ throw 'ChatGPT main window handle is stale or mismatched.' }
    if($Expected.PSObject.Properties['window_handle'] -and [string]$Expected.window_handle -and [string]$Expected.window_handle -ne [string]$Actual.window_handle){ throw 'ChatGPT window handle is stale or mismatched.' }
    if([string]$Expected.window_class_name -ne [string]$Actual.window_class_name){ throw 'ChatGPT window class is stale or mismatched.' }
    if([string]$Expected.window_title -ne [string]$Actual.window_title){ throw 'ChatGPT window title is stale or mismatched.' }
    if([string]$Expected.account_proof_text -ne [string]$Actual.account_proof_text){ throw 'ChatGPT account proof text is stale or mismatched.' }
    if([string]$Expected.conversation_fingerprint_sha256 -ne [string]$Actual.conversation_fingerprint_sha256){ throw 'ChatGPT conversation fingerprint is stale or mismatched.' }
}

function Test-AidosDesktopChatGPTEnrollmentEquivalent {
    param($Existing,$Candidate)
    $keys=@(
        'schema_version','adapter_type','project_root','reviewer_role','reviewer_identity',
        'process_name','process_id','session_id','window_title','window_class_name',
        'conversation_proof_text','account_proof_text','conversation_fingerprint_sha256'
    )
    foreach($key in $keys){
        if($Existing.PSObject.Properties[$key] -and [string]$Existing.$key -ne [string]$Candidate.$key){ return $false }
    }
    return $true
}

function New-AidosDesktopChatGPTStubBackend {
    param(
        [bool]$InteractiveSession=$true,
        [bool]$ConversationMatches=$true,
        [bool]$NoResponse=$false,
        [string]$ResponseText,
        [string]$ProcessName='ChatGPT',
        [string]$WindowTitle='ChatGPT',
        [string]$WindowClassName='ApplicationFrameWindow'
    )
    $state=[pscustomobject]@{
        send_count=0
        read_count=0
        composer_text=$null
        last_prompt_text=$null
        last_prompt_sha256=$null
    }
    if($NoResponse){
        $ResponseText=$null
    } elseif(-not $PSBoundParameters.ContainsKey('ResponseText')){
        $ResponseText=@'
{
  "schema_version": "0.1",
  "envelope_type": "REVIEW_RESPONSE",
  "review_id": "stub-review",
  "project_id": "stub-project",
  "project_root": "/stub",
  "project_mode": "NEW_PROJECT",
  "definition_id": "DEF-1",
  "definition_version": 1,
  "execution_id": "EXEC-1",
  "revision": 1,
  "reviewer_role": "WORKER_AGENT",
  "reviewer_identity": "agents/WORKER_AGENT.md",
  "assignment_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "package_manifest_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "outcome": "PASS",
  "reason": "approved",
  "evidence_refs": [],
  "repair_guidance": [],
  "responded_at": "2026-01-01T00:00:00Z",
  "responded_by": "agents/WORKER_AGENT.md"
}
'@
    }
    [pscustomobject]@{
        State=$state
        AssertInteractiveSession = ({
            param()
            if(-not $InteractiveSession){ throw 'Windows session is locked or unavailable.' }
            $true
        }).GetNewClosure()
        GetProcessContext = ({
            param([string]$ExpectedProcessName)
            if(-not $ConversationMatches){
                return [pscustomobject]@{
                    present=$true
                    process_id=1111
                    process_name=$ExpectedProcessName
                    session_id=1
                    main_window_handle='42'
                    window_handle='42'
                    window_title='Wrong Conversation'
                    window_class_name='WrongClass'
                    window_is_minimized=$false
                    window_is_foreground=$true
                    window_is_visible=$true
                    window_source='stub'
                }
            }
            [pscustomobject]@{
                present=$true
                process_id=1111
                process_name=$ExpectedProcessName
                session_id=1
                main_window_handle='42'
                window_handle='42'
                window_title=$WindowTitle
                window_class_name=$WindowClassName
                window_is_minimized=$false
                window_is_foreground=$true
                window_is_visible=$true
                window_source='stub'
            }
        }).GetNewClosure()
        LocateConversation = ({
            param($Context,[string]$ProofText,$Enrollment)
            if(-not $ConversationMatches){ throw 'Expected enrolled ChatGPT conversation is not active.' }
            [pscustomobject]@{
                conversation_fingerprint = [ordered]@{
                    process_name=$Context.process_name
                    session_id=$Context.session_id
                    window_title=$Context.window_title
                    window_class_name=$Context.window_class_name
                    account_proof_text=$Enrollment.account_proof_text
                    conversation_proof_text=$ProofText
                    conversation_path=@([ordered]@{name='root';control_type='Window'})
                }
                conversation_fingerprint_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(([ordered]@{
                    process_name=$Context.process_name
                    session_id=$Context.session_id
                    window_title=$Context.window_title
                    window_class_name=$Context.window_class_name
                    account_proof_text=$Enrollment.account_proof_text
                    conversation_proof_text=$ProofText
                    conversation_path=@([ordered]@{name='root';control_type='Window'})
                } | ConvertTo-Json -Depth 100 -Compress)))).ToLowerInvariant()
            }
        }).GetNewClosure()
        InspectComposer = ({
            param($Context,$Enrollment)
            [pscustomobject]@{
                present=$true
                composer_text=$state.composer_text
                composer_text_sha256=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){$null}else{[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$state.composer_text))).ToLowerInvariant()}
                composer_text_length=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){0}else{([string]$state.composer_text).Length}
            }
        }).GetNewClosure()
        FocusConversation = ({
            param($Context,$Enrollment)
            if(-not $ConversationMatches){ throw 'Expected enrolled ChatGPT conversation is not active.' }
            $Context.window_is_foreground=$true
            $Context.window_is_minimized=$false
            $Context
        }).GetNewClosure()
        SendPrompt = ({
            param($Context,$Enrollment,[string]$PromptText,$Assignment)
            if(-not $ConversationMatches){ throw 'Expected enrolled ChatGPT conversation is not active.' }
            $before=[string]$state.composer_text
            $mutationOccurred=([string]::IsNullOrWhiteSpace($before) -or $before -ne [string]$PromptText)
            $state.send_count++
            $state.last_prompt_text=$PromptText
            $state.last_prompt_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($PromptText))).ToLowerInvariant()
            if([string]$state.composer_text -ne [string]$PromptText){ $state.composer_text=$PromptText }
            [pscustomobject]@{
                schema_version='0.1'
                assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}elseif($Assignment -and $Assignment.PSObject.Properties['assignment'] -and $Assignment.assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment.assignment_id}else{$null}
                assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['sha256']){[string]$Assignment.sha256}else{$null}
                conversation_fingerprint_sha256=if($Enrollment -and $Enrollment.PSObject.Properties['conversation_fingerprint_sha256']){[string]$Enrollment.conversation_fingerprint_sha256}else{$null}
                composer_state='COMMITTED'
                composer_result='MATCHING_EXACT'
                mutation_occurred=$mutationOccurred
                send_invocation_state='INVOKED'
                committed_message_proof_state='PROVEN'
                failure_reason=$null
                committed=$true
            }
        }).GetNewClosure()
        ReadLatestResponseText = ({
            param($Context,$Enrollment,[int]$Attempt,$Assignment)
            if($NoResponse){ return $null }
            if(-not $ConversationMatches){ return $null }
            if($state.send_count -lt 1){ return $null }
            $state.read_count++
            $ResponseText
        }).GetNewClosure()
    }
}

function New-AidosDesktopChatGPTWindowsBackend {
    param([string]$ProcessName='ChatGPT')
    Initialize-AidosDesktopChatGPTWindowsAutomation
    [pscustomobject]@{
        AssertInteractiveSession = {
            param()
            if(-not (Test-AidosDesktopChatGPTInteractiveSession)){ throw 'Windows session is locked or unavailable.' }
            $true
        }
        GetProcessContext = {
            param([string]$ExpectedProcessName)
            $context=Get-AidosDesktopChatGPTProcessContext $ExpectedProcessName
            if(-not $context){ return $null }
            $context
        }
        InspectComposer = {
            param($Context,$Enrollment)
            if(-not $Context){ throw 'ChatGPT process/window is not present.' }
            if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){ throw 'ChatGPT window is not present.' }
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not $root){ throw 'ChatGPT window is not accessible through UI Automation.' }
            $composer=Get-AidosDesktopChatGPTComposerElement $root
            $text=Get-AidosDesktopChatGPTElementText $composer
            [pscustomobject]@{
                present=$true
                composer_text=$text
                composer_text_sha256=if([string]::IsNullOrWhiteSpace([string]$text)){$null}else{Get-AidosDesktopChatGPTTextSha256 $text}
                composer_text_length=if([string]::IsNullOrWhiteSpace([string]$text)){0}else{([string]$text).Length}
            }
        }
        LocateConversation = {
            param($Context,[string]$ProofText,$Enrollment)
            if(-not $Context){ throw 'ChatGPT process/window is not present.' }
            if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){ throw 'ChatGPT window is not present.' }
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not $root){ throw 'ChatGPT window is not accessible through UI Automation.' }
            if(-not [string]::IsNullOrWhiteSpace([string]$Enrollment.account_proof_text)){
                $accountMatches=@($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))
                $accountSeen=$false
                foreach($element in $accountMatches){
                    $text=Get-AidosDesktopChatGPTElementText $element
                    if(-not [string]::IsNullOrWhiteSpace([string]$text) -and [string]$text.IndexOf([string]$Enrollment.account_proof_text,[StringComparison]::OrdinalIgnoreCase) -ge 0){
                        $accountSeen=$true
                        break
                    }
                }
                if(-not $accountSeen){ throw 'ChatGPT account proof text is stale or mismatched.' }
            }
            $element=Find-AidosDesktopChatGPTConversationElement $root $ProofText
            $fingerprint=Get-AidosDesktopChatGPTElementFingerprint $element
            [pscustomobject]@{
                conversation_fingerprint=$fingerprint
                conversation_fingerprint_sha256=(Get-AidosDesktopChatGPTFingerprintHash $fingerprint)
            }
        }
        FocusConversation = {
            param($Context,$Enrollment)
            Initialize-AidosDesktopChatGPTWindowsAutomation
            if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){ throw 'ChatGPT window is not present.' }
            $handle=[IntPtr]([int64]$Context.window_handle)
            if($Context.window_is_minimized){ [void][AidosNativeDesktopV3]::ShowWindowAsync($handle,9) }
            [void][AidosNativeDesktopV3]::SetForegroundWindow($handle)
            Start-Sleep -Milliseconds 150
            $Context.window_is_foreground=([AidosNativeDesktopV3]::GetForegroundWindow() -eq $handle)
            $root=[System.Windows.Automation.AutomationElement]::FromHandle($handle)
            if(-not $root){ throw 'ChatGPT window is not accessible through UI Automation.' }
            $composer=Get-AidosDesktopChatGPTComposerElement $root
            $uiaFocus=$false
            try {
                $composer.SetFocus()
                Start-Sleep -Milliseconds 100
                $uiaFocus=[bool]$composer.Current.HasKeyboardFocus
            } catch {}
            $Context | Add-Member -NotePropertyName window_uia_focus_proven -NotePropertyValue $uiaFocus -Force
            if(-not (Test-AidosDesktopChatGPTWindowFocusProof $Context)){ throw 'ChatGPT window could not be brought to foreground or given UI Automation composer focus.' }
            $Context.window_is_minimized=$false
            $Context
        }
        SendPrompt = {
            param($Context,$Enrollment,[string]$PromptText,$Assignment)
            Initialize-AidosDesktopChatGPTWindowsAutomation
            if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){ throw 'ChatGPT window is not present.' }
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not $root){ throw 'ChatGPT window is not accessible through UI Automation.' }
            $composer=Get-AidosDesktopChatGPTComposerElement $root
            $before=Get-AidosDesktopChatGPTElementText $composer
            $mutationOccurred=([string]$before -ne [string]$PromptText)
            $composer.SetFocus()
            Start-Sleep -Milliseconds 100
            $Context | Add-Member -NotePropertyName window_uia_focus_proven -NotePropertyValue ([bool]$composer.Current.HasKeyboardFocus) -Force
            if(-not (Test-AidosDesktopChatGPTWindowFocusProof $Context)){ throw 'ChatGPT composer focus proof is required before send.' }
            if($mutationOccurred){
                try {
                    $valuePattern=$composer.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
                    if($valuePattern){
                        $valuePattern.SetValue($PromptText)
                    } else {
                        throw 'ValuePattern not available.'
                    }
                } catch {
                    Set-Clipboard -Value $PromptText
                    $composer.SetFocus()
                    [System.Windows.Forms.SendKeys]::SendWait('^v')
                }
            }
            $submit=$null
            for($attempt=0;$attempt -lt 20;$attempt++){
                $matches=@($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object {
                    $_.Current.AutomationId -eq 'composer-submit-button' -and
                    $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
                    $_.Current.IsEnabled
                })
                if($matches.Count -eq 1){ $submit=$matches[0]; break }
                if($matches.Count -gt 1){ throw 'ChatGPT composer submit control is ambiguous.' }
                Start-Sleep -Milliseconds 100
            }
            if(-not $submit){ throw 'ChatGPT composer submit control is not available or enabled.' }
            try {
                $invoke=$submit.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                $invoke.Invoke()
            } catch { throw "ChatGPT composer submit control cannot be invoked through UI Automation: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 250
            $remaining=Get-AidosDesktopChatGPTElementText $composer
            if(-not[string]::IsNullOrWhiteSpace([string]$remaining) -and [string]$remaining.IndexOf($PromptText,[StringComparison]::Ordinal)-ge0){throw 'ChatGPT composer still contains the exact outbound payload after submit; committed-send proof is absent.'}
            [pscustomobject]@{
                schema_version='0.1'
                assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}elseif($Assignment -and $Assignment.PSObject.Properties['assignment'] -and $Assignment.assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment.assignment_id}else{$null}
                assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['sha256']){[string]$Assignment.sha256}else{$null}
                conversation_fingerprint_sha256=if($Enrollment -and $Enrollment.PSObject.Properties['conversation_fingerprint_sha256']){[string]$Enrollment.conversation_fingerprint_sha256}else{$null}
                composer_state='COMMITTED'
                composer_result=if([string]::IsNullOrWhiteSpace([string]$before)){'EMPTY'}elseif([string]$before -eq [string]$PromptText){'MATCHING_EXACT'}elseif(([string]$before).IndexOf([string]$PromptText,[StringComparison]::Ordinal) -ge 0){'DUPLICATE'}else{'MISMATCH'}
                mutation_occurred=$mutationOccurred
                send_invocation_state='INVOKED'
                committed_message_proof_state='PROVEN'
                failure_reason=$null
                committed=$true
            }
        }
        ReadLatestResponseText = {
            param($Context,$Enrollment,[int]$Attempt,$Assignment)
            if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){ return $null }
            $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
            if(-not $root){ return $null }
            $elements=@($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))
            $candidates=@()
            foreach($element in $elements){
                $text=Get-AidosDesktopChatGPTElementText $element
                if([string]::IsNullOrWhiteSpace([string]$text)){ continue }
                if([string]$text.IndexOf('"envelope_type":"REVIEW_RESPONSE"',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                   [string]$text.IndexOf('"envelope_type": "REVIEW_RESPONSE"',[StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                   [string]$text.IndexOf([string]$Assignment.review_id,[StringComparison]::OrdinalIgnoreCase) -ge 0){
                    $candidates += $text
                }
            }
            if(-not $candidates){ return $null }
            $candidates | Select-Object -Last 1
        }
    }
}

function New-AidosDesktopChatGPTEnrollmentObject {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ReviewerRole,
        [Parameter(Mandatory)][string]$ReviewerIdentity,
        [Parameter(Mandatory)]$ProcessContext,
        [Parameter(Mandatory)]$ConversationFingerprint,
        [Parameter(Mandatory)][string]$ConversationProofText,
        [Parameter(Mandatory)][AllowEmptyString()][string]$AccountProofText
    )
    $projectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    [ordered]@{
        schema_version='0.1'
        adapter_type='DESKTOP_CHATGPT'
        project_root=$projectRoot
        reviewer_role=[string]$ReviewerRole
        reviewer_identity=[string]$ReviewerIdentity
        process_name=[string]$ProcessContext.process_name
        process_id=[string]$ProcessContext.process_id
        session_id=[string]$ProcessContext.session_id
        main_window_handle=[string]$ProcessContext.main_window_handle
        window_handle=[string]$ProcessContext.window_handle
        window_title=[string]$ProcessContext.window_title
        window_class_name=[string]$ProcessContext.window_class_name
        window_is_minimized=[bool]$ProcessContext.window_is_minimized
        window_source=[string]$ProcessContext.window_source
        conversation_proof_text=[string]$ConversationProofText
        account_proof_text=[string]$AccountProofText
        conversation_fingerprint=$ConversationFingerprint
        conversation_fingerprint_sha256=(Get-AidosDesktopChatGPTFingerprintHash $ConversationFingerprint)
        enrolled_at=[DateTimeOffset]::UtcNow.ToString('o')
        enrolled_by='BRIDGE'
        updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        adapter_version='0.1'
    }
}

function Test-AidosDesktopChatGPTEnrollmentBinding {
    param($Enrollment,$ReviewerBinding,$ProcessContext)
    if([string]$Enrollment.reviewer_identity -ne [string]$ReviewerBinding.identity){ throw 'Desktop ChatGPT enrollment reviewer identity mismatch.' }
    if([string]$Enrollment.reviewer_role -ne [string]$ReviewerBinding.role){ throw 'Desktop ChatGPT enrollment reviewer role mismatch.' }
    if([string]$Enrollment.process_name -ne [string]$ProcessContext.process_name){ throw 'Desktop ChatGPT process identity mismatch.' }
    if([string]$Enrollment.session_id -ne [string]$ProcessContext.session_id){ throw 'Desktop ChatGPT Windows session mismatch.' }
    if($Enrollment.PSObject.Properties['process_id'] -and [string]$Enrollment.process_id -and [string]$Enrollment.process_id -ne [string]$ProcessContext.process_id){ throw 'Desktop ChatGPT process id mismatch.' }
    if($Enrollment.PSObject.Properties['main_window_handle'] -and [string]$Enrollment.main_window_handle -and [string]$Enrollment.main_window_handle -ne [string]$ProcessContext.main_window_handle){ throw 'Desktop ChatGPT main window handle mismatch.' }
    if($Enrollment.PSObject.Properties['window_handle'] -and [string]$Enrollment.window_handle -and [string]$Enrollment.window_handle -ne [string]$ProcessContext.window_handle){ throw 'Desktop ChatGPT window handle mismatch.' }
    if([string]$Enrollment.window_class_name -ne [string]$ProcessContext.window_class_name){ throw 'Desktop ChatGPT window class mismatch.' }
    if([string]$Enrollment.window_title -ne [string]$ProcessContext.window_title){ throw 'Desktop ChatGPT window title mismatch.' }
}

function Get-AidosDesktopChatGPTReviewEvidenceDocuments {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Assignment,
        [Parameter(Mandatory)]$Manifest,
        [int]$MaximumDocumentBytes=131072,
        [int]$MaximumTotalBytes=524288
    )
    if($MaximumDocumentBytes -lt 4){ throw 'Desktop review per-document transport limit must be at least 4 bytes.' }
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    $prefix=$root+[IO.Path]::DirectorySeparatorChar
    $documents=[System.Collections.Generic.List[object]]::new()
    $total=0
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    $references=@([pscustomobject]@{kind='MANIFEST';path=[string]$Assignment.package_manifest_path;sha256=[string]$Assignment.package_manifest_sha256}) + @($Assignment.evidence_refs)
    foreach($reference in $references){
        $relative=[string]$reference.path
        if([IO.Path]::IsPathRooted($relative)){ throw "Desktop review evidence path must be project-relative: $relative" }
        $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
        if(-not $path.StartsWith($prefix,$comparison)){ throw "Desktop review evidence path escapes project root: $relative" }
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){ throw "Desktop review evidence is missing: $relative" }
        $bytes=[IO.File]::ReadAllBytes($path)
        $total+=$bytes.Length
        if($total -gt $MaximumTotalBytes){ throw 'Desktop review evidence exceeds the total transport limit.' }
        $sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        if($sha -ne [string]$reference.sha256){ throw "Desktop review evidence hash mismatch: $relative" }
        try{$text=$utf8.GetString($bytes)}catch{throw "Desktop review evidence is not UTF-8 text: $relative"}
        if($text.IndexOf([char]0) -ge 0){ throw "Desktop review evidence is not UTF-8 text: $relative" }
        if($text -match '(?im)-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|(?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[:=]\s*["'']?(?:Bearer\s+)?[A-Za-z0-9+/=_-]{16,}'){
            throw "Desktop review evidence is not secret-free: $relative"
        }
        if($bytes.Length -le $MaximumDocumentBytes){
            $null=$documents.Add([ordered]@{kind=[string]$reference.kind;path=$relative;sha256=$sha;content=$text})
            continue
        }

        $chunks=[System.Collections.Generic.List[object]]::new()
        $offset=0
        while($offset -lt $bytes.Length){
            $end=[Math]::Min($offset+$MaximumDocumentBytes,$bytes.Length)
            if($end -lt $bytes.Length){
                while($end -gt $offset -and (($bytes[$end] -band 0xC0) -eq 0x80)){$end--}
            }
            if($end -le $offset){ throw "Desktop review evidence cannot be chunked on a UTF-8 boundary within the per-document transport limit: $relative" }
            $length=$end-$offset
            $chunkBytes=[byte[]]::new($length)
            [Array]::Copy($bytes,$offset,$chunkBytes,0,$length)
            try{$chunkText=$utf8.GetString($chunkBytes)}catch{throw "Desktop review evidence chunk is not UTF-8 text: $relative"}
            $chunkSha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($chunkBytes)).ToLowerInvariant()
            $null=$chunks.Add([pscustomobject]@{content=$chunkText;sha256=$chunkSha})
            $offset=$end
        }

        $chunkCount=$chunks.Count
        for($index=0;$index -lt $chunkCount;$index++){
            $chunk=$chunks[$index]
            $null=$documents.Add([ordered]@{
                kind=[string]$reference.kind
                path=$relative
                sha256=$sha
                source_bytes=$bytes.Length
                transport_chunk_index=$index+1
                transport_chunk_count=$chunkCount
                transport_chunk_sha256=[string]$chunk.sha256
                content=[string]$chunk.content
            })
        }
    }
    @($documents)
}

function New-AidosDesktopChatGPTPrompt {
    param(
        [Parameter(Mandatory)][string]$AssignmentText,
        [Parameter(Mandatory)]$ResponseTemplate,
        [Parameter(Mandatory)][object[]]$EvidenceDocuments
    )
    $responseTemplateText=$ResponseTemplate | ConvertTo-Json -Depth 100 -Compress
    $evidenceText=$EvidenceDocuments | ConvertTo-Json -Depth 100 -Compress
    @"
You are the AIDOS Worker reviewer.
Review only the attached canonical assignment and attached, hash-verified authorized evidence.
Do not rely on chat history, filesystem access, unbound files, or secrets.
Return exactly one raw JSON REVIEW_RESPONSE object: no markdown, prose, code fences, or commentary.
Copy every binding field and evidence_refs exactly from the response template. Choose one permitted outcome and replace only outcome, reason, repair_guidance when appropriate, and responded_at.

CANONICAL REVIEW_ASSIGNMENT:
$AssignmentText

AUTHORIZED_EVIDENCE_DOCUMENTS:
$evidenceText

REVIEW_RESPONSE_TEMPLATE:
$responseTemplateText
"@
}

function ConvertFrom-AidosDesktopChatGPTStrictResponseText {
    param([Parameter(Mandatory)][string]$Text,[string[]]$ExpectedPathValues=@())
    $trim=([string]$Text).Trim()
    if($trim.StartsWith('```')){
        if($trim -notmatch '^```(?:json)?\s*(?<body>[\s\S]*?)\s*```$'){ throw 'Review response must be a single fenced JSON block or raw JSON object.' }
        $trim=$Matches.body.Trim()
    }
    if($trim -notmatch '^\{[\s\S]*\}$'){ throw 'Review response must be a single JSON object without extra prose.' }
    try { return ($trim | ConvertFrom-Json -Depth 100) } catch {
        # ChatGPT occasionally renders Windows/relative paths with literal
        # separators despite receiving JSON-escaped text. Repair only exact
        # bridge-bound path values; all identities and all other malformed JSON
        # remain fail-closed and normal binding validation still follows.
        $allowed=@{}
        foreach($value in @($ExpectedPathValues | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })){ $allowed[[string]$value]=$true }
        $pathFieldPattern=[regex]::new('"(?<name>project_root|path)"\s*:\s*"(?<value>(?:\\.|[^"\\])*)"')
        $repaired=$pathFieldPattern.Replace($trim,[System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $value=[string]$match.Groups['value'].Value
            if($allowed.ContainsKey($value)){
                return '"'+[string]$match.Groups['name'].Value+'":'+($value | ConvertTo-Json -Compress)
            }
            $match.Value
        })
        if($repaired -cne $trim){
            try { return ($repaired | ConvertFrom-Json -Depth 100) } catch {}
        }
        throw "Review response is not valid JSON: $($_.Exception.Message)"
    }
}

function Write-AidosDesktopChatGPTEnrollmentAtomic {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Value)
    $path=Get-AidosDesktopChatGPTEnrollmentPath $ProjectRoot
    $dir=Split-Path -Parent $path
    if(-not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-AidosDesktopChatGPTJsonAtomic $path $Value
}

function Read-AidosDesktopChatGPTEnrollment {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path=Get-AidosDesktopChatGPTEnrollmentPath $ProjectRoot
    if(Test-Path -LiteralPath $path -PathType Leaf){ Read-AidosDesktopChatGPTJson $path } else { $null }
}

function Write-AidosDesktopChatGPTStateAtomic {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId,[Parameter(Mandatory)]$Value)
    $path=Get-AidosDesktopChatGPTStatePath $ProjectRoot $ReviewId
    $dir=Split-Path -Parent $path
    if(-not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-AidosDesktopChatGPTJsonAtomic $path $Value
}

function Read-AidosDesktopChatGPTState {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId)
    $path=Get-AidosDesktopChatGPTStatePath $ProjectRoot $ReviewId
    if(Test-Path -LiteralPath $path -PathType Leaf){ Read-AidosDesktopChatGPTJson $path } else { $null }
}

function Invoke-AidosDesktopChatGPTEnroll {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ConversationProofText,
        [string]$AccountProofText='',
        [string]$ProcessName='ChatGPT',
        [object]$Backend
    )
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $reviewerBinding=Get-AidosReviewReviewerBinding $ProjectRoot
    if(-not $Backend){ $Backend=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName }
    & $Backend.AssertInteractiveSession | Out-Null
    $context=& $Backend.GetProcessContext $ProcessName
    if(-not $context -or -not $context.present){ throw 'ChatGPT process/window is not present.' }
    if($context.window_is_minimized -or -not (Test-AidosDesktopChatGPTWindowFocusProof $context)){ $context=& $Backend.FocusConversation $context ([pscustomobject]@{}) }
    if(-not (Test-AidosDesktopChatGPTWindowFocusProof $context)){ throw 'ChatGPT window could not be brought to foreground or given UI Automation composer focus.' }
    $loc=& $Backend.LocateConversation $context $ConversationProofText ([pscustomobject]@{account_proof_text=$AccountProofText})
    $enrollment=New-AidosDesktopChatGPTEnrollmentObject $ProjectRoot $reviewerBinding.role $reviewerBinding.identity $context $loc.conversation_fingerprint $ConversationProofText $AccountProofText
    $existing=Read-AidosDesktopChatGPTEnrollment $ProjectRoot
    if($existing){
        if(-not (Test-AidosDesktopChatGPTEnrollmentEquivalent $existing $enrollment)){ throw 'Desktop ChatGPT enrollment already exists and does not match the current conversation binding.' }
        return [pscustomobject]@{
            enrollment_path=(Get-AidosDesktopChatGPTEnrollmentPath $ProjectRoot)
            enrollment_sha256=(Get-FileHash -LiteralPath (Get-AidosDesktopChatGPTEnrollmentPath $ProjectRoot) -Algorithm SHA256).Hash.ToLowerInvariant()
            reviewer_role=$reviewerBinding.role
            reviewer_identity=$reviewerBinding.identity
            conversation_fingerprint_sha256=$existing.conversation_fingerprint_sha256
            status='ENROLLED'
            idempotent=$true
        }
    }
    Write-AidosDesktopChatGPTEnrollmentAtomic $ProjectRoot $enrollment
    [pscustomobject]@{
        enrollment_path=(Get-AidosDesktopChatGPTEnrollmentPath $ProjectRoot)
        enrollment_sha256=(Get-FileHash -LiteralPath (Get-AidosDesktopChatGPTEnrollmentPath $ProjectRoot) -Algorithm SHA256).Hash.ToLowerInvariant()
        reviewer_role=$reviewerBinding.role
        reviewer_identity=$reviewerBinding.identity
        conversation_fingerprint_sha256=$enrollment.conversation_fingerprint_sha256
        status='ENROLLED'
        idempotent=$false
    }
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
        [object]$Backend
    )
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    if(-not(Test-Path -LiteralPath $AssignmentPath -PathType Leaf)){
        $reviewId=[string](Split-Path -Leaf (Split-Path -Parent $AssignmentPath))
        if([string]::IsNullOrWhiteSpace($reviewId)){ throw "Review assignment is missing and no review ID can be derived: $AssignmentPath" }
        $state=Read-AidosDesktopChatGPTState $ProjectRoot $reviewId
        $responsePath=Get-AidosDesktopChatGPTResponsePath $ProjectRoot $reviewId
        if($state -and $state.status -eq 'HANDOFF_COMPLETE' -and (Test-Path -LiteralPath $responsePath -PathType Leaf)){
            $record=Read-AidosReviewRecord $ProjectRoot $reviewId
            $response=Read-AidosDesktopChatGPTJson $responsePath
            return [pscustomobject]@{review_id=$reviewId;status='HANDOFF_COMPLETE';idempotent=$true;assignment_sha256=$record.assignment_sha256;response_path=$responsePath;response_sha256=$state.response_sha256;response=$response;adapter_state=$state}
        }
        throw "Review assignment is missing before handoff completion: $AssignmentPath"
    }
    $AssignmentPath=Resolve-AidosFileSystemPath $AssignmentPath
    $assignmentText=Get-Content -LiteralPath $AssignmentPath -Raw -Encoding UTF8
    if([string]::IsNullOrWhiteSpace([string]$assignmentText)){ throw 'Review assignment JSON is required.' }
    $assignment=$assignmentText | ConvertFrom-Json -Depth 100
    $reviewId=[string]$assignment.review_id
    $record=Read-AidosReviewRecord $ProjectRoot $reviewId
    $reviewerBinding=Get-AidosReviewReviewerBinding $ProjectRoot
    $manifestPath=Join-Path $ProjectRoot ([string]$record.package_manifest_path)
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){ throw "Review manifest not found: $manifestPath" }
    $manifest=Read-AidosJson $manifestPath
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Test-AidosReviewAssignmentBinding $ProjectRoot $assignment $manifest $manifestSha $reviewerBinding | Out-Null
    $assignmentSha=(Get-FileHash -LiteralPath $AssignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]$record.assignment_sha256 -and [string]$record.assignment_sha256 -ne $assignmentSha){ throw 'Review assignment hash mismatch.' }
    if(-not $Backend){ $Backend=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName }
    $enrollmentPath=Get-AidosDesktopChatGPTEnrollmentPath $ProjectRoot
    if(-not(Test-Path -LiteralPath $enrollmentPath -PathType Leaf)){ throw 'Desktop ChatGPT conversation enrollment is required before send.' }
    $enrollment=Read-AidosDesktopChatGPTEnrollment $ProjectRoot
    $state=Read-AidosDesktopChatGPTState $ProjectRoot $reviewId
    $responsePath=Get-AidosDesktopChatGPTResponsePath $ProjectRoot $reviewId
    $responseExists=Test-Path -LiteralPath $responsePath -PathType Leaf
    if($state -and $state.status -eq 'HANDOFF_COMPLETE' -and $responseExists){
        $response=Read-AidosDesktopChatGPTJson $responsePath
        return [pscustomobject]@{
            review_id=$reviewId
            status='HANDOFF_COMPLETE'
            idempotent=$true
            assignment_sha256=$assignmentSha
            response_path=$responsePath
            response_sha256=$state.response_sha256
            response=$response
            adapter_state=$state
        }
    }
    if($state -and $state.status -eq 'HANDOFF_COMPLETE' -and -not $responseExists){
        throw 'Review handoff is complete but the response sidecar is missing.'
    }

    if($responseExists){
        $responseText=Get-Content -LiteralPath $responsePath -Raw -Encoding UTF8
    } elseif($state -and (($state.status -in @('SENT','RECEIVED','VALIDATED')) -or ($state.status -eq 'WAITING_INTERACTIVE_SESSION' -and [string]$state.delivery_status -eq 'SENT'))){
        $interactive=$true
        try { & $Backend.AssertInteractiveSession | Out-Null } catch { $interactive=$false }
        if(-not $interactive){
            $waiting=[ordered]@{
                schema_version='0.1'
                adapter_type='DESKTOP_CHATGPT'
                project_root=$ProjectRoot
                reviewer_role=$reviewerBinding.role
                reviewer_identity=$reviewerBinding.identity
                review_id=$reviewId
                assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$AssignmentPath)
                assignment_sha256=$assignmentSha
                enrollment_path=$enrollmentPath
                conversation_fingerprint_sha256=$enrollment.conversation_fingerprint_sha256
                status='WAITING_INTERACTIVE_SESSION'
                delivery_status='SENT'
                sent_at=$state.sent_at
                received_at=$state.received_at
                validated_at=$state.validated_at
                last_error='WINDOWS_LOCKED_OR_SESSION_UNAVAILABLE'
                updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            }
            Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $waiting
            return [pscustomobject]@{
                review_id=$reviewId
                status='WAITING_INTERACTIVE_SESSION'
                idempotent=$false
                adapter_state=[pscustomobject]$waiting
            }
        }
        $context=& $Backend.GetProcessContext $ProcessName
        if(-not $context -or -not $context.present){ throw 'ChatGPT process/window is not present.' }
        Test-AidosDesktopChatGPTEnrollmentBinding $enrollment $reviewerBinding $context | Out-Null
        if($context.window_is_minimized -or -not (Test-AidosDesktopChatGPTWindowFocusProof $context)){ $context=& $Backend.FocusConversation $context $enrollment }
        if(-not (Test-AidosDesktopChatGPTWindowFocusProof $context)){ throw 'ChatGPT window could not be brought to foreground or given UI Automation composer focus.' }
        $responseText=$null
        for($attempt=0;$attempt -lt $ResponseTimeoutSeconds;$attempt++){
            Start-Sleep -Seconds 1
            $responseText=& $Backend.ReadLatestResponseText $context $enrollment ($attempt+1) $assignment
            if(-not [string]::IsNullOrWhiteSpace([string]$responseText)){ break }
        }
        if([string]::IsNullOrWhiteSpace([string]$responseText)){
            $waiting=[ordered]@{
                schema_version='0.1'
                adapter_type='DESKTOP_CHATGPT'
                project_root=$ProjectRoot
                reviewer_role=$reviewerBinding.role
                reviewer_identity=$reviewerBinding.identity
                review_id=$reviewId
                assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$AssignmentPath)
                assignment_sha256=$assignmentSha
                enrollment_path=$enrollmentPath
                conversation_fingerprint_sha256=$enrollment.conversation_fingerprint_sha256
                status='SENT'
                last_error='RESPONSE_NOT_READY'
                updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            }
            Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $waiting
            return [pscustomobject]@{
                review_id=$reviewId
                status='SENT'
                waiting_for_response=$true
                idempotent=$false
                adapter_state=[pscustomobject]$waiting
            }
        }
    } else {
        $interactive=$true
        try { & $Backend.AssertInteractiveSession | Out-Null } catch { $interactive=$false }
        if(-not $interactive){
            $waiting=[ordered]@{
                schema_version='0.1'
                adapter_type='DESKTOP_CHATGPT'
                project_root=$ProjectRoot
                reviewer_role=$reviewerBinding.role
                reviewer_identity=$reviewerBinding.identity
                review_id=$reviewId
                assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$AssignmentPath)
                assignment_sha256=$assignmentSha
                enrollment_path=$enrollmentPath
                conversation_fingerprint_sha256=$enrollment.conversation_fingerprint_sha256
                status='WAITING_INTERACTIVE_SESSION'
                delivery_status='PREPARED'
                last_error='WINDOWS_LOCKED_OR_SESSION_UNAVAILABLE'
                updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            }
            Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $waiting
            return [pscustomobject]@{
                review_id=$reviewId
                status='WAITING_INTERACTIVE_SESSION'
                idempotent=$false
                adapter_state=[pscustomobject]$waiting
            }
        }
        $context=& $Backend.GetProcessContext $ProcessName
        if(-not $context -or -not $context.present){ throw 'ChatGPT process/window is not present.' }
        Test-AidosDesktopChatGPTEnrollmentBinding $enrollment $reviewerBinding $context | Out-Null
        if($context.window_is_minimized -or -not (Test-AidosDesktopChatGPTWindowFocusProof $context)){ $context=& $Backend.FocusConversation $context $enrollment }
        if(-not (Test-AidosDesktopChatGPTWindowFocusProof $context)){ throw 'ChatGPT window could not be brought to foreground or given UI Automation composer focus.' }
        $prepared=[ordered]@{
            schema_version='0.1'
            adapter_type='DESKTOP_CHATGPT'
            project_root=$ProjectRoot
            reviewer_role=$reviewerBinding.role
            reviewer_identity=$reviewerBinding.identity
            review_id=$reviewId
            assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$AssignmentPath)
            assignment_sha256=$assignmentSha
            enrollment_path=$enrollmentPath
            conversation_fingerprint_sha256=$enrollment.conversation_fingerprint_sha256
            status='PREPARED'
            updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        }
        Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $prepared
        $evidenceDocuments=Get-AidosDesktopChatGPTReviewEvidenceDocuments $ProjectRoot $assignment $manifest
        $responseTemplate=[ordered]@{
            schema_version='0.1'
            envelope_type='REVIEW_RESPONSE'
            review_id=$reviewId
            project_id=[string]$assignment.project_id
            project_root=[string]$assignment.project_root
            project_mode=[string]$assignment.project_mode
            definition_id=[string]$assignment.definition_id
            definition_version=[int]$assignment.definition_version
            execution_id=[string]$assignment.execution_id
            revision=[int]$assignment.revision
            reviewer_role=[string]$assignment.reviewer_role
            reviewer_identity=[string]$assignment.reviewer_identity
            assignment_sha256=$assignmentSha
            package_manifest_sha256=$manifestSha
            outcome='PASS'
            reason='Replace with the evidence-based review reason.'
            evidence_refs=@($assignment.evidence_refs)
            repair_guidance=@()
            responded_at=[DateTimeOffset]::UtcNow.ToString('o')
            responded_by=[string]$assignment.reviewer_identity
        }
        $prompt=New-AidosDesktopChatGPTPrompt $assignmentText $responseTemplate $evidenceDocuments
        $prepared.status='SENT'
        $prepared.sent_at=[DateTimeOffset]::UtcNow.ToString('o')
        $prepared.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $prepared
        & $Backend.SendPrompt $context $enrollment $prompt
        $responseText=$null
        for($attempt=0;$attempt -lt $ResponseTimeoutSeconds;$attempt++){
            Start-Sleep -Seconds 1
            $responseText=& $Backend.ReadLatestResponseText $context $enrollment ($attempt+1) $assignment
            if(-not [string]::IsNullOrWhiteSpace([string]$responseText)){ break }
        }
        if([string]::IsNullOrWhiteSpace([string]$responseText)){
            $prepared.status='SENT'
            $prepared.last_error='RESPONSE_NOT_READY'
            $prepared.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $prepared
            return [pscustomobject]@{
                review_id=$reviewId
                status='SENT'
                waiting_for_response=$true
                idempotent=$false
                adapter_state=[pscustomobject]$prepared
            }
        }
    }

    $received=[ordered]@{
        schema_version='0.1'
        adapter_type='DESKTOP_CHATGPT'
        project_root=$ProjectRoot
        reviewer_role=$reviewerBinding.role
        reviewer_identity=$reviewerBinding.identity
        review_id=$reviewId
        assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$AssignmentPath)
        assignment_sha256=$assignmentSha
        enrollment_path=$enrollmentPath
        conversation_fingerprint_sha256=$enrollment.conversation_fingerprint_sha256
        status='RECEIVED'
        received_at=[DateTimeOffset]::UtcNow.ToString('o')
        updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $received
    try {
        $boundPaths=@([string]$assignment.project_root)+@($assignment.evidence_refs | ForEach-Object { [string]$_.path })
        $response=ConvertFrom-AidosDesktopChatGPTStrictResponseText $responseText $boundPaths
        if([string]$response.review_id -ne [string]$reviewId){ throw 'Review response review_id is stale or mismatched.' }
        if([string]$response.assignment_sha256 -ne [string]$assignmentSha){ throw 'Review assignment hash mismatch.' }
        if([string]$response.package_manifest_sha256 -ne [string]$manifestSha){ throw 'Review package manifest hash mismatch.' }
        Test-AidosReviewResponseBinding $ProjectRoot $response $assignment $manifest $record $assignmentSha | Out-Null
    } catch {
        $rejectedPath=Join-Path (Get-AidosDesktopChatGPTReviewPath $ProjectRoot $reviewId) 'RESPONSE_REJECTED.json'
        $rejected=[ordered]@{
            schema_version='0.1'
            review_id=$reviewId
            assignment_sha256=$assignmentSha
            response_text_sha256=(Get-AidosDesktopChatGPTTextSha256 $responseText)
            response_text=$responseText
            rejected_at=[DateTimeOffset]::UtcNow.ToString('o')
            rejection_reason=$_.Exception.Message
        }
        Write-AidosDesktopChatGPTJsonAtomic $rejectedPath $rejected
        $received.response_rejected_path=[IO.Path]::GetRelativePath($ProjectRoot,$rejectedPath)
        $received.response_rejected_sha256=(Get-FileHash -LiteralPath $rejectedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $received.last_error=$_.Exception.Message
        $received.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $received
        throw
    }
    $responseJson=$response | ConvertTo-Json -Depth 100 -Compress
    $responseSha=Get-AidosDesktopChatGPTTextSha256 $responseJson
    $responsePathDir=Split-Path -Parent $responsePath
    if(-not(Test-Path -LiteralPath $responsePathDir -PathType Container)){ New-Item -ItemType Directory -Path $responsePathDir -Force | Out-Null }
    Write-AidosDesktopChatGPTJsonAtomic $responsePath $response
    $responseSha=(Get-FileHash -LiteralPath $responsePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $validated=[ordered]@{
        schema_version='0.1'
        adapter_type='DESKTOP_CHATGPT'
        project_root=$ProjectRoot
        reviewer_role=$reviewerBinding.role
        reviewer_identity=$reviewerBinding.identity
        review_id=$reviewId
        assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$AssignmentPath)
        assignment_sha256=$assignmentSha
        response_path=[IO.Path]::GetRelativePath($ProjectRoot,$responsePath)
        response_sha256=$responseSha
        enrollment_path=$enrollmentPath
        conversation_fingerprint_sha256=$enrollment.conversation_fingerprint_sha256
        status='VALIDATED'
        validated_at=[DateTimeOffset]::UtcNow.ToString('o')
        updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $validated
    $handoff=[ordered]@{}
    foreach($p in $validated.GetEnumerator()){ $handoff[$p.Key]=$p.Value }
    $handoff.status='HANDOFF_COMPLETE'
    $handoff.handoff_complete_at=[DateTimeOffset]::UtcNow.ToString('o')
    $handoff.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    Write-AidosDesktopChatGPTStateAtomic $ProjectRoot $reviewId $handoff
    [pscustomobject]@{
        review_id=$reviewId
        status='HANDOFF_COMPLETE'
        idempotent=$false
        assignment_sha256=$assignmentSha
        response_path=$responsePath
        response_sha256=$responseSha
        response=$response
        adapter_state=[pscustomobject]$handoff
    }
}

Export-ModuleMember -Function Get-AidosDesktopChatGPTAdapterRoot,Get-AidosDesktopChatGPTReviewRoot,Get-AidosDesktopChatGPTEnrollmentPath,Get-AidosDesktopChatGPTReviewPath,Get-AidosDesktopChatGPTStatePath,Get-AidosDesktopChatGPTResponsePath,Test-AidosDesktopChatGPTInteractiveSession,Get-AidosDesktopChatGPTProcessContextCandidates,Select-AidosDesktopChatGPTProcessContext,Get-AidosDesktopChatGPTProcessContext,Get-AidosDesktopChatGPTElementText,Get-AidosDesktopChatGPTElementFingerprint,Get-AidosDesktopChatGPTFingerprintHash,Find-AidosDesktopChatGPTConversationElement,Test-AidosDesktopChatGPTFingerprintMatch,New-AidosDesktopChatGPTStubBackend,New-AidosDesktopChatGPTWindowsBackend,New-AidosDesktopChatGPTEnrollmentObject,Test-AidosDesktopChatGPTEnrollmentBinding,New-AidosDesktopChatGPTPrompt,ConvertFrom-AidosDesktopChatGPTStrictResponseText,Write-AidosDesktopChatGPTEnrollmentAtomic,Read-AidosDesktopChatGPTEnrollment,Write-AidosDesktopChatGPTStateAtomic,Read-AidosDesktopChatGPTState,Invoke-AidosDesktopChatGPTEnroll,Invoke-AidosDesktopChatGPTReview
