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
 'bridge/AidosPersistentLocalDesktopAgent.psm1'
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

# Repeated top-level reloads must leave the dispatcher callable and all preparation exports resolvable.
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPreparationRuntime.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
foreach($name in @('Invoke-AidosPreparationDispatcherTick','Invoke-AidosPreparationResume','Invoke-AidosPreparationRuntimeOnboarding','Get-AidosRegisteredProject','Submit-AidosHumanInputResponse')){
    if(-not(Get-Command $name -ErrorAction SilentlyContinue)){throw "ASSERTION FAILED: command unavailable after module graph reload: $name"}
    $passed++
}
Write-Output "PASS: $passed preparation/host module graph assertions"
