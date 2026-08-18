[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.psm1'
$source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$script:passed=0
function Assert-Fresh([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

Assert-Fresh ($source.IndexOf('function Get-AidosDesktopChatGPTFreshComposerObservation',[StringComparison]::Ordinal) -ge 0) 'fresh composer observation helper exists'
Assert-Fresh ($source.IndexOf("AutomationId -eq 'prompt-textarea'",[StringComparison]::Ordinal) -ge 0) 'fresh lookup rebinds the prompt textarea from the current window root'
Assert-Fresh ($source.IndexOf('function Wait-AidosDesktopChatGPTFreshComposerCleared',[StringComparison]::Ordinal) -ge 0) 'bounded post-submit fresh observation helper exists'
Assert-Fresh ($source.IndexOf("if([string]::IsNullOrWhiteSpace([string]`$fresh.composer_text)){return `$fresh}",[StringComparison]::Ordinal) -ge 0) 'only a fresh empty composer proves the alternate committed-send path'
Assert-Fresh ($source.IndexOf("Fresh ChatGPT composer contains unrelated text after submit; committed-send proof remains fail-closed.",[StringComparison]::Ordinal) -ge 0) 'unrelated fresh composer text remains fail-closed'
Assert-Fresh ($source.IndexOf("Fresh ChatGPT composer still contains the exact outbound payload after bounded submit observation; committed-send proof is absent.",[StringComparison]::Ordinal) -ge 0) 'fresh exact outbound payload remains fail-closed after bounded observation'
Assert-Fresh ($source.IndexOf('$freshComposerObservation=Get-Command Get-AidosDesktopChatGPTFreshComposerObservation -CommandType Function -ErrorAction Stop',[StringComparison]::Ordinal) -ge 0) 'fresh composer observation command is captured before deferred callback execution'
Assert-Fresh ($source.IndexOf('$freshComposerCleared=Get-Command Wait-AidosDesktopChatGPTFreshComposerCleared -CommandType Function -ErrorAction Stop',[StringComparison]::Ordinal) -ge 0) 'bounded fresh composer wait command is captured before deferred callback execution'
Assert-Fresh ($source.IndexOf('& $freshComposerObservation -Context $Context',[StringComparison]::Ordinal) -ge 0) 'deferred callbacks invoke the captured fresh observation command explicitly'
Assert-Fresh ($source.IndexOf('& $freshComposerCleared -Context $Context -PromptText $PromptText',[StringComparison]::Ordinal) -ge 0) 'post-submit callback invokes the captured bounded wait command explicitly'
Assert-Fresh ($source.IndexOf("if(`$message -ne 'ChatGPT composer still contains the exact outbound payload after submit; committed-send proof is absent.'){throw}",[StringComparison]::Ordinal) -ge 0) 'send recovery is limited to the known stale post-submit failure'
Assert-Fresh ($source.IndexOf("committed_message_proof_source='FRESH_EMPTY_COMPOSER'",[StringComparison]::Ordinal) -ge 0) 'alternate commit proof records its source explicitly'
Assert-Fresh ($source.IndexOf('Add-AidosDesktopChatGPTFreshComposerProof -Backend $backend',[StringComparison]::Ordinal) -ge 0) 'fresh composer proof is composed into the live resilient Windows backend'

Write-Output "PASS: $passed fresh composer proof assertions"
