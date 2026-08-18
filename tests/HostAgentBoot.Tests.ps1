[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'bridge/AidosPersistentLocalDesktopAgent.psm1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$script:passed=0
function Assert-Boot([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

Assert-Boot ($text.IndexOf('Invoke-AidosStartupReconciliation -ProjectRoot',[StringComparison]::Ordinal) -lt 0) 'legacy startup reconciliation is not synchronous in host-agent boot path'
Assert-Boot ($text.IndexOf("startup_reconciliation='DEFERRED_TO_TICK'",[StringComparison]::Ordinal) -ge 0) 'host agent records startup reconciliation as deferred to normal tick'
$started=$text.IndexOf("Add-AidosHostAgentEvent $StateRoot 'AGENT_STARTED'",[StringComparison]::Ordinal)
$tickLoop=$text.IndexOf('do {',[StringComparison]::Ordinal,$started)
Assert-Boot ($started -ge 0 -and $tickLoop -gt $started) 'agent enters normal tick loop immediately after bounded boot bookkeeping'

Write-Output "PASS: $passed host-agent boot assertions"
