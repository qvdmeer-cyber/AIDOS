Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Stable module entrypoint. The base implementation is preserved separately so
# live ChatGPT Classic actor-message range recovery can extend response capture
# without weakening the existing assignment-bound JSON selector.
. (Join-Path $PSScriptRoot 'AidosDesktopChatGPTWindowDiscovery.Base.ps1')

# Direct strict selector used by both sibling-fragment and parent-message range
# recovery. This intentionally mirrors the preserved selector, but makes the
# separator-free adjacent-fragment reconstruction explicit and typed so Windows
# PowerShell binding cannot reinterpret the surface collection.
function Select-AidosDesktopChatGPTResolvedActorResponseText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Texts,
        [Parameter(Mandatory)]$Assignment
    )
    if($Texts.Count-eq0){return $null}
    if(-not$Assignment){return $null}
    $assignmentObject=if($Assignment.PSObject.Properties['assignment']){$Assignment.assignment}else{$Assignment}
    if(-not$assignmentObject -or [string]::IsNullOrWhiteSpace([string]$assignmentObject.assignment_id)){return $null}
    $assignmentId=[string]$assignmentObject.assignment_id
    $expectedAssignmentHashes=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if($Assignment.PSObject.Properties['sha256'] -and -not[string]::IsNullOrWhiteSpace([string]$Assignment.sha256)){[void]$expectedAssignmentHashes.Add([string]$Assignment.sha256)}
    elseif($Assignment.PSObject.Properties['assignment_sha256'] -and -not[string]::IsNullOrWhiteSpace([string]$Assignment.assignment_sha256)){[void]$expectedAssignmentHashes.Add([string]$Assignment.assignment_sha256)}

    $surfaces=[Collections.Generic.List[string]]::new()
    $seenSurfaces=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($text in @($Texts)){
        if([string]::IsNullOrWhiteSpace([string]$text)){continue}
        $value=[string]$text
        if($seenSurfaces.Add($value)){$surfaces.Add($value)}
    }
    if($surfaces.Count-eq0){return $null}

    $orderedSurfaces=$surfaces.ToArray()
    if($orderedSurfaces.Count-gt1){
        # Newline aggregation remains a fallback for controls that represent
        # separate rendered lines. Exact separator-free reconstruction is added
        # last so it has higher precedence when both forms parse as valid JSON.
        $aggregate=[string]::Join("`n",[string[]]$orderedSurfaces)
        if($seenSurfaces.Add($aggregate)){$surfaces.Add($aggregate)}
        $compact=[string]::Join('',[string[]]$orderedSurfaces)
        if(-not[string]::IsNullOrWhiteSpace($compact) -and $seenSurfaces.Add($compact)){$surfaces.Add($compact)}
    }

    if($expectedAssignmentHashes.Count-eq0){
        foreach($surface in $surfaces.ToArray()){
            if($surface.IndexOf('RUNTIME_ACTOR_RESULT',[StringComparison]::OrdinalIgnoreCase)-lt0){continue}
            if($surface.IndexOf($assignmentId,[StringComparison]::OrdinalIgnoreCase)-lt0){continue}
            foreach($candidate in @(Get-AidosDesktopChatGPTJsonObjectCandidates -Text $surface)){
                if($candidate.IndexOf('REQUIRED:',[StringComparison]::OrdinalIgnoreCase)-lt0 -and $candidate.IndexOf('REQUIRED_NONEMPTY:',[StringComparison]::OrdinalIgnoreCase)-lt0){continue}
                try{$parsed=$candidate|ConvertFrom-Json -Depth 100}catch{continue}
                if([string]$parsed.envelope_type-ne'RUNTIME_ACTOR_RESULT'){continue}
                if([string]$parsed.assignment_id-ne$assignmentId){continue}
                $templateHash=[string]$parsed.assignment_sha256
                if($templateHash-match'^[0-9a-fA-F]{64}$'){[void]$expectedAssignmentHashes.Add($templateHash)}
            }
        }
    }

    $responses=[Collections.Generic.List[string]]::new()
    $seenResponses=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($surface in $surfaces.ToArray()){
        if($surface.IndexOf('RUNTIME_ACTOR_RESULT',[StringComparison]::OrdinalIgnoreCase)-lt0){continue}
        if($surface.IndexOf($assignmentId,[StringComparison]::OrdinalIgnoreCase)-lt0){continue}
        foreach($candidate in @(Get-AidosDesktopChatGPTJsonObjectCandidates -Text $surface)){
            if($candidate.IndexOf('REQUIRED:',[StringComparison]::OrdinalIgnoreCase)-ge0){continue}
            if($candidate.IndexOf('REQUIRED_NONEMPTY:',[StringComparison]::OrdinalIgnoreCase)-ge0){continue}
            try{$parsed=$candidate|ConvertFrom-Json -Depth 100}catch{continue}
            if([string]$parsed.envelope_type-ne'RUNTIME_ACTOR_RESULT'){continue}
            if([string]$parsed.assignment_id-ne$assignmentId){continue}
            $candidateHash=[string]$parsed.assignment_sha256
            if($candidateHash-notmatch'^[0-9a-fA-F]{64}$'){continue}
            if($expectedAssignmentHashes.Count-gt0 -and -not$expectedAssignmentHashes.Contains($candidateHash)){continue}
            if($seenResponses.Add($candidate)){$responses.Add($candidate)}
        }
    }
    if($responses.Count-eq0){return $null}
    $responses[$responses.Count-1]
}

function Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ElementTexts,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AncestorRangeTexts,
        [Parameter(Mandatory)]$Assignment
    )
    $direct=$null
    if($ElementTexts.Count-gt0){
        $direct=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts $ElementTexts -Assignment $Assignment
    }
    if(-not[string]::IsNullOrWhiteSpace([string]$direct)){return $direct}
    if($AncestorRangeTexts.Count-eq0){return $null}
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
    foreach($candidateElement in $chain.ToArray()){
        try{$text=[string]$textPattern.RangeFromChild($candidateElement).GetText(-1)}catch{continue}
        if([string]::IsNullOrWhiteSpace($text)){continue}
        if($text.Length-gt$MaximumRangeCharacters){continue}
        if($seen.Add($text)){$values.Add($text)}
    }
    $values.ToArray()
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
    Select-AidosDesktopChatGPTResolvedActorResponseText -Texts ($allTexts.ToArray()) -Assignment $Assignment
}

Export-ModuleMember -Function Initialize-AidosDesktopChatGPTWindowDiscovery,Get-AidosWindowDiscoveryText,Get-AidosWindowDiscoveryClass,Get-AidosDesktopChatGPTFallbackProcessContexts,Get-AidosDesktopChatGPTResilientProcessContext,Get-AidosDesktopChatGPTFreshComposerObservation,Wait-AidosDesktopChatGPTFreshComposerCleared,Add-AidosDesktopChatGPTFreshComposerProof,Get-AidosDesktopChatGPTElementSearchTexts,Get-AidosDesktopChatGPTJsonObjectCandidates,Select-AidosDesktopChatGPTResolvedActorResponseText,Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts,Get-AidosDesktopChatGPTActorResponseAncestorRangeTexts,Get-AidosDesktopChatGPTResolvedActorResponseText,Add-AidosDesktopChatGPTResolvedActorResponseReader,Add-AidosDesktopChatGPTConversationProofRecovery,New-AidosDesktopChatGPTResilientWindowsBackend,New-AidosDesktopChatGPTWindowsBackend
