[CmdletBinding()]
param([string]$WslDistribution = 'Ubuntu')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'WindowsPath.Tests.ps1 must run under Windows PowerShell 7.' }

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosBridge.psm1') -Force
$passed = 0
function Assert-PathTest([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "ASSERTION FAILED: $Message" }; $script:passed++ }

$localOne = Join-Path ([IO.Path]::GetTempPath()) ('aidos-path-one-' + [guid]::NewGuid().ToString('N'))
$localTwo = Join-Path ([IO.Path]::GetTempPath()) ('aidos-path-two-' + [guid]::NewGuid().ToString('N'))
$leaf = 'aidos-unc-' + [guid]::NewGuid().ToString('N')
$wslPath = "/tmp/$leaf"
$uncPath = "\\wsl.localhost\$WslDistribution\tmp\$leaf"

New-Item -ItemType Directory -Path $localOne,$localTwo | Out-Null
& wsl.exe --distribution $WslDistribution --exec mkdir -p $wslPath
if ($LASTEXITCODE -ne 0) { throw "Unable to create WSL UNC regression fixture in '$WslDistribution'." }
& wsl.exe --distribution $WslDistribution --exec git -C $wslPath init -q
& wsl.exe --distribution $WslDistribution --exec git -C $wslPath remote add origin https://github.com/aidos-smoke/runtime-test.git

try {
    $resolvedLocal = Resolve-AidosFileSystemPath $localOne
    Assert-PathTest ($resolvedLocal -eq $localOne) 'normal Windows local path remains native'
    Assert-PathTest (Test-AidosSameFileSystemPath $localOne "Microsoft.PowerShell.Core\FileSystem::$localOne") 'provider-qualified Windows local path compares equal'
    Assert-PathTest (-not (Test-AidosSameFileSystemPath $localOne $localTwo)) 'genuinely different Windows roots compare unequal'

    $resolvedUnc = Resolve-AidosFileSystemPath $uncPath
    Assert-PathTest ($resolvedUnc.StartsWith("\\wsl.localhost\$WslDistribution\",[StringComparison]::OrdinalIgnoreCase)) 'wsl.localhost path remains a native UNC path'
    Assert-PathTest (Test-AidosSameFileSystemPath $uncPath "Microsoft.PowerShell.Core\FileSystem::$uncPath") 'provider-qualified WSL UNC path compares equal'
    Assert-PathTest (-not (Test-AidosSameFileSystemPath $uncPath $localOne)) 'WSL UNC and Windows local roots compare unequal'

    New-Item -ItemType Directory -Path (Join-Path $uncPath '.aidos') -Force | Out-Null
    $profilePath=Join-Path $uncPath '.aidos/PROJECT.json'
    $profile=[ordered]@{schema_version='0.1';project_id='WINDOWS-PATH-TEST';project_mode='NEW_PROJECT';repository='aidos-smoke/runtime-test';official_root=$uncPath;git_runtime=[ordered]@{kind='WINDOWS_WSL';distribution=$WslDistribution;project_root=$wslPath;git_path='git'}}
    $profile|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM
    $binding=Test-AidosProjectBinding $uncPath
    Assert-PathTest ($binding.Valid -and $binding.GitRuntime -eq 'WINDOWS_WSL' -and $binding.GitRoot -eq $wslPath) 'WSL-native project binding uses WSL Git and exact Linux root'
    $profile.git_runtime.project_root='/tmp';$profile|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM
    try { Test-AidosProjectBinding $uncPath|Out-Null;throw 'Expected wrong WSL worktree rejection.' } catch { Assert-PathTest ($_.Exception.Message -match 'Not a readable Git worktree|does not equal registered WSL project_root') 'wrong WSL worktree is rejected' }

    Write-Output "PASS: $passed Windows path assertions"
} finally {
    Remove-Item -LiteralPath $localOne,$localTwo -Recurse -Force -ErrorAction SilentlyContinue
    & wsl.exe --distribution $WslDistribution --exec rm -rf -- $wslPath
}
