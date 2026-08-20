from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)


bootstrap_path = Path("bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1")
bootstrap = bootstrap_path.read_text(encoding="utf-8")
bootstrap = replace_once(
    bootstrap,
    '"Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -Global -DisableNameChecking"',
    '"Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -Force -Global -DisableNameChecking"',
    "bootstrap runtime manager import",
)
bootstrap_path.write_text(bootstrap, encoding="utf-8")


test_path = Path("tests/RepositoryHandoffBootstrap.Tests.ps1")
test = test_path.read_text(encoding="utf-8")
test = replace_once(
    test,
    '"Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -Global -DisableNameChecking"',
    '"Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot \'AidosRuntimeProjectManager.psm1\') -Force -Global -DisableNameChecking"',
    "bootstrap test runtime manager transform",
)
test = replace_once(
    test,
    'Assert-Bootstrap ($bridgeRuntime.Contains("AidosRuntimeProjectManager.psm1\') -Global")) \'runtime manager command is exported into bridge-visible session scope\'',
    'Assert-Bootstrap ($bridgeRuntime.Contains("AidosRuntimeProjectManager.psm1\') -Force -Global")) \'runtime manager is force-refreshed and exported into bridge-visible session scope\'',
    "bootstrap test runtime manager assertion",
)
anchor = 'Write-Output "PASS: $passed repository handoff bootstrap assertions"'
if test.count(anchor) != 1:
    raise RuntimeError("bootstrap test final output anchor is missing or ambiguous")
regression = r'''
$refreshRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-runtime-manager-refresh-'+[guid]::NewGuid().ToString('N'))
$refreshModulePath=Join-Path $refreshRoot 'AidosRuntimeProjectManager.psm1'
try {
    New-Item -ItemType Directory -Path $refreshRoot -Force|Out-Null
    "function Get-AidosRuntimeManagerRefreshSentinel { 'OLD' }`nExport-ModuleMember -Function Get-AidosRuntimeManagerRefreshSentinel"|Set-Content -LiteralPath $refreshModulePath -Encoding utf8NoBOM
    Import-Module $refreshModulePath -Global -DisableNameChecking
    Assert-Bootstrap ((Get-AidosRuntimeManagerRefreshSentinel) -eq 'OLD') 'runtime manager refresh fixture starts with the preloaded implementation'
    "function Get-AidosRuntimeManagerRefreshSentinel { 'NEW' }`nExport-ModuleMember -Function Get-AidosRuntimeManagerRefreshSentinel"|Set-Content -LiteralPath $refreshModulePath -Encoding utf8NoBOM
    Import-Module $refreshModulePath -Force -Global -DisableNameChecking
    Assert-Bootstrap ((Get-AidosRuntimeManagerRefreshSentinel) -eq 'NEW') 'force-global import replaces a preloaded runtime manager implementation'
} finally {
    Remove-Module AidosRuntimeProjectManager -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $refreshRoot){Remove-Item -LiteralPath $refreshRoot -Recurse -Force}
}

'''
test = test.replace(anchor, regression + anchor)
test_path.write_text(test, encoding="utf-8")
