from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)

binding_path = Path('bridge/AidosRepositoryThinkerBinding.psm1')
binding = binding_path.read_text(encoding='utf-8')
anchor = 'function New-AidosRepositoryThinkerWindowsBackend {'
helper = r'''function Get-AidosRepositoryThinkerComposerElement {
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
    if(-not[bool]$composer.Current.HasKeyboardFocus -and -not[bool]$Context.window_is_foreground){throw 'ChatGPT composer focus proof is required before send.'}

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

'''
binding = replace_once(binding, anchor, helper + anchor, 'Repository Thinker backend anchor')
binding = replace_once(binding, '        SendPrompt=$desktop.SendPrompt', "        SendPrompt={param($Context,$Binding,$PromptText,$Assignment);Invoke-AidosRepositoryThinkerPromptSend -Context $Context -Binding $Binding -PromptText $PromptText -Assignment $Assignment}", 'Repository Thinker SendPrompt binding')
binding_path.write_text(binding, encoding='utf-8')

test_path = Path('tests/RepositoryThinkerBinding.Tests.ps1')
test = test_path.read_text(encoding='utf-8')
test_anchor = "function Assert-BindingThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{& $Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw \"ASSERTION FAILED: $Message; unexpected error: $($_.Exception.Message)\"}};if(-not$thrown){throw \"ASSERTION FAILED: $Message; no exception\"};$script:passed++}\n"
checks = test_anchor + '''\n$bindingSource=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRepositoryThinkerBinding.psm1') -Raw -Encoding UTF8
Assert-Binding ($bindingSource.Contains("[System.Windows.Forms.SendKeys]::SendWait('^a')") -and $bindingSource.Contains("[System.Windows.Forms.SendKeys]::SendWait('^v')")) 'Repository Thinker rehydrates the composer through real keyboard/clipboard input events'
Assert-Binding ($bindingSource.Contains("@('composer-submit-button')") -and $bindingSource.Contains("@('send-button','composer-send-button')")) 'Repository Thinker supports bounded current and alternate send automation identifiers'
Assert-Binding ($bindingSource.Contains("@('Send prompt','Send message','Send')")) 'Repository Thinker has a bounded accessible-name send fallback'
Assert-Binding ($bindingSource.Contains("SendWait('{ENTER}')")) 'Repository Thinker has a keyboard Enter fallback after exact composer proof'
Assert-Binding ($bindingSource.Contains('committed-send proof is absent')) 'Repository Thinker remains fail-closed unless the outbound payload leaves the composer'
Assert-Binding (-not$bindingSource.Contains('SendPrompt=$desktop.SendPrompt')) 'Repository Thinker no longer delegates trigger sending to the legacy Desktop sender'
'''
test = replace_once(test, test_anchor, checks, 'Repository Thinker test assertion anchor')
test_path.write_text(test, encoding='utf-8')
