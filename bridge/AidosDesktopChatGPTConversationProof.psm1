Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -DisableNameChecking

function Get-AidosDesktopChatGPTProofSearchValues {
    param($Element)
    if(-not $Element){return @()}
    $values=[System.Collections.Generic.List[string]]::new()
    try {
        $textPattern=$Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if($textPattern){
            $text=[string]$textPattern.DocumentRange.GetText(-1)
            if(-not[string]::IsNullOrWhiteSpace($text)){$values.Add($text)}
        }
    } catch {}
    try {
        $valuePattern=$Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if($valuePattern){
            $text=[string]$valuePattern.Current.Value
            if(-not[string]::IsNullOrWhiteSpace($text)){$values.Add($text)}
        }
    } catch {}
    foreach($value in @($Element.Current.Name,$Element.Current.HelpText,$Element.Current.AutomationId,$Element.Current.ClassName)){
        if(-not[string]::IsNullOrWhiteSpace([string]$value)){$values.Add([string]$value)}
    }
    @($values|Select-Object -Unique)
}

function Get-AidosDesktopChatGPTProofElementDepth {
    param($Element)
    if(-not $Element){return 0}
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
    $depth=0;$current=$Element
    while($current){$depth++;try{$current=$walker.GetParent($current)}catch{$current=$null}}
    $depth
}

function Select-AidosDesktopChatGPTMostSpecificProofCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Candidates,[string]$ProofText='conversation proof')
    if($Candidates.Count-eq0){throw "Conversation proof text '$ProofText' was not found in the active ChatGPT window."}
    $ordered=@($Candidates|Sort-Object @{Expression={[bool]$_.exact};Descending=$true},@{Expression={[int]$_.text_length};Descending=$false},@{Expression={[int]$_.depth};Descending=$true})
    $best=$ordered[0]
    $ties=@($ordered|Where-Object {[bool]$_.exact-eq[bool]$best.exact -and [int]$_.text_length-eq[int]$best.text_length -and [int]$_.depth-eq[int]$best.depth})
    if($ties.Count-ne1){throw "Conversation proof text '$ProofText' remains ambiguous after most-specific UIA selection."}
    $best
}

function Find-AidosDesktopChatGPTMostSpecificConversationElement {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RootElement,[Parameter(Mandatory)][string]$ProofText)
    $candidates=[System.Collections.Generic.List[object]]::new()
    foreach($element in @($RootElement.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))){
        $matching=@(Get-AidosDesktopChatGPTProofSearchValues $element|Where-Object {
            -not[string]::IsNullOrWhiteSpace([string]$_) -and ([string]$_).IndexOf($ProofText,[StringComparison]::OrdinalIgnoreCase)-ge0
        })
        if($matching.Count-eq0){continue}
        $exact=@($matching|Where-Object {[string]::Equals(([string]$_).Trim(),$ProofText,[StringComparison]::OrdinalIgnoreCase)})
        $shortest=@($matching|Sort-Object Length|Select-Object -First 1)[0]
        $candidates.Add([pscustomobject][ordered]@{
            element=$element
            exact=($exact.Count-gt0)
            text_length=([string]$shortest).Length
            depth=(Get-AidosDesktopChatGPTProofElementDepth $element)
        })
    }
    $best=Select-AidosDesktopChatGPTMostSpecificProofCandidate -Candidates @($candidates) -ProofText $ProofText
    $best.element
}

function Get-AidosDesktopChatGPTConversationDocumentElement {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RootElement,[switch]$AllowMissing)
    if($RootElement.Current.ControlType -eq [System.Windows.Automation.ControlType]::Document){return $RootElement}
    $condition=New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ControlTypeProperty),([System.Windows.Automation.ControlType]::Document)
    $document=$RootElement.FindFirst([System.Windows.Automation.TreeScope]::Subtree,$condition)
    if(-not$document){
        if($AllowMissing){return $null}
        throw 'ChatGPT conversation document/RootWebArea was not found through UI Automation.'
    }
    $document
}

