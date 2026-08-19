[CmdletBinding()]
param(
    [ValidateSet('Install','Start','StartBridge','StartGateway','Stop','Status','BindThinker','UnbindThinker','ResetThinkerTrigger','RotateKey','ShowApiKey','ShowOpenApi','ShowInstructions','FunnelStatus','Tick','Uninstall')]
    [string]$Command='Status',
    [string]$StateRoot,
    [string]$RegistryRoot,
    [string]$BuilderRoot,
    [string]$ContractsRoot,
    [string]$AidosRoot,
    [string]$AuthorizedUser='AIDOS\qvdm',
    [string]$ProcessName='ChatGPT Classic',
    [string]$ProjectId,
    [string]$ConversationTitle,
    [string]$HandoffId,
    [string]$PublicUrl,
    [int]$GatewayPort=47831,
    [ValidateSet(443,8443,10000)][int]$PublicPort=443,
    [int]$RecoveryIntervalSeconds=30,
    [int]$MaxProjectsPerTick=6,
    [bool]$Push=$true,
    [switch]$RetireClassicTransport,
    [switch]$SkipFunnel,
    [switch]$RepairUrlAcl,
    [switch]$CopyToClipboard,
    [switch]$KeepFunnel,
    [switch]$RemoveState
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not$IsWindows){throw 'The AIDOS repository handoff host must run with PowerShell 7 in Windows.'}

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -Global -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffInstallation.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffOpenApi.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffGateway.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryThinkerBinding.psm1') -DisableNameChecking

if([string]::IsNullOrWhiteSpace($StateRoot)){$StateRoot=Get-AidosRepositoryHandoffHostDefaultStateRoot}
$StateRoot=[IO.Path]::GetFullPath($StateRoot)
if([string]::IsNullOrWhiteSpace($AidosRoot)){$AidosRoot=Split-Path $PSScriptRoot -Parent}
$AidosRoot=[IO.Path]::GetFullPath($AidosRoot)
$reposRoot=Split-Path $AidosRoot -Parent
if([string]::IsNullOrWhiteSpace($RegistryRoot)){$RegistryRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\project-registry'}
if([string]::IsNullOrWhiteSpace($BuilderRoot)){$BuilderRoot=Join-Path $reposRoot 'AIDOS-Builder'}
if([string]::IsNullOrWhiteSpace($ContractsRoot)){$ContractsRoot=Join-Path $reposRoot 'AIDOS-Contracts'}
$taskName=Get-AidosRepositoryHandoffHostTaskName
$legacyTaskName=Get-AidosRepositoryHandoffLegacyTaskName
$self=$PSCommandPath

function Write-AidosRepositoryHostJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $dir=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }finally{
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}
    }
}

function Read-AidosRepositoryHostConfiguration {
    $path=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind config
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Repository handoff host is not installed.'}
    Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
}

function Get-AidosRepositoryHostPowerShellPath {
    $path=Join-Path $PSHOME 'pwsh.exe'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'PowerShell 7 pwsh.exe is unavailable.'}
    $path
}

function Get-AidosRepositoryHostTailscalePath {
    $command=Get-Command tailscale.exe,tailscale -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    if($command){return [string]$command.Source}
    $candidate=Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}
    throw 'Tailscale CLI is unavailable. Install and sign in to Tailscale or use -SkipFunnel with an explicit HTTPS PublicUrl.'
}

