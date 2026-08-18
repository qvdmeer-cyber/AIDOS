[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Discovery([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$context=[pscustomobject][ordered]@{present=$true;process_id=42;process_name='ChatGPT Classic';session_id=1;main_window_handle='0';window_handle='123';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$true;window_is_visible=$true;window_source='EnumWindowsFallback';usable_application_window=$true}
$resolved=Get-AidosDesktopChatGPTResilientProcessContext -ProcessName 'ChatGPT Classic' -PrimaryResolver {param($name);throw 'primary missing MainWindowHandle'} -FallbackResolver {param($name);$context}
Assert-Discovery ($resolved.window_source -eq 'EnumWindowsFallback' -and $resolved.window_handle -eq '123') 'one exact fallback candidate recovers primary MainWindowHandle failure'

$threw=$false
try{Get-AidosDesktopChatGPTResilientProcessContext -ProcessName 'ChatGPT Classic' -PrimaryResolver {param($name);throw 'primary unavailable'} -FallbackResolver {param($name);@()}|Out-Null}catch{$threw=$true}
Assert-Discovery $threw 'zero fallback candidates fail closed'

$second=$context|Select-Object *;$second.window_handle='456'
$threw=$false
try{Get-AidosDesktopChatGPTResilientProcessContext -ProcessName 'ChatGPT Classic' -PrimaryResolver {param($name);throw 'primary unavailable'} -FallbackResolver {param($name);@($context,$second)}|Out-Null}catch{$threw=$true}
Assert-Discovery $threw 'multiple fallback candidates fail closed'

$hostText=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosPersistentLocalDesktopAgent.psm1') -Raw
$thinkerText=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1') -Raw
Assert-Discovery ($hostText -match 'ResilientProcessContextCommand=.*ExportedCommands\[''Get-AidosDesktopChatGPTResilientProcessContext''\]' -and $hostText -match '& \$script:ResilientProcessContextCommand') 'host shell health binds the exact exported resilient discovery command'
Assert-Discovery ($thinkerText -match 'New-AidosDesktopThinkerWindowsBackend' -and $thinkerText -match 'ResilientProcessContextCommand=.*ExportedCommands\[''Get-AidosDesktopChatGPTResilientProcessContext''\]' -and $thinkerText -match '& \$resilientProcessContext') 'Thinker transport backend binds the exact exported resilient discovery command'

Write-Output "PASS: $passed resilient Desktop ChatGPT discovery assertions"
