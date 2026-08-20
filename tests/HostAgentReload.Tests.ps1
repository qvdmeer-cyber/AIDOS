[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'tools/Reload-AidosAutonomousPreparation.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$script:passed=0
function Assert-Reload([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

Assert-Reload ($text.IndexOf("([DateTimeOffset]`$Lease.process_started_at).UtcDateTime.Ticks",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("`$Process.StartTime.ToUniversalTime().Ticks",[StringComparison]::Ordinal) -ge 0) 'reload requires exact process start-time identity match without culture-dependent timestamp text'
Assert-Reload ($text.IndexOf("ProcessName -notin @('pwsh','pwsh.exe')",[StringComparison]::Ordinal) -ge 0) 'reload refuses to terminate unexpected process types'
Assert-Reload ($text.IndexOf("owner_id -ne [string]`$lease.owner_id",[StringComparison]::Ordinal) -ge 0) 'reload refuses cleanup if lease ownership changed'
Assert-Reload ($text.IndexOf("Stop-Process -Id ([int]`$process.Id) -Force",[StringComparison]::Ordinal) -ge 0) 'reload force-stops only the exact leased legacy agent PID after identity validation'

Assert-Reload ($text.IndexOf("AIDOS Repository Handoff Host",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("AIDOS Persistent Local Desktop Agent",[StringComparison]::Ordinal) -ge 0) 'reload names both replacement and legacy transport tasks explicitly'
Assert-Reload ($text.IndexOf("repository-handoff-host",[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $text.IndexOf("CONFIG.json",[StringComparison]::Ordinal) -ge 0) 'reload requires durable Repository Handoff installation state before switching authorities'
Assert-Reload ($text.IndexOf("-xor `$repositoryConfigPresent",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("partially installed",[StringComparison]::OrdinalIgnoreCase) -ge 0) 'partial Repository Handoff installation fails closed instead of reviving legacy transport'
Assert-Reload ($text.IndexOf("Disable-AidosLegacyDesktopTransportTask",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("Disable-ScheduledTask -TaskName `$TaskName",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload disables the legacy scheduled task'
Assert-Reload ($text.IndexOf("Invoke-AidosRepositoryHandoffHostBootstrap.ps1",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("-Command Stop -StateRoot `$repositoryHostStateRoot",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload stops the running host through its canonical bootstrap'
Assert-Reload ($text.IndexOf("Start-ScheduledTask -TaskName `$repositoryHostTaskName",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload restarts the canonical scheduled task rather than invoking the blocking supervisor inline'
Assert-Reload ($text.IndexOf('[int]$TimeoutSeconds=60',[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload allows a bounded 60-second startup window'
Assert-Reload ($text.IndexOf("`$bridgeRunning=",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("`$gatewayRunning=",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload verifies bridge and gateway health as well as the host supervisor'
Assert-Reload ($text.IndexOf("`$hostRunning -and `$bridgeRunning -and `$gatewayRunning",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("fresh healthy RUNNING heartbeat",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload requires a fresh healthy post-update host heartbeat before success'
Assert-Reload ($text.IndexOf("Install-AidosHostSelfUpdate.ps1",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload still reapplies the self-update watchdog installer'
Assert-Reload ($text.IndexOf("status='RELOADED_REPOSITORY_HANDOFF'",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload reports its selected transport authority explicitly'

$repoBranch=[regex]::Match($text,'(?s)if\(\$repositoryTask -and \$repositoryConfigPresent\)\{.*?exit 0\s*\}').Value
Assert-Reload (-not[string]::IsNullOrWhiteSpace($repoBranch) -and $repoBranch.IndexOf('Enable-AidosAutonomousPreparation.ps1',[StringComparison]::Ordinal) -lt 0) 'Repository Handoff path never calls the legacy enable bootstrap'
Assert-Reload ($text.IndexOf("Compatibility path for hosts that have not migrated",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("Enable-AidosAutonomousPreparation.ps1",[StringComparison]::Ordinal) -ge 0) 'legacy-only hosts retain the historical autonomous-preparation reload fallback'

Write-Output "PASS: $passed host-agent reload assertions"
