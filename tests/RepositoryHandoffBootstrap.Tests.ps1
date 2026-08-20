[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bootstrapPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'
$hostPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHost.ps1'
$bridgePath=Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1'
$handoffPath=Join-Path $root 'bridge/AidosRepositoryHandoff.psm1'
$gatewayPath=Join-Path $root 'bridge/AidosRepositoryHandoffGateway.psm1'
$text=Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8
$hostText=Get-Content -LiteralPath $hostPath -Raw -Encoding UTF8
$bridgeText=Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8
$handoffText=Get-Content -LiteralPath $handoffPath -Raw -Encoding UTF8
$gatewayText=Get-Content -LiteralPath $gatewayPath -Raw -Encoding UTF8

$script:passed=0
function Assert-Bootstrap([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

Assert-Bootstrap ($text.Contains("`$runtimeHost=Join-Path `$PSScriptRoot ('Invoke-AidosRepositoryHandoffHost.runtime.'")) 'bootstrap materializes a temporary runtime host'
Assert-Bootstrap ($text.Contains("`$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.'")) 'bootstrap materializes a temporary runtime bridge'
Assert-Bootstrap ($text.Contains("`$runtimeHandoffName='AidosRepositoryHandoff.runtime.'")) 'bootstrap materializes a temporary runtime handoff module'
Assert-Bootstrap ($text.Contains("`$runtimeGatewayName='AidosRepositoryHandoffGateway.runtime.'")) 'bootstrap materializes a temporary runtime gateway module'
Assert-Bootstrap ($text.Contains("`$script:AidosWindowsSessionModule=Import-Module")) 'runtime host stores the imported Windows-session module object'
Assert-Bootstrap ($text.Contains("`$updated.entry_point=`$PSCommandPath")) 'successful install persists bootstrap as scheduled-task entrypoint'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeBridge){Remove-Item -LiteralPath `$runtimeBridge -Force}")) 'temporary runtime bridge is removed'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeHandoff){Remove-Item -LiteralPath `$runtimeHandoff -Force}")) 'temporary runtime handoff module is removed'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeGateway){Remove-Item -LiteralPath `$runtimeGateway -Force}")) 'temporary runtime gateway module is removed'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeHost){Remove-Item -LiteralPath `$runtimeHost -Force}")) 'temporary runtime host is removed'

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
Assert-Bootstrap ([regex]::Matches($handoffText,[regex]::Escape($handoffTarget)).Count-eq1) 'canonical handoff has one raw reparse-point link guard'
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
    $explicitLink=(-not[string]::IsNullOrWhiteSpace($linkType)) -or (-not[string]::IsNullOrWhiteSpace($linkTarget))
    $fullName=if($Item.PSObject.Properties['FullName']){[string]$Item.FullName}else{''}
    $wslProviderPath=$fullName.StartsWith('\\wsl.localhost\',[StringComparison]::OrdinalIgnoreCase) -or $fullName.StartsWith('\\wsl$\',[StringComparison]::OrdinalIgnoreCase)
    if($wslProviderPath){return $explicitLink}
    $reparse -or $explicitLink
}
'@
$handoffRuntime=$handoffText.Replace($handoffTarget,$handoffReplacement)
Assert-Bootstrap ($handoffRuntime.Contains("StartsWith('\\wsl.localhost\'")) 'runtime handoff recognizes the WSL localhost provider path'
Assert-Bootstrap ($handoffRuntime.Contains('if($wslProviderPath){return $explicitLink}')) 'runtime handoff ignores provider-only reparse flags but retains explicit link metadata'
$handoffTokens=$null
$handoffErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($handoffRuntime,[ref]$handoffTokens,[ref]$handoffErrors)
Assert-Bootstrap (@($handoffErrors).Count-eq0) ('runtime handoff parses: '+(@($handoffErrors|ForEach-Object Message)-join'; '))

$gatewayTarget='$status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20;$status.heartbeat_at=[DateTimeOffset]::UtcNow.ToString(''o'');Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value $status'
Assert-Bootstrap ([regex]::Matches($gatewayText,[regex]::Escape($gatewayTarget)).Count-eq1) 'canonical gateway has one StrictMode-sensitive heartbeat assignment'
$gatewayReplacement='$status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20;$heartbeat=[DateTimeOffset]::UtcNow.ToString(''o'');if([string]$status.status-ne''RUNNING'' -or [int]$status.pid-ne$PID){$status=[pscustomobject][ordered]@{schema_version=''0.2'';status=''RUNNING'';pid=$PID;listen_prefix=[string]$config.listen_prefix;started_at=$heartbeat;heartbeat_at=$heartbeat}}else{$status|Add-Member -NotePropertyName heartbeat_at -NotePropertyValue $heartbeat -Force};Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value $status'
$gatewayRuntime=$gatewayText.Replace($gatewayTarget,$gatewayReplacement)
Assert-Bootstrap (-not$gatewayRuntime.Contains('$status.heartbeat_at=')) 'runtime gateway removes direct StrictMode heartbeat assignment'
Assert-Bootstrap ($gatewayRuntime.Contains("if([string]`$status.status-ne'RUNNING' -or [int]`$status.pid-ne`$PID)")) 'runtime gateway repairs stale terminal status from a prior instance'
Assert-Bootstrap ($gatewayRuntime.Contains('Add-Member -NotePropertyName heartbeat_at')) 'runtime gateway can add a missing heartbeat property idempotently'
$gatewayTokens=$null
$gatewayErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($gatewayRuntime,[ref]$gatewayTokens,[ref]$gatewayErrors)
Assert-Bootstrap (@($gatewayErrors).Count-eq0) ('runtime gateway parses: '+(@($gatewayErrors|ForEach-Object Message)-join'; '))

