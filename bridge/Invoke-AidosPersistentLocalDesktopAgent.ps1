[CmdletBinding()]
param(
 [ValidateSet('Install','Start','Stop','Status','HandoffToConsole','Uninstall','Snapshot','Tick')][string]$Command='Start',
 [string]$ProjectRoot, [string]$AuthorizedUser='AIDOS\qvdm', [string]$ProcessName='ChatGPT Classic', [string]$StateRoot, [int]$PollSeconds=5, [switch]$Once
)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'This Windows host-agent command must be run with PowerShell 7 on Windows.'}
Import-Module (Join-Path $PSScriptRoot 'AidosPersistentLocalDesktopAgent.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosWindowsSession.psm1') -Force -DisableNameChecking
if(-not $StateRoot){$StateRoot=Get-AidosHostAgentDefaultStateRoot}
$taskName='AIDOS Persistent Local Desktop Agent'
$self=$PSCommandPath
function Get-AidosPersistentAgentTaskStatus {
    $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if(-not $task){return $null}
    $info=Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    [pscustomobject]@{
        task_name=$taskName
        state=[string]$task.State
        last_run_time=if($info){$info.LastRunTime}else{$null}
        last_task_result=if($info){$info.LastTaskResult}else{$null}
        next_run_time=if($info){$info.NextRunTime}else{$null}
    }
}
function Write-AidosPersistentAgentLocalLauncher {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$EntryPoint,[Parameter(Mandatory)][string]$BoundProjectRoot,[Parameter(Mandatory)][string]$BoundAuthorizedUser,[Parameter(Mandatory)][string]$BoundProcessName,[Parameter(Mandatory)][int]$BoundPollSeconds)
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){New-Item -ItemType Directory -Path $Root -Force|Out-Null}
    $configPath=Join-Path $Root 'CONFIG.json'
    $launcherPath=Join-Path $Root 'LAUNCHER.ps1'
    $config=[ordered]@{schema_version='0.1';entry_point=$EntryPoint;project_root=$BoundProjectRoot;authorized_user=$BoundAuthorizedUser;process_name=$BoundProcessName;state_root=$Root;poll_seconds=$BoundPollSeconds}
    $config|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
    $launcher=@'
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSCommandPath
$configPath=Join-Path $root 'CONFIG.json'
$statusPath=Join-Path $root 'STATUS.json'
$logPath=Join-Path $root 'STARTUP_ERROR.log'
$stdoutPath=Join-Path $root 'CHILD_STDOUT.log'
$stderrPath=Join-Path $root 'CHILD_STDERR.log'
try {
    Remove-Item -LiteralPath $stdoutPath,$stderrPath,$logPath -Force -ErrorAction SilentlyContinue
    $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
    if(-not(Test-Path -LiteralPath ([string]$config.entry_point) -PathType Leaf)){throw "Agent entrypoint is unavailable: $($config.entry_point)"}
    $engine=Join-Path $PSHOME 'pwsh.exe'
    $arguments=@(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',([string]$config.entry_point),
        '-Command','Start',
        '-ProjectRoot',([string]$config.project_root),
        '-AuthorizedUser',([string]$config.authorized_user),
        '-ProcessName',([string]$config.process_name),
        '-StateRoot',([string]$config.state_root),
        '-PollSeconds',([string][int]$config.poll_seconds)
    )
    $process=Start-Process -FilePath $engine -ArgumentList $arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -Wait -PassThru -WindowStyle Hidden
    if($process.ExitCode -ne 0){
        $stderr=if(Test-Path -LiteralPath $stderrPath){Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue}else{$null}
        $stdout=if(Test-Path -LiteralPath $stdoutPath){Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue}else{$null}
        $detail=@("Agent child PowerShell exited with code $($process.ExitCode).")
        if(-not [string]::IsNullOrWhiteSpace([string]$stderr)){$detail += "STDERR:`n$stderr"}
        if(-not [string]::IsNullOrWhiteSpace([string]$stdout)){$detail += "STDOUT:`n$stdout"}
        throw ($detail -join "`n")
    }
    exit 0
} catch {
    $message=$_.Exception.ToString()
    $message|Set-Content -LiteralPath $logPath -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';status='STARTUP_ERROR';heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o');reason=$_.Exception.Message;detail=$message}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $statusPath -Encoding utf8NoBOM
    exit 1
}
'@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding utf8NoBOM
    [pscustomobject]@{launcher_path=$launcherPath;config_path=$configPath}
}
switch($Command){
 'Install' {
    if([string]::IsNullOrWhiteSpace($ProjectRoot)){throw 'Install requires ProjectRoot.'}
    $installationAuthorization=Test-AidosAuthorizedInteractiveSession -Snapshot (Get-AidosInteractiveSessionSnapshot) -AuthorizedUser $AuthorizedUser
    if(-not $installationAuthorization.allowed){throw "Install requires the existing unlocked interactive token for '$AuthorizedUser': $($installationAuthorization.reason)."}
    $engine=Join-Path $PSHOME 'pwsh.exe';if(-not(Test-Path -LiteralPath $engine -PathType Leaf)){throw 'Install requires PowerShell 7 (pwsh.exe); do not register a Windows PowerShell 5 task.'}
    $local=Write-AidosPersistentAgentLocalLauncher -Root $StateRoot -EntryPoint $self -BoundProjectRoot $ProjectRoot -BoundAuthorizedUser $AuthorizedUser -BoundProcessName $ProcessName -BoundPollSeconds $PollSeconds
    $arg="-NoLogo -NoProfile -WindowStyle Hidden -File `"$($local.launcher_path)`""
    $action=New-ScheduledTaskAction -Execute $engine -Argument $arg
    $principal=New-ScheduledTaskPrincipal -UserId $AuthorizedUser -LogonType Interactive -RunLevel Limited
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $AuthorizedUser
    $settings=New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description 'AIDOS host-only desktop review transport agent; requires existing unlocked interactive user session.' -Force|Out-Null
    Start-ScheduledTask -TaskName $taskName
    [pscustomobject]@{status='INSTALLED';task_name=$taskName;state_root=$StateRoot;launcher_path=$local.launcher_path}|ConvertTo-Json -Depth 20
 }
 'Start' {if([string]::IsNullOrWhiteSpace($ProjectRoot)){throw 'Start requires ProjectRoot.'};Start-AidosPersistentLocalDesktopAgent -ProjectRoot $ProjectRoot -AuthorizedUser $AuthorizedUser -ProcessName $ProcessName -StateRoot $StateRoot -PollSeconds $PollSeconds -Once:$Once}
 'Stop' {Stop-AidosHostAgent -StateRoot $StateRoot;[pscustomobject]@{status='STOP_REQUESTED';state_root=$StateRoot}|ConvertTo-Json}
 'Status' {
    $startupLogPath=Join-Path $StateRoot 'STARTUP_ERROR.log'
    $stdoutPath=Join-Path $StateRoot 'CHILD_STDOUT.log'
    $stderrPath=Join-Path $StateRoot 'CHILD_STDERR.log'
    [pscustomobject]@{
        task=(Get-AidosPersistentAgentTaskStatus)
        agent=(Get-AidosHostAgentStatus -StateRoot $StateRoot)
        startup_error_log=if(Test-Path -LiteralPath $startupLogPath){Get-Content -LiteralPath $startupLogPath -Raw}else{$null}
        child_stdout=if(Test-Path -LiteralPath $stdoutPath){Get-Content -LiteralPath $stdoutPath -Raw}else{$null}
        child_stderr=if(Test-Path -LiteralPath $stderrPath){Get-Content -LiteralPath $stderrPath -Raw}else{$null}
        state_root=$StateRoot
    }|ConvertTo-Json -Depth 100
 }
 'Snapshot' { $s=Get-AidosInteractiveSessionSnapshot;$expectedSessionId=-1;if($null -ne $s.session_id){$expectedSessionId=[int]$s.session_id};$h=Get-AidosHostAgentShellHealth -ProcessName $ProcessName -ExpectedSessionId $expectedSessionId;[pscustomobject]@{snapshot=$s;authorization=(Test-AidosAuthorizedInteractiveSession $s $AuthorizedUser);chatgpt=$h;agent=(Get-AidosHostAgentStatus $StateRoot);task=(Get-AidosPersistentAgentTaskStatus)}|ConvertTo-Json -Depth 100 }
 'HandoffToConsole' {Invoke-AidosAuthorizedSessionHandoffToConsole -AuthorizedUser $AuthorizedUser|ConvertTo-Json -Depth 100}
 'Tick' {if([string]::IsNullOrWhiteSpace($ProjectRoot)){throw 'Tick requires ProjectRoot.'};Invoke-AidosHostAgentTick -ProjectRoot $ProjectRoot -AuthorizedUser $AuthorizedUser -ProcessName $ProcessName -StateRoot $StateRoot|ConvertTo-Json -Depth 100}
 'Uninstall' { $fullStateRoot=[IO.Path]::GetFullPath($StateRoot);if($fullStateRoot.TrimEnd('\\') -eq [IO.Path]::GetPathRoot($fullStateRoot).TrimEnd('\\')){throw 'Refusing to remove a filesystem root as host-agent state.'};Stop-AidosHostAgent -StateRoot $fullStateRoot;Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue;if(Test-Path -LiteralPath $fullStateRoot){Remove-Item -LiteralPath $fullStateRoot -Recurse -Force};[pscustomobject]@{status='UNINSTALLED';task_name=$taskName;removed_state_root=$fullStateRoot;note='Removed only the AIDOS-owned scheduled task and host-agent state directory.'}|ConvertTo-Json}
}
