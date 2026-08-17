[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -DisableNameChecking
$script:passed=0
function Assert-Recovery([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-dirty-onboarding-'+[guid]::NewGuid().ToString('N'))
try {
    $projectRoot=Join-Path $base 'project'
    $registryRoot=Join-Path $base 'registry'
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/seed.txt') -Value 'seed' -Encoding utf8NoBOM
    & git -C $projectRoot add .aidos/seed.txt
    & git -C $projectRoot commit -q -m seed

    Register-AidosPreparationProject -RegistryRoot $registryRoot -ProjectId 'DIRTY-RECOVERY' -Repository 'https://example.invalid/dirty.git' -LocalRoot $projectRoot -ProjectMode NEW_PROJECT -RunnerPolicy UNATTENDED_ALLOWED -GitRuntimeKind NATIVE -AllowedPersistencePaths @('.aidos')|Out-Null
    Set-AidosPreparationProjectPhase -RegistryRoot $registryRoot -ProjectId 'DIRTY-RECOVERY' -Phase RUNTIME_ONBOARDING -Status READY_FOR_ONBOARDING|Out-Null

    Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/partial-runtime.txt') -Value 'partial' -Encoding utf8NoBOM
    $global:AidosDirtyRecoveryOnboardingCalled=$false
    $tick=Invoke-AidosPreparationDispatcherTick -RegistryRoot $registryRoot -SyncProcessor {throw 'Preparation project synchronization requires a clean worktree.'} -OnboardingProcessor {
        param($project)
        $global:AidosDirtyRecoveryOnboardingCalled=$true
        [pscustomobject]@{status='PROMOTED';project_id=[string]$project.project_id}
    }
    Assert-Recovery $global:AidosDirtyRecoveryOnboardingCalled 'authorized .aidos dirt resumes onboarding instead of self-blocking on clean sync'
    Assert-Recovery ($tick.status -eq 'PROCESSED' -and $tick.results[0].status -eq 'PROMOTED') 'authorized dirty recovery reaches onboarding result'
    Assert-Recovery ($tick.results[0].sync.status -eq 'DIRTY_RECOVERY_ALLOWED') 'dirty recovery is explicit in dispatcher evidence'

    Remove-Item -LiteralPath (Join-Path $projectRoot '.aidos/partial-runtime.txt') -Force
    Set-Content -LiteralPath (Join-Path $projectRoot 'outside.txt') -Value 'unauthorized' -Encoding utf8NoBOM
    $global:AidosDirtyRecoveryOnboardingCalled=$false
    $blocked=Invoke-AidosPreparationDispatcherTick -RegistryRoot $registryRoot -SyncProcessor {throw 'Preparation project synchronization requires a clean worktree.'} -OnboardingProcessor {
        $global:AidosDirtyRecoveryOnboardingCalled=$true
        [pscustomobject]@{status='PROMOTED'}
    }
    Assert-Recovery (-not $global:AidosDirtyRecoveryOnboardingCalled) 'dirty path outside allowed persistence scope never enters onboarding'
    Assert-Recovery ($blocked.status -eq 'ERROR' -and $blocked.results[0].status -eq 'SYNC_ERROR') 'unauthorized dirt remains fail-closed'
    Assert-Recovery ([string]$blocked.results[0].error -like '*unauthorized changed path*outside.txt*') 'negative recovery evidence identifies unauthorized path'
} finally {
    Remove-Variable -Name AidosDirtyRecoveryOnboardingCalled -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed dirty onboarding recovery assertions"
