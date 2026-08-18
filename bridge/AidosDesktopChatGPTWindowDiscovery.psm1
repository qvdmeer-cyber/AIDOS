Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:BaseDesktopChatGPTModule = Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -DisableNameChecking -PassThru
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPTConversationProof.psm1') -DisableNameChecking

# Capture the base factory from the exact imported module instance. This remains
# stable even when the resilient compatibility shim exports the same public name.
$script:BaseDesktopChatGPTWindowsBackendCommand = $script:BaseDesktopChatGPTModule.ExportedCommands['New-AidosDesktopChatGPTWindowsBackend']
if($null-eq$script:BaseDesktopChatGPTWindowsBackendCommand){throw 'Base Desktop ChatGPT Windows backend factory is unavailable.'}

function Initialize-AidosDesktopChatGPTWindowDiscovery {
    if(-not [OperatingSystem]::IsWindows()){throw 'Desktop ChatGPT window discovery is Windows-only.'}
    if(-not ('AidosWindowDiscoveryV1' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AidosWindowDiscoveryV1 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)] public static extern int GetWindowTextW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)] public static extern int GetClassNameW(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
}
'@
    }
    if(-not ('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
}

function Get-AidosWindowDiscoveryText {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)
    $sb=New-Object System.Text.StringBuilder 2048
    [void][AidosWindowDiscoveryV1]::GetWindowTextW($WindowHandle,$sb,$sb.Capacity)
    $sb.ToString()
}

function Get-AidosWindowDiscoveryClass {
    param([Parameter(Mandatory)][IntPtr]$WindowHandle)
    $sb=New-Object System.Text.StringBuilder 256
    [void][AidosWindowDiscoveryV1]::GetClassNameW($WindowHandle,$sb,$sb.Capacity)
    $sb.ToString()
}

function Get-AidosDesktopChatGPTFallbackProcessContexts {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic')
    Initialize-AidosDesktopChatGPTWindowDiscovery
    $sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $processes=@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $sessionId})
    if($processes.Count-eq0){return @()}
    $byPid=@{}
    foreach($process in $processes){$byPid[[int]$process.Id]=$process}
    $handles=[Collections.Generic.List[IntPtr]]::new()
    $callback=[AidosWindowDiscoveryV1+EnumWindowsProc]{
        param([IntPtr]$hWnd,[IntPtr]$lParam)
        $pid=0
        [void][AidosWindowDiscoveryV1]::GetWindowThreadProcessId($hWnd,[ref]$pid)
        if($byPid.ContainsKey([int]$pid)){$handles.Add($hWnd)}
        return $true
    }.GetNewClosure()
    [void][AidosWindowDiscoveryV1]::EnumWindows($callback,[IntPtr]::Zero)
    $contexts=[Collections.Generic.List[object]]::new()
    foreach($handle in @($handles)){
        $pid=0;[void][AidosWindowDiscoveryV1]::GetWindowThreadProcessId($handle,[ref]$pid)
        $process=$byPid[[int]$pid]
        if(-not$process){continue}
        if(-not[AidosWindowDiscoveryV1]::IsWindowVisible($handle)){continue}
        $windowText=Get-AidosWindowDiscoveryText $handle
        $windowClass=Get-AidosWindowDiscoveryClass $handle
        if([string]::IsNullOrWhiteSpace($windowText)-or$windowClass-ne'Chrome_WidgetWin_1'){continue}
        try{$uia=[Windows.Automation.AutomationElement]::FromHandle($handle)}catch{$uia=$null}
        if(-not$uia){continue}
        $uiaPid=[int]$uia.Current.ProcessId
        $uiaHandle=[int64]$uia.Current.NativeWindowHandle
        $uiaClass=[string]$uia.Current.ClassName
        $uiaType=[string]$uia.Current.ControlType.ProgrammaticName
        $uiaName=[string]$uia.Current.Name
        $typeOk=($uiaType -match '(^|\.|:)Window$' -or $uiaType -match 'Window$')
        $titleOk=(-not[string]::IsNullOrWhiteSpace($uiaName) -and [string]::Equals($uiaName,$windowText,[StringComparison]::Ordinal))
        $usable=([int]$process.SessionId-eq$sessionId -and $uiaPid-eq[int]$process.Id -and $uiaHandle-eq[int64]$handle.ToInt64() -and $uiaClass-eq$windowClass -and $typeOk -and $titleOk)
        if(-not$usable){continue}
        $contexts.Add([pscustomobject][ordered]@{
            present=$true;process_id=[int]$process.Id;process_name=[string]$process.ProcessName;session_id=[int]$process.SessionId;
            main_window_handle=[string](([IntPtr]$process.MainWindowHandle).ToInt64());window_handle=[string]$handle.ToInt64();window_title=$windowText;window_class_name=$windowClass;
            window_is_minimized=[AidosWindowDiscoveryV1]::IsIconic($handle);window_is_foreground=([AidosWindowDiscoveryV1]::GetForegroundWindow()-eq$handle);window_is_visible=$true;
            window_source='EnumWindowsFallback';uia_process_id=$uiaPid;uia_native_window_handle=[string]$uiaHandle;uia_class_name=$uiaClass;uia_control_type=$uiaType;uia_name=$uiaName;
            usable_application_window=$true;proof_reason='Accepted EnumWindows fallback shell candidate.';proof_failures=@()
        })
    }
    @($contexts)
}

