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

Assert-Bootstrap ($text.Contains("`$runtimeHost=Join-Path `$PSScriptRoot ('Invoke-AidosRepositoryHandoffHost.runtime.'")) 'bootstrap materializes a temporary runtime host beside the canonical host'
Assert-Bootstrap ($text.Contains("`$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.'")) 'bootstrap materializes a temporary runtime bridge beside the canonical bridge'
Assert-Bootstrap ($text.Contains("`$bridgeTarget='`$assignment=`$pending.assignment'")) 'bootstrap identifies the live pending-assignment shape mismatch exactly'
Assert-Bootstrap ($text.Contains("`$bridgeReplacement='`$assignment=`$pending'")) 'bootstrap corrects pending actor assignment records to the raw runtime contract'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeBridge){Remove-Item -LiteralPath `$runtimeBridge -Force}")) 'temporary runtime bridge is removed after every invocation'
Assert-Bootstrap ($text.Contains("`$output=& `$runtimeHost @PSBoundParameters")) 'bootstrap invokes the runtime copy with the exact operator parameters'
Assert-Bootstrap ($text.Contains("`$script:AidosWindowsSessionModule=Import-Module")) 'runtime host stores the imported Windows-session module object'
Assert-Bootstrap ($text.Contains('-Force -PassThru -DisableNameChecking')) 'runtime module import returns the loaded module object'
Assert-Bootstrap ($text.Contains("`$snapshot=& `$script:AidosWindowsSessionModule { Get-AidosInteractiveSessionSnapshot }")) 'snapshot executes inside the loaded module session state'
Assert-Bootstrap ($text.Contains("`$authorization=& `$script:AidosWindowsSessionModule { param(`$Snapshot,`$AuthorizedUser) Test-AidosAuthorizedInteractiveSession")) 'authorization executes inside the loaded module session state'
Assert-Bootstrap (-not$text.Contains('function global:Get-AidosInteractiveSessionSnapshot')) 'bootstrap does not rely on global proxy command lookup'
Assert-Bootstrap (-not$text.Contains('AidosWindowsSession\Get-AidosInteractiveSessionSnapshot')) 'bootstrap does not rely on module-qualified name lookup'
Assert-Bootstrap ($text.Contains("`$updated.entry_point=`$PSCommandPath")) 'successful install persists bootstrap as scheduled-task entrypoint'
Assert-Bootstrap ($text.Contains("Stop-ScheduledTask -TaskName `$taskName")) 'bootstrap stops the initial runtime-backed task before replacing its durable entrypoint'
Assert-Bootstrap ($text.Contains("Start-ScheduledTask -TaskName `$taskName")) 'bootstrap restarts the task after durable entrypoint replacement'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeHost){Remove-Item -LiteralPath `$runtimeHost -Force}")) 'temporary runtime host is removed after every invocation'

$bridgeTarget='$assignment=$pending.assignment'
Assert-Bootstrap ([regex]::Matches($bridgeText,[regex]::Escape($bridgeTarget)).Count-eq1) 'canonical bridge currently contains exactly one pending-assignment mismatch target'
$bridgeRuntime=$bridgeText.Replace($bridgeTarget,'$assignment=$pending')
Assert-Bootstrap (-not$bridgeRuntime.Contains('$assignment=$pending.assignment')) 'runtime bridge has no wrapper-style pending assignment access'
Assert-Bootstrap ($bridgeRuntime.Contains('$assignment=$pending')) 'runtime bridge consumes raw pending runtime actor assignment records'
$bridgeTokens=$null
$bridgeErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($bridgeRuntime,[ref]$bridgeTokens,[ref]$bridgeErrors)
Assert-Bootstrap (@($bridgeErrors).Count-eq0) ('runtime bridge parses without errors: '+(@($bridgeErrors|ForEach-Object Message)-join'; '))

$runtimeBridgeName='AidosRepositoryHandoffBridge.runtime.test.psm1'
$replacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking" = "`$script:AidosWindowsSessionModule=Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -Force -PassThru -DisableNameChecking"
    "Import-Module (Join-Path `$PSScriptRoot 'AidosRepositoryHandoffBridge.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot '$runtimeBridgeName') -Force -DisableNameChecking"
    '$snapshot=Get-AidosInteractiveSessionSnapshot' = '$snapshot=& $script:AidosWindowsSessionModule { Get-AidosInteractiveSessionSnapshot }'
    '$authorization=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser' = '$authorization=& $script:AidosWindowsSessionModule { param($Snapshot,$AuthorizedUser) Test-AidosAuthorizedInteractiveSession -Snapshot $Snapshot -AuthorizedUser $AuthorizedUser } $snapshot $ExpectedUser'
}
$runtime=$hostText
foreach($pair in $replacements.GetEnumerator()){
    $matches=[regex]::Matches($runtime,[regex]::Escape([string]$pair.Key)).Count
    Assert-Bootstrap ($matches-eq1) "canonical host contains exactly one replacement target: $($pair.Key)"
    $runtime=$runtime.Replace([string]$pair.Key,[string]$pair.Value)
}
Assert-Bootstrap ($runtime.Contains('$script:AidosWindowsSessionModule=Import-Module')) 'runtime host retains loaded module object'
Assert-Bootstrap ($runtime.Contains($runtimeBridgeName)) 'runtime host imports the temporary corrected bridge module'
Assert-Bootstrap ($runtime.Contains('$snapshot=& $script:AidosWindowsSessionModule { Get-AidosInteractiveSessionSnapshot }')) 'runtime host has module-object snapshot invocation'
Assert-Bootstrap ($runtime.Contains('$authorization=& $script:AidosWindowsSessionModule { param($Snapshot,$AuthorizedUser) Test-AidosAuthorizedInteractiveSession')) 'runtime host has module-object authorization invocation'
Assert-Bootstrap (-not$runtime.Contains('$snapshot=Get-AidosInteractiveSessionSnapshot')) 'runtime host has no unqualified snapshot call'
Assert-Bootstrap (-not$runtime.Contains('$authorization=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser')) 'runtime host has no unqualified authorization call'
$tokens=$null
$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($runtime,[ref]$tokens,[ref]$errors)
Assert-Bootstrap (@($errors).Count-eq0) ('module-object runtime host parses without errors: '+(@($errors|ForEach-Object Message)-join'; '))

