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
$handoffOriginal=Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1'
$actorHandoffOriginal=Join-Path $PSScriptRoot 'AidosRepositoryActorHandoff.psm1'
$reviewHandoffOriginal=Join-Path $PSScriptRoot 'AidosRepositoryReviewHandoff.psm1'
$gatewayOriginal=Join-Path $PSScriptRoot 'AidosRepositoryHandoffGateway.psm1'
if(-not(Test-Path -LiteralPath $original -PathType Leaf)){throw "Repository handoff host entrypoint is unavailable: $original"}
if(-not(Test-Path -LiteralPath $bridgeOriginal -PathType Leaf)){throw "Repository handoff bridge module is unavailable: $bridgeOriginal"}
if(-not(Test-Path -LiteralPath $handoffOriginal -PathType Leaf)){throw "Repository handoff module is unavailable: $handoffOriginal"}
if(-not(Test-Path -LiteralPath $actorHandoffOriginal -PathType Leaf)){throw "Repository actor handoff module is unavailable: $actorHandoffOriginal"}
if(-not(Test-Path -LiteralPath $reviewHandoffOriginal -PathType Leaf)){throw "Repository review handoff module is unavailable: $reviewHandoffOriginal"}
if(-not(Test-Path -LiteralPath $gatewayOriginal -PathType Leaf)){throw "Repository handoff gateway module is unavailable: $gatewayOriginal"}