function Get-AidosDesktopChatGPTResilientProcessContext {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic',[scriptblock]$PrimaryResolver,[scriptblock]$FallbackResolver)
    if($PrimaryResolver){
        try{$primary=& $PrimaryResolver $ProcessName;if($primary){return $primary}}catch{$primaryError=$_.Exception.Message}
    }elseif(Get-Command Get-AidosDesktopChatGPTProcessContext -ErrorAction SilentlyContinue){
        try{$primary=Get-AidosDesktopChatGPTProcessContext -ProcessName $ProcessName;if($primary){return $primary}}catch{$primaryError=$_.Exception.Message}
    }
    $fallback=if($FallbackResolver){@(& $FallbackResolver $ProcessName)}else{@(Get-AidosDesktopChatGPTFallbackProcessContexts -ProcessName $ProcessName)}
    if($fallback.Count-eq1){return $fallback[0]}
    if($fallback.Count-gt1){
        $details=($fallback|ForEach-Object{"pid=$($_.process_id);handle=$($_.window_handle);title=$($_.window_title)"})-join' | '
        throw "Multiple fallback ChatGPT shell windows were discovered: $details"
    }
    if([string]::IsNullOrWhiteSpace([string]$primaryError)){$primaryError='Primary ChatGPT shell discovery returned no usable window.'}
    throw "ChatGPT shell discovery failed. Primary: $primaryError Fallback: no exact PID/session/UIA-bound visible shell candidate."
}

function ConvertTo-AidosDesktopChatGPTComposerSemanticText {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text='')
    if([string]::Equals($Text,'Vraag het aan ChatGPT',[StringComparison]::Ordinal)){return ''}
    $Text
}

function Get-AidosDesktopChatGPTFreshComposerObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    Initialize-AidosDesktopChatGPTWindowDiscovery
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw 'ChatGPT window is not present.'}
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not$root){throw 'ChatGPT window is not accessible through UI Automation.'}
    $matches=@($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition)|Where-Object {
        $_.Current.AutomationId -eq 'prompt-textarea' -and
        $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
        $_.Current.IsKeyboardFocusable
    })
    if($matches.Count-ne1){throw "Expected exactly one fresh ChatGPT composer control, found $($matches.Count)."}
    $composer=$matches[0]
    $text=''
    try {
        $valuePattern=$composer.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if($valuePattern){$text=[string]$valuePattern.Current.Value}
    } catch {}
    if([string]::IsNullOrWhiteSpace($text)){
        try {
            $textPattern=$composer.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
            if($textPattern){$text=[string]$textPattern.DocumentRange.GetText(-1)}
        } catch {}
    }
    $text=ConvertTo-AidosDesktopChatGPTComposerSemanticText -Text $text
    $hash=if([string]::IsNullOrWhiteSpace($text)){$null}else{[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()}
    [pscustomobject][ordered]@{
        present=$true
        composer_text=$text
        composer_text_sha256=$hash
        composer_text_length=$text.Length
        observation='FRESH_UIA_LOOKUP'
    }
}

function Wait-AidosDesktopChatGPTFreshComposerCleared {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$PromptText,
        [int]$Attempts=10,
        [int]$DelayMilliseconds=200
    )
    for($attempt=1;$attempt-le$Attempts;$attempt++){
        Start-Sleep -Milliseconds $DelayMilliseconds
        $fresh=Get-AidosDesktopChatGPTFreshComposerObservation -Context $Context
        if([string]::IsNullOrWhiteSpace([string]$fresh.composer_text)){return $fresh}
        if(-not[string]::Equals([string]$fresh.composer_text,$PromptText,[StringComparison]::Ordinal)){
            throw 'Fresh ChatGPT composer contains unrelated text after submit; committed-send proof remains fail-closed.'
        }
    }
    throw 'Fresh ChatGPT composer still contains the exact outbound payload after bounded submit observation; committed-send proof is absent.'
}