function Invoke-AidosRepositoryHostNative {
    param([Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowFailure)
    $output=@(& $FilePath @Arguments 2>&1)
    $exitCode=$LASTEXITCODE
    $result=[pscustomobject][ordered]@{
        file_path=$FilePath
        arguments=@($Arguments)
        exit_code=$exitCode
        output=@($output|ForEach-Object {[string]$_})
    }
    if(-not$AllowFailure -and $exitCode-ne0){throw "Command failed ($exitCode): $FilePath $($Arguments -join ' ') :: $($result.output -join '; ')"}
    $result
}

function Test-AidosRepositoryHostAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AidosRepositoryHostAuthorizedSession {
    param([Parameter(Mandatory)][string]$ExpectedUser)
    $snapshot=Get-AidosInteractiveSessionSnapshot
    $authorization=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser
    if(-not$authorization.allowed){throw "Repository handoff host requires the unlocked interactive session for '$ExpectedUser': $($authorization.reason)."}
    $current=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    if(-not[string]::Equals($current,$ExpectedUser,[StringComparison]::OrdinalIgnoreCase)){throw "Current Windows identity '$current' does not match AuthorizedUser '$ExpectedUser'."}
    [pscustomobject][ordered]@{snapshot=$snapshot;authorization=$authorization;current_user=$current}
}

function Test-AidosRepositoryGatewayPrefixAccess {
    param([Parameter(Mandatory)][string]$Prefix)
    $listener=[Net.HttpListener]::new()
    $listener.Prefixes.Add($Prefix)
    try{
        $listener.Start()
        $listener.Stop()
        $true
    }catch [UnauthorizedAccessException]{$false}
    catch [Net.HttpListenerException]{if($_.Exception.ErrorCode-eq5){$false}else{throw}}
    finally{$listener.Close()}
}

function Ensure-AidosRepositoryGatewayUrlAcl {
    param([Parameter(Mandatory)][string]$ExpectedUser,[Parameter(Mandatory)][int]$Port,[switch]$Repair)
    $prefix=Get-AidosRepositoryHandoffUrlPrefix -Port $Port
    if(Test-AidosRepositoryGatewayPrefixAccess -Prefix $prefix){return [pscustomobject][ordered]@{status='ACCESSIBLE';prefix=$prefix;changed=$false}}
    $arguments=Get-AidosRepositoryHandoffUrlAclArguments -AuthorizedUser $ExpectedUser -Port $Port
    if(-not(Test-AidosRepositoryHostAdministrator)){throw "HttpListener URL ACL is missing for '$ExpectedUser'. Re-run Install from an elevated PowerShell 7 window, or run: netsh.exe $($arguments -join ' ')"}
    $netsh=Join-Path $env:WINDIR 'System32\netsh.exe'
    $add=Invoke-AidosRepositoryHostNative -FilePath $netsh -Arguments $arguments -AllowFailure
    if($add.exit_code-ne0){
        if(-not$Repair){throw "Unable to add URL ACL without replacing an existing registration. Re-run Install with -RepairUrlAcl after verifying no other service owns '$prefix'. Output: $($add.output -join '; ')"}
        $null=Invoke-AidosRepositoryHostNative -FilePath $netsh -Arguments (Get-AidosRepositoryHandoffUrlAclArguments -AuthorizedUser $ExpectedUser -Port $Port -Delete) -AllowFailure
        $null=Invoke-AidosRepositoryHostNative -FilePath $netsh -Arguments $arguments
    }
    if(-not(Test-AidosRepositoryGatewayPrefixAccess -Prefix $prefix)){throw "URL ACL was configured but '$prefix' remains inaccessible."}
    [pscustomobject][ordered]@{status='CONFIGURED';prefix=$prefix;changed=$true}
}

function Protect-AidosRepositoryGatewayKey {
    param([Parameter(Mandatory)][string]$KeyPath,[Parameter(Mandatory)][string]$ExpectedUser)
    if(-not(Test-Path -LiteralPath $KeyPath -PathType Leaf)){throw 'Repository handoff gateway key file is missing.'}
    $icacls=Join-Path $env:WINDIR 'System32\icacls.exe'
    $result=Invoke-AidosRepositoryHostNative -FilePath $icacls -Arguments @($KeyPath,'/inheritance:r','/grant:r',"${ExpectedUser}:(F)",'SYSTEM:(F)')
    [pscustomobject][ordered]@{status='PROTECTED';path=$KeyPath;result=$result}
}

function Get-AidosRepositoryHostTaskStatus {
    param([string]$Name=$taskName)
    $task=Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if(-not$task){return $null}
    $info=Get-ScheduledTaskInfo -TaskName $Name -ErrorAction SilentlyContinue
    [pscustomobject][ordered]@{
        task_name=$Name
        state=[string]$task.State
        last_run_time=if($info){$info.LastRunTime}else{$null}
        last_task_result=if($info){$info.LastTaskResult}else{$null}
        next_run_time=if($info){$info.NextRunTime}else{$null}
    }
}

function Stop-AidosRepositoryHostTask {
    param([int]$TimeoutSeconds=15)
    $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if(-not$task){return}
    $stopPath=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind stop
    $stopDir=Split-Path -Parent $stopPath
    if(-not(Test-Path -LiteralPath $stopDir -PathType Container)){New-Item -ItemType Directory -Path $stopDir -Force|Out-Null}
    Set-Content -LiteralPath $stopPath -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
    try{$config=Read-AidosRepositoryHostConfiguration;Stop-AidosRepositoryHandoffBridge -StateRoot ([string]$config.bridge_state_root)|Out-Null;Stop-AidosRepositoryHandoffGateway -StateRoot ([string]$config.gateway_state_root)|Out-Null}catch{}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while([DateTimeOffset]::UtcNow-lt$deadline){
        $current=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if(-not$current -or [string]$current.State-ne'Running'){return}
        Start-Sleep -Milliseconds 250
    }
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
}

function Retire-AidosClassicTransportTask {
    param([switch]$Approved)
    $legacy=Get-ScheduledTask -TaskName $legacyTaskName -ErrorAction SilentlyContinue
    if(-not$legacy){return [pscustomobject][ordered]@{status='NOT_INSTALLED';task_name=$legacyTaskName}}
    if(-not$Approved){throw "Legacy transport task '$legacyTaskName' is still installed. Re-run Install with -RetireClassicTransport to prevent two transport authorities from running concurrently."}
    $legacyState=Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'
    try{
        if(-not(Test-Path -LiteralPath $legacyState -PathType Container)){New-Item -ItemType Directory -Path $legacyState -Force|Out-Null}
        Set-Content -LiteralPath (Join-Path $legacyState 'STOP') -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
    }catch{}
    Stop-ScheduledTask -TaskName $legacyTaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $legacyTaskName -Confirm:$false -ErrorAction Stop
    [pscustomobject][ordered]@{status='RETIRED';task_name=$legacyTaskName;preserved_state_root=$legacyState}
}

function Register-AidosRepositoryHostTask {
    param([Parameter(Mandatory)][string]$ExpectedUser,[Parameter(Mandatory)][string]$VbsPath)
    if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop}
    $wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
    $action=New-ScheduledTaskAction -Execute $wscript -Argument "`"$VbsPath`""
    $principal=New-ScheduledTaskPrincipal -UserId $ExpectedUser -LogonType Interactive -RunLevel Limited
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $ExpectedUser
    $settings=New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description 'AIDOS repository-only Thinker/Worker handoff host. ChatGPT is activation-only; actor content moves through the repository gateway.'|Out-Null
    [pscustomobject][ordered]@{status='REGISTERED';task_name=$taskName;authorized_user=$ExpectedUser;launcher=$VbsPath}
}

function Get-AidosRepositoryTailscaleStatus {
    param([Parameter(Mandatory)][string]$TailscalePath)
    $result=Invoke-AidosRepositoryHostNative -FilePath $TailscalePath -Arguments @('status','--json')
    ConvertFrom-AidosTailscaleStatusJson -Json ($result.output -join "`n")
}