function Get-AidosDesktopChatGPTDocumentConversationProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RootElement,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$ProofText,
        [AllowEmptyString()][string]$AccountProofText=''
    )
    $document=Get-AidosDesktopChatGPTConversationDocumentElement -RootElement $RootElement
    try{$textPattern=$document.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)}catch{$textPattern=$null}
    if(-not$textPattern){throw 'ChatGPT conversation document does not expose TextPattern.'}
    $documentText=[string]$textPattern.DocumentRange.GetText(-1)
    if([string]::IsNullOrWhiteSpace($documentText)){throw 'ChatGPT conversation document text is unavailable.'}

    $first=$documentText.IndexOf($ProofText,[StringComparison]::OrdinalIgnoreCase)
    if($first-lt0){throw "Conversation proof text '$ProofText' was not found in the active ChatGPT document."}
    # This is already a single, UIA-bound ChatGPT Document/RootWebArea. The same
    # enrollment marker may be represented twice by the desktop accessibility
    # tree (or quoted by the enrolled conversation); repetition inside that one
    # document is not evidence of a second conversation.
    if(-not[string]::IsNullOrWhiteSpace($AccountProofText) -and $documentText.IndexOf($AccountProofText,[StringComparison]::OrdinalIgnoreCase)-lt0){throw 'ChatGPT account proof text is stale or mismatched.'}

    $documentValue=''
    try {
        $valuePattern=$document.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if($valuePattern){$documentValue=[string]$valuePattern.Current.Value}
    }catch{}
    $fingerprint=[ordered]@{
        process_name=[string]$Context.process_name
        session_id=[string]$Context.session_id
        window_title=[string]$Context.window_title
        window_class_name=[string]$Context.window_class_name
        proof_surface='DOCUMENT'
        document_name=[string]$document.Current.Name
        document_automation_id=[string]$document.Current.AutomationId
        document_class_name=[string]$document.Current.ClassName
        document_control_type=[string]$document.Current.ControlType.ProgrammaticName
        document_value=$documentValue
        conversation_proof_text=$ProofText
    }
    [pscustomobject][ordered]@{
        conversation_fingerprint=$fingerprint
        conversation_fingerprint_sha256=(Get-AidosDesktopChatGPTFingerprintHash $fingerprint)
    }
}

function Get-AidosDesktopChatGPTElementConversationProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RootElement,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$ProofText,
        [AllowEmptyString()][string]$AccountProofText=''
    )
    # Chromium/Electron does not guarantee that its accessibility tree exposes a
    # ControlType.Document/RootWebArea. When it does not, the enrollment marker
    # itself remains the authoritative conversation proof. Select its unique,
    # most-specific UIA carrier and separately verify account proof when bound.
    $proofElement=Find-AidosDesktopChatGPTMostSpecificConversationElement -RootElement $RootElement -ProofText $ProofText
    if(-not[string]::IsNullOrWhiteSpace($AccountProofText)){
        $null=Find-AidosDesktopChatGPTMostSpecificConversationElement -RootElement $RootElement -ProofText $AccountProofText
    }
    $fingerprint=[ordered]@{
        process_name=[string]$Context.process_name
        session_id=[string]$Context.session_id
        window_title=[string]$Context.window_title
        window_class_name=[string]$Context.window_class_name
        proof_surface='MOST_SPECIFIC_UIA_ELEMENT'
        proof_element_name=[string]$proofElement.Current.Name
        proof_element_automation_id=[string]$proofElement.Current.AutomationId
        proof_element_class_name=[string]$proofElement.Current.ClassName
        proof_element_control_type=[string]$proofElement.Current.ControlType.ProgrammaticName
        conversation_proof_text=$ProofText
        account_proof_text=$AccountProofText
    }
    [pscustomobject][ordered]@{
        conversation_fingerprint=$fingerprint
        conversation_fingerprint_sha256=(Get-AidosDesktopChatGPTFingerprintHash $fingerprint)
    }
}

function Get-AidosDesktopChatGPTProofSurfaceName {
    param($Fingerprint)
    if(-not$Fingerprint){return $null}
    if($Fingerprint.PSObject.Properties['proof_surface'] -and -not[string]::IsNullOrWhiteSpace([string]$Fingerprint.proof_surface)){return [string]$Fingerprint.proof_surface}
    # Fingerprints written before proof_surface was explicit were created only by
    # the Document/RootWebArea proof path.
    if($Fingerprint.PSObject.Properties['document_control_type']){return 'DOCUMENT_LEGACY'}
    $null
}

