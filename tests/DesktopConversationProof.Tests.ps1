[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$proofModulePath=Join-Path $root 'bridge/AidosDesktopChatGPTConversationProof.psm1'
Import-Module $proofModulePath -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Proof([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$parent=[pscustomobject]@{id='parent';exact=$false;text_length=6000;depth=8}
$message=[pscustomobject]@{id='message';exact=$true;text_length=64;depth=15}
$rootContainer=[pscustomobject]@{id='root';exact=$false;text_length=50000;depth=2}
$selected=Select-AidosDesktopChatGPTMostSpecificProofCandidate -Candidates @($rootContainer,$parent,$message) -ProofText 'AIDOS_THINKER_TRANSPORT_ENROLLMENT::marker'
Assert-Proof ($selected.id -eq 'message') 'exact message element wins over parent and root containers containing the same proof text'

$short=[pscustomobject]@{id='short';exact=$false;text_length=90;depth=10}
$long=[pscustomobject]@{id='long';exact=$false;text_length=9000;depth=20}
$selected=Select-AidosDesktopChatGPTMostSpecificProofCandidate -Candidates @($long,$short) -ProofText 'marker'
Assert-Proof ($selected.id -eq 'short') 'shortest containing text wins when no exact match exists'

$shallow=[pscustomobject]@{id='shallow';exact=$false;text_length=90;depth=5}
$deep=[pscustomobject]@{id='deep';exact=$false;text_length=90;depth=12}
$selected=Select-AidosDesktopChatGPTMostSpecificProofCandidate -Candidates @($shallow,$deep) -ProofText 'marker'
Assert-Proof ($selected.id -eq 'deep') 'deepest UIA node wins when exactness and text length are equal'

$threw=$false
try{Select-AidosDesktopChatGPTMostSpecificProofCandidate -Candidates @([pscustomobject]@{id='a';exact=$true;text_length=10;depth=4},[pscustomobject]@{id='b';exact=$true;text_length=10;depth=4}) -ProofText 'marker'|Out-Null}catch{$threw=$true}
Assert-Proof $threw 'truly equivalent proof candidates remain fail-closed'

$thinkerModule=Get-Module AidosDesktopThinkerTransport -ErrorAction Stop
$command=& $thinkerModule { Get-Command New-AidosDesktopChatGPTWindowsBackend -ErrorAction Stop }
Assert-Proof ($command.Source -eq 'AidosDesktopChatGPTWindowDiscovery') 'Thinker module scope resolves the resilient backend wrapper after the base Desktop ChatGPT module'

$proofSource=Get-Content -LiteralPath $proofModulePath -Raw -Encoding UTF8
$backendStart=$proofSource.IndexOf('function New-AidosDesktopChatGPTResilientConversationBackend',[StringComparison]::Ordinal)
$backendText=$proofSource.Substring($backendStart)
Assert-Proof ($backendText.IndexOf('Get-AidosDesktopChatGPTDocumentConversationProof',[StringComparison]::Ordinal) -ge 0) 'live resilient backend uses document-root conversation proof'
Assert-Proof ($backendText.IndexOf('.FindAll(',[StringComparison]::Ordinal) -lt 0) 'live resilient backend does not enumerate the full Chromium UIA subtree'

Write-Output "PASS: $passed resilient conversation proof assertions"
