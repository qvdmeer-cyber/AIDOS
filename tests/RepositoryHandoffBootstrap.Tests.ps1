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

Assert-Bootstrap ($text.Contains("Import-Module `$sessionModule -Force -Global -DisableNameChecking")) 'bootstrap imports Windows session commands into global runspace scope'
Assert-Bootstrap ($text.Contains("`$output=& `$original @PSBoundParameters")) 'bootstrap forwards the exact host command parameters'
Assert-Bootstrap ($text.Contains("`$updated.entry_point=`$PSCommandPath")) 'successful install persists bootstrap as scheduled-task entrypoint'
Assert-Bootstrap ($text.Contains("Stop-ScheduledTask -TaskName `$taskName")) 'bootstrap stops the just-created task before replacing its entrypoint'
Assert-Bootstrap ($text.Contains("Start-ScheduledTask -TaskName `$taskName")) 'bootstrap restarts the task after durable entrypoint replacement'

Write-Output "PASS: $passed repository handoff bootstrap assertions"
