[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosPlatformRepairSupervisor.psm1') -Force -DisableNameChecking
$passed=0
function Assert-Repair([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
Assert-Repair ((Get-AidosPlatformRepairClassification -Component 'ChatGPT Thinker transport' -ErrorText 'composer sentinel failed') -eq 'PLATFORM_TRANSPORT') 'ChatGPT transport blockers classify as platform transport'
Assert-Repair ((Get-AidosPlatformRepairClassification -Component 'unknown' -ErrorText 'authority decision required') -eq 'HUMAN_REQUIRED') 'unknown authority blockers fail closed for human review'
Assert-Repair ((Test-AidosPlatformRepairPaths -Repository AIDOS -Paths @('bridge/x.psm1','tests/x.Tests.ps1'))) 'Core platform paths are allowlisted'
try { Test-AidosPlatformRepairPaths -Repository AIDOS -Paths @('.aidos/STATE.json') | Out-Null; throw 'expected forbidden path rejection' } catch { Assert-Repair ($_.Exception.Message -match 'forbidden|allowlist') 'project state is forbidden from platform repair' }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-platform-repair-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp -Force|Out-Null
try {
    $blocker=New-AidosPlatformRepairBlocker -StateRoot $temp -Component 'ChatGPT Thinker transport' -ErrorText 'ChatGPT composer sentinel proof failed' -Repository AIDOS -EvidenceRefs @('trigger:AIDOS-INTERFACE/H1')
    Assert-Repair ($blocker.classification -eq 'PLATFORM_TRANSPORT' -and $blocker.status -eq 'DETECTED') 'blocker is durable and classified without touching project state'
    $assignment=New-AidosPlatformRepairAssignment -StateRoot $temp -Blocker (Get-Content -Raw -LiteralPath $blocker.path|ConvertFrom-Json)
    Assert-Repair ($assignment.status -eq 'ASSIGNED' -and (Test-Path -LiteralPath $assignment.assignment_path)) 'platform blocker produces a bounded Codex repair assignment'
    $validated=Complete-AidosPlatformRepairValidation -StateRoot $temp -RepairId $blocker.repair_id -TestsPassed $true -Commit ('a'*40) -ChangedPaths @('bridge/AidosRepositoryThinkerBinding.psm1','tests/RepositoryThinkerBinding.Tests.ps1')
    Assert-Repair ($validated.status -eq 'VALIDATED') 'repair advances only with passing tests and allowlisted paths'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output "PASS: $passed platform repair supervisor assertions"
