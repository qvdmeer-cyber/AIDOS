from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)

# 1. Repository Thinker: fresh composer lookup + line-ending-stable payload proof.
binding_path = Path('bridge/AidosRepositoryThinkerBinding.psm1')
binding = binding_path.read_text(encoding='utf-8')

anchor = 'function Find-AidosRepositoryThinkerSubmitElement {'
helper = r'''function ConvertTo-AidosRepositoryThinkerComposerComparableText {
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

'''
if 'function ConvertTo-AidosRepositoryThinkerComposerComparableText {' not in binding:
    binding = replace_once(binding, anchor, helper + anchor, 'composer comparable helper anchor')

old_hydration = r'''    $composerExact=$false
    for($attempt=0;$attempt-lt30;$attempt++){
        Start-Sleep -Milliseconds 100
        $current=[string](Get-AidosDesktopChatGPTElementText $composer)
        if([string]::Equals($current,$PromptText,[StringComparison]::Ordinal)){$composerExact=$true;break}
    }
    if(-not$composerExact){throw 'ChatGPT composer did not contain the exact outbound payload after keyboard hydration.'}'''
new_hydration = r'''    $composerExact=$false
    $current=$null
    for($attempt=0;$attempt-lt30;$attempt++){
        Start-Sleep -Milliseconds 100
        $currentComposer=Get-AidosRepositoryThinkerComposerElement -RootElement $root
        $current=[string](Get-AidosDesktopChatGPTElementText $currentComposer)
        if(Test-AidosRepositoryThinkerComposerTextMatch -Expected $PromptText -Observed $current){$composer=$currentComposer;$composerExact=$true;break}
    }
    if(-not$composerExact){
        $expectedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $PromptText
        $observedComparable=ConvertTo-AidosRepositoryThinkerComposerComparableText -Text $current
        throw "ChatGPT composer did not contain the outbound payload after fresh keyboard hydration proof (expected_length=$($expectedComparable.Length); observed_length=$(if($null-eq$observedComparable){0}else{$observedComparable.Length}))."
    }'''
binding = replace_once(binding, old_hydration, new_hydration, 'fresh composer hydration proof')
binding_path.write_text(binding, encoding='utf-8')

# 2. Self-update installer: explicit preserve mode, never infer self-mutation safety from task State alone.
installer_path = Path('tools/Install-AidosHostSelfUpdate.ps1')
installer = installer_path.read_text(encoding='utf-8')
installer = replace_once(
    installer,
    "    [string]$AuthorizedUser='AIDOS\\qvdm',\n    [int]$IntervalMinutes=5\n)",
    "    [string]$AuthorizedUser='AIDOS\\qvdm',\n    [int]$IntervalMinutes=5,\n    [switch]$PreserveExistingTask\n)",
    'self-update installer preserve parameter'
)
old_existing = r'''if($existing){
    $existingUser=[string]$existing.Principal.UserId
    $leaf=($AuthorizedUser-split'\\')[-1]
    if(-not([string]::Equals($existingUser,$AuthorizedUser,[StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($existingUser,$leaf,[StringComparison]::OrdinalIgnoreCase))){throw 'Existing self-update task belongs to a different user.'}
    if([string]$existing.State -eq 'Running'){
        # A self-update reload re-enters normal bootstrap while this exact limited-user
        # watchdog task is still running. Re-registering the currently executing task
        # requires Task Scheduler mutation rights the watchdog intentionally does not
        # have. Its action path is stable, so preserve the task and let its existing
        # repetition schedule invoke the updated script on the next run.
        $provisioning='REUSED_RUNNING'
        $startTask=$false
    }else{
        Set-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal|Out-Null
        $provisioning='UPDATED'
    }
}else{
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'AIDOS fail-closed Core update validator and lease-safe host reload watchdog.'|Out-Null
    $provisioning='CREATED'
}'''
new_existing = r'''if($existing){
    $existingUser=[string]$existing.Principal.UserId
    $leaf=($AuthorizedUser-split'\\')[-1]
    if(-not([string]::Equals($existingUser,$AuthorizedUser,[StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($existingUser,$leaf,[StringComparison]::OrdinalIgnoreCase))){throw 'Existing self-update task belongs to a different user.'}
    if($PreserveExistingTask){
        # A Core self-update reload must never attempt to mutate its own Task Scheduler
        # registration. Task State is not a reliable proof that the launcher child is
        # no longer executing, and the limited-user watchdog intentionally lacks task
        # mutation authority. The action path is stable; refreshing the launcher file
        # above is sufficient for the next scheduled invocation.
        $provisioning='PRESERVED_EXISTING'
        $startTask=$false
    }elseif([string]$existing.State -eq 'Running'){
        $provisioning='REUSED_RUNNING'
        $startTask=$false
    }else{
        Set-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal|Out-Null
        $provisioning='UPDATED'
    }
}elseif($PreserveExistingTask){
    throw 'Self-update reload requested preservation but the watchdog task is not installed.'
}else{
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'AIDOS fail-closed Core update validator and lease-safe host reload watchdog.'|Out-Null
    $provisioning='CREATED'
}'''
installer = replace_once(installer, old_existing, new_existing, 'self-update installer preserve behavior')
installer_path.write_text(installer, encoding='utf-8')