function Get-AidosDesktopChatGPTResilientConversationProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RootElement,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$ProofText,
        [AllowEmptyString()][string]$AccountProofText='',
        $ExistingFingerprint,
        [AllowEmptyString()][string]$ExistingFingerprintSha256=''
    )
    $document=Get-AidosDesktopChatGPTConversationDocumentElement -RootElement $RootElement -AllowMissing
    $observed=if($document){
        # Preserve the established Document proof path whenever ChatGPT exposes it.
        Get-AidosDesktopChatGPTDocumentConversationProof -RootElement $RootElement -Context $Context -ProofText $ProofText -AccountProofText $AccountProofText
    }else{
        Get-AidosDesktopChatGPTElementConversationProof -RootElement $RootElement -Context $Context -ProofText $ProofText -AccountProofText $AccountProofText
    }

    # An enrolled conversation can survive a Chromium accessibility-provider
    # representation change. Reuse its durable identity only when the current
    # observation has independently re-proven the same enrollment marker/account
    # and the only identity difference is the known proof-surface class.
    if($ExistingFingerprint -and -not[string]::IsNullOrWhiteSpace($ExistingFingerprintSha256)){
        $oldSurface=Get-AidosDesktopChatGPTProofSurfaceName $ExistingFingerprint
        $newSurface=Get-AidosDesktopChatGPTProofSurfaceName $observed.conversation_fingerprint
        $surfaceChanged=(
            $oldSurface -in @('DOCUMENT','DOCUMENT_LEGACY','MOST_SPECIFIC_UIA_ELEMENT') -and
            $newSurface -in @('DOCUMENT','MOST_SPECIFIC_UIA_ELEMENT') -and
            $oldSurface -ne $newSurface -and
            -not($oldSurface-eq'DOCUMENT_LEGACY' -and $newSurface-eq'DOCUMENT')
        )
        if($surfaceChanged){
            return [pscustomobject][ordered]@{
                conversation_fingerprint=$ExistingFingerprint
                conversation_fingerprint_sha256=$ExistingFingerprintSha256
                proof_surface_rebound=$true
                observed_conversation_fingerprint=$observed.conversation_fingerprint
                observed_conversation_fingerprint_sha256=$observed.conversation_fingerprint_sha256
            }
        }
    }
    $observed
}

function New-AidosDesktopChatGPTResilientConversationBackend {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Backend)
    $values=[ordered]@{}
    foreach($property in $Backend.PSObject.Properties){$values[[string]$property.Name]=$property.Value}
    # LocateConversation runs later from a backend callback scope. Capture the
    # exact resilient proof command now instead of depending on ambient exports.
    $resilientConversationProof=Get-Command Get-AidosDesktopChatGPTResilientConversationProof -CommandType Function -ErrorAction Stop
    $values['LocateConversation']=({
        param($Context,[string]$ProofText,$Enrollment)
        if(-not$Context){throw 'ChatGPT process/window is not present.'}
        if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw 'ChatGPT window is not present.'}
        if(-not ('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
        $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
        if(-not$root){throw 'ChatGPT window is not accessible through UI Automation.'}
        $accountProof='';$existingFingerprint=$null;$existingFingerprintSha=''
        if($Enrollment){
            if($Enrollment.PSObject.Properties['account_proof_text']){$accountProof=[string]$Enrollment.account_proof_text}
            if($Enrollment.PSObject.Properties['conversation_fingerprint']){$existingFingerprint=$Enrollment.conversation_fingerprint}
            if($Enrollment.PSObject.Properties['conversation_fingerprint_sha256']){$existingFingerprintSha=[string]$Enrollment.conversation_fingerprint_sha256}
        }
        & $resilientConversationProof -RootElement $root -Context $Context -ProofText $ProofText -AccountProofText $accountProof -ExistingFingerprint $existingFingerprint -ExistingFingerprintSha256 $existingFingerprintSha
    }).GetNewClosure()
    [pscustomobject]$values
}

Export-ModuleMember -Function Get-AidosDesktopChatGPTProofSearchValues,Get-AidosDesktopChatGPTProofElementDepth,Select-AidosDesktopChatGPTMostSpecificProofCandidate,Find-AidosDesktopChatGPTMostSpecificConversationElement,Get-AidosDesktopChatGPTConversationDocumentElement,Get-AidosDesktopChatGPTDocumentConversationProof,Get-AidosDesktopChatGPTElementConversationProof,Get-AidosDesktopChatGPTProofSurfaceName,Get-AidosDesktopChatGPTResilientConversationProof,New-AidosDesktopChatGPTResilientConversationBackend
