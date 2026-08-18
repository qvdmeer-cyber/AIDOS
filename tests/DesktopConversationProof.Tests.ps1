[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$proofModulePath=Join-Path $root 'bridge/AidosDesktopChatGPTConversationProof.psm1'
$windowModulePath=[IO.Path]::GetFullPath((Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.psm1'))
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

$windowModule=@(Get-Module AidosDesktopChatGPTWindowDiscovery -All -ErrorAction Stop|Where-Object {[IO.Path]::GetFullPath([string]$_.Path) -eq $windowModulePath}|Select-Object -Last 1)[0]
Assert-Proof ($null-ne$windowModule) 'exact window-discovery module instance is loaded from the expected path'
$shim=$windowModule.ExportedCommands['New-AidosDesktopChatGPTWindowsBackend']
$resilient=$windowModule.ExportedCommands['New-AidosDesktopChatGPTResilientWindowsBackend']
$base=$windowModule.SessionState.PSVariable.GetValue('BaseDesktopChatGPTWindowsBackendCommand')
Assert-Proof ($null-ne$shim) 'window-discovery module exports the compatibility shim used by existing Thinker callers'
Assert-Proof ($null-ne$resilient) 'window-discovery module exports the uniquely named resilient backend factory'
Assert-Proof ($null-ne$base) 'window-discovery module retains an exact captured base backend command'
Assert-Proof ($base.Source -eq 'AidosDesktopChatGPT') 'resilient wrapper captures base backend from the exact AidosDesktopChatGPT module instance'
Assert-Proof ($base.Name -eq 'New-AidosDesktopChatGPTWindowsBackend') 'captured base command is the original Windows backend factory'
Assert-Proof ($shim.Source -eq 'AidosDesktopChatGPTWindowDiscovery') 'compatibility shim belongs to the window-discovery module'
Assert-Proof ($resilient.Source -eq 'AidosDesktopChatGPTWindowDiscovery') 'uniquely named resilient factory belongs to the window-discovery module'
Assert-Proof (-not [object]::ReferenceEquals($shim,$base)) 'compatibility shim is not the captured base command object'

$proofSource=Get-Content -LiteralPath $proofModulePath -Raw -Encoding UTF8
$backendStart=$proofSource.IndexOf('function New-AidosDesktopChatGPTResilientConversationBackend',[StringComparison]::Ordinal)
$backendText=$proofSource.Substring($backendStart)
Assert-Proof ($backendText.IndexOf('$resilientConversationProof=Get-Command Get-AidosDesktopChatGPTResilientConversationProof',[StringComparison]::Ordinal) -ge 0 -and $backendText.IndexOf('& $resilientConversationProof',[StringComparison]::Ordinal) -ge 0) 'live resilient backend captures the layered conversation-proof resolver for callback execution'
Assert-Proof ($backendText.IndexOf('.FindAll(',[StringComparison]::Ordinal) -lt 0) 'live backend callback delegates UIA enumeration to the bounded proof resolver rather than embedding discovery logic'
Assert-Proof ($proofSource.IndexOf('Get-AidosDesktopChatGPTConversationDocumentElement -RootElement $RootElement -AllowMissing',[StringComparison]::Ordinal) -ge 0) 'resilient proof first probes the established Document/RootWebArea path without treating absence as fatal'
Assert-Proof ($proofSource.IndexOf('Get-AidosDesktopChatGPTElementConversationProof -RootElement $RootElement',[StringComparison]::Ordinal) -ge 0) 'missing Document/RootWebArea falls back to unique most-specific enrollment-marker proof'
Assert-Proof ($proofSource.IndexOf("proof_surface='MOST_SPECIFIC_UIA_ELEMENT'",[StringComparison]::Ordinal) -ge 0) 'fallback fingerprint records the non-Document proof surface explicitly'
Assert-Proof ($proofSource.IndexOf('Find-AidosDesktopChatGPTMostSpecificConversationElement -RootElement $RootElement -ProofText $AccountProofText',[StringComparison]::Ordinal) -ge 0) 'fallback independently verifies bound account proof'
Assert-Proof ($proofSource.IndexOf('remains ambiguous after most-specific UIA selection',[StringComparison]::Ordinal) -ge 0) 'ambiguous fallback proof remains fail-closed'
Assert-Proof ($proofSource.IndexOf('is ambiguous in the active ChatGPT document',[StringComparison]::Ordinal) -lt 0) 'one UIA-bound conversation document accepts repeated enrollment marker representations'

Write-Output "PASS: $passed resilient conversation proof assertions"