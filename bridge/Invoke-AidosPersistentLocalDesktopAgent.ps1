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
switch($Command){
 'Install' { if([string]::IsNullOrWhiteSpace($ProjectRoot)){throw 'Install requires ProjectRoot.'}; $installationAuthorization=Test-AidosAuthorizedInteractiveSession -Snapshot (Get-AidosInteractiveSessionSnapshot) -AuthorizedUser $AuthorizedUser;if(-not $installationAuthorization.allowed){throw "Install requires the existing unlocked interactive token for '$AuthorizedUser': $($installationAuthorization.reason)."}; $engine=Join-Path $PSHOME 'pwsh.exe';if(-not(Test-Path -LiteralPath $engine -PathType Leaf)){throw 'Install requires PowerShell 7 (pwsh.exe); do not register a Windows PowerShell 5 task.'}; $arg="-NoLogo -NoProfile -WindowStyle Hidden -File `"$self`" -Command Start -ProjectRoot `"$ProjectRoot`" -AuthorizedUser `"$AuthorizedUser`" -ProcessName `"$ProcessName`" -StateRoot `"$StateRoot`" -PollSeconds $PollSeconds"; $action=New-ScheduledTaskAction -Execute $engine -Argument $arg; $principal=New-ScheduledTaskPrincipal -UserId $AuthorizedUser -LogonType Interactive -RunLevel Limited; $trigger=New-ScheduledTaskTrigger -AtLogOn -User $AuthorizedUser; $settings=New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0); Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description 'AIDOS host-only desktop review transport agent; requires existing unlocked interactive user session.' -Force|Out-Null; Start-ScheduledTask -TaskName $taskName; [pscustomobject]@{status='INSTALLED';task_name=$taskName;state_root=$StateRoot}|ConvertTo-Json -Depth 20 }
 'Start' {if([string]::IsNullOrWhiteSpace($ProjectRoot)){throw 'Start requires ProjectRoot.'};Start-AidosPersistentLocalDesktopAgent -ProjectRoot $ProjectRoot -AuthorizedUser $AuthorizedUser -ProcessName $ProcessName -StateRoot $StateRoot -PollSeconds $PollSeconds -Once:$Once}
 'Stop' {Stop-AidosHostAgent -StateRoot $StateRoot;[pscustomobject]@{status='STOP_REQUESTED';state_root=$StateRoot}|ConvertTo-Json}
 'Status' {Get-AidosHostAgentStatus -StateRoot $StateRoot|ConvertTo-Json -Depth 100}
 'Snapshot' { $s=Get-AidosInteractiveSessionSnapshot;$h=Get-AidosHostAgentShellHealth -ProcessName $ProcessName -ExpectedSessionId (if($null -eq $s.session_id){-1}else{[int]$s.session_id});[pscustomobject]@{snapshot=$s;authorization=(Test-AidosAuthorizedInteractiveSession $s $AuthorizedUser);chatgpt=$h;agent=(Get-AidosHostAgentStatus $StateRoot)}|ConvertTo-Json -Depth 100 }
 'HandoffToConsole' {Invoke-AidosAuthorizedSessionHandoffToConsole -AuthorizedUser $AuthorizedUser|ConvertTo-Json -Depth 100}
 'Tick' {if([string]::IsNullOrWhiteSpace($ProjectRoot)){throw 'Tick requires ProjectRoot.'};Invoke-AidosHostAgentTick -ProjectRoot $ProjectRoot -AuthorizedUser $AuthorizedUser -ProcessName $ProcessName -StateRoot $StateRoot|ConvertTo-Json -Depth 100}
 'Uninstall' { $fullStateRoot=[IO.Path]::GetFullPath($StateRoot);if($fullStateRoot.TrimEnd('\\') -eq [IO.Path]::GetPathRoot($fullStateRoot).TrimEnd('\\')){throw 'Refusing to remove a filesystem root as host-agent state.'};Stop-AidosHostAgent -StateRoot $fullStateRoot;Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue;if(Test-Path -LiteralPath $fullStateRoot){Remove-Item -LiteralPath $fullStateRoot -Recurse -Force};[pscustomobject]@{status='UNINSTALLED';task_name=$taskName;removed_state_root=$fullStateRoot;note='Removed only the AIDOS-owned scheduled task and host-agent state directory.'}|ConvertTo-Json}
}
