[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$modulePath=Join-Path $root 'bridge/AidosReviewAuthorityRecovery.psm1'
$toolPath=Join-Path $root 'tools/Request-AidosIndependentReReview.ps1'
Import-Module $modulePath -Force -DisableNameChecking

$script:passed=0
function Assert-ReReview([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

function New-ReviewRecord {
    param(
        [string]$Reason='Independent evidence confirms the accepted execution passed validation.',
        [string]$RespondedAt='2026-08-20T10:10:00.0000000+00:00',
        [object[]]$RepairGuidance=@()
    )
    [pscustomobject][ordered]@{
        review_id='review-authority-1'
        response=[pscustomobject][ordered]@{
            outcome='PASS'
            reason=$Reason
            repair_guidance=@($RepairGuidance)
            responded_at=$RespondedAt
        }
    }
}

$placeholder=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord -Reason 'Replace with the evidence-based review reason.')
Assert-ReReview (-not[bool]$placeholder.valid -and [bool]$placeholder.recoverable -and [string]$placeholder.reason-eq'UNRESOLVED_RESPONSE_TEMPLATE') 'legacy placeholder review is classified as recoverable invalid authority'

$required=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord -RepairGuidance @('REQUIRED: replace or remove'))
Assert-ReReview (-not[bool]$required.valid -and [string]$required.reason-eq'UNRESOLVED_RESPONSE_TEMPLATE') 'nested unresolved response values invalidate review authority'

$badTime=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord -RespondedAt 'not-a-time')
Assert-ReReview (-not[bool]$badTime.valid -and [string]$badTime.reason-eq'REVIEW_TIMESTAMP_INVALID') 'invalid response timestamp is recoverable authority failure'

$valid=Get-AidosReviewAuthorityAssessment -ReviewRecord (New-ReviewRecord)
Assert-ReReview ([bool]$valid.valid -and -not[bool]$valid.recoverable -and [string]$valid.reason-eq'VALID') 'resolved evidence-based review remains authority-valid'

$moduleSource=Get-Content -LiteralPath $modulePath -Raw -Encoding UTF8
$toolSource=Get-Content -LiteralPath $toolPath -Raw -Encoding UTF8
Assert-ReReview ($moduleSource -match "transport_state-ne'CLEANED'") 'recovery is restricted to durable cleaned historical reviews'
Assert-ReReview ($moduleSource -match "state.state-ne'IDLE'.*state.state-ne'TASK_READY'") 'recovery accepts only idle or its idempotent already-planned task state'
Assert-ReReview ($moduleSource -match "RepairKind 'REVIEW_AUTHORITY_RECOVERY'") 'recovery uses a distinct durable repair kind'
Assert-ReReview ($moduleSource -match 'Write-AidosRepairRevision') 'recovery returns through the existing revision model rather than rewriting history'
Assert-ReReview ($moduleSource -match 'AUTHORITY_AUDIT\.json') 'recovery persists a bound authority audit'
Assert-ReReview ($toolSource -match 'Request-AidosIndependentReReview') 'operator entrypoint invokes the bounded recovery primitive'

Write-Output "PASS: $passed review authority recovery assertions"
