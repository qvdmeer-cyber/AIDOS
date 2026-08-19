[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8

$script:passed=0
function Assert-Bootstrap([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

Assert-Bootstrap ($text.Contains("Import-Module `$sessionModule -Force -Global -DisableNameChecking")) 'bootstrap imports Windows session module into the runspace'
Assert-Bootstrap ($text.Contains("Get-Command 'AidosWindowsSession\Get-AidosInteractiveSessionSnapshot' -ErrorAction Stop")) 'bootstrap proves module-qualified session snapshot export exists'
Assert-Bootstrap ($text.Contains("Get-Command 'AidosWindowsSession\Test-AidosAuthorizedInteractiveSession' -ErrorAction Stop")) 'bootstrap proves module-qualified authorization export exists'
Assert-Bootstrap ($text.Contains('function global:Get-AidosInteractiveSessionSnapshot')) 'bootstrap publishes explicit global snapshot proxy'
Assert-Bootstrap ($text.Contains('AidosWindowsSession\Get-AidosInteractiveSessionSnapshot')) 'snapshot proxy invokes module-qualified command'
Assert-Bootstrap ($text.Contains('function global:Test-AidosAuthorizedInteractiveSession')) 'bootstrap publishes explicit global authorization proxy'
Assert-Bootstrap ($text.Contains('AidosWindowsSession\Test-AidosAuthorizedInteractiveSession -Snapshot $Snapshot -AuthorizedUser $AuthorizedUser -Policy $Policy')) 'authorization proxy preserves exact parameters'
Assert-Bootstrap ($text.Contains("`$output=. `$original @PSBoundParameters")) 'bootstrap dot-sources the canonical host with exact parameters in the same scope'
Assert-Bootstrap (-not$text.Contains("`$output=& `$original @PSBoundParameters")) 'bootstrap does not invoke the host in an isolated child script scope'
Assert-Bootstrap ($text.Contains("`$updated.entry_point=`$PSCommandPath")) 'successful install persists bootstrap as scheduled-task entrypoint'
Assert-Bootstrap ($text.Contains("Stop-ScheduledTask -TaskName `$taskName")) 'bootstrap stops the just-created task before replacing its entrypoint'
Assert-Bootstrap ($text.Contains("Start-ScheduledTask -TaskName `$taskName")) 'bootstrap restarts the task after durable entrypoint replacement'

Write-Output "PASS: $passed repository handoff bootstrap assertions"