$runtimeHandoffName='AidosRepositoryHandoff.runtime.test.psm1'
$runtimeReviewHandoffName='AidosRepositoryReviewHandoff.runtime.test.psm1'
$bridgeRuntime=$bridgeText
Assert-Bootstrap (-not$bridgeText.Contains("Where-Object status -eq'ERROR'")) 'canonical bridge no longer contains the invalid shorthand error filter'
Assert-Bootstrap ([regex]::Matches($bridgeText,[regex]::Escape("Where-Object { `$_.status -eq 'ERROR' }")).Count-ge2) 'canonical bridge contains explicit error-filter scriptblocks'
$bridgeTransforms=[ordered]@{
    '$assignment=$pending.assignment' = '$assignment=$pending'
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRuntimeProjectManager.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot 'AidosRuntimeProjectManager.psm1') -Force -Global -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeHandoffName') -Force -DisableNameChecking"
    "`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -Global -PassThru -DisableNameChecking" = "`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot '$runtimeReviewHandoffName') -Force -Global -PassThru -DisableNameChecking"
}
foreach($pair in $bridgeTransforms.GetEnumerator()){
    $expected=1
    Assert-Bootstrap ([regex]::Matches($bridgeRuntime,[regex]::Escape([string]$pair.Key)).Count-eq$expected) "canonical bridge contains expected runtime target: $($pair.Key)"
    $bridgeRuntime=$bridgeRuntime.Replace([string]$pair.Key,[string]$pair.Value)
}
Assert-Bootstrap (-not$bridgeRuntime.Contains('$assignment=$pending.assignment')) 'runtime bridge removes wrapper-style pending assignment access'
Assert-Bootstrap ($bridgeRuntime.Contains('$assignment=$pending')) 'runtime bridge consumes raw pending assignment records'
Assert-Bootstrap ($bridgeRuntime.Contains("AidosRuntimeProjectManager.psm1') -Force -Global")) 'runtime manager is force-refreshed and exported into bridge-visible session scope'
Assert-Bootstrap ($bridgeRuntime.Contains($runtimeHandoffName)) 'runtime bridge imports the WSL-compatible handoff module'
Assert-Bootstrap ($bridgeRuntime.Contains("`$script:AidosRepositoryReviewHandoffModule=Import-Module (Join-Path `$PSScriptRoot '$runtimeReviewHandoffName') -Force -Global -PassThru")) 'runtime bridge stores the exact temporary review module object'
Assert-Bootstrap ($bridgeRuntime.Contains('& $script:AidosRepositoryReviewHandoffModule {')) 'runtime bridge invokes review publication through the imported module object'
Assert-Bootstrap (-not$bridgeRuntime.Contains('AidosRepositoryReviewHandoff\Publish-AidosRepositoryReviewHandoff')) 'runtime bridge no longer uses the stale canonical review module qualifier'
$bridgeTokens=$null
$bridgeErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($bridgeRuntime,[ref]$bridgeTokens,[ref]$bridgeErrors)
Assert-Bootstrap (@($bridgeErrors).Count-eq0) ('runtime bridge parses: '+(@($bridgeErrors|ForEach-Object Message)-join'; '))

