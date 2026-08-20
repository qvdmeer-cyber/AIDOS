from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0 and new in text:
        return text
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)

bridge_path = Path('bridge/AidosRepositoryHandoffBridge.psm1')
bridge = bridge_path.read_text(encoding='utf-8')
old = '''    $reviewPublisher={
        param($Project)
        & $script:AidosRepositoryReviewHandoffModule { param($ReviewProject,$ReviewPush) Publish-AidosRepositoryReviewHandoff -Project $ReviewProject -Push:$ReviewPush } $Project ([bool]$Push)
    }.GetNewClosure()'''
new = '''    $reviewHandoffModules=@($script:AidosRepositoryReviewHandoffModule)
    if($reviewHandoffModules.Count-ne1){throw 'Repository review module binding must resolve to exactly one imported module.'}
    $reviewPublisherCommand=$reviewHandoffModules[0].ExportedCommands['Publish-AidosRepositoryReviewHandoff']
    if($null-eq$reviewPublisherCommand){throw 'Repository review publisher command is unavailable from the imported module.'}
    $reviewPublisher={
        param($Project)
        & $reviewPublisherCommand -Project $Project -Push:$Push
    }.GetNewClosure()'''
bridge = replace_once(bridge, old, new, 'review publisher closure')
bridge_path.write_text(bridge, encoding='utf-8')

test_path = Path('tests/RepositoryHandoffBridge.Tests.ps1')
test = test_path.read_text(encoding='utf-8')
old_scope_assert = "    Assert-Bridge ($bridgeSource.Contains('& $script:AidosRepositoryReviewHandoffModule {')) 'review publisher executes in the imported review module scope'\n"
new_scope_assert = "    Assert-Bridge (-not$bridgeSource.Contains('& $script:AidosRepositoryReviewHandoffModule {')) 'review publisher closure does not resolve the bridge script-scope module binding after GetNewClosure'\n"
test = replace_once(test, old_scope_assert, new_scope_assert, 'obsolete script-scope publisher assertion')
anchor = "    Assert-Bridge (-not$bridgeSource.Contains('AidosRepositoryReviewHandoff\\Publish-AidosRepositoryReviewHandoff')) 'bridge does not depend on the canonical review module qualifier'\n"
if anchor not in test:
    raise RuntimeError('bridge test publisher assertion anchor missing')
extra = anchor + "    Assert-Bridge ($bridgeSource.Contains(\"`$reviewHandoffModules=@(`$script:AidosRepositoryReviewHandoffModule)\")) 'review publisher normalizes the imported module binding before closure creation'\n    Assert-Bridge ($bridgeSource.Contains(\"`$reviewPublisherCommand=`$reviewHandoffModules[0].ExportedCommands['Publish-AidosRepositoryReviewHandoff']\")) 'review publisher captures exact exported CommandInfo'\n    Assert-Bridge ($bridgeSource.Contains('& $reviewPublisherCommand -Project $Project -Push:$Push')) 'review closure invokes captured CommandInfo directly'\n"
if "review publisher captures exact exported CommandInfo" not in test:
    test = test.replace(anchor, extra)

final_anchor = '    Write-Output "PASS: $passed repository handoff bridge assertions"\n'
if final_anchor not in test:
    raise RuntimeError('bridge test final anchor missing')
regression = r'''    $commandModule=New-Module -Name AidosReviewClosureFixture -ScriptBlock {
        function Invoke-AidosReviewClosureFixture { param([string]$Value) "MODULE::$Value" }
        Export-ModuleMember -Function Invoke-AidosReviewClosureFixture
    }
    try {
        $modules=@($commandModule)
        $command=$modules[0].ExportedCommands['Invoke-AidosReviewClosureFixture']
        $value='BOUND'
        $closure={ & $command -Value $value }.GetNewClosure()
        Assert-Bridge ((& $closure) -eq 'MODULE::BOUND') 'GetNewClosure preserves captured exported CommandInfo invocation'
    } finally {
        Remove-Module AidosReviewClosureFixture -Force -ErrorAction SilentlyContinue
    }

'''
if 'GetNewClosure preserves captured exported CommandInfo invocation' not in test:
    test = test.replace(final_anchor, regression + final_anchor)
test_path.write_text(test, encoding='utf-8')