function Set-AidosRepositoryFunnel {
    param([Parameter(Mandatory)][string]$TailscalePath,[int]$LocalPort,[int]$HttpsPort,[switch]$Disable)
    Invoke-AidosRepositoryHostNative -FilePath $TailscalePath -Arguments (Get-AidosRepositoryHandoffFunnelArguments -LocalPort $LocalPort -PublicPort $HttpsPort -Disable:$Disable)
}

function Read-AidosRepositoryChildStatus {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    try{Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}catch{[pscustomobject]@{status='INVALID';error=$_.Exception.Message}}
}

function Acquire-AidosRepositoryHostLease {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$OwnerId,[switch]$AfterReclaim)
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){New-Item -ItemType Directory -Path $Root -Force|Out-Null}
    $path=Get-AidosRepositoryHandoffHostPath -StateRoot $Root -Kind lease
    try{
        $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{
            $lease=[ordered]@{schema_version='0.1';owner_id=$OwnerId;pid=$PID;process_started_at=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');started_at=[DateTimeOffset]::UtcNow.ToString('o')}
            $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($lease|ConvertTo-Json -Compress))
            $stream.Write($bytes,0,$bytes.Length)
            $stream.Flush($true)
        }finally{$stream.Dispose()}
        [pscustomobject]$lease
    }catch [IO.IOException]{
        if($AfterReclaim){throw 'Repository handoff host lease is already owned by another process.'}
        try{
            $existing=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
            $process=Get-Process -Id ([int]$existing.pid) -ErrorAction SilentlyContinue
            $alive=$null-ne$process -and [string]$existing.process_started_at-eq$process.StartTime.ToUniversalTime().ToString('o')
        }catch{$alive=$true}
        if($alive){throw 'Repository handoff host lease is already owned by another process.'}
        Remove-Item -LiteralPath $path -Force
        Acquire-AidosRepositoryHostLease -Root $Root -OwnerId $OwnerId -AfterReclaim
    }
}

