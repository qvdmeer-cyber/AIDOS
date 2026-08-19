[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bootstrap=Get-Content -LiteralPath (Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1') -Raw -Encoding UTF8

$checks=@(
    @{needle="`$runtimeReviewHandoffName='AidosRepositoryReviewHandoff.runtime.'";message='bootstrap materializes runtime review handoff'},
    @{needle="Import-Module (Join-Path `$PSScriptRoot '`$runtimeActorHandoffName')";message='gateway routes actor dependency through runtime actor module'},
    @{needle="Import-Module (Join-Path `$PSScriptRoot '`$runtimeReviewHandoffName')";message='gateway routes review dependency through runtime review module'},
    @{needle="if(Test-Path -LiteralPath `$runtimeReviewHandoff){Remove-Item -LiteralPath `$runtimeReviewHandoff -Force}";message='runtime review module is cleaned up'}
)

$passed=0
foreach($check in $checks){
    if(-not$bootstrap.Contains([string]$check.needle)){throw "ASSERTION FAILED: $($check.message)"}
    $passed++
}

$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'),[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw ('ASSERTION FAILED: bootstrap parses: '+(@($errors|ForEach-Object Message)-join'; '))}
$passed++

Write-Output "PASS: $passed nested repository handoff runtime routing assertions"
