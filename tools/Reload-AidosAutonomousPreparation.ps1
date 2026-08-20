[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$Distribution='Ubuntu',
    [string]$WslReposRoot='/home/aidos/repos',
    [string]$PreparationProjectId='AIDOS-INTERFACE',
    [string]$PreparationRepository='https://github.com/qvdmeer-cyber/AIDOS-interface.git',
    [string]$PreparationProjectName='AIDOS-interface',
    [string]$RuntimeProjectRoot,
    [string]$AuthorizedUser='AIDOS\qvdm'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'This reload must run with PowerShell 7 on the Windows AIDOS host.'}
if([string]::IsNullOrWhiteSpace($StateRoot)){$StateRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'}

function Test-AidosLeaseProcessIdentity {
    param([Parameter(Mandatory)]$Lease,[Parameter(Mandatory)]$Process)
    if([int]$Lease.pid -ne [int]$Process.Id){return $false}
    # ConvertFrom-Json materializes ISO timestamps as DateTime.  Stringifying that
    # value is culture-dependent, so compare the stable UTC tick identity instead.
    $expected=([DateTimeOffset]$Lease.process_started_at).UtcDateTime.Ticks
    $actual=$Process.StartTime.ToUniversalTime().Ticks
    $expected -eq $actual
}

function Stop-AidosLeasedHostAgentProcess {
    param([Parameter(Mandatory)][string]$Root)
    $leasePath=Join-Path $Root 'LEASE.json'
    if(-not(Test-Path -LiteralPath $leasePath -PathType Leaf)){return [pscustomobject]@{status='NO_LEASE';pid=$null}}
    $lease=Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
    if($null-eq$lease.pid -or [string]::IsNullOrWhiteSpace([string]$lease.process_started_at)){throw 'AIDOS host-agent lease is malformed; refusing to terminate any process.'}
    $process=Get-Process -Id ([int]$lease.pid) -ErrorAction SilentlyContinue
    if($process){
        if(-not(Test-AidosLeaseProcessIdentity -Lease $lease -Process $process)){throw 'AIDOS host-agent lease PID identity no longer matches the live process; refusing force termination.'}
        if([string]$process.ProcessName -notin @('pwsh','pwsh.exe')){throw "AIDOS host-agent lease points to unexpected process '$($process.ProcessName)'; refusing force termination."}
        Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
        for($attempt=0;$attempt -lt40;$attempt++){
            Start-Sleep -Milliseconds 250
            if(-not(Get-Process -Id ([int]$process.Id) -ErrorAction SilentlyContinue)){break}
        }
        if(Get-Process -Id ([int]$process.Id) -ErrorAction SilentlyContinue){throw 'AIDOS leased host-agent process did not terminate within the bounded reload window.'}
    }
    if(Test-Path -LiteralPath $leasePath -PathType Leaf){
        $current=Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
        if([string]$current.owner_id -ne [string]$lease.owner_id -or [int]$current.pid -ne [int]$lease.pid){throw 'AIDOS host-agent lease changed ownership during reload; refusing cleanup.'}
        Remove-Item -LiteralPath $leasePath -Force
    }
    [pscustomobject]@{status='LEASED_AGENT_STOPPED';pid=[int]$lease.pid;owner_id=[string]$lease.owner_id}
}

function Disable-AidosLegacyDesktopTransportTask {
    param([Parameter(Mandatory)][string]$TaskName)
    $task=Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if(-not$task){return [pscustomobject]@{status='NOT_INSTALLED';task_name=$TaskName}}
    if([string]$task.State -eq 'Running'){Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop}
    Disable-ScheduledTask -TaskName $TaskName -ErrorAction Stop|Out-Null
    [pscustomobject]@{status='DISABLED';task_name=$TaskName}
}

function Wait-AidosRepositoryHostReload {
    param(
        [Parameter(Mandatory)][string]$StatusPath,
        [Parameter(Mandatory)][DateTimeOffset]$StartedAt,
        [int]$TimeoutSeconds=60
    )
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        if(Test-Path -LiteralPath $StatusPath -PathType Leaf){
            try{
                $status=Get-Content -LiteralPath $StatusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
                $hostRunning=[string]$status.status -eq 'RUNNING'
                $bridgeRunning=$status.PSObject.Properties['bridge'] -and $null-ne$status.bridge -and [string]$status.bridge.status -eq 'RUNNING'
                $gatewayRunning=$status.PSObject.Properties['gateway'] -and $null-ne$status.gateway -and [string]$status.gateway.status -eq 'RUNNING'
                if($hostRunning -and $bridgeRunning -and $gatewayRunning -and -not[string]::IsNullOrWhiteSpace([string]$status.heartbeat_at)){
                    $heartbeat=[DateTimeOffset]::Parse([string]$status.heartbeat_at)
                    if($heartbeat -ge $StartedAt){return $status}
                }
            }catch{}
        }
    }while([DateTimeOffset]::UtcNow -lt $deadline)
    throw 'Repository handoff host did not publish a fresh healthy RUNNING heartbeat within the bounded reload window.'
}