function Add-AidosDesktopChatGPTFreshComposerProof {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Backend)
    $primarySend=$Backend.SendPrompt
    $freshComposerObservation=Get-Command Get-AidosDesktopChatGPTFreshComposerObservation -CommandType Function -ErrorAction Stop
    $freshComposerCleared=Get-Command Wait-AidosDesktopChatGPTFreshComposerCleared -CommandType Function -ErrorAction Stop
    $Backend.InspectComposer=({
        param($Context,$Enrollment)
        & $freshComposerObservation -Context $Context
    }).GetNewClosure()
    $Backend.SendPrompt=({
        param($Context,$Enrollment,[string]$PromptText,$Assignment)
        $before=& $freshComposerObservation -Context $Context
        try{return & $primarySend $Context $Enrollment $PromptText $Assignment}catch{
            $message=$_.Exception.Message
            if($message -ne 'ChatGPT composer still contains the exact outbound payload after submit; committed-send proof is absent.'){throw}
        }
        $fresh=& $freshComposerCleared -Context $Context -PromptText $PromptText
        [pscustomobject][ordered]@{
            schema_version='0.1'
            assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}elseif($Assignment -and $Assignment.PSObject.Properties['assignment'] -and $Assignment.assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment.assignment_id}else{$null}
            assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['sha256']){[string]$Assignment.sha256}else{$null}
            conversation_fingerprint_sha256=if($Enrollment -and $Enrollment.PSObject.Properties['conversation_fingerprint_sha256']){[string]$Enrollment.conversation_fingerprint_sha256}else{$null}
            composer_state='COMMITTED'
            composer_result=if([string]::IsNullOrWhiteSpace([string]$before.composer_text)){'EMPTY'}elseif([string]::Equals([string]$before.composer_text,$PromptText,[StringComparison]::Ordinal)){'MATCHING_EXACT'}else{'MISMATCH'}
            mutation_occurred=(-not[string]::Equals([string]$before.composer_text,$PromptText,[StringComparison]::Ordinal))
            send_invocation_state='INVOKED'
            committed_message_proof_state='PROVEN'
            committed_message_proof_source='FRESH_EMPTY_COMPOSER'
            failure_reason=$null
            committed=$true
        }
    }).GetNewClosure()
    $Backend
}

function Add-AidosDesktopChatGPTConversationProofRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Backend)
    $primaryLocate=$Backend.LocateConversation
    $elementProof=Get-Command Get-AidosDesktopChatGPTElementConversationProof -CommandType Function -ErrorAction Stop
    $Backend.LocateConversation=({
        param($Context,[string]$ProofText,$Enrollment)
        try{return & $primaryLocate $Context $ProofText $Enrollment}catch{$primaryError=$_.Exception.Message}
        if(-not$Context -or [string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw $primaryError}
        if(-not ('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
        $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
        if(-not$root){throw $primaryError}
        $accountProof=''
        if($Enrollment -and $Enrollment.PSObject.Properties['account_proof_text']){$accountProof=[string]$Enrollment.account_proof_text}
        try{$observed=& $elementProof -RootElement $root -Context $Context -ProofText $ProofText -AccountProofText $accountProof}
        catch{throw "$primaryError Recovery proof failed: $($_.Exception.Message)"}
        if($Enrollment -and $Enrollment.PSObject.Properties['conversation_fingerprint_sha256'] -and -not[string]::IsNullOrWhiteSpace([string]$Enrollment.conversation_fingerprint_sha256) -and $Enrollment.PSObject.Properties['conversation_fingerprint'] -and $Enrollment.conversation_fingerprint){
            return [pscustomobject][ordered]@{
                conversation_fingerprint=$Enrollment.conversation_fingerprint
                conversation_fingerprint_sha256=[string]$Enrollment.conversation_fingerprint_sha256
                proof_surface_rebound=$true
                observed_conversation_fingerprint=$observed.conversation_fingerprint
                observed_conversation_fingerprint_sha256=$observed.conversation_fingerprint_sha256
                primary_proof_error=$primaryError
            }
        }
        $observed
    }).GetNewClosure()
    $Backend
}

function New-AidosDesktopChatGPTResilientWindowsBackend {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic')
    $backend=& $script:BaseDesktopChatGPTWindowsBackendCommand -ProcessName $ProcessName
    $primaryResolver=$backend.GetProcessContext
    $backend.GetProcessContext=({
        param([string]$RequestedProcessName)
        Get-AidosDesktopChatGPTResilientProcessContext -ProcessName $RequestedProcessName -PrimaryResolver $primaryResolver
    }).GetNewClosure()
    $backend=New-AidosDesktopChatGPTResilientConversationBackend -Backend $backend
    $backend=Add-AidosDesktopChatGPTFreshComposerProof -Backend $backend
    Add-AidosDesktopChatGPTConversationProofRecovery -Backend $backend
}

# Compatibility shim for existing Thinker callers. It deliberately delegates to
# the uniquely named wrapper; the base command above is bound to the exact base
# module instance and therefore cannot resolve back to this shim.
function New-AidosDesktopChatGPTWindowsBackend {
    [CmdletBinding()]
    param([string]$ProcessName='ChatGPT Classic')
    New-AidosDesktopChatGPTResilientWindowsBackend -ProcessName $ProcessName
}

Export-ModuleMember -Function Initialize-AidosDesktopChatGPTWindowDiscovery,Get-AidosWindowDiscoveryText,Get-AidosWindowDiscoveryClass,Get-AidosDesktopChatGPTFallbackProcessContexts,Get-AidosDesktopChatGPTResilientProcessContext,Get-AidosDesktopChatGPTFreshComposerObservation,Wait-AidosDesktopChatGPTFreshComposerCleared,Add-AidosDesktopChatGPTFreshComposerProof,Add-AidosDesktopChatGPTConversationProofRecovery,New-AidosDesktopChatGPTResilientWindowsBackend,New-AidosDesktopChatGPTWindowsBackend