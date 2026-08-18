[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'tools/Reload-AidosAutonomousPreparation.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$script:passed=0
function Assert-Reload([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

Assert-Reload ($text.IndexOf("[string]`$Lease.process_started_at -eq `$actual",[StringComparison]::Ordinal) -ge 0) 'reload requires exact process start-time identity match'
Assert-Reload ($text.IndexOf("ProcessName -notin @('pwsh','pwsh.exe')",[StringComparison]::Ordinal) -ge 0) 'reload refuses to terminate unexpected process types'
Assert-Reload ($text.IndexOf("owner_id -ne [string]`$lease.owner_id",[StringComparison]::Ordinal) -ge 0) 'reload refuses cleanup if lease ownership changed'
Assert-Reload ($text.IndexOf("Stop-Process -Id ([int]`$process.Id) -Force",[StringComparison]::Ordinal) -ge 0) 'reload force-stops only the exact leased agent PID after identity validation'
Assert-Reload ($text.IndexOf("Stop-ScheduledTask -TaskName `$taskName",[StringComparison]::Ordinal) -ge 0) 'reload stops scheduled task host before leased child process cleanup'

Write-Output "PASS: $passed host-agent reload assertions"
