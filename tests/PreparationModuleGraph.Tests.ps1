[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$modules=@(
 'bridge/AidosProjectRegistry.psm1',
 'bridge/AidosHumanInput.psm1',
 'bridge/AidosPreparationRuntime.psm1',
 'bridge/AidosPreparationOnboarding.psm1',
 'bridge/AidosPreparationDispatcher.psm1',
 'bridge/AidosPersistentLocalDesktopAgent.psm1',
 'bridge/AidosRuntimeProjectManager.psm1',
 'bridge/AidosRuntimeActorAssignments.psm1',
 'bridge/AidosRuntimeActorTransport.psm1',
 'bridge/AidosRuntimeActorResultConsumer.psm1',
 'bridge/AidosDesktopThinkerTransport.psm1'
)
$passed=0
foreach($relative in $modules){
    $path=Join-Path $root $relative
    $text=Get-Content -LiteralPath $path -Raw
    if($text -match "Import-Module[^\r\n]+-Force"){
        throw "ASSERTION FAILED: internal runtime dependency import uses -Force in $relative"
    }
    $passed++
}

$expected=@{
 'AidosPreparationDispatcher'='Invoke-AidosPreparationDispatcherTick'
 'AidosPreparationRuntime'='Invoke-AidosPreparationResume'
 'AidosPreparationOnboarding'='Invoke-AidosPreparationRuntimeOnboarding'
 'AidosProjectRegistry'='Get-AidosRegisteredProject'
 'AidosHumanInput'='Submit-AidosHumanInputResponse'
 'AidosRuntimeProjectManager'='Invoke-AidosRuntimeProjectManagerTick'
 'AidosRuntimeActorAssignments'='New-AidosRuntimeActorAssignment'
 'AidosRuntimeActorTransport'='Save-AidosRuntimeActorResult'
 'AidosRuntimeActorResultConsumer'='Invoke-AidosRuntimeActorResultConsumerTick'
 'AidosDesktopThinkerTransport'='Invoke-AidosDesktopThinkerAssignment'
}
foreach($moduleName in $expected.Keys){
    $path=Join-Path $root ('bridge/'+$moduleName+'.psm1')
    $module=Import-Module $path -Force -DisableNameChecking -PassThru
    $command=Get-Command -Name $expected[$moduleName] -Module $module.Name -ErrorAction SilentlyContinue
    if(-not$command){throw "ASSERTION FAILED: $($expected[$moduleName]) is not exported by owning module $moduleName"}
    $passed++
}

# Repeated dispatcher reload itself must remain callable; nested dependencies need not leak globally.
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPreparationRuntime.psm1') -Force -DisableNameChecking
$dispatcher=Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking -PassThru
if(-not(Get-Command 'Invoke-AidosPreparationDispatcherTick' -Module $dispatcher.Name -ErrorAction SilentlyContinue)){throw 'ASSERTION FAILED: dispatcher unavailable after reload sequence'}
$passed++
Write-Output "PASS: $passed preparation/host/runtime module graph assertions"
