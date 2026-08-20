[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$script:passed=0
function Assert-SelfUpdate([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$watchdog=Get-Content -LiteralPath (Join-Path $root 'tools/Invoke-AidosHostSelfUpdate.ps1') -Raw -Encoding UTF8
$installer=Get-Content -LiteralPath (Join-Path $root 'tools/Install-AidosHostSelfUpdate.ps1') -Raw -Encoding UTF8
$enable=Get-Content -LiteralPath (Join-Path $root 'tools/Enable-AidosAutonomousPreparation.ps1') -Raw -Encoding UTF8
$portable=Get-Content -LiteralPath (Join-Path $root 'tools/Test-AidosCorePortable.ps1') -Raw -Encoding UTF8

Assert-SelfUpdate ($watchdog -match "status','--porcelain=v1") 'watchdog refuses to update a dirty Core worktree'
Assert-SelfUpdate ($watchdog -match "merge-base','--is-ancestor") 'watchdog proves fast-forward ancestry before update'
Assert-SelfUpdate ($watchdog -match "worktree','add','--detach") 'remote candidate is validated in a detached temporary worktree'
Assert-SelfUpdate ($watchdog -match 'Test-AidosCorePortable\.ps1') 'watchdog runs aggregate Core validation against candidate commit'
Assert-SelfUpdate ($watchdog -match 'Convert-WslPathToUnc') 'candidate validation resolves the detached WSL worktree through its Windows UNC path'
Assert-SelfUpdate ($watchdog -match 'AIDOS-core-validation') 'candidate validation copies the bound WSL candidate into an ephemeral local validation mirror'
Assert-SelfUpdate ($watchdog.Contains("Join-Path `$PSHOME 'pwsh.exe'")) 'candidate validation reuses the installed Windows PowerShell 7 engine'
Assert-SelfUpdate ($watchdog -match '-ExecutionPolicy Bypass -File \$validator -RepoRoot \$validationRoot') 'candidate validation runs the localized mirror in an isolated host pwsh child with bounded execution-policy bypass'
Assert-SelfUpdate ($watchdog -notmatch 'command -v pwsh') 'self-update no longer requires an independent PowerShell installation inside WSL'
Assert-SelfUpdate ($watchdog -match "merge','--ff-only") 'watchdog applies only fast-forward Core updates'
Assert-SelfUpdate ($watchdog -match 'SELF_UPDATE_RELOAD_REQUIRED\.json') 'watchdog persists reload-required recovery across process failure'
Assert-SelfUpdate ($watchdog -match 'Reload-AidosAutonomousPreparation\.ps1') 'validated update reuses the lease-safe Core reload lifecycle'
Assert-SelfUpdate ($installer -match "RunLevel Limited") 'self-update task runs with limited user authority'
Assert-SelfUpdate ($installer -match 'MultipleInstances IgnoreNew') 'self-update task refuses concurrent watchdog instances'
Assert-SelfUpdate ($installer -match "existing\.State -eq 'Running'") 'a running watchdog task is detected before any task mutation'
Assert-SelfUpdate ($installer -match "provisioning='REUSED_RUNNING'") 'reload reuses an already running watchdog task instead of modifying itself'
Assert-SelfUpdate ($installer -match 'if\(\$startTask\)\{Start-ScheduledTask') 'reused running watchdog is not recursively restarted'
Assert-SelfUpdate ($enable -match 'Install-AidosHostSelfUpdate\.ps1') 'normal autonomous enable installs/updates the watchdog'
Assert-SelfUpdate ($portable -match "Get-ChildItem.*tests") 'candidate validator discovers the full regression-test directory'
Assert-SelfUpdate ($portable -match 'Parser\]::ParseFile') 'candidate validator performs PowerShell syntax validation'

Write-Output "PASS: $passed host self-update contract assertions"
