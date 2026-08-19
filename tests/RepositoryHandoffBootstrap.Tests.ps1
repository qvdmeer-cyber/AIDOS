[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bootstrapPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'
$hostPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHost.ps1'
$text=Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8
$host=Get-Content -LiteralPath $hostPath -Raw -Encoding UTF8

$script:passed=0
function Assert-Bootstrap([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

Assert-Bootstrap ($text.Contains("`$runtimeHost=Join-Path `$PSScriptRoot ('Invoke-AidosRepositoryHandoffHost.runtime.'")) 'bootstrap materializes a temporary runtime host beside the canonical host'
Assert-Bootstrap ($text.Contains("`$output=& `$runtimeHost @PSBoundParameters")) 'bootstrap invokes the runtime copy with the exact operator parameters'
Assert-Bootstrap (-not$text.Contains('function global:Get-AidosInteractiveSessionSnapshot')) 'bootstrap no longer relies on global proxy command lookup'
Assert-Bootstrap (-not$text.Contains('function global:Test-AidosAuthorizedInteractiveSession')) 'bootstrap no longer relies on global authorization proxy lookup'
Assert-Bootstrap ($text.Contains("`$updated.entry_point=`$PSCommandPath")) 'successful install persists bootstrap as scheduled-task entrypoint'
Assert-Bootstrap ($text.Contains("Stop-ScheduledTask -TaskName `$taskName")) 'bootstrap stops the initial runtime-backed task before replacing its durable entrypoint'
Assert-Bootstrap ($text.Contains("Start-ScheduledTask -TaskName `$taskName")) 'bootstrap restarts the task after durable entrypoint replacement'
Assert-Bootstrap ($text.Contains("if(Test-Path -LiteralPath `$runtimeHost){Remove-Item -LiteralPath `$runtimeHost -Force}")) 'temporary runtime host is removed after every invocation'

$replacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -Force -Global -DisableNameChecking"
    '$snapshot=Get-AidosInteractiveSessionSnapshot' = '$snapshot=AidosWindowsSession\Get-AidosInteractiveSessionSnapshot'
    '$authorization=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser' = '$authorization=AidosWindowsSession\Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser'
}
$runtime=$host
foreach($pair in $replacements.GetEnumerator()){
    $matches=[regex]::Matches($runtime,[regex]::Escape([string]$pair.Key)).Count
    Assert-Bootstrap ($matches-eq1) "canonical host contains exactly one replacement target: $($pair.Key)"
    $runtime=$runtime.Replace([string]$pair.Key,[string]$pair.Value)
}
Assert-Bootstrap ($runtime.Contains('AidosWindowsSession\Get-AidosInteractiveSessionSnapshot')) 'runtime host uses module-qualified snapshot command'
Assert-Bootstrap ($runtime.Contains('AidosWindowsSession\Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser')) 'runtime host uses module-qualified authorization command'
Assert-Bootstrap (-not$runtime.Contains('$snapshot=Get-AidosInteractiveSessionSnapshot')) 'runtime host has no unqualified snapshot call'
Assert-Bootstrap (-not$runtime.Contains('$authorization=Test-AidosAuthorizedInteractiveSession -Snapshot $snapshot -AuthorizedUser $ExpectedUser')) 'runtime host has no unqualified authorization call'
$tokens=$null
$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($runtime,[ref]$tokens,[ref]$errors)
Assert-Bootstrap (@($errors).Count-eq0) ('module-qualified runtime host parses without errors: '+(@($errors|ForEach-Object Message)-join'; '))

Write-Output "PASS: $passed repository handoff bootstrap assertions"
