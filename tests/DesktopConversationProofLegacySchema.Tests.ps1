[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDesktopChatGPTConversationProof.psm1') -Force -DisableNameChecking
$passed=0
function Assert-Legacy([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$legacy=[pscustomobject][ordered]@{
    process_name='ChatGPT Classic'
    session_id='1'
    window_title='ChatGPT Classic'
    window_class_name='Chrome_WidgetWin_1'
    document_name='Transport Enrollment Acknowledgment'
    document_automation_id='RootWebArea'
    document_class_name=''
    document_control_type='ControlType.Document'
    document_value='https://chatgpt.com/c/example-conversation'
    conversation_proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::example'
}
$current=[pscustomobject][ordered]@{
    process_name='ChatGPT Classic'
    session_id='1'
    window_title='ChatGPT Classic'
    window_class_name='Chrome_WidgetWin_1'
    proof_surface='DOCUMENT'
    document_name='A renamed conversation title'
    document_automation_id='RootWebArea'
    document_class_name=''
    document_control_type='ControlType.Document'
    document_value='https://chatgpt.com/c/example-conversation'
    conversation_proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::example'
}
Assert-Legacy (Test-AidosDesktopChatGPTLegacyDocumentFingerprintEquivalent -ExistingFingerprint $legacy -ObservedFingerprint $current) 'legacy Document fingerprint remains equivalent when only explicit proof_surface metadata and mutable document title differ'

$wrongUrl=$current.PSObject.Copy();$wrongUrl.document_value='https://chatgpt.com/c/other-conversation'
Assert-Legacy (-not(Test-AidosDesktopChatGPTLegacyDocumentFingerprintEquivalent -ExistingFingerprint $legacy -ObservedFingerprint $wrongUrl)) 'different conversation URL fails legacy schema revalidation'
$wrongSession=$current.PSObject.Copy();$wrongSession.session_id='2'
Assert-Legacy (-not(Test-AidosDesktopChatGPTLegacyDocumentFingerprintEquivalent -ExistingFingerprint $legacy -ObservedFingerprint $wrongSession)) 'different Windows session fails legacy schema revalidation'
$wrongMarker=$current.PSObject.Copy();$wrongMarker.conversation_proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::other'
Assert-Legacy (-not(Test-AidosDesktopChatGPTLegacyDocumentFingerprintEquivalent -ExistingFingerprint $legacy -ObservedFingerprint $wrongMarker)) 'different enrollment marker fails legacy schema revalidation'

Write-Output "PASS: $passed legacy conversation fingerprint schema assertions"
