[CmdletBinding()]
param(
    [string]$Distribution='Ubuntu',
    [string]$WslReposRoot='/home/aidos/repos',
    [string]$StateRoot,
    [string]$AuthorizedUser='AIDOS\qvdm',
    [int]$IntervalMinutes=5,
    [switch]$PreserveExistingTask
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not$IsWindows){throw 'AIDOS host self-update installation must run from Windows PowerShell 7.'}
if($IntervalMinutes-lt1){throw 'IntervalMinutes must be at least 1.'}
if([string]::IsNullOrWhiteSpace($StateRoot)){$StateRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'}
if(-not(Test-Path -LiteralPath $StateRoot -PathType Container)){New-Item -ItemType Directory -Path $StateRoot -Force|Out-Null}

$taskName='AIDOS Host Self Update'
$engine=Join-Path $PSHOME 'pwsh.exe'
if(-not(Test-Path -LiteralPath $engine -PathType Leaf)){throw 'PowerShell 7 engine is unavailable.'}
$relative=$WslReposRoot.TrimStart('/').Replace('/','\')
$scriptPath="\\wsl.localhost\$Distribution\$relative\AIDOS\tools\Invoke-AidosHostSelfUpdate.ps1"
if(-not(Test-Path -LiteralPath $scriptPath -PathType Leaf)){throw "Self-update watchdog script is unavailable: $scriptPath"}

$currentUser=[Security.Principal.WindowsIdentity]::GetCurrent().Name
if(-not[string]::Equals($currentUser,$AuthorizedUser,[StringComparison]::OrdinalIgnoreCase)){throw "Self-update installation requires the authorized interactive user '$AuthorizedUser'; current identity is '$currentUser'."}

$arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Distribution `"$Distribution`" -WslReposRoot `"$WslReposRoot`" -StateRoot `"$StateRoot`" -AuthorizedUser `"$AuthorizedUser`""
$launcherPath=Join-Path $StateRoot 'SELF_UPDATE_LAUNCHER.vbs'
$command="`"$engine`" $arguments"
$escapedCommand=$command.Replace('"','""')
$launcher=@"
Option Explicit
Dim shell, command, rc
Set shell = CreateObject("WScript.Shell")
command = "$escapedCommand"
rc = shell.Run(command, 0, True)
WScript.Quit rc
"@
Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ascii
$wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
if(-not(Test-Path -LiteralPath $wscript -PathType Leaf)){throw 'Windows Script Host is unavailable.'}
$action=New-ScheduledTaskAction -Execute $wscript -Argument "`"$launcherPath`""
$principal=New-ScheduledTaskPrincipal -UserId $AuthorizedUser -LogonType Interactive -RunLevel Limited
$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$startTask=$true
if($existing){
    $existingUser=[string]$existing.Principal.UserId
    $leaf=($AuthorizedUser-split'\\')[-1]
    if(-not([string]::Equals($existingUser,$AuthorizedUser,[StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($existingUser,$leaf,[StringComparison]::OrdinalIgnoreCase))){throw 'Existing self-update task belongs to a different user.'}
    if($PreserveExistingTask){
        # A Core self-update reload must never attempt to mutate its own Task Scheduler
        # registration. Task State is not a reliable proof that the launcher child is
        # no longer executing, and the limited-user watchdog intentionally lacks task
        # mutation authority. The action path is stable; refreshing the launcher file
        # above is sufficient for the next scheduled invocation.
        $provisioning='PRESERVED_EXISTING'
        $startTask=$false
    }elseif([string]$existing.State -eq 'Running'){
        $provisioning='REUSED_RUNNING'
        $startTask=$false
    }else{
        Set-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal|Out-Null
        $provisioning='UPDATED'
    }
}elseif($PreserveExistingTask){
    throw 'Self-update reload requested preservation but the watchdog task is not installed.'
}else{
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'AIDOS fail-closed Core update validator and lease-safe host reload watchdog.'|Out-Null
    $provisioning='CREATED'
}
if($startTask){Enable-ScheduledTask -TaskName $taskName|Out-Null;Start-ScheduledTask -TaskName $taskName}
[pscustomobject][ordered]@{status='INSTALLED';task_name=$taskName;task_provisioning=$provisioning;interval_minutes=$IntervalMinutes;script_path=$scriptPath;state_root=$StateRoot;authorized_user=$AuthorizedUser;launcher_path=$launcherPath}