$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.test.psm1'
$runtimeGatewayName='AidosRepositoryHandoffGateway.runtime.test.psm1'
$hostReplacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking" = "`$script:AidosWindowsSessionModule=Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -Force -PassThru -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoffBridge.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeBridgeName') -Force -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoffGateway.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeGatewayName') -Force -DisableNameChecking"
    '$snapshot=Get-AidosInteractiveSessionSnapshot' = '$snapshot=& $script:AidosWindowsSessionModule { Get-AidosInteractiveSessionSnapshot }'
    '$authorization=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser' = '$authorization=& $script:AidosWindowsSessionModule { param($Snapshot,$AuthorizedUser) Test-AidosAuthorizedInteractiveSession -Snapshot $Snapshot -AuthorizedUser $AuthorizedUser } $snapshot $ExpectedUser'
}
$runtimeHost=$hostText
foreach($pair in $hostReplacements.GetEnumerator()){
    $matches=[regex]::Matches($runtimeHost,[regex]::Escape([string]$pair.Key)).Count
    Assert-Bootstrap ($matches-eq1) "canonical host contains one replacement target: $($pair.Key)"
    $runtimeHost=$runtimeHost.Replace([string]$pair.Key,[string]$pair.Value)
}
Assert-Bootstrap ($runtimeHost.Contains($runtimeBridgeName)) 'runtime host imports corrected runtime bridge'
Assert-Bootstrap ($runtimeHost.Contains($runtimeGatewayName)) 'runtime host imports restart-safe runtime gateway'
Assert-Bootstrap ($hostText.Contains('$stop=Stop-AidosRepositoryHostTask')) 'Stop command delegates to the bounded canonical host-stop lifecycle'
Assert-Bootstrap (-not$hostText.Contains("status='STOP_REQUESTED'")) 'Stop command no longer returns before host shutdown completes'
$tokens=$null
$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($runtimeHost,[ref]$tokens,[ref]$errors)
Assert-Bootstrap (@($errors).Count-eq0) ('runtime host parses: '+(@($errors|ForEach-Object Message)-join'; '))


$refreshRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-runtime-manager-refresh-'+[guid]::NewGuid().ToString('N'))
$refreshModulePath=Join-Path $refreshRoot 'AidosRuntimeProjectManager.psm1'
try {
    New-Item -ItemType Directory -Path $refreshRoot -Force|Out-Null
    "function Get-AidosRuntimeManagerRefreshSentinel { 'OLD' }`nExport-ModuleMember -Function Get-AidosRuntimeManagerRefreshSentinel"|Set-Content -LiteralPath $refreshModulePath -Encoding utf8NoBOM
    Import-Module $refreshModulePath -Global -DisableNameChecking
    Assert-Bootstrap ((Get-AidosRuntimeManagerRefreshSentinel) -eq 'OLD') 'runtime manager refresh fixture starts with the preloaded implementation'
    "function Get-AidosRuntimeManagerRefreshSentinel { 'NEW' }`nExport-ModuleMember -Function Get-AidosRuntimeManagerRefreshSentinel"|Set-Content -LiteralPath $refreshModulePath -Encoding utf8NoBOM
    Import-Module $refreshModulePath -Force -Global -DisableNameChecking
    Assert-Bootstrap ((Get-AidosRuntimeManagerRefreshSentinel) -eq 'NEW') 'force-global import replaces a preloaded runtime manager implementation'
} finally {
    Remove-Module AidosRuntimeProjectManager -Force -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $refreshRoot){Remove-Item -LiteralPath $refreshRoot -Recurse -Force}
}

Write-Output "PASS: $passed repository handoff bootstrap assertions"
