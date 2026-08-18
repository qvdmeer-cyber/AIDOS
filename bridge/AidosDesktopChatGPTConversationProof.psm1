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
    if($candidates.Count-eq0){throw "Conversation proof text '$ProofText' was not found in the active ChatGPT window."}
    $ordered=@($candidates|Sort-Object @{Expression={$_.exact};Descending=$true},@{Expression={$_.text_length};Descending=$false},@{Expression={$_.depth};Descending=$true})
    $best=$ordered[0]
    $ties=@($ordered|Where-Object {$_.exact-eq$best.exact -and $_.text_length-eq$best.text_length -and $_.depth-eq$best.depth})
    if($ties.Count-ne1){throw "Conversation proof text '$ProofText' remains ambiguous after most-specific UIA selection."}
    $best.element
}

function New-AidosDesktopChatGPTResilientConversationBackend {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Backend)
    $values=[ordered]@{}
    foreach($property in $Backend.PSObject.Properties){$values[[string]$property.Name]=$property.Value}
    $values['LocateConversation']=({
        param($Context,[string]$ProofText,$Enrollment)
        if(-not$Context){throw 'ChatGPT process/window is not present.'}
        if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw 'ChatGPT window is not present.'}
        if(-not ('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
        $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
        if(-not$root){throw 'ChatGPT window is not accessible through UI Automation.'}
        if(-not[string]::IsNullOrWhiteSpace([string]$Enrollment.account_proof_text)){
            $seen=$false
            foreach($element in @($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))){
                foreach($value in @(Get-AidosDesktopChatGPTProofSearchValues $element)){
                    if((-not[string]::IsNullOrWhiteSpace([string]$value)) -and ([string]$value).IndexOf([string]$Enrollment.account_proof_text,[StringComparison]::OrdinalIgnoreCase)-ge0){$seen=$true;break}
                }
                if($seen){break}
            }
            if(-not$seen){throw 'ChatGPT account proof text is stale or mismatched.'}
        }
        $element=Find-AidosDesktopChatGPTMostSpecificConversationElement -RootElement $root -ProofText $ProofText
        $fingerprint=Get-AidosDesktopChatGPTElementFingerprint $element
        [pscustomobject][ordered]@{conversation_fingerprint=$fingerprint;conversation_fingerprint_sha256=(Get-AidosDesktopChatGPTFingerprintHash $fingerprint)}
    }).GetNewClosure()
    [pscustomobject]$values
}

Export-ModuleMember -Function Get-AidosDesktopChatGPTProofSearchValues,Get-AidosDesktopChatGPTProofElementDepth,Find-AidosDesktopChatGPTMostSpecificConversationElement,New-AidosDesktopChatGPTResilientConversationBackend
