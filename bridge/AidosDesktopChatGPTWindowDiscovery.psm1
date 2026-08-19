Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Stable module entrypoint. The base implementation is preserved separately so
# live ChatGPT Classic actor-message range recovery can extend response capture
# without weakening the existing assignment-bound JSON selector.
. (Join-Path $PSScriptRoot 'AidosDesktopChatGPTWindowDiscovery.Base.ps1')

function Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ElementTexts,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AncestorRangeTexts,
        [Parameter(Mandatory)]$Assignment
    )
    $direct=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts $ElementTexts -Assignment $Assignment
    if(-not[string]::IsNullOrWhiteSpace([string]$direct)){return $direct}
    Select-AidosDesktopChatGPTResolvedActorResponseText -Texts $AncestorRangeTexts -Assignment $Assignment
}

function Get-AidosDesktopChatGPTActorResponseAncestorRangeTexts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Element,
        [int]$MaximumAncestorLevels=8,
        [int]$MaximumRangeCharacters=262144
    )
    if(-not$Element){return @()}
    Initialize-AidosDesktopChatGPTWindowDiscovery
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
    $chain=[System.Collections.Generic.List[object]]::new()
    $current=$Element
    $document=$null
    for($level=0;$level-lt$MaximumAncestorLevels -and $current;$level++){
        try {
            if($current.Current.ControlType -eq [System.Windows.Automation.ControlType]::Document){$document=$current;break}
        } catch {}
        $chain.Add($current)
        try{$current=$walker.GetParent($current)}catch{$current=$null}
    }
    if(-not$document){return @()}
    try{$textPattern=$document.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)}catch{$textPattern=$null}
    if(-not$textPattern){return @()}
    $values=[System.Collections.Generic.List[string]]::new()
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($candidateElement in @($chain)){
        try{$text=[string]$textPattern.RangeFromChild($candidateElement).GetText(-1)}catch{continue}
        if([string]::IsNullOrWhiteSpace($text)){continue}
        if($text.Length-gt$MaximumRangeCharacters){continue}
        if($seen.Add($text)){$values.Add($text)}
    }
    @($values)
}

function Get-AidosDesktopChatGPTResolvedActorResponseText {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Assignment)
    if(-not$Assignment){return $null}
    $assignmentObject=if($Assignment.PSObject.Properties['assignment']){$Assignment.assignment}else{$Assignment}
    if(-not$assignmentObject -or [string]::IsNullOrWhiteSpace([string]$assignmentObject.assignment_id)){return $null}
    $assignmentId=[string]$assignmentObject.assignment_id
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){return $null}
    Initialize-AidosDesktopChatGPTWindowDiscovery
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not$root){return $null}

    $allTexts=[System.Collections.Generic.List[string]]::new()
    $rootTexts=@(Get-AidosDesktopChatGPTElementSearchTexts -Element $root)
    foreach($text in $rootTexts){if(-not[string]::IsNullOrWhiteSpace([string]$text)){$allTexts.Add([string]$text)}}

    foreach($element in @($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))){
        try{if([string]$element.Current.AutomationId-eq'prompt-textarea'){continue}}catch{}
        $elementTexts=@(Get-AidosDesktopChatGPTElementSearchTexts -Element $element)
        foreach($text in $elementTexts){if(-not[string]::IsNullOrWhiteSpace([string]$text)){$allTexts.Add([string]$text)}}
        $boundSurface=$false
        foreach($text in $elementTexts){
            if([string]::IsNullOrWhiteSpace([string]$text)){continue}
            if(([string]$text).IndexOf('RUNTIME_ACTOR_RESULT',[StringComparison]::OrdinalIgnoreCase)-ge0 -and ([string]$text).IndexOf($assignmentId,[StringComparison]::OrdinalIgnoreCase)-ge0){$boundSurface=$true;break}
        }
        if(-not$boundSurface){continue}
        $ancestorTexts=@(Get-AidosDesktopChatGPTActorResponseAncestorRangeTexts -Element $element)
        $resolved=Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts -ElementTexts $elementTexts -AncestorRangeTexts $ancestorTexts -Assignment $Assignment
        if(-not[string]::IsNullOrWhiteSpace([string]$resolved)){return $resolved}
    }

    # Preserve the existing sibling-fragment fallback for accessibility trees
    # where a complete response is reconstructed only after aggregating controls.
    Select-AidosDesktopChatGPTResolvedActorResponseText -Texts @($allTexts) -Assignment $Assignment
}

Export-ModuleMember -Function Initialize-AidosDesktopChatGPTWindowDiscovery,Get-AidosWindowDiscoveryText,Get-AidosWindowDiscoveryClass,Get-AidosDesktopChatGPTFallbackProcessContexts,Get-AidosDesktopChatGPTResilientProcessContext,Get-AidosDesktopChatGPTFreshComposerObservation,Wait-AidosDesktopChatGPTFreshComposerCleared,Add-AidosDesktopChatGPTFreshComposerProof,Get-AidosDesktopChatGPTElementSearchTexts,Get-AidosDesktopChatGPTJsonObjectCandidates,Select-AidosDesktopChatGPTResolvedActorResponseText,Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts,Get-AidosDesktopChatGPTActorResponseAncestorRangeTexts,Get-AidosDesktopChatGPTResolvedActorResponseText,Add-AidosDesktopChatGPTResolvedActorResponseReader,Add-AidosDesktopChatGPTConversationProofRecovery,New-AidosDesktopChatGPTResilientWindowsBackend,New-AidosDesktopChatGPTWindowsBackend
