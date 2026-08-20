from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)


bridge_path = Path("bridge/AidosRepositoryHandoffBridge.psm1")
bridge = bridge_path.read_text(encoding="utf-8")
bridge = replace_once(
    bridge,
    "Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -Global -DisableNameChecking",
    "$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -Global -PassThru -DisableNameChecking",
    "canonical review module import",
)
bridge = replace_once(
    bridge,
    "        AidosRepositoryReviewHandoff\\Publish-AidosRepositoryReviewHandoff -Project $Project -Push:$Push",
    "        & $script:AidosRepositoryReviewHandoffModule { param($ReviewProject,$ReviewPush) Publish-AidosRepositoryReviewHandoff -Project $ReviewProject -Push:$ReviewPush } $Project ([bool]$Push)",
    "review publisher module-qualified call",
)
bridge_path.write_text(bridge, encoding="utf-8")


bootstrap_path = Path("bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1")
bootstrap = bootstrap_path.read_text(encoding="utf-8")
bootstrap = replace_once(
    bootstrap,
    '    "Import-Module (Join-Path `$PSScriptRoot \'AidosRepositoryReviewHandoff.psm1\') -Global -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot \'$runtimeReviewHandoffName\') -Force -Global -DisableNameChecking"',
    '    "`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot \'AidosRepositoryReviewHandoff.psm1\') -Global -PassThru -DisableNameChecking" = "`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot \'$runtimeReviewHandoffName\') -Force -Global -PassThru -DisableNameChecking"',
    "bootstrap runtime review module import",
)
bootstrap_path.write_text(bootstrap, encoding="utf-8")


test_path = Path("tests/RepositoryHandoffBootstrap.Tests.ps1")
test = test_path.read_text(encoding="utf-8")
test = replace_once(
    test,
    "$runtimeHandoffName='AidosRepositoryHandoff.runtime.test.psm1'\n$bridgeRuntime=$bridgeText",
    "$runtimeHandoffName='AidosRepositoryHandoff.runtime.test.psm1'\n$runtimeReviewHandoffName='AidosRepositoryReviewHandoff.runtime.test.psm1'\n$bridgeRuntime=$bridgeText",
    "bootstrap test runtime review name",
)
test = replace_once(
    test,
    '    "Import-Module (Join-Path `$PSScriptRoot \'AidosRepositoryHandoff.psm1\') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot \'$runtimeHandoffName\') -Force -DisableNameChecking"\n}',
    '    "Import-Module (Join-Path `$PSScriptRoot \'AidosRepositoryHandoff.psm1\') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot \'$runtimeHandoffName\') -Force -DisableNameChecking"\n    "`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot \'AidosRepositoryReviewHandoff.psm1\') -Global -PassThru -DisableNameChecking" = "`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot \'$runtimeReviewHandoffName\') -Force -Global -PassThru -DisableNameChecking"\n}',
    "bootstrap test review transform",
)
test = replace_once(
    test,
    "Assert-Bootstrap ($bridgeRuntime.Contains($runtimeHandoffName)) 'runtime bridge imports the WSL-compatible handoff module'",
    "Assert-Bootstrap ($bridgeRuntime.Contains($runtimeHandoffName)) 'runtime bridge imports the WSL-compatible handoff module'\nAssert-Bootstrap ($bridgeRuntime.Contains(\"`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot '$runtimeReviewHandoffName') -Force -Global -PassThru\")) 'runtime bridge stores the exact temporary review module object'\nAssert-Bootstrap ($bridgeRuntime.Contains('& $script:AidosRepositoryReviewHandoffModule {')) 'runtime bridge invokes review publication through the imported module object'\nAssert-Bootstrap (-not$bridgeRuntime.Contains('AidosRepositoryReviewHandoff\\Publish-AidosRepositoryReviewHandoff')) 'runtime bridge no longer uses the stale canonical review module qualifier'",
    "bootstrap test review assertions",
)
test_path.write_text(test, encoding="utf-8")


bridge_test_path = Path("tests/RepositoryHandoffBridge.Tests.ps1")
bridge_test = bridge_test_path.read_text(encoding="utf-8")
anchor = "    $runtimeManagerSource=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Raw -Encoding UTF8\n"
if bridge_test.count(anchor) != 1:
    raise RuntimeError("bridge test source anchor missing or ambiguous")
checks = anchor + "    $bridgeSource=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1') -Raw -Encoding UTF8\n    Assert-Bridge ($bridgeSource.Contains('$script:AidosRepositoryReviewHandoffModule=Import-Module')) 'bridge stores the imported review module object'\n    Assert-Bridge ($bridgeSource.Contains('& $script:AidosRepositoryReviewHandoffModule {')) 'review publisher executes in the imported review module scope'\n    Assert-Bridge (-not$bridgeSource.Contains('AidosRepositoryReviewHandoff\\Publish-AidosRepositoryReviewHandoff')) 'bridge does not depend on the canonical review module qualifier'\n"
bridge_test = bridge_test.replace(anchor, checks)
bridge_test_path.write_text(bridge_test, encoding="utf-8")
