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
$bridgeOriginal=Join-Path $PSScriptRoot 'AidosRepositoryHandoffBridge.psm1'
if(-not(Test-Path -LiteralPath $original -PathType Leaf)){throw "Repository handoff host entrypoint is unavailable: $original"}
if(-not(Test-Path -LiteralPath $bridgeOriginal -PathType Leaf)){throw "Repository handoff bridge module is unavailable: $bridgeOriginal"}

# The operator machine has proven that both unqualified command lookup and
# module-qualified lookup are unreliable for a module loaded from this UNC/WSL
# path. Materialize one temporary runtime host beside the canonical host and
# hold the imported Windows-session module as an object. Invoke the required
# functions inside that module object's own session state; no module-name or
# exported-function lookup is then required at call time.
#
# The live bridge also exposed an integration mismatch: pending runtime actor
# enumeration returns raw RUNTIME_ACTOR_ASSIGNMENT records, while the new
# repository bridge expected a wrapper with `.assignment`. Keep the canonical
# source immutable here, but materialize a runtime bridge copy with the exact
# contract correction until the bridge source itself is consolidated.
$bridgeSource=Get-Content -LiteralPath $bridgeOriginal -Raw -Encoding UTF8
$bridgeTarget='$assignment=$pending.assignment'
$bridgeReplacement='$assignment=$pending'
$bridgeMatches=[regex]::Matches($bridgeSource,[regex]::Escape($bridgeTarget)).Count
if($bridgeMatches-ne1){throw "Repository host bootstrap expected exactly one pending-assignment bridge source match; found $bridgeMatches."}
$bridgeSource=$bridgeSource.Replace($bridgeTarget,$bridgeReplacement)

$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.'+[guid]::NewGuid().ToString('N')+'.psm1'
$runtimeBridge=Join-Path $PSScriptRoot $runtimeBridgeName
$runtimeBridgeBytes=[Text.UTF8Encoding]::new($false).GetBytes($bridgeSource)
$runtimeBridgeStream=[IO.FileStream]::new($runtimeBridge,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
    $runtimeBridgeStream.Write($runtimeBridgeBytes,0,$runtimeBridgeBytes.Length)
    $runtimeBridgeStream.Flush($true)
}finally{
    $runtimeBridgeStream.Dispose()
}

$source=Get-Content -LiteralPath $original -Raw -Encoding UTF8
$replacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking" = "`$script:AidosWindowsSessionModule=Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -Force -PassThru -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoffBridge.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeBridgeName') -Force -DisableNameChecking"
    '$snapshot=Get-AidosInteractiveSessionSnapshot' = '$snapshot=& $script:AidosWindowsSessionModule { Get-AidosInteractiveSessionSnapshot }'
    '$authorization=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser' = '$authorization=& $script:AidosWindowsSessionModule { param($Snapshot,$AuthorizedUser) Test-AidosAuthorizedInteractiveSession -Snapshot $Snapshot -AuthorizedUser $AuthorizedUser } $snapshot $ExpectedUser'
}
foreach($pair in $replacements.GetEnumerator()){
    $matches=[regex]::Matches($source,[regex]::Escape([string]$pair.Key)).Count
    if($matches-ne1){throw "Repository host bootstrap expected exactly one source match for: $($pair.Key); found $matches."}
    $source=$source.Replace([string]$pair.Key,[string]$pair.Value)
}

$runtimeHost=Join-Path $PSScriptRoot ('Invoke-AidosRepositoryHandoffHost.runtime.'+[guid]::NewGuid().ToString('N')+'.ps1')
$runtimeBytes=[Text.UTF8Encoding]::new($false).GetBytes($source)
$runtimeStream=[IO.FileStream]::new($runtimeHost,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
    $runtimeStream.Write($runtimeBytes,0,$runtimeBytes.Length)
    $runtimeStream.Flush($true)
}finally{
    $runtimeStream.Dispose()
}

try{
    $output=& $runtimeHost @PSBoundParameters

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

        # The canonical installer initially persists its own runtime path and
        # starts the task. Stop that task while the temporary runtime copies
        # still exist, atomically replace the durable entrypoint with this
        # bootstrap, then restart. Every later host/bridge/gateway command
        # therefore passes through the same runtime materialization.
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
}finally{
    if(Test-Path -LiteralPath $runtimeHost){Remove-Item -LiteralPath $runtimeHost -Force}
    if(Test-Path -LiteralPath $runtimeBridge){Remove-Item -LiteralPath $runtimeBridge -Force}
}
