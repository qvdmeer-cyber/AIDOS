[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bootstrapPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'
$hostPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHost.ps1'
$bridgePath=Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1'
$text=Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8
$hostText=Get-Content -LiteralPath $hostPath -Raw -Encoding UTF8
$bridgeText=Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8

$script:passed=0
function Assert-Bootstrap([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

Assert-Bootstrap ($text.Contains("`$runtimeHost=Join-Path `$PSScriptRoot ('Invoke-AidosRepositoryHandoffHost.runtime.'")) 'bootstrap materializes a temporary runtime host'
Assert-Bootstrap ($text.Contains("`$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.'")) 'bootstrap materializes a temporary runtime bridge'
Assert-Bootstrap ($text.Contains("`$script:AidosWindowsSessionModule=Import-Module")) 'runtime host stores the imported Windows-session module object'
Assert-Bootstrap ($text.Contains("`$updated.entry_point=`$PSCommandPath")) 'successful install persists bootstrap as scheduled-task entrypoint'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeBridge){Remove-Item -LiteralPath `$runtimeBridge -Force}")) 'temporary runtime bridge is removed'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeHost){Remove-Item -LiteralPath `$runtimeHost -Force}")) 'temporary runtime host is removed'

$bridgeRuntime=$bridgeText
$assignmentTarget='$assignment=$pending.assignment'
Assert-Bootstrap ([regex]::Matches($bridgeRuntime,[regex]::Escape($assignmentTarget)).Count-eq1) 'canonical bridge has one wrapper-style pending assignment target'
$bridgeRuntime=$bridgeRuntime.Replace($assignmentTarget,'$assignment=$pending')

$whereTarget="Where-Object status -eq'ERROR'"
Assert-Bootstrap ([regex]::Matches($bridgeRuntime,[regex]::Escape($whereTarget)).Count-eq2) 'canonical bridge has two fragile error predicates'
$whereReplacement="Where-Object { `$_.status -eq 'ERROR' }"
$bridgeRuntime=$bridgeRuntime.Replace($whereTarget,$whereReplacement)

Assert-Bootstrap (-not$bridgeRuntime.Contains('$assignment=$pending.assignment')) 'runtime bridge removes wrapper-style pending assignment access'
Assert-Bootstrap ($bridgeRuntime.Contains('$assignment=$pending')) 'runtime bridge consumes raw pending assignment records'
Assert-Bootstrap (-not$bridgeRuntime.Contains($whereTarget)) 'runtime bridge removes fragile Where-Object property syntax'
Assert-Bootstrap ([regex]::Matches($bridgeRuntime,[regex]::Escape($whereReplacement)).Count-eq2) 'runtime bridge uses explicit predicates for both error collections'

$bridgeTokens=$null
$bridgeErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($bridgeRuntime,[ref]$bridgeTokens,[ref]$bridgeErrors)
Assert-Bootstrap (@($bridgeErrors).Count-eq0) ('runtime bridge parses: '+(@($bridgeErrors|ForEach-Object Message)-join'; '))

$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.test.psm1'
$hostReplacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking" = "`$script:AidosWindowsSessionModule=Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -Force -PassThru -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoffBridge.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeBridgeName') -Force -DisableNameChecking"
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
$tokens=$null
$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($runtimeHost,[ref]$tokens,[ref]$errors)
Assert-Bootstrap (@($errors).Count-eq0) ('runtime host parses: '+(@($errors|ForEach-Object Message)-join'; '))

Write-Output "PASS: $passed repository handoff bootstrap assertions"
