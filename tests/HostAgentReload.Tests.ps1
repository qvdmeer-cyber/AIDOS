[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'tools/Reload-AidosAutonomousPreparation.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$ignorePath=Join-Path $root '.gitignore'
$ignore=Get-Content -LiteralPath $ignorePath -Raw -Encoding UTF8
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
Assert-Reload ($text.IndexOf('New-AidosRepositoryHandoffLauncherText|Set-Content',[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload refreshes the durable launcher before any restart'
Assert-Reload ($text.IndexOf('Canonical Repository Handoff stop returned while the scheduled task was still Running.',[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload trusts the canonical stop boundary and only verifies its postcondition'
Assert-Reload ($text.IndexOf('AddSeconds(15)',[StringComparison]::Ordinal) -lt 0) 'Repository Handoff reload no longer imposes a second shorter scheduler shutdown window'
Assert-Reload ($text.IndexOf("Start-ScheduledTask -TaskName `$repositoryHostTaskName",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload restarts the canonical scheduled task rather than invoking the blocking supervisor inline'
Assert-Reload ($text.IndexOf('[int]$TimeoutSeconds=60',[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload retains a bounded 60-second startup window'
Assert-Reload ($text.IndexOf('[int]$PreviousHostPid=0',[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("`$previousRepositoryHostPid",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload captures and binds the previous supervisor process identity'
Assert-Reload ($text.IndexOf("`$freshHostIdentity=",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("`$hostPid-ne`$PreviousHostPid",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload requires a different post-restart supervisor PID'
Assert-Reload ($text.IndexOf("Get-Process -Id `$hostPid",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("Get-Process -Id `$bridgePid",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("Get-Process -Id `$gatewayPid",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload resolves live supervisor, bridge and gateway processes'
Assert-Reload ($text.IndexOf("`$hostAlive=",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("`$bridgeAlive=",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("`$gatewayAlive=",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload validates all runtime PIDs as live PowerShell processes'
Assert-Reload ($text.IndexOf("`$bridgeError=",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("`$gatewayError=",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("child entered ERROR",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload fails immediately on explicit child ERROR state'
Assert-Reload ($text.IndexOf("`$hostRunning -and `$freshHostIdentity -and `$hostAlive -and `$bridgeAlive -and `$gatewayAlive",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload accepts a fresh live supervisor without waiting for the first complete bridge tick'
Assert-Reload ($text.IndexOf('$heartbeat=[DateTimeOffset]$status.heartbeat_at',[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload casts materialized heartbeat values directly to DateTimeOffset'
Assert-Reload ($text.IndexOf('Parse([string]$status.heartbeat_at',[StringComparison]::Ordinal) -lt 0) 'Repository Handoff reload never round-trips heartbeat values through culture-dependent string parsing'
$previousCulture=[Threading.Thread]::CurrentThread.CurrentCulture
try{
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('nl-NL')
    $materializedHeartbeat=[datetime]::new(2026,8,20,16,53,38,[DateTimeKind]::Local)
    $cultureIndependentHeartbeat=[DateTimeOffset]$materializedHeartbeat
    Assert-Reload ($cultureIndependentHeartbeat.Year-eq2026 -and $cultureIndependentHeartbeat.Month-eq8 -and $cultureIndependentHeartbeat.Day-eq20 -and $cultureIndependentHeartbeat.Hour-eq16) 'materialized DateTime heartbeat converts under nl-NL without culture-dependent reparsing'
}finally{
    [Threading.Thread]::CurrentThread.CurrentCulture=$previousCulture
}
Assert-Reload ($text.IndexOf("-PreviousHostPid `$previousRepositoryHostPid",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff restart passes the pre-stop supervisor PID into the health gate'
Assert-Reload ($text.IndexOf("fresh RUNNING supervisor with live bridge and gateway processes",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff timeout explains the process-identity health contract'
Assert-Reload ($text.IndexOf("Install-AidosHostSelfUpdate.ps1",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload still reapplies the self-update watchdog installer'
Assert-Reload ($text.IndexOf("status='RELOADED_REPOSITORY_HANDOFF'",[StringComparison]::Ordinal) -ge 0) 'Repository Handoff reload reports its selected transport authority explicitly'

$runtimeIgnorePatterns=@(
    'bridge/AidosRepositoryHandoff.runtime.*.psm1',
    'bridge/AidosRepositoryActorHandoff.runtime.*.psm1',
    'bridge/AidosRepositoryReviewHandoff.runtime.*.psm1',
    'bridge/AidosRepositoryHandoffGateway.runtime.*.psm1',
    'bridge/AidosRepositoryHandoffBridge.runtime.*.psm1',
    'bridge/Invoke-AidosRepositoryHandoffHost.runtime.*.ps1'
)
foreach($pattern in $runtimeIgnorePatterns){
    Assert-Reload (@($ignore -split "`r?`n"|Where-Object {$_ -ceq $pattern}).Count -eq 1) "live Repository Handoff runtime artifact is ignored exactly once: $pattern"
}

$repoBranch=[regex]::Match($text,'(?s)if\(\$repositoryTask -and \$repositoryConfigPresent\)\{.*?exit 0\s*\}').Value
Assert-Reload (-not[string]::IsNullOrWhiteSpace($repoBranch) -and $repoBranch.IndexOf('Enable-AidosAutonomousPreparation.ps1',[StringComparison]::Ordinal) -lt 0) 'Repository Handoff path never calls the legacy enable bootstrap'
Assert-Reload ($text.IndexOf("Compatibility path for hosts that have not migrated",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("Enable-AidosAutonomousPreparation.ps1",[StringComparison]::Ordinal) -ge 0) 'legacy-only hosts retain the historical autonomous-preparation reload fallback'

Write-Output "PASS: $passed host-agent reload assertions"
