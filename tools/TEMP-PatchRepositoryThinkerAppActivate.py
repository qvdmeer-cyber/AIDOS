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

anchor = "    $desktop=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName\n"
replacement = anchor + "    $desktopFocus=$desktop.FocusConversation\n"
binding = replace_once(binding, anchor, replacement, 'desktop focus capture')

old = "        FocusConversation=$desktop.FocusConversation"
new = r'''        FocusConversation=({
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
        }).GetNewClosure()'''
binding = replace_once(binding, old, new, 'Repository Thinker focus binding')
binding_path.write_text(binding, encoding='utf-8')

test_path = Path('tests/RepositoryThinkerBinding.Tests.ps1')
test = test_path.read_text(encoding='utf-8')
anchor = "Assert-Binding (-not$bindingSource.Contains('SendPrompt=$desktop.SendPrompt')) 'Repository Thinker no longer delegates trigger sending to the legacy Desktop sender'\n"
extra = anchor + "Assert-Binding ($bindingSource.Contains('New-Object -ComObject WScript.Shell') -and $bindingSource.Contains('AppActivate([int]$Context.process_id)')) 'Repository Thinker explicitly activates the bound ChatGPT process before legacy focus proof'\nAssert-Binding ($bindingSource.Contains('$desktopFocus=$desktop.FocusConversation') -and -not$bindingSource.Contains('FocusConversation=$desktop.FocusConversation')) 'Repository Thinker wraps the proven Desktop focus routine instead of delegating it directly'\n"
if 'Repository Thinker explicitly activates the bound ChatGPT process before legacy focus proof' not in test:
    if test.count(anchor) != 1:
        raise RuntimeError('Repository Thinker test anchor missing or ambiguous')
    test = test.replace(anchor, extra)
test_path.write_text(test, encoding='utf-8')
