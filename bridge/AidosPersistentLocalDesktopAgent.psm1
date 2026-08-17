Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosOperator.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosPreparationDispatcher.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopSessionGate.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosWindowsSession.psm1') -Force -DisableNameChecking

function Get-AidosHostAgentDefaultStateRoot {
    if(-not $IsWindows){ return (Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-host-agent') }
    Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'
}
function Get-AidosHostAgentDefaultPreparationRegistryRoot {
    if(-not $IsWindows){ return (Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-project-registry') }
    Join-Path $env:LOCALAPPDATA 'AIDOS\project-registry'
}
function Get-AidosHostAgentPath { param([string]$StateRoot,[ValidateSet('lease','status','stop','events')][string]$Kind)
    $names=@{lease='LEASE.json';status='STATUS.json';stop='STOP';events='EVENTS.jsonl'}
    Join-Path $StateRoot $names[$Kind]
}
function Write-AidosHostAgentJsonAtomic { param([string]$Path,$Value)
    $dir=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"; $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM; Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Add-AidosHostAgentEvent { param([string]$StateRoot,[string]$Type,$Payload)
    $dir=Split-Path -Parent (Get-AidosHostAgentPath $StateRoot events);if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    ([ordered]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');event_type=$Type;payload=$Payload}|ConvertTo-Json -Depth 100 -Compress)|Add-Content -LiteralPath (Get-AidosHostAgentPath $StateRoot events) -Encoding utf8NoBOM
}
function Get-AidosHostAgentProperty {
    param($Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if($null -eq $Object){return $Default}
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){return $Default}
    $property.Value
}
function Acquire-AidosHostAgentLease {
    param([string]$StateRoot,[string]$OwnerId=([guid]::NewGuid().ToString()),[switch]$AfterStaleReclaim)
    if(-not(Test-Path $StateRoot)){New-Item -ItemType Directory -Path $StateRoot -Force|Out-Null}
    $path=Get-AidosHostAgentPath $StateRoot lease
    try {
        $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $lease=[ordered]@{schema_version='0.1';owner_id=$OwnerId;pid=$PID;started_at=[DateTimeOffset]::UtcNow.ToString('o');process_started_at=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')};$bytes=[Text.Encoding]::UTF8.GetBytes(($lease|ConvertTo-Json -Compress));$stream.Write($bytes,0,$bytes.Length) } finally {$stream.Dispose()}
        [pscustomobject]$lease
    } catch [IO.IOException] {
        if($AfterStaleReclaim){ throw 'Persistent Local Desktop Agent lease already exists; another agent owns this desktop.' }
        try {$existing=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 20;$process=Get-Process -Id ([int]$existing.pid) -ErrorAction SilentlyContinue;$alive=$process -and [string]$existing.process_started_at -eq $process.StartTime.ToUniversalTime().ToString('o')}catch{$alive=$true}
        if($alive){throw 'Persistent Local Desktop Agent lease already exists; another agent owns this desktop.'}
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        return Acquire-AidosHostAgentLease -StateRoot $StateRoot -OwnerId $OwnerId -AfterStaleReclaim
    }
}
function Release-AidosHostAgentLease { param([string]$StateRoot,[string]$OwnerId)
    $path=Get-AidosHostAgentPath $StateRoot lease;if(-not(Test-Path $path)){return}
    $lease=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -Depth 20
    if([string]$lease.owner_id -ne $OwnerId){throw 'Host-agent lease owner mismatch.'};Remove-Item -LiteralPath $path -Force
}
function Get-AidosHostAgentStatus { param([string]$StateRoot=(Get-AidosHostAgentDefaultStateRoot))
    $path=Get-AidosHostAgentPath $StateRoot status;if(Test-Path $path){Get-Content $path -Raw|ConvertFrom-Json -Depth 100}else{$null}
}
function Stop-AidosHostAgent { param([string]$StateRoot=(Get-AidosHostAgentDefaultStateRoot))
    $dir=$StateRoot;if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};Set-Content -LiteralPath (Get-AidosHostAgentPath $StateRoot stop) -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
}
function Get-AidosHostAgentShellHealth {
    param([string]$ProcessName='ChatGPT Classic',[int]$ExpectedSessionId=-1)
    try {
        $context=Get-AidosDesktopChatGPTProcessContext -ProcessName $ProcessName
        if($ExpectedSessionId -ge 0 -and [int]$context.session_id -ne $ExpectedSessionId){throw 'ChatGPT shell session differs from authorized session.'}
        [pscustomobject]@{status='HEALTHY';process_id=$context.process_id;session_id=$context.session_id;window_handle=$context.window_handle;detail=$context}
    } catch {[pscustomobject]@{status='UNAVAILABLE';reason=$_.Exception.Message}}
}
function Get-AidosHostAgentAssignmentPath { param([string]$ProjectRoot,[string]$ReviewId,$Record)
    if($Record.assignment_path){return (Resolve-AidosRecordBoundPath $ProjectRoot ([string]$Record.assignment_path))};Join-Path (Join-Path $ProjectRoot ([string]$Record.package_path)) 'REVIEW_ASSIGNMENT.json'
}
function Invoke-AidosHostAgentTick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$AuthorizedUser,
        [string]$ProcessName='ChatGPT Classic',
        [string]$StateRoot=(Get-AidosHostAgentDefaultStateRoot),
        [int]$ResponseTimeoutSeconds=5,
        [string]$PreparationRegistryRoot,
        [string]$BuilderRoot,
        [string]$ContractsRoot,
        [switch]$PreparationPush,
        [scriptblock]$PreparationDispatcher,
        [scriptblock]$SnapshotProvider,
        [scriptblock]$ShellHealthProvider,
        [scriptblock]$ReviewReconciler,
        [scriptblock]$ReviewConsumer,
        [scriptblock]$DesktopReviewInvoker
    )
    $preparation=$null
    if($PreparationDispatcher){
        try{$preparation=& $PreparationDispatcher}catch{$preparation=[pscustomobject]@{status='ERROR';error=$_.Exception.Message}}
    }elseif(-not[string]::IsNullOrWhiteSpace($PreparationRegistryRoot)){
        try{$preparation=Invoke-AidosPreparationDispatcherTick -RegistryRoot $PreparationRegistryRoot -BuilderRoot $BuilderRoot -ContractsRoot $ContractsRoot -Push:$PreparationPush}catch{$preparation=[pscustomobject]@{status='ERROR';error=$_.Exception.Message}}
    }
    $snapshot=if($SnapshotProvider){& $SnapshotProvider}else{Get-AidosInteractiveSessionSnapshot}
    $auth=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $AuthorizedUser
    $shell=if($auth.allowed){if($ShellHealthProvider){& $ShellHealthProvider $ProcessName ([int]$snapshot.session_id)}else{Get-AidosHostAgentShellHealth -ProcessName $ProcessName -ExpectedSessionId ([int]$snapshot.session_id)}}else{[pscustomobject]@{status='NOT_CHECKED';reason=$auth.reason}}
    $result=[ordered]@{status='IDLE';authorized=$auth.allowed;reason=$auth.reason;snapshot=$snapshot;shell=$shell;control=$null;preparation_result=$preparation;project_result=$null}
    if(-not $auth.allowed){$result.status='WAITING_INFRASTRUCTURE';return [pscustomobject]$result}
    $control=Get-AidosOperatorControlState -ProjectRoot $ProjectRoot
    $result.control=$control
    if([string]$control.mode -eq 'PAUSED'){$result.status='PAUSED';$result.reason='OPERATOR_CONTROL';return [pscustomobject]$result}
    if([string]$control.mode -eq 'SAFE_STOPPED'){$result.status='SAFE_STOPPED';$result.reason='OPERATOR_CONTROL';return [pscustomobject]$result}
    $reconciled=if($ReviewReconciler){& $ReviewReconciler $ProjectRoot}else{Invoke-AidosReviewReconciliation -ProjectRoot $ProjectRoot}
    $result.project_result=$reconciled
    if([string]$reconciled.status -ne 'PUBLISHED'){ $result.status=[string]$reconciled.status;return [pscustomobject]$result }
    $reviewId=[string]$reconciled.review_id;$record=Read-AidosReviewRecord $ProjectRoot $reviewId
    if(-not $record){$result.status='RECOVERY_REQUIRED';$result.reason='REVIEW_RECORD_MISSING';return [pscustomobject]$result}
    $adapterState=Read-AidosDesktopChatGPTState $ProjectRoot $reviewId
    $responsePath=Get-AidosDesktopChatGPTResponsePath $ProjectRoot $reviewId
    if($adapterState -and [string]$adapterState.status -eq 'HANDOFF_COMPLETE' -and (Test-Path -LiteralPath $responsePath -PathType Leaf)){
        try {$consumed=if($ReviewConsumer){& $ReviewConsumer $ProjectRoot $responsePath}else{Invoke-AidosReviewConsumer -ProjectRoot $ProjectRoot -ResponsePath $responsePath -Actor BRIDGE}}
        catch {$result.status='RECOVERY_REQUIRED';$result.reason="REVIEW_CONSUME_FAILED: $($_.Exception.Message)";return [pscustomobject]$result}
        $result.status='CONSUMED';$result.project_result=$consumed;return [pscustomobject]$result
    }
    if($shell.status -ne 'HEALTHY'){$result.status='WAITING_INFRASTRUCTURE';$result.reason='CHATGPT_SHELL_UNAVAILABLE';return [pscustomobject]$result}
    $assignmentPath=Get-AidosHostAgentAssignmentPath $ProjectRoot $reviewId $record
    $desktop=if($DesktopReviewInvoker){& $DesktopReviewInvoker $ProjectRoot $assignmentPath}else{AidosDesktopSessionGate\Invoke-AidosDesktopChatGPTReview -ProjectRoot $ProjectRoot -AssignmentPath $assignmentPath -ProcessName $ProcessName -ResponseTimeoutSeconds $ResponseTimeoutSeconds -WaitForInteractiveSession:$false}
    $result.status=[string]$desktop.status;$result.project_result=$desktop
    if([string]$desktop.status -eq 'HANDOFF_COMPLETE'){
        try {$consumed=if($ReviewConsumer){& $ReviewConsumer $ProjectRoot (Get-AidosDesktopChatGPTResponsePath $ProjectRoot $reviewId)}else{Invoke-AidosReviewConsumer -ProjectRoot $ProjectRoot -ResponsePath (Get-AidosDesktopChatGPTResponsePath $ProjectRoot $reviewId) -Actor BRIDGE}}
        catch {$result.status='RECOVERY_REQUIRED';$result.reason="REVIEW_CONSUME_FAILED: $($_.Exception.Message)";return [pscustomobject]$result}
        $result.status='CONSUMED';$result.project_result=$consumed
    }
    [pscustomobject]$result
}
function Start-AidosPersistentLocalDesktopAgent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$AuthorizedUser='AIDOS\qvdm',
        [string]$ProcessName='ChatGPT Classic',
        [string]$StateRoot=(Get-AidosHostAgentDefaultStateRoot),
        [int]$PollSeconds=5,
        [int]$ResponseTimeoutSeconds=5,
        [string]$PreparationRegistryRoot,
        [string]$BuilderRoot,
        [string]$ContractsRoot,
        [switch]$PreparationPush,
        [switch]$Once
    )
    if(-not $IsWindows){throw 'Persistent Local Desktop Agent must run in an interactive Windows user session.'}
    $owner=[guid]::NewGuid().ToString();$failureCount=0;$null=Acquire-AidosHostAgentLease -StateRoot $StateRoot -OwnerId $owner
    try {
        Remove-Item -LiteralPath (Get-AidosHostAgentPath $StateRoot stop) -Force -ErrorAction SilentlyContinue
        $boot=[ordered]@{schema_version='0.1';owner_id=$owner;pid=$PID;project_root=$ProjectRoot;preparation_registry_root=$PreparationRegistryRoot;authorized_user=$AuthorizedUser;process_name=$ProcessName;heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o');phase='BOOTING';last_tick=$null;failure_count=0}
        Write-AidosHostAgentJsonAtomic (Get-AidosHostAgentPath $StateRoot status) $boot
        Add-AidosHostAgentEvent $StateRoot 'AGENT_BOOTING' @{owner_id=$owner;project_root=$ProjectRoot;authorized_user=$AuthorizedUser;preparation_registry_root=$PreparationRegistryRoot}
        try {
            $startup=Invoke-AidosStartupReconciliation -ProjectRoot $ProjectRoot
            Add-AidosHostAgentEvent $StateRoot 'AGENT_STARTED' @{owner_id=$owner;project_root=$ProjectRoot;authorized_user=$AuthorizedUser;startup_reconciliation=$startup.status}
        } catch {
            $failureCount=1
            $boot.phase='STARTUP_ERROR';$boot.failure_count=$failureCount;$boot.startup_error=$_.Exception.Message;$boot.heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosHostAgentJsonAtomic (Get-AidosHostAgentPath $StateRoot status) $boot
            Add-AidosHostAgentEvent $StateRoot 'AGENT_STARTUP_ERROR' @{owner_id=$owner;error=$_.Exception.Message}
        }
        do {
            try {$tick=Invoke-AidosHostAgentTick -ProjectRoot $ProjectRoot -AuthorizedUser $AuthorizedUser -ProcessName $ProcessName -StateRoot $StateRoot -ResponseTimeoutSeconds $ResponseTimeoutSeconds -PreparationRegistryRoot $PreparationRegistryRoot -BuilderRoot $BuilderRoot -ContractsRoot $ContractsRoot -PreparationPush:$PreparationPush; $failureCount=0}
            catch {$tick=[pscustomobject]@{status='ERROR';reason=$_.Exception.Message};$failureCount=1+[int]$failureCount}
            $status=[ordered]@{schema_version='0.1';owner_id=$owner;pid=$PID;project_root=$ProjectRoot;preparation_registry_root=$PreparationRegistryRoot;authorized_user=$AuthorizedUser;process_name=$ProcessName;heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o');phase='RUNNING';last_tick=$tick;failure_count=$failureCount}
            Write-AidosHostAgentJsonAtomic (Get-AidosHostAgentPath $StateRoot status) $status
            Add-AidosHostAgentEvent $StateRoot 'TICK' @{status=(Get-AidosHostAgentProperty $tick 'status' 'UNKNOWN');reason=(Get-AidosHostAgentProperty $tick 'reason' $null);preparation_status=(Get-AidosHostAgentProperty (Get-AidosHostAgentProperty $tick 'preparation_result' $null) 'status' $null)}
            if($Once -or (Test-Path -LiteralPath (Get-AidosHostAgentPath $StateRoot stop))){break};Start-Sleep -Seconds ([Math]::Min(60,[Math]::Max(1,$PollSeconds)*[Math]::Min(8,[Math]::Max(1,$failureCount+1))) )
        } while($true)
    } finally { Add-AidosHostAgentEvent $StateRoot 'AGENT_STOPPED' @{owner_id=$owner};Release-AidosHostAgentLease -StateRoot $StateRoot -OwnerId $owner }
}
Export-ModuleMember -Function Get-AidosHostAgentDefaultStateRoot,Get-AidosHostAgentDefaultPreparationRegistryRoot,Get-AidosHostAgentStatus,Stop-AidosHostAgent,Acquire-AidosHostAgentLease,Release-AidosHostAgentLease,Get-AidosHostAgentShellHealth,Invoke-AidosHostAgentTick,Start-AidosPersistentLocalDesktopAgent