function Release-AidosRepositoryHostLease {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$OwnerId)
    $path=Get-AidosRepositoryHandoffHostPath -StateRoot $Root -Kind lease
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return}
    $lease=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
    if([string]$lease.owner_id-ne$OwnerId){throw 'Repository handoff host lease owner mismatch.'}
    Remove-Item -LiteralPath $path -Force
}

function Start-AidosRepositoryChildProcess {
    param([Parameter(Mandatory)][string]$PowerShellPath,[Parameter(Mandatory)][string]$EntryPoint,[Parameter(Mandatory)][string]$ChildCommand,[Parameter(Mandatory)][string]$Root)
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$PowerShellPath
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    foreach($argument in @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$EntryPoint,'-Command',$ChildCommand,'-StateRoot',$Root)){$start.ArgumentList.Add($argument)}
    [Diagnostics.Process]::Start($start)
}

function Start-AidosRepositoryHostSupervisor {
    $config=Read-AidosRepositoryHostConfiguration
    $null=Assert-AidosRepositoryHostAuthorizedSession -ExpectedUser ([string]$config.authorized_user)
    $owner=[guid]::NewGuid().ToString()
    $null=Acquire-AidosRepositoryHostLease -Root $StateRoot -OwnerId $owner
    $stopPath=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind stop
    $statusPath=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind status
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    $engine=Get-AidosRepositoryHostPowerShellPath
    $bridge=$null
    $gateway=$null
    try{
        $bridge=Start-AidosRepositoryChildProcess -PowerShellPath $engine -EntryPoint ([string]$config.entry_point) -ChildCommand StartBridge -Root $StateRoot
        $gateway=Start-AidosRepositoryChildProcess -PowerShellPath $engine -EntryPoint ([string]$config.entry_point) -ChildCommand StartGateway -Root $StateRoot
        while(-not(Test-Path -LiteralPath $stopPath -PathType Leaf)){
            if($bridge.HasExited){throw "Repository handoff bridge child exited with code $($bridge.ExitCode)."}
            if($gateway.HasExited){throw "Repository handoff gateway child exited with code $($gateway.ExitCode)."}
            Write-AidosRepositoryHostJsonAtomic -Path $statusPath -Value ([ordered]@{
                schema_version='0.1';status='RUNNING';owner_id=$owner;pid=$PID;authorized_user=[string]$config.authorized_user;public_url=[string]$config.public_url;bridge_pid=$bridge.Id;gateway_pid=$gateway.Id;bridge=(Read-AidosRepositoryChildStatus -Path (Join-Path ([string]$config.bridge_state_root) 'STATUS.json'));gateway=(Read-AidosRepositoryChildStatus -Path (Join-Path ([string]$config.gateway_state_root) 'STATUS.json'));heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o')
            })
            Start-Sleep -Seconds 1
        }
        Write-AidosRepositoryHostJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='STOPPING';pid=$PID;observed_at=[DateTimeOffset]::UtcNow.ToString('o')})
    }catch{
        Write-AidosRepositoryHostJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='ERROR';pid=$PID;observed_at=[DateTimeOffset]::UtcNow.ToString('o');error=$_.Exception.Message})
        throw
    }finally{
        try{Stop-AidosRepositoryHandoffBridge -StateRoot ([string]$config.bridge_state_root)|Out-Null}catch{}
        try{Stop-AidosRepositoryHandoffGateway -StateRoot ([string]$config.gateway_state_root)|Out-Null}catch{}
        foreach($child in @($bridge,$gateway)){
            if($null-eq$child){continue}
            try{if(-not$child.WaitForExit(10000)){$child.Kill($true);$child.WaitForExit()}}catch{}
            $child.Dispose()
        }
        Release-AidosRepositoryHostLease -Root $StateRoot -OwnerId $owner
        $current=Read-AidosRepositoryChildStatus -Path $statusPath
        if($null-eq$current -or [string]$current.status-ne'ERROR'){Write-AidosRepositoryHostJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='STOPPED';pid=$PID;stopped_at=[DateTimeOffset]::UtcNow.ToString('o')})}
    }
}

