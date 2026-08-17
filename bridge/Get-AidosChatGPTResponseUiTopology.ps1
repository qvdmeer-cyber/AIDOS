[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReviewId,
    [string]$ProcessName='ChatGPT Classic'
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){ throw 'ChatGPT response UI topology probe is Windows-only.' }

Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

$processes=@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object {
    $_.SessionId -eq [System.Diagnostics.Process]::GetCurrentProcess().SessionId -and [int64]$_.MainWindowHandle -ne 0
})
if($processes.Count -ne 1){
    throw "Expected exactly one visible '$ProcessName' shell in the current session; found $($processes.Count)."
}

$process=$processes[0]
$root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$process.MainWindowHandle))
if(-not $root){ throw 'ChatGPT UI Automation root is unavailable.' }

function Get-ElementTexts {
    param([Parameter(Mandatory)]$Element)
    $values=@()
    try {
        $pattern=$Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if($pattern){
            $text=[string]$pattern.DocumentRange.GetText(-1)
            if(-not [string]::IsNullOrWhiteSpace($text)){ $values += $text }
        }
    } catch {}
    try {
        $pattern=$Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if($pattern){
            $text=[string]$pattern.Current.Value
            if(-not [string]::IsNullOrWhiteSpace($text)){ $values += $text }
        }
    } catch {}
    foreach($text in @($Element.Current.Name,$Element.Current.HelpText)){
        if(-not [string]::IsNullOrWhiteSpace([string]$text)){ $values += [string]$text }
    }
    @($values | Select-Object -Unique)
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Get-AncestorChain {
    param([Parameter(Mandatory)]$Element)
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
    $items=@()
    $current=$Element
    for($depth=0;$current -and $depth -lt 12;$depth++){
        $items += [pscustomobject]@{
            depth=$depth
            control_type=[string]$current.Current.ControlType.ProgrammaticName
            localized_control_type=[string]$current.Current.LocalizedControlType
            automation_id=[string]$current.Current.AutomationId
            class_name=[string]$current.Current.ClassName
            name=[string]$current.Current.Name
        }
        try { $current=$walker.GetParent($current) } catch { $current=$null }
    }
    @($items)
}

$all=@($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))
$matches=@()
$seen=@{}

foreach($element in $all){
    foreach($text in @(Get-ElementTexts $element)){
        if([string]::IsNullOrWhiteSpace($text)){ continue }
        $hasReviewId=$text.IndexOf($ReviewId,[StringComparison]::OrdinalIgnoreCase) -ge 0
        $hasEnvelope=($text.IndexOf('REVIEW_RESPONSE',[StringComparison]::OrdinalIgnoreCase) -ge 0)
        if(-not ($hasReviewId -and $hasEnvelope)){ continue }
        $sha=Get-TextSha256 $text
        $identity="$sha|$([string]$element.Current.AutomationId)|$([string]$element.Current.ControlType.ProgrammaticName)"
        if($seen.ContainsKey($identity)){ continue }
        $seen[$identity]=$true
        $trim=$text.Trim()
        $shape=if($trim -match '^\{[\s\S]*\}$'){'RAW_JSON_SHAPE'}elseif($trim -match '^```(?:json)?\s*[\s\S]*?\s*```$'){'FENCED_JSON_SHAPE'}else{'MIXED_TEXT'}
        $prefix=if($trim.Length -gt 120){$trim.Substring(0,120)}else{$trim}
        $suffix=if($trim.Length -gt 120){$trim.Substring($trim.Length-120)}else{$trim}
        $matches += [pscustomobject]@{
            text_sha256=$sha
            text_length=$text.Length
            text_shape=$shape
            prefix=$prefix
            suffix=$suffix
            control_type=[string]$element.Current.ControlType.ProgrammaticName
            localized_control_type=[string]$element.Current.LocalizedControlType
            automation_id=[string]$element.Current.AutomationId
            class_name=[string]$element.Current.ClassName
            name=[string]$element.Current.Name
            ancestors=Get-AncestorChain $element
        }
    }
}

[pscustomobject]@{
    observed_at=[DateTimeOffset]::UtcNow.ToString('o')
    review_id=$ReviewId
    process_id=$process.Id
    session_id=$process.SessionId
    main_window_handle=[int64]$process.MainWindowHandle
    match_count=$matches.Count
    matches=@($matches)
} | ConvertTo-Json -Depth 20
