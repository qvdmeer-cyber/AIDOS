[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$proofModulePath=Join-Path $root 'bridge/AidosDesktopChatGPTConversationProof.psm1'
$windowModulePath=[IO.Path]::GetFullPath((Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.psm1'))
$windowBasePath=[IO.Path]::GetFullPath((Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.Base.ps1'))
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

$emptyError=$null
try{Select-AidosDesktopChatGPTMostSpecificProofCandidate -Candidates @() -ProofText 'missing-marker'|Out-Null}catch{$emptyError=$_.Exception.Message}
Assert-Proof ($emptyError -eq "Conversation proof text 'missing-marker' was not found in the active ChatGPT window.") 'empty fallback candidate sets produce the intended fail-closed proof error instead of parameter binding failure'

Assert-Proof ((Get-AidosDesktopChatGPTProofSurfaceName ([pscustomobject]@{proof_surface='DOCUMENT'})) -eq 'DOCUMENT') 'explicit Document proof surface is recognized'
Assert-Proof ((Get-AidosDesktopChatGPTProofSurfaceName ([pscustomobject]@{document_control_type='ControlType.Document'})) -eq 'DOCUMENT_LEGACY') 'legacy Document fingerprint is recognized for representation migration'
Assert-Proof ((Get-AidosDesktopChatGPTProofSurfaceName ([pscustomobject]@{proof_surface='MOST_SPECIFIC_UIA_ELEMENT'})) -eq 'MOST_SPECIFIC_UIA_ELEMENT') 'element fallback proof surface is recognized'

$storedContext=[pscustomobject]@{process_name='ChatGPT Classic';session_id='1';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1'}
$storedFingerprint=[pscustomobject]@{process_name='ChatGPT Classic';session_id='1';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';document_value='https://chatgpt.com/c/example-conversation'}
Assert-Proof (Test-AidosDesktopChatGPTStoredConversationIdentity -Context $storedContext -ExistingFingerprint $storedFingerprint -ObservedDocumentValue 'https://chatgpt.com/c/example-conversation') 'stored enrolled conversation URL revalidates the same ChatGPT shell after historic marker virtualization'
Assert-Proof (-not(Test-AidosDesktopChatGPTStoredConversationIdentity -Context $storedContext -ExistingFingerprint $storedFingerprint -ObservedDocumentValue 'https://chatgpt.com/c/other-conversation')) 'different conversation URL fails closed'
Assert-Proof (-not(Test-AidosDesktopChatGPTStoredConversationIdentity -Context ([pscustomobject]@{process_name='ChatGPT Classic';session_id='2';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1'}) -ExistingFingerprint $storedFingerprint -ObservedDocumentValue 'https://chatgpt.com/c/example-conversation')) 'different Windows session fails stored conversation revalidation'
Assert-Proof (-not(Test-AidosDesktopChatGPTStoredConversationIdentity -Context ([pscustomobject]@{process_name='ChatGPT Classic';session_id='1';window_title='Other';window_class_name='Chrome_WidgetWin_1'}) -ExistingFingerprint $storedFingerprint -ObservedDocumentValue 'https://chatgpt.com/c/example-conversation')) 'different shell title fails stored conversation revalidation'

$storedSelected=Select-AidosDesktopChatGPTStoredConversationDocumentCandidate -Candidates @([pscustomobject]@{id='outer';depth=3},[pscustomobject]@{id='conversation';depth=9})
Assert-Proof ($storedSelected.id -eq 'conversation') 'deepest exact URL-matching Document wins over broader Document containers'
Assert-Proof ($null-eq(Select-AidosDesktopChatGPTStoredConversationDocumentCandidate -Candidates @())) 'no exact stored URL Document returns no revalidation candidate'
$storedAmbiguous=$false
try{Select-AidosDesktopChatGPTStoredConversationDocumentCandidate -Candidates @([pscustomobject]@{id='a';depth=9},[pscustomobject]@{id='b';depth=9})|Out-Null}catch{$storedAmbiguous=$true}
Assert-Proof $storedAmbiguous 'equally specific stored URL Documents remain fail-closed'

$windowModule=@(Get-Module AidosDesktopChatGPTWindowDiscovery -All -ErrorAction Stop|Where-Object {[IO.Path]::GetFullPath([string]$_.Path) -eq $windowModulePath}|Select-Object -Last 1)[0]
Assert-Proof ($null-ne$windowModule) 'exact window-discovery module instance is loaded from the expected path'
$shim=$windowModule.ExportedCommands['New-AidosDesktopChatGPTWindowsBackend']
$resilient=$windowModule.ExportedCommands['New-AidosDesktopChatGPTResilientWindowsBackend']
$recovery=$windowModule.ExportedCommands['Add-AidosDesktopChatGPTConversationProofRecovery']
$base=$windowModule.SessionState.PSVariable.GetValue('BaseDesktopChatGPTWindowsBackendCommand')
Assert-Proof ($null-ne$shim) 'window-discovery module exports the compatibility shim used by existing Thinker callers'
Assert-Proof ($null-ne$resilient) 'window-discovery module exports the uniquely named resilient backend factory'
Assert-Proof ($null-ne$recovery) 'window-discovery module exports the document-proof recovery wrapper'
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
Assert-Proof ($proofSource.IndexOf('Find-AidosDesktopChatGPTStoredConversationDocument -RootElement $RootElement -Context $Context -ExistingFingerprint $ExistingFingerprint',[StringComparison]::Ordinal) -ge 0) 'enrolled Thinker searches all Document elements for its exact stored conversation URL before generic Document proof'
Assert-Proof ($proofSource.IndexOf('$RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,$condition)',[StringComparison]::Ordinal) -ge 0) 'stored conversation lookup enumerates the complete Document subtree rather than accepting the first Document'
Assert-Proof ($proofSource.IndexOf('Get-AidosDesktopChatGPTConversationDocumentElement -RootElement $RootElement -AllowMissing',[StringComparison]::Ordinal) -ge 0) 'generic Document/RootWebArea proof remains available after stored URL revalidation'
Assert-Proof ($proofSource.IndexOf("proof_surface_revalidated='STORED_CONVERSATION_URL'",[StringComparison]::Ordinal) -ge 0) 'successful URL revalidation explicitly records its durable proof mechanism'
Assert-Proof ($proofSource.IndexOf('Get-AidosDesktopChatGPTElementConversationProof -RootElement $RootElement',[StringComparison]::Ordinal) -ge 0) 'missing Document/RootWebArea falls back to unique most-specific enrollment-marker proof'
Assert-Proof ($proofSource.IndexOf("proof_surface='MOST_SPECIFIC_UIA_ELEMENT'",[StringComparison]::Ordinal) -ge 0) 'fallback fingerprint records the non-Document proof surface explicitly'
Assert-Proof ($proofSource.IndexOf('Find-AidosDesktopChatGPTMostSpecificConversationElement -RootElement $RootElement -ProofText $AccountProofText',[StringComparison]::Ordinal) -ge 0) 'fallback independently verifies bound account proof'
Assert-Proof ($proofSource.IndexOf("`$oldSurface -in @('DOCUMENT','DOCUMENT_LEGACY','MOST_SPECIFIC_UIA_ELEMENT')",[StringComparison]::Ordinal) -ge 0) 'existing enrollment identity can be retained only across explicitly known proof-surface classes'
Assert-Proof ($proofSource.IndexOf('conversation_fingerprint_sha256=$ExistingFingerprintSha256',[StringComparison]::Ordinal) -ge 0) 'known proof-surface migration retains the durable enrolled conversation identity after current proof succeeds'
Assert-Proof ($proofSource.IndexOf('remains ambiguous after most-specific UIA selection',[StringComparison]::Ordinal) -ge 0) 'ambiguous fallback proof remains fail-closed'
Assert-Proof ($proofSource.IndexOf('is ambiguous in the active ChatGPT document',[StringComparison]::Ordinal) -lt 0) 'one UIA-bound conversation document accepts repeated enrollment marker representations'

$windowSource=Get-Content -LiteralPath $windowModulePath -Raw -Encoding UTF8
$windowBaseSource=Get-Content -LiteralPath $windowBasePath -Raw -Encoding UTF8
Assert-Proof ($windowSource.IndexOf(". (Join-Path `$PSScriptRoot 'AidosDesktopChatGPTWindowDiscovery.Base.ps1')",[StringComparison]::Ordinal) -ge 0) 'window-discovery module loads the preserved base implementation before layered response recovery'
Assert-Proof ($windowBaseSource.IndexOf('function Add-AidosDesktopChatGPTConversationProofRecovery',[StringComparison]::Ordinal) -ge 0) 'Windows backend contains a final recovery layer for a non-conversation Document surface'
Assert-Proof ($windowBaseSource.IndexOf('try{return & $primaryLocate $Context $ProofText $Enrollment}catch{$primaryError=$_.Exception.Message}',[StringComparison]::Ordinal) -ge 0) 'recovery is attempted only after the primary conversation proof actually fails'
Assert-Proof ($windowBaseSource.IndexOf('Get-AidosDesktopChatGPTElementConversationProof',[StringComparison]::Ordinal) -ge 0) 'recovery re-proves the enrollment marker through the established most-specific UIA element proof'
Assert-Proof ($windowBaseSource.IndexOf('conversation_fingerprint_sha256=[string]$Enrollment.conversation_fingerprint_sha256',[StringComparison]::Ordinal) -ge 0) 'successful recovery retains the already-enrolled durable conversation identity'
Assert-Proof ($windowBaseSource.IndexOf('$backend=New-AidosDesktopChatGPTResilientConversationBackend -Backend $backend',[StringComparison]::Ordinal) -ge 0 -and $windowBaseSource.IndexOf('Add-AidosDesktopChatGPTConversationProofRecovery -Backend $backend',[StringComparison]::Ordinal) -ge 0) 'Windows backend composes primary resilient proof before final recovery proof'

Write-Output "PASS: $passed resilient conversation proof assertions"