# The operator machine has proven that both unqualified command lookup and
# module-qualified lookup are unreliable for modules loaded from this UNC/WSL
# path. Materialize temporary runtime copies beside the canonical modules.
#
# The Windows WSL provider can report ordinary repository items as LinkType=HardLink
# without any LinkTarget/Target. Treat that specific provider-only shape as
# ordinary content while still rejecting real targets and other explicit link
# types. On normal Windows paths retain the conservative ReparsePoint check.
$handoffSource=Get-Content -LiteralPath $handoffOriginal -Raw -Encoding UTF8
$handoffTarget=@'
function Test-AidosRepositoryPathItemIsLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item)
    $reparse=(($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    $linkType=$null
    if($Item.PSObject.Properties['LinkType']){$linkType=[string]$Item.LinkType}
    $reparse -or -not[string]::IsNullOrWhiteSpace($linkType)
}
'@
$handoffReplacement=@'
function Test-AidosRepositoryPathItemIsLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item)
    $reparse=(($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    $linkType=$null
    if($Item.PSObject.Properties['LinkType']){$linkType=[string]$Item.LinkType}
    $linkTarget=$null
    if($Item.PSObject.Properties['LinkTarget']){$linkTarget=[string]$Item.LinkTarget}
    elseif($Item.PSObject.Properties['Target']){$linkTarget=[string]$Item.Target}
    $hasLinkType=-not[string]::IsNullOrWhiteSpace($linkType)
    $hasLinkTarget=-not[string]::IsNullOrWhiteSpace($linkTarget)
    $fullName=if($Item.PSObject.Properties['FullName']){[string]$Item.FullName}else{''}
    $wslProviderPath=$fullName.StartsWith('\\wsl.localhost\',[StringComparison]::OrdinalIgnoreCase) -or $fullName.StartsWith('\\wsl$\',[StringComparison]::OrdinalIgnoreCase)
    if($wslProviderPath){
        $providerOnlyHardLink=[string]::Equals($linkType,'HardLink',[StringComparison]::OrdinalIgnoreCase) -and -not$hasLinkTarget
        return $hasLinkTarget -or ($hasLinkType -and -not$providerOnlyHardLink)
    }
    $reparse -or $hasLinkType -or $hasLinkTarget
}
'@
$handoffMatches=[regex]::Matches($handoffSource,[regex]::Escape($handoffTarget)).Count
if($handoffMatches-ne1){throw "Repository host bootstrap expected exactly one repository-link guard source match; found $handoffMatches."}
$handoffSource=$handoffSource.Replace($handoffTarget,$handoffReplacement)

$runtimeHandoffName='AidosRepositoryHandoff.runtime.'+[guid]::NewGuid().ToString('N')+'.psm1'
$runtimeHandoff=Join-Path $PSScriptRoot $runtimeHandoffName
$runtimeHandoffBytes=[Text.UTF8Encoding]::new($false).GetBytes($handoffSource)
$runtimeHandoffStream=[IO.FileStream]::new($runtimeHandoff,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$runtimeHandoffStream.Write($runtimeHandoffBytes,0,$runtimeHandoffBytes.Length);$runtimeHandoffStream.Flush($true)}finally{$runtimeHandoffStream.Dispose()}

# Actor publication imports its own handoff module. Route that nested dependency
# through the same WSL-safe runtime handoff module or it bypasses the validator
# used directly by the bridge and gateway.
$actorHandoffSource=Get-Content -LiteralPath $actorHandoffOriginal -Raw -Encoding UTF8
$actorHandoffTarget="Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking"
$actorHandoffReplacement="Import-Module (Join-Path `$PSScriptRoot '$runtimeHandoffName') -Force -DisableNameChecking"
$actorHandoffMatches=[regex]::Matches($actorHandoffSource,[regex]::Escape($actorHandoffTarget)).Count
if($actorHandoffMatches-ne1){throw "Repository host bootstrap expected exactly one actor-handoff dependency match; found $actorHandoffMatches."}
$actorHandoffSource=$actorHandoffSource.Replace($actorHandoffTarget,$actorHandoffReplacement)
$runtimeActorHandoffName='AidosRepositoryActorHandoff.runtime.'+[guid]::NewGuid().ToString('N')+'.psm1'
$runtimeActorHandoff=Join-Path $PSScriptRoot $runtimeActorHandoffName
$runtimeActorHandoffBytes=[Text.UTF8Encoding]::new($false).GetBytes($actorHandoffSource)
$runtimeActorHandoffStream=[IO.FileStream]::new($runtimeActorHandoff,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$runtimeActorHandoffStream.Write($runtimeActorHandoffBytes,0,$runtimeActorHandoffBytes.Length);$runtimeActorHandoffStream.Flush($true)}finally{$runtimeActorHandoffStream.Dispose()}

# Review publication also imports the canonical handoff module. Give it the same
# WSL-safe dependency so review reads and writes cannot reintroduce the provider
# false-positive into gateway or bridge module scope.
$reviewHandoffSource=Get-Content -LiteralPath $reviewHandoffOriginal -Raw -Encoding UTF8
$reviewHandoffTarget="Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking"
$reviewHandoffReplacement="Import-Module (Join-Path `$PSScriptRoot '$runtimeHandoffName') -Force -DisableNameChecking"
$reviewHandoffMatches=[regex]::Matches($reviewHandoffSource,[regex]::Escape($reviewHandoffTarget)).Count
if($reviewHandoffMatches-ne1){throw "Repository host bootstrap expected exactly one review-handoff dependency match; found $reviewHandoffMatches."}
$reviewHandoffSource=$reviewHandoffSource.Replace($reviewHandoffTarget,$reviewHandoffReplacement)
$runtimeReviewHandoffName='AidosRepositoryReviewHandoff.runtime.'+[guid]::NewGuid().ToString('N')+'.psm1'
$runtimeReviewHandoff=Join-Path $PSScriptRoot $runtimeReviewHandoffName
$runtimeReviewHandoffBytes=[Text.UTF8Encoding]::new($false).GetBytes($reviewHandoffSource)
$runtimeReviewHandoffStream=[IO.FileStream]::new($runtimeReviewHandoff,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$runtimeReviewHandoffStream.Write($runtimeReviewHandoffBytes,0,$runtimeReviewHandoffBytes.Length);$runtimeReviewHandoffStream.Flush($true)}finally{$runtimeReviewHandoffStream.Dispose()}

# A previous gateway instance may publish terminal STOPPED state after a new
# instance has already started. Route every nested repository handoff dependency
# through the same WSL-safe runtime modules.
$gatewaySource=Get-Content -LiteralPath $gatewayOriginal -Raw -Encoding UTF8
$gatewayReplacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeHandoffName') -Force -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryActorHandoff.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeActorHandoffName') -Force -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeReviewHandoffName') -Force -DisableNameChecking"
}
foreach($pair in $gatewayReplacements.GetEnumerator()){
    $matches=[regex]::Matches($gatewaySource,[regex]::Escape([string]$pair.Key)).Count
    if($matches-ne1){throw "Repository host bootstrap expected exactly one gateway dependency match for: $($pair.Key); found $matches."}
    $gatewaySource=$gatewaySource.Replace([string]$pair.Key,[string]$pair.Value)
}
$gatewayTarget='$status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20;$status.heartbeat_at=[DateTimeOffset]::UtcNow.ToString(''o'');Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value $status'
$gatewayReplacement='$status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20;$heartbeat=[DateTimeOffset]::UtcNow.ToString(''o'');if([string]$status.status-ne''RUNNING'' -or [int]$status.pid-ne$PID){$status=[pscustomobject][ordered]@{schema_version=''0.2'';status=''RUNNING'';pid=$PID;listen_prefix=[string]$config.listen_prefix;started_at=$heartbeat;heartbeat_at=$heartbeat}}else{$status|Add-Member -NotePropertyName heartbeat_at -NotePropertyValue $heartbeat -Force};Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value $status'
$gatewayMatches=[regex]::Matches($gatewaySource,[regex]::Escape($gatewayTarget)).Count
if($gatewayMatches-ne1){throw "Repository host bootstrap expected exactly one gateway heartbeat source match; found $gatewayMatches."}
$gatewaySource=$gatewaySource.Replace($gatewayTarget,$gatewayReplacement)
$runtimeGatewayName='AidosRepositoryHandoffGateway.runtime.'+[guid]::NewGuid().ToString('N')+'.psm1'
$runtimeGateway=Join-Path $PSScriptRoot $runtimeGatewayName
$runtimeGatewayBytes=[Text.UTF8Encoding]::new($false).GetBytes($gatewaySource)
$runtimeGatewayStream=[IO.FileStream]::new($runtimeGateway,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$runtimeGatewayStream.Write($runtimeGatewayBytes,0,$runtimeGatewayBytes.Length);$runtimeGatewayStream.Flush($true)}finally{$runtimeGatewayStream.Dispose()}

