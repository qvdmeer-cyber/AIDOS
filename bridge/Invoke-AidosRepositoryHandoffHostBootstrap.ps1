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

# The canonical host defines its command helpers in script scope. Dot-source it
# into this bootstrap scope after globally importing the session commands, so
# both operator invocations and later scheduled-task runs resolve the exported
# Windows-session functions deterministically.
Import-Module $sessionModule -Force -Global -DisableNameChecking

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
