from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)

binding_path = Path('bridge/AidosRepositoryThinkerBinding.psm1')
binding = binding_path.read_text(encoding='utf-8')

anchor = '''function Find-AidosRepositoryThinkerSubmitElement {'''
helper = r'''function Test-AidosRepositoryThinkerComposerFocusProof {
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

'''
if 'function Test-AidosRepositoryThinkerComposerFocusProof {' not in binding:
    binding = replace_once(binding, anchor, helper + anchor, 'focus proof helper anchor')

old_focus = "    $composer.SetFocus()\n    Start-Sleep -Milliseconds 100\n    if(-not[bool]$composer.Current.HasKeyboardFocus){throw 'ChatGPT composer keyboard focus proof is required before send.'}"
new_focus = r'''    $composer.SetFocus()
    $focusProven=$false
    for($attempt=0;$attempt-lt10;$attempt++){
        Start-Sleep -Milliseconds 100
        if(Test-AidosRepositoryThinkerComposerFocusProof -Composer $composer){$focusProven=$true;break}
        try{$composer.SetFocus()}catch{}
    }
    if(-not$focusProven){throw 'ChatGPT composer keyboard focus proof is required before send.'}'''
binding = replace_once(binding, old_focus, new_focus, 'initial composer focus proof')

old_enter = "        $composer.SetFocus()\n        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')"
new_enter = r'''        $composer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
        $composer.SetFocus()
        Start-Sleep -Milliseconds 100
        if(-not(Test-AidosRepositoryThinkerComposerFocusProof -Composer $composer)){throw 'ChatGPT composer keyboard focus proof is required before Enter fallback.'}
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')'''
binding = replace_once(binding, old_enter, new_enter, 'Enter fallback focus proof')
binding_path.write_text(binding, encoding='utf-8')

test_path = Path('tests/RepositoryThinkerBinding.Tests.ps1')
test = test_path.read_text(encoding='utf-8')
old_assert = '''Assert-Binding ($bindingSource.Contains("if(-not[bool]`$composer.Current.HasKeyboardFocus){throw 'ChatGPT composer keyboard focus proof is required before send.'}")) 'Repository Thinker requires explicit composer keyboard focus before clipboard or Enter input'\n'''
new_assert = '''Assert-Binding ($bindingSource.Contains('function Test-AidosRepositoryThinkerComposerFocusProof') -and $bindingSource.Contains('[System.Windows.Automation.AutomationElement]::FocusedElement')) 'Repository Thinker inspects the actual focused UIA element for composer focus proof'\nAssert-Binding ($bindingSource.Contains('[System.Windows.Automation.TreeWalker]::RawViewWalker') -and $bindingSource.Contains("AutomationId -eq 'prompt-textarea'")) 'Repository Thinker accepts only focus within the unique prompt-textarea ancestry'\nAssert-Binding ($bindingSource.Contains('Test-AidosRepositoryThinkerComposerFocusProof -Composer $composer') -and $bindingSource.Contains("throw 'ChatGPT composer keyboard focus proof is required before send.'")) 'Repository Thinker requires focused composer ancestry before clipboard input'\nAssert-Binding ($bindingSource.Contains("throw 'ChatGPT composer keyboard focus proof is required before Enter fallback.'")) 'Repository Thinker re-proves focused composer ancestry before Enter fallback'\n'''
test = replace_once(test, old_assert, new_assert, 'focus regression assertion')
test_path.write_text(test, encoding='utf-8')