# Correct the remaining bridge-specific runtime boundaries.
$bridgeSource=Get-Content -LiteralPath $bridgeOriginal -Raw -Encoding UTF8
$bridgeReplacements=[ordered]@{
    '$assignment=$pending.assignment' = '$assignment=$pending'
    "Where-Object status -eq'ERROR'" = "Where-Object { `$_.status -eq 'ERROR' }"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRuntimeProjectManager.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot 'AidosRuntimeProjectManager.psm1') -Global -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeHandoffName') -Force -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryActorHandoff.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeActorHandoffName') -Force -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -Global -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeReviewHandoffName') -Force -Global -DisableNameChecking"
}
foreach($pair in $bridgeReplacements.GetEnumerator()){
    $matches=[regex]::Matches($bridgeSource,[regex]::Escape([string]$pair.Key)).Count
    $expected=if([string]$pair.Key -eq "Where-Object status -eq'ERROR'"){2}else{1}
    if($matches-ne$expected){throw "Repository host bootstrap expected $expected bridge source match(es) for: $($pair.Key); found $matches."}
    $bridgeSource=$bridgeSource.Replace([string]$pair.Key,[string]$pair.Value)
}
$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.'+[guid]::NewGuid().ToString('N')+'.psm1'
$runtimeBridge=Join-Path $PSScriptRoot $runtimeBridgeName
$runtimeBridgeBytes=[Text.UTF8Encoding]::new($false).GetBytes($bridgeSource)
$runtimeBridgeStream=[IO.FileStream]::new($runtimeBridge,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$runtimeBridgeStream.Write($runtimeBridgeBytes,0,$runtimeBridgeBytes.Length);$runtimeBridgeStream.Flush($true)}finally{$runtimeBridgeStream.Dispose()}

$source=Get-Content -LiteralPath $original -Raw -Encoding UTF8
$replacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking" = "`$script:AidosWindowsSessionModule=Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -Force -PassThru -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoffBridge.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeBridgeName') -Force -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoffGateway.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeGatewayName') -Force -DisableNameChecking"
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
try{$runtimeStream.Write($runtimeBytes,0,$runtimeBytes.Length);$runtimeStream.Flush($true)}finally{$runtimeStream.Dispose()}

try{
    $output=& $runtimeHost @PSBoundParameters
    if($Command-eq'Install'){
        $resolvedStateRoot=if([string]::IsNullOrWhiteSpace($StateRoot)){Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-host'}else{[IO.Path]::GetFullPath($StateRoot)}
        $configPath=Join-Path $resolvedStateRoot 'CONFIG.json'
        if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw 'Repository handoff host installation completed without durable CONFIG.json.'}
        $taskName='AIDOS Repository Handoff Host'
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
        $updated=[ordered]@{}
        foreach($property in $config.PSObject.Properties){$updated[$property.Name]=$property.Value}
        $updated.entry_point=$PSCommandPath
        $updated.bootstrap_entry_point=$PSCommandPath
        $updated.bootstrap_updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        $temporary="$configPath.$([guid]::NewGuid().ToString('N')).tmp"
        try{$updated|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $temporary -Encoding utf8NoBOM;Move-Item -LiteralPath $temporary -Destination $configPath -Force}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
    }
    $output
}finally{
    if(Test-Path -LiteralPath $runtimeHost){Remove-Item -LiteralPath $runtimeHost -Force}
    if(Test-Path -LiteralPath $runtimeBridge){Remove-Item -LiteralPath $runtimeBridge -Force}
    if(Test-Path -LiteralPath $runtimeReviewHandoff){Remove-Item -LiteralPath $runtimeReviewHandoff -Force}
    if(Test-Path -LiteralPath $runtimeActorHandoff){Remove-Item -LiteralPath $runtimeActorHandoff -Force}
    if(Test-Path -LiteralPath $runtimeHandoff){Remove-Item -LiteralPath $runtimeHandoff -Force}
    if(Test-Path -LiteralPath $runtimeGateway){Remove-Item -LiteralPath $runtimeGateway -Force}
}