function Copy-OrReturnAidosRepositoryText {
    param([Parameter(Mandatory)][string]$Text,[switch]$Clipboard)
    if($Clipboard){Set-Clipboard -Value $Text;return [pscustomobject][ordered]@{status='COPIED';character_count=$Text.Length}}
    $Text
}

switch($Command){
    'Install' {
        $session=Assert-AidosRepositoryHostAuthorizedSession -ExpectedUser $AuthorizedUser
        foreach($required in @($AidosRoot,$RegistryRoot,$BuilderRoot,$ContractsRoot)){if(-not(Test-Path -LiteralPath $required -PathType Container)){throw "Required AIDOS directory is unavailable: $required"}}
        Stop-AidosRepositoryHostTask
        $legacy=Retire-AidosClassicTransportTask -Approved:$RetireClassicTransport
        $urlAcl=Ensure-AidosRepositoryGatewayUrlAcl -ExpectedUser $AuthorizedUser -Port $GatewayPort -Repair:$RepairUrlAcl
        $tailscalePath=$null
        $funnel=$null
        if($SkipFunnel){
            if([string]::IsNullOrWhiteSpace($PublicUrl)){throw 'Install with -SkipFunnel requires an explicit HTTPS PublicUrl.'}
        }else{
            $tailscalePath=Get-AidosRepositoryHostTailscalePath
            $tailscaleStatus=Get-AidosRepositoryTailscaleStatus -TailscalePath $tailscalePath
            if([string]::IsNullOrWhiteSpace($PublicUrl)){$PublicUrl=[string]$tailscaleStatus.public_url}
            $funnel=Set-AidosRepositoryFunnel -TailscalePath $tailscalePath -LocalPort $GatewayPort -HttpsPort $PublicPort
        }
        $bridgeState=Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-bridge'
        $gatewayState=Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-gateway'
        $null=Initialize-AidosRepositoryHandoffBridge -RegistryRoot $RegistryRoot -BuilderRoot $BuilderRoot -ContractsRoot $ContractsRoot -AidosRoot $AidosRoot -StateRoot $bridgeState -RecoveryIntervalSeconds $RecoveryIntervalSeconds -MaxProjectsPerTick $MaxProjectsPerTick
        $null=Initialize-AidosRepositoryHandoffGateway -RegistryRoot $RegistryRoot -AidosRoot $AidosRoot -StateRoot $gatewayState -BridgeStateRoot $bridgeState -Port $GatewayPort
        $keyPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $gatewayState -Kind key
        $keyProtection=Protect-AidosRepositoryGatewayKey -KeyPath $keyPath -ExpectedUser $AuthorizedUser
        $configuration=New-AidosRepositoryHandoffHostConfiguration -EntryPoint $self -AidosRoot $AidosRoot -RegistryRoot $RegistryRoot -BuilderRoot $BuilderRoot -ContractsRoot $ContractsRoot -HostStateRoot $StateRoot -BridgeStateRoot $bridgeState -GatewayStateRoot $gatewayState -AuthorizedUser $AuthorizedUser -ProcessName $ProcessName -PublicUrl $PublicUrl -TailscalePath ([string]$tailscalePath) -GatewayPort $GatewayPort -PublicPort $PublicPort -RecoveryIntervalSeconds $RecoveryIntervalSeconds -MaxProjectsPerTick $MaxProjectsPerTick -Push $Push
        $files=Write-AidosRepositoryHandoffHostFiles -Configuration $configuration -PowerShellPath (Get-AidosRepositoryHostPowerShellPath)
        $openapi=Write-AidosRepositoryHandoffOpenApiDocument -ServerUrl ([string]$configuration.public_url) -Path ([string]$configuration.openapi_path)
        $task=Register-AidosRepositoryHostTask -ExpectedUser $AuthorizedUser -VbsPath ([string]$files.vbs_path)
        Start-ScheduledTask -TaskName $taskName
        [pscustomobject][ordered]@{
            status='INSTALLED';task=$task;legacy_transport=$legacy;authorized_session=$session;url_acl=$urlAcl;public_url=[string]$configuration.public_url;funnel=if($SkipFunnel){[pscustomobject]@{status='SKIPPED_EXTERNAL_HTTPS'}}else{$funnel};openapi_path=[string]$openapi.path;instructions_path=[string]$configuration.instructions_path;api_key_path=$keyPath;api_key_protection=$keyProtection;manual_setup=@('Create or edit one private AIDOS Repository Thinker GPT.','Paste GPT_INSTRUCTIONS.md into Instructions.','Create a custom Action from OPENAPI.json.','Configure API-key authentication as Bearer and paste the value from API_KEY.txt.','Use a non-Pro model that supports Actions.','Create, rename and pin one chat per project, then run BindThinker while that chat is active.')
        }|ConvertTo-Json -Depth 100
    }
    'Start' {Start-AidosRepositoryHostSupervisor}
    'StartBridge' {$config=Read-AidosRepositoryHostConfiguration;Start-AidosRepositoryHandoffBridge -StateRoot ([string]$config.bridge_state_root) -Push:([bool]$config.push)}
    'StartGateway' {$config=Read-AidosRepositoryHostConfiguration;Start-AidosRepositoryHandoffGateway -StateRoot ([string]$config.gateway_state_root) -Push:([bool]$config.push)}
    'Stop' {
        $config=Read-AidosRepositoryHostConfiguration
        $stopPath=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind stop
        if(-not(Test-Path -LiteralPath $StateRoot -PathType Container)){New-Item -ItemType Directory -Path $StateRoot -Force|Out-Null}
        Set-Content -LiteralPath $stopPath -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
        Stop-AidosRepositoryHandoffBridge -StateRoot ([string]$config.bridge_state_root)|Out-Null
        Stop-AidosRepositoryHandoffGateway -StateRoot ([string]$config.gateway_state_root)|Out-Null
        [pscustomobject][ordered]@{status='STOP_REQUESTED';task=(Get-AidosRepositoryHostTaskStatus);state_root=$StateRoot}|ConvertTo-Json -Depth 50
    }
    'Status' {
        $config=$null
        if(Test-Path -LiteralPath (Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind config) -PathType Leaf){$config=Read-AidosRepositoryHostConfiguration}
        $funnelStatus=$null
        if($config -and -not[string]::IsNullOrWhiteSpace([string]$config.tailscale_path)){$funnelStatus=Invoke-AidosRepositoryHostNative -FilePath ([string]$config.tailscale_path) -Arguments @('funnel','status','--json') -AllowFailure}
        [pscustomobject][ordered]@{
            task=(Get-AidosRepositoryHostTaskStatus);legacy_task=(Get-AidosRepositoryHostTaskStatus -Name $legacyTaskName);host=(Read-AidosRepositoryChildStatus -Path (Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind status));config=$config;bridge=if($config){Read-AidosRepositoryChildStatus -Path (Join-Path ([string]$config.bridge_state_root) 'STATUS.json')}else{$null};gateway=if($config){Read-AidosRepositoryChildStatus -Path (Join-Path ([string]$config.gateway_state_root) 'STATUS.json')}else{$null};funnel=$funnelStatus;state_root=$StateRoot
        }|ConvertTo-Json -Depth 100
    }
    'BindThinker' {
        if([string]::IsNullOrWhiteSpace($ProjectId)){throw 'BindThinker requires ProjectId.'}
        $config=Read-AidosRepositoryHostConfiguration
        $project=Get-AidosRegisteredProject -RegistryRoot ([string]$config.registry_root) -ProjectId $ProjectId
        if([string]::IsNullOrWhiteSpace($ConversationTitle)){$ConversationTitle="AIDOS :: $ProjectId :: THINKER"}
        Bind-AidosRepositoryThinkerConversation -StateRoot ([string]$config.bridge_state_root) -ProjectId $ProjectId -Repository ([string]$project.repository) -ExpectedConversationTitle $ConversationTitle -ProcessName ([string]$config.process_name)|ConvertTo-Json -Depth 50
    }
    'UnbindThinker' {
        if([string]::IsNullOrWhiteSpace($ProjectId)){throw 'UnbindThinker requires ProjectId.'}
        $config=Read-AidosRepositoryHostConfiguration
        Remove-AidosRepositoryThinkerBinding -StateRoot ([string]$config.bridge_state_root) -ProjectId $ProjectId|ConvertTo-Json -Depth 20
    }
    'ResetThinkerTrigger' {
        if([string]::IsNullOrWhiteSpace($ProjectId) -or [string]::IsNullOrWhiteSpace($HandoffId)){throw 'ResetThinkerTrigger requires ProjectId and HandoffId.'}
        $config=Read-AidosRepositoryHostConfiguration
        Reset-AidosRepositoryThinkerTrigger -StateRoot ([string]$config.bridge_state_root) -ProjectId $ProjectId -HandoffId $HandoffId|ConvertTo-Json -Depth 20
    }
    'RotateKey' {
        $config=Read-AidosRepositoryHostConfiguration
        Stop-AidosRepositoryHostTask
        $null=Initialize-AidosRepositoryHandoffGateway -RegistryRoot ([string]$config.registry_root) -AidosRoot ([string]$config.aidos_root) -StateRoot ([string]$config.gateway_state_root) -BridgeStateRoot ([string]$config.bridge_state_root) -Port ([int]$config.gateway_port) -RotateKey
        $keyPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot ([string]$config.gateway_state_root) -Kind key
        $protection=Protect-AidosRepositoryGatewayKey -KeyPath $keyPath -ExpectedUser ([string]$config.authorized_user)
        Start-ScheduledTask -TaskName $taskName
        [pscustomobject][ordered]@{status='ROTATED';api_key_path=$keyPath;protection=$protection;required_action='Update Bearer API key in the private GPT Action.'}|ConvertTo-Json -Depth 50
    }
    'ShowApiKey' {$config=Read-AidosRepositoryHostConfiguration;$path=Get-AidosRepositoryHandoffGatewayPath -StateRoot ([string]$config.gateway_state_root) -Kind key;Copy-OrReturnAidosRepositoryText -Text ((Get-Content -LiteralPath $path -Raw -Encoding ASCII).Trim()) -Clipboard:$CopyToClipboard}
    'ShowOpenApi' {$config=Read-AidosRepositoryHostConfiguration;Copy-OrReturnAidosRepositoryText -Text (Get-Content -LiteralPath ([string]$config.openapi_path) -Raw -Encoding UTF8) -Clipboard:$CopyToClipboard}
    'ShowInstructions' {$config=Read-AidosRepositoryHostConfiguration;Copy-OrReturnAidosRepositoryText -Text (Get-Content -LiteralPath ([string]$config.instructions_path) -Raw -Encoding UTF8) -Clipboard:$CopyToClipboard}
    'FunnelStatus' {
        $config=Read-AidosRepositoryHostConfiguration
        if([string]::IsNullOrWhiteSpace([string]$config.tailscale_path)){throw 'This installation does not manage Tailscale Funnel.'}
        Invoke-AidosRepositoryHostNative -FilePath ([string]$config.tailscale_path) -Arguments @('funnel','status','--json') -AllowFailure|ConvertTo-Json -Depth 50
    }
    'Tick' {$config=Read-AidosRepositoryHostConfiguration;Invoke-AidosRepositoryHandoffBridgeTick -RegistryRoot ([string]$config.registry_root) -StateRoot ([string]$config.bridge_state_root) -BuilderRoot ([string]$config.builder_root) -ContractsRoot ([string]$config.contracts_root) -AidosRoot ([string]$config.aidos_root) -MaxProjects ([int]$config.max_projects_per_tick) -Push:([bool]$config.push)|ConvertTo-Json -Depth 100}
    'Uninstall' {
        $config=$null
        if(Test-Path -LiteralPath (Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind config) -PathType Leaf){$config=Read-AidosRepositoryHostConfiguration}
        if($config){Stop-AidosRepositoryHostTask}
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $funnel=$null
        if($config -and -not$KeepFunnel -and -not[string]::IsNullOrWhiteSpace([string]$config.tailscale_path)){
            try{$funnel=Set-AidosRepositoryFunnel -TailscalePath ([string]$config.tailscale_path) -LocalPort ([int]$config.gateway_port) -HttpsPort ([int]$config.public_port) -Disable}catch{$funnel=[pscustomobject]@{status='ERROR';error=$_.Exception.Message}}
        }
        $removed=@()
        $preserved=@()
        if($config){$preserved=@($StateRoot,[string]$config.bridge_state_root,[string]$config.gateway_state_root)|Select-Object -Unique}else{$preserved=@($StateRoot)}
        if($RemoveState){
            foreach($path in @($preserved)){
                if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force;$removed+=$path}
            }
            $preserved=@()
        }
        [pscustomobject][ordered]@{status='UNINSTALLED';task_name=$taskName;funnel=$funnel;removed_state_roots=$removed;preserved_state=$preserved}|ConvertTo-Json -Depth 50
    }
}
