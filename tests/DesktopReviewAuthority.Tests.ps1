[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$modulePath=Join-Path $root 'bridge/AidosDesktopSessionGate.psm1'
Import-Module $modulePath -Force -DisableNameChecking

$script:passed=0
function Assert-ReviewAuthority([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

$manifestSha='b'*64
$assignment=[pscustomobject][ordered]@{
    review_id='review-authority-1'
    package_manifest_sha256=$manifestSha
}

function New-ReviewResponseText {
    param(
        [string]$Outcome='PASS',
        [string]$Reason='Evidence shows the bound validation and terminal result satisfy the accepted execution.',
        [string]$RespondedAt='2026-08-20T10:05:00.0000000+00:00',
        [object[]]$RepairGuidance=@()
    )
    [ordered]@{
        schema_version='0.1'
        envelope_type='REVIEW_RESPONSE'
        review_id='review-authority-1'
        project_id='AIDOS-INTERFACE'
        project_root='C:\AIDOS\AIDOS-interface'
        project_mode='NEW_PROJECT'
        definition_id='DEF-1'
        definition_version=1
        execution_id='EXEC-1'
        revision=3
        reviewer_role='WORKER_AGENT'
        reviewer_identity='agents/WORKER_AGENT.md'
        assignment_sha256=('a'*64)
        package_manifest_sha256=$manifestSha
        outcome=$Outcome
        reason=$Reason
        evidence_refs=@([ordered]@{kind='VALIDATION_RESULT';path='.aidos/evidence.json';sha256=('c'*64)})
        repair_guidance=@($RepairGuidance)
        responded_at=$RespondedAt
        responded_by='agents/WORKER_AGENT.md'
    }|ConvertTo-Json -Depth 100 -Compress
}

$legacyTemplate=New-ReviewResponseText -Reason 'Replace with the evidence-based review reason.'
Assert-ReviewAuthority ([string]::IsNullOrWhiteSpace([string](Select-AidosDesktopStrictReviewResponseText -Texts @($legacyTemplate) -Assignment $assignment))) 'legacy fully bound PASS template is not accepted as an inbound review'

$requiredTemplate=New-ReviewResponseText -Outcome 'REQUIRED: choose one permitted outcome' -Reason 'REQUIRED_NONEMPTY: evidence-based review reason' -RespondedAt 'REQUIRED: ISO-8601 timestamp' -RepairGuidance @('REQUIRED: replace or remove')
Assert-ReviewAuthority ([string]::IsNullOrWhiteSpace([string](Select-AidosDesktopStrictReviewResponseText -Texts @($requiredTemplate) -Assignment $assignment))) 'unresolved response-template sentinels are rejected recursively'

$badTimestamp=New-ReviewResponseText -RespondedAt 'not-a-time'
Assert-ReviewAuthority ([string]::IsNullOrWhiteSpace([string](Select-AidosDesktopStrictReviewResponseText -Texts @($badTimestamp) -Assignment $assignment))) 'non-ISO review timestamps are rejected'

$resolved=New-ReviewResponseText
$selected=Select-AidosDesktopStrictReviewResponseText -Texts @($legacyTemplate,$resolved) -Assignment $assignment
Assert-ReviewAuthority (-not[string]::IsNullOrWhiteSpace([string]$selected)) 'a separate resolved reviewer response is selected when the outbound template is also visible'
$parsed=$selected|ConvertFrom-Json -Depth 100
Assert-ReviewAuthority ([string]$parsed.reason -eq 'Evidence shows the bound validation and terminal result satisfy the accepted execution.') 'selected review is the evidence-based response rather than the template'

$fenced=[string]::Concat('```json',"`n",$resolved,"`n",'```')
$fencedSelected=Select-AidosDesktopStrictReviewResponseText -Texts @($fenced) -Assignment $assignment
Assert-ReviewAuthority (-not[string]::IsNullOrWhiteSpace([string]$fencedSelected)) 'a single fenced resolved response remains supported'

$wrongAssignment=[pscustomobject]@{review_id='review-authority-1';package_manifest_sha256=('d'*64)}
Assert-ReviewAuthority ([string]::IsNullOrWhiteSpace([string](Select-AidosDesktopStrictReviewResponseText -Texts @($resolved) -Assignment $wrongAssignment))) 'manifest-mismatched response surfaces are ignored'

Assert-ReviewAuthority ([string](Resolve-AidosDesktopReviewMessageDirection -Texts @('You said:')) -eq 'USER') 'user accessibility heading is classified as USER'
Assert-ReviewAuthority ([string](Resolve-AidosDesktopReviewMessageDirection -Texts @('ChatGPT said:')) -eq 'ASSISTANT') 'ChatGPT accessibility heading is classified as ASSISTANT'
Assert-ReviewAuthority ([string](Resolve-AidosDesktopReviewMessageDirection -Texts @('AIDOS Repository Thinker said:')) -eq 'ASSISTANT') 'custom GPT accessibility heading is classified as ASSISTANT'
Assert-ReviewAuthority ([string](Resolve-AidosDesktopReviewMessageDirection -Texts @('You said:','ChatGPT said:')) -eq 'UNKNOWN') 'mixed ancestor conversation text fails direction closed'
Assert-ReviewAuthority ([string](Resolve-AidosDesktopReviewMessageDirection -Texts @('{"reason":"Anything said:"}')) -eq 'UNKNOWN') 'JSON response content cannot impersonate an accessibility role heading'

$userSurface=[pscustomobject]@{direction='USER';texts=@($resolved)}
$unknownSurface=[pscustomobject]@{direction='UNKNOWN';texts=@($resolved)}
$assistantSurface=[pscustomobject]@{direction='ASSISTANT';texts=@($resolved)}
Assert-ReviewAuthority ([string]::IsNullOrWhiteSpace([string](Select-AidosDesktopStrictReviewResponseSurface -Surfaces @($userSurface) -Assignment $assignment))) 'a valid-looking JSON response on the outbound USER message surface is rejected'
Assert-ReviewAuthority ([string]::IsNullOrWhiteSpace([string](Select-AidosDesktopStrictReviewResponseSurface -Surfaces @($unknownSurface) -Assignment $assignment))) 'a valid-looking JSON response without proven direction is rejected'
$assistantSelected=Select-AidosDesktopStrictReviewResponseSurface -Surfaces @($userSurface,$assistantSurface) -Assignment $assignment
Assert-ReviewAuthority (-not[string]::IsNullOrWhiteSpace([string]$assistantSelected)) 'only the separately proven ASSISTANT response surface is accepted when the outbound prompt remains visible'

$stub=[pscustomobject]@{
    AssertInteractiveSession={ $true }
    ReadLatestResponseText={ 'underlying reader must be replaced' }
}
$gate=[pscustomobject]@{snapshot=$null;decision=$null}
$gated=New-AidosDesktopSessionGateBackend -Backend $stub -Policy UNATTENDED_ALLOWED -GateState $gate -UseStrictUiResponseReader $true
$scopeResult=& $gated.ReadLatestResponseText ([pscustomobject]@{window_handle=''}) ([pscustomobject]@{}) 1 $assignment
Assert-ReviewAuthority ($null-eq$scopeResult) 'strict-reader callback retains its private command after leaving module construction scope'

$source=Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8
Assert-ReviewAuthority ($source -match 'New-AidosDesktopChatGPTResilientWindowsBackend') 'default desktop review path is wired to the resilient conversation backend'
Assert-ReviewAuthority ($source -match '\$\{function:Get-AidosDesktopStrictReviewResponseText\}') 'strict reader is captured before the persistent callback closure is created'
Assert-ReviewAuthority ($source -match "direction-ne'ASSISTANT'") 'strict extraction requires a proven assistant-message surface'
$surfaceFunction=[regex]::Match($source,'(?s)function Get-AidosDesktopReviewMessageSurface.*?function Get-AidosDesktopStrictReviewResponseText').Value
Assert-ReviewAuthority (-not$surfaceFunction.Contains('Get-AidosDesktopChatGPTElementText $current')) 'message direction is derived from accessibility metadata, never candidate response content'

Write-Output "PASS: $passed desktop review authority assertions"
