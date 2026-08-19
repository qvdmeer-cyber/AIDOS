[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$windowDiscoveryPath=Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.psm1'
$thinkerTransportPath=Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1'

$windowDiscovery=Import-Module $windowDiscoveryPath -Force -PassThru -DisableNameChecking
foreach($name in @(
    'Get-AidosDesktopChatGPTResilientProcessContext',
    'Get-AidosDesktopChatGPTResolvedActorResponseText',
    'New-AidosDesktopChatGPTResilientWindowsBackend',
    'New-AidosDesktopChatGPTWindowsBackend'
)){
    if($null-eq$windowDiscovery.ExportedCommands[$name]){throw "ASSERTION FAILED: WindowDiscovery export '$name' is unavailable."}
}

$thinkerTransport=Import-Module $thinkerTransportPath -Force -PassThru -DisableNameChecking
if($null-eq$thinkerTransport){throw 'ASSERTION FAILED: Thinker transport module did not import.'}

Write-Output 'PASS: Desktop WindowDiscovery module exports are visible to Thinker transport.'
