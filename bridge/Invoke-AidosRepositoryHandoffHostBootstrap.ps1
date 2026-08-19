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
if(-not$IsWindows){throw 'The AIDOS repository handoff host bootstrap must run with PowerShell 7 in Windows.'}

$original=Join-Path $PSScriptRoot 'Invoke-AidosRepositoryHandoffHost.ps1'
$sessionModule=Join-Path $PSScriptRoot 'AidosWindowsSession.psm1'
if(-not(Test-Path -LiteralPath $original -PathType Leaf)){throw "Repository handoff host entrypoint is unavailable: $original"}
if(-not(Test-Path -LiteralPath $sessionModule -PathType Leaf)){throw "Windows session module is unavailable: $sessionModule"}

# Windows/UNC PowerShell runspaces do not reliably surface imported module
# exports to script-defined functions by unqualified name. Import the module,
# prove its module-qualified exports exist, then publish two ordinary global
# proxy functions for the exact session commands used by the canonical host.
Import-Module $sessionModule -Force -Global -DisableNameChecking
Get-Command 'AidosWindowsSession\Get-AidosInteractiveSessionSnapshot' -ErrorAction Stop|Out-Null
Get-Command 'AidosWindowsSession\Test-AidosAuthorizedInteractiveSession' -ErrorAction Stop|Out-Null

function global:Get-AidosInteractiveSessionSnapshot {
    [CmdletBinding()]
    param()
    AidosWindowsSession\Get-AidosInteractiveSessionSnapshot
}

function global:Test-AidosAuthorizedInteractiveSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$AuthorizedUser,
        [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$Policy='SUPERVISED'
    )
    AidosWindowsSession\Test-AidosAuthorizedInteractiveSession -Snapshot $Snapshot -AuthorizedUser $AuthorizedUser -Policy $Policy
}

# Dot-source the canonical host in the same runspace after the explicit proxies
# exist. The bootstrap itself becomes the scheduled-task entrypoint after a
# successful installation, so the same binding is recreated on every start.
$output=. $original @PSBoundParameters

if($Command-eq'Install'){
    $resolvedStateRoot=if([string]::IsNullOrWhiteSpace($StateRoot)){
        Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-host'
    }else{
        [IO.Path]::GetFullPath($StateRoot)
    }
    $configPath=Join-Path $resolvedStateRoot 'CONFIG.json'
    if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){
        throw 'Repository handoff host installation completed without durable CONFIG.json.'
    }

    $taskName='AIDOS Repository Handoff Host'
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    $updated=[ordered]@{}
    foreach($property in $config.PSObject.Properties){$updated[$property.Name]=$property.Value}
    $updated.entry_point=$PSCommandPath
    $updated.bootstrap_entry_point=$PSCommandPath
    $updated.bootstrap_updated_at=[DateTimeOffset]::UtcNow.ToString('o')

    $temporary="$configPath.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        $updated|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $temporary -Encoding utf8NoBOM
        Move-Item -LiteralPath $temporary -Destination $configPath -Force
    }finally{
        if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}
    }

    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
}

$output
