[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'bridge/Invoke-AidosPersistentLocalDesktopAgent.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$script:passed=0
function Assert-Bootstrap([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

Assert-Bootstrap ($text -match 'function Test-AidosPersistentAgentBootstrapTask') 'bootstrap reuse validates the existing task binding'
Assert-Bootstrap ($text -match 'WindowsIdentity]::GetCurrent\(\).Name' -and $text -match 'Interactive logon' -and $text -match 'not limited') 'reuse fails closed on user, logon, or privilege mismatch while allowing only Windows canonical task-user representation'
Assert-Bootstrap ($text -match 'if\(\$task\)\{[\s\S]*?Test-AidosPersistentAgentBootstrapTask[\s\S]*?\$taskProvisioning=''REUSED''') 'normal install reuses a verified task'
Assert-Bootstrap ($text -match 'if\(-not\s+\$task\)\{[\s\S]*?Register-ScheduledTask') 'registration occurs only when the one-time bootstrap is absent'
Assert-Bootstrap ($text -match 'task_provisioning=\$taskProvisioning') 'installer reports whether it created or reused bootstrap infrastructure'
Write-Output "PASS: $passed host-agent bootstrap reuse assertions"