# Prove the PowerShell mechanism itself: invoking a scriptblock with a PSModuleInfo
# as the call target executes inside that module's session state and can resolve
# its own functions without exported-command or module-name lookup.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-module-object-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $modulePath=Join-Path $temp 'FixtureSession.psm1'
    @'
function Get-FixtureSnapshot { [pscustomobject]@{ value='snapshot' } }
function Test-FixtureAuthorization { param($Snapshot,[string]$User) [pscustomobject]@{ allowed=($Snapshot.value -eq 'snapshot' -and $User -eq 'AIDOS\qvdm') } }
Export-ModuleMember -Function Get-FixtureSnapshot,Test-FixtureAuthorization
'@|Set-Content -LiteralPath $modulePath -Encoding utf8NoBOM
    $module=Import-Module $modulePath -Force -PassThru
    $snapshot=& $module { Get-FixtureSnapshot }
    $authorization=& $module { param($Snapshot,$User) Test-FixtureAuthorization -Snapshot $Snapshot -User $User } $snapshot 'AIDOS\qvdm'
    Assert-Bootstrap ([string]$snapshot.value-eq'snapshot') 'PSModuleInfo invocation executes snapshot function inside module session state'
    Assert-Bootstrap ([bool]$authorization.allowed) 'PSModuleInfo invocation passes arguments to authorization function inside module session state'
}finally{
    Remove-Module FixtureSession -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "PASS: $passed repository handoff bootstrap assertions"