$aidosRoot=Split-Path $PSScriptRoot -Parent
$repositoryHostStateRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-host'
$repositoryHostConfigPath=Join-Path $repositoryHostStateRoot 'CONFIG.json'
$repositoryHostStatusPath=Join-Path $repositoryHostStateRoot 'STATUS.json'
$repositoryHostTaskName='AIDOS Repository Handoff Host'
$legacyTaskName='AIDOS Persistent Local Desktop Agent'
$repositoryTask=Get-ScheduledTask -TaskName $repositoryHostTaskName -ErrorAction SilentlyContinue
$repositoryConfigPresent=Test-Path -LiteralPath $repositoryHostConfigPath -PathType Leaf

if(($null-ne$repositoryTask) -xor $repositoryConfigPresent){
    throw 'Repository handoff authority is partially installed; refusing to fall back to legacy desktop transport during Core reload.'
}

# Always stop only an exactly leased legacy agent process. When Repository Handoff
# is installed it is the transport authority, so the legacy task is then disabled
# and must not be reinstalled by the old autonomous-preparation bootstrap.
$stopped=Stop-AidosLeasedHostAgentProcess -Root $StateRoot

if($repositoryTask -and $repositoryConfigPresent){
    $repositoryWasRunning=([string]$repositoryTask.State -eq 'Running')
    $legacyTask=Disable-AidosLegacyDesktopTransportTask -TaskName $legacyTaskName
    $repositoryBootstrap=Join-Path $aidosRoot 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'
    if(-not(Test-Path -LiteralPath $repositoryBootstrap -PathType Leaf)){throw "Repository handoff host bootstrap is unavailable: $repositoryBootstrap"}

    if($repositoryWasRunning){
        & $repositoryBootstrap -Command Stop -StateRoot $repositoryHostStateRoot|Out-Null
        $deadline=[DateTimeOffset]::UtcNow.AddSeconds(15)
        do{
            Start-Sleep -Milliseconds 250
            $current=Get-ScheduledTask -TaskName $repositoryHostTaskName -ErrorAction SilentlyContinue
            if(-not$current -or [string]$current.State -ne 'Running'){break}
        }while([DateTimeOffset]::UtcNow -lt $deadline)
        $current=Get-ScheduledTask -TaskName $repositoryHostTaskName -ErrorAction SilentlyContinue
        if(-not$current){throw 'Repository handoff host scheduled task disappeared during reload.'}
        if([string]$current.State -eq 'Running'){throw 'Repository handoff host scheduled task did not stop within the bounded reload window.'}

        $restartStartedAt=[DateTimeOffset]::UtcNow
        Start-ScheduledTask -TaskName $repositoryHostTaskName -ErrorAction Stop
        $repositoryStatus=Wait-AidosRepositoryHostReload -StatusPath $repositoryHostStatusPath -StartedAt $restartStartedAt
    }else{
        $repositoryStatus=if(Test-Path -LiteralPath $repositoryHostStatusPath -PathType Leaf){
            try{Get-Content -LiteralPath $repositoryHostStatusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50}catch{$null}
        }else{$null}
    }

    $selfUpdateInstaller=Join-Path $aidosRoot 'tools/Install-AidosHostSelfUpdate.ps1'
    if(-not(Test-Path -LiteralPath $selfUpdateInstaller -PathType Leaf)){throw 'AIDOS host self-update installer is unavailable.'}
    $selfUpdate=& $selfUpdateInstaller -Distribution $Distribution -WslReposRoot $WslReposRoot -StateRoot $StateRoot -AuthorizedUser $AuthorizedUser

    [pscustomobject][ordered]@{
        status='RELOADED_REPOSITORY_HANDOFF'
        repository_host_task=$repositoryHostTaskName
        repository_host_was_running=$repositoryWasRunning
        repository_host_status=$repositoryStatus
        legacy_agent=$stopped
        legacy_task=$legacyTask
        host_self_update=$selfUpdate
    }|ConvertTo-Json -Depth 100
    exit 0
}

# Compatibility path for hosts that have not migrated to Repository Handoff yet.
# In that legacy-only topology the historical autonomous-preparation bootstrap
# remains authoritative and retains its stable scheduled-task behavior.
$enable=Join-Path $aidosRoot 'tools/Enable-AidosAutonomousPreparation.ps1'
if(-not(Test-Path -LiteralPath $enable -PathType Leaf)){throw "AIDOS enable script is unavailable: $enable"}
& $enable -Distribution $Distribution -WslReposRoot $WslReposRoot -PreparationProjectId $PreparationProjectId -PreparationRepository $PreparationRepository -PreparationProjectName $PreparationProjectName -RuntimeProjectRoot $RuntimeProjectRoot -AuthorizedUser $AuthorizedUser
