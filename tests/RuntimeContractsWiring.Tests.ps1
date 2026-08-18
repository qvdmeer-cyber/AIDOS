[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$script:passed=0
function Assert-Wiring([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$dispatcher=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Raw -Encoding UTF8
$manager=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Raw -Encoding UTF8

Assert-Wiring ($dispatcher -match 'Invoke-AidosRuntimeProjectManagerTick\s+-RegistryRoot\s+\$RegistryRoot\s+-MaxProjects\s+\$MaxItems\s+-ContractsRoot\s+\$ContractsRoot') 'host dispatcher passes ContractsRoot into the default Runtime Project Manager'
Assert-Wiring ($manager -match 'Invoke-AidosRuntimeActorResultConsumerTick\s+-RegistryRoot\s+\$RegistryRoot\s+-AidosRoot\s+\$AidosRoot\s+-ContractsRoot\s+\$ContractsRoot') 'Runtime Project Manager passes ContractsRoot into the default actor-result consumer'
Assert-Wiring ($manager -match 'Invoke-AidosRuntimeHumanInputResumeTick\s+-RegistryRoot\s+\$RegistryRoot\s+-AidosRoot\s+\$AidosRoot') 'Runtime Project Manager invokes Definition Human Input resume before next actor scheduling'
Assert-Wiring ($manager.IndexOf('Invoke-AidosRuntimeHumanInputResumeTick',[StringComparison]::Ordinal) -lt $manager.IndexOf('$projects=@(Get-AidosRuntimeRegistryProjects',[StringComparison]::Ordinal)) 'Human Input resume wiring precedes actor selection'

Write-Output "PASS: $passed runtime Contracts wiring assertions"