# 3. Reload surface: propagate explicit preservation only when invoked by Core self-update.
reload_path = Path('tools/Reload-AidosAutonomousPreparation.ps1')
reload = reload_path.read_text(encoding='utf-8')
reload = replace_once(
    reload,
    "    [string]$RuntimeProjectRoot,\n    [string]$AuthorizedUser='AIDOS\\qvdm'\n)",
    "    [string]$RuntimeProjectRoot,\n    [string]$AuthorizedUser='AIDOS\\qvdm',\n    [switch]$PreserveSelfUpdateTask\n)",
    'reload preserve parameter'
)
reload = replace_once(
    reload,
    '$selfUpdate=& $selfUpdateInstaller -Distribution $Distribution -WslReposRoot $WslReposRoot -StateRoot $StateRoot -AuthorizedUser $AuthorizedUser',
    '$selfUpdate=& $selfUpdateInstaller -Distribution $Distribution -WslReposRoot $WslReposRoot -StateRoot $StateRoot -AuthorizedUser $AuthorizedUser -PreserveExistingTask:$PreserveSelfUpdateTask',
    'reload installer preservation propagation'
)
reload_path.write_text(reload, encoding='utf-8')

# 4. Watchdog: every reload it initiates explicitly preserves its own scheduled task.
watchdog_path = Path('tools/Invoke-AidosHostSelfUpdate.ps1')
watchdog = watchdog_path.read_text(encoding='utf-8')
old_call = '& $reloadScript -StateRoot $StateRoot -Distribution $Distribution -WslReposRoot $WslReposRoot -AuthorizedUser $AuthorizedUser|Out-Null'
new_call = '& $reloadScript -StateRoot $StateRoot -Distribution $Distribution -WslReposRoot $WslReposRoot -AuthorizedUser $AuthorizedUser -PreserveSelfUpdateTask|Out-Null'
count = watchdog.count(old_call)
if count == 0 and watchdog.count(new_call) == 2:
    pass
elif count == 2:
    watchdog = watchdog.replace(old_call, new_call)
else:
    raise RuntimeError(f'watchdog reload propagation: expected two old calls, found {count}')
watchdog_path.write_text(watchdog, encoding='utf-8')

# 5. Regression contracts.
self_test_path = Path('tests/HostSelfUpdateContract.Tests.ps1')
self_test = self_test_path.read_text(encoding='utf-8')
if "$reload=Get-Content -LiteralPath (Join-Path $root 'tools/Reload-AidosAutonomousPreparation.ps1')" not in self_test:
    self_test = replace_once(
        self_test,
        "$installer=Get-Content -LiteralPath (Join-Path $root 'tools/Install-AidosHostSelfUpdate.ps1') -Raw -Encoding UTF8\n",
        "$installer=Get-Content -LiteralPath (Join-Path $root 'tools/Install-AidosHostSelfUpdate.ps1') -Raw -Encoding UTF8\n$reload=Get-Content -LiteralPath (Join-Path $root 'tools/Reload-AidosAutonomousPreparation.ps1') -Raw -Encoding UTF8\n",
        'self-update contract reload source'
    )
contract_anchor = "Assert-SelfUpdate ($watchdog -match 'Reload-AidosAutonomousPreparation\\.ps1') 'validated update reuses the lease-safe Core reload lifecycle'\n"
contract_extra = contract_anchor + "Assert-SelfUpdate ($watchdog -match '-PreserveSelfUpdateTask') 'watchdog explicitly preserves its own scheduled task during reload'\nAssert-SelfUpdate ($reload -match 'PreserveSelfUpdateTask' -and $reload -match '-PreserveExistingTask:\\$PreserveSelfUpdateTask') 'reload propagates explicit self-update task preservation'\nAssert-SelfUpdate ($installer -match 'PreserveExistingTask' -and $installer -match \"provisioning='PRESERVED_EXISTING'\") 'installer supports fail-closed preservation without Task Scheduler mutation'\n"
if 'watchdog explicitly preserves its own scheduled task during reload' not in self_test:
    self_test = replace_once(self_test, contract_anchor, contract_extra, 'self-update preservation assertions')
self_test_path.write_text(self_test, encoding='utf-8')

binding_test_path = Path('tests/RepositoryThinkerBinding.Tests.ps1')
binding_test = binding_test_path.read_text(encoding='utf-8')
binding_anchor = "Assert-Binding ($bindingSource.Contains('committed-send proof is absent')) 'Repository Thinker remains fail-closed unless the outbound payload leaves the composer'\n"
binding_extra = binding_anchor + "Assert-Binding ($bindingSource.Contains('function ConvertTo-AidosRepositoryThinkerComposerComparableText') -and $bindingSource.Contains('.Replace(\"`r`n\",\"`n\").Replace(\"`r\",\"`n\")')) 'Repository Thinker normalizes only transport line endings for composer hydration proof'\nAssert-Binding ($bindingSource.Contains('$currentComposer=Get-AidosRepositoryThinkerComposerElement -RootElement $root') -and $bindingSource.Contains('Test-AidosRepositoryThinkerComposerTextMatch -Expected $PromptText -Observed $current')) 'Repository Thinker rebinds the live composer before proving hydrated payload text'\n"
if 'normalizes only transport line endings for composer hydration proof' not in binding_test:
    binding_test = replace_once(binding_test, binding_anchor, binding_extra, 'Repository Thinker hydration assertions')
binding_test_path.write_text(binding_test, encoding='utf-8')
