[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryReviewHandoff.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-ReviewHandoff([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-Throws([scriptblock]$Action,[string]$Pattern,[string]$Message){
    try{& $Action;throw "ASSERTION FAILED: $Message"}catch{if($_.Exception.Message -notmatch $Pattern){throw}};$script:passed++
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-review-handoff-'+[guid]::NewGuid().ToString('N'))
$reviewId='REVIEW-1';$reviewRoot=Join-Path $temp ".aidos/reviews/$reviewId"
New-Item -ItemType Directory -Path $reviewRoot -Force|Out-Null
try{
    $responseSha=('a'*64)
    $record=[ordered]@{
        schema_version='0.1';review_id=$reviewId;transport_state='CLEANED';response=[ordered]@{outcome='REPAIR'};response_sha256=$responseSha
        response_accepted_at='2026-08-21T12:00:00Z';decision=[ordered]@{outcome='REPAIR';target_state='TASK_READY'}
        consumed_at='2026-08-21T12:00:01Z';consume_ack=[ordered]@{review_id=$reviewId};cleaned_at='2026-08-21T12:00:02Z'
    }
    $record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $reviewRoot 'REVIEW.json') -Encoding utf8NoBOM

    $proof=Get-AidosRepositoryReviewResultProof -ProjectRoot $temp -ReviewId $reviewId -ResponseSha256 $responseSha
    Assert-ReviewHandoff ([string]$proof.payload_ref-eq'.aidos/reviews/REVIEW-1/REVIEW.json') 'cleaned result uses the durable review record as handoff payload'
    Assert-ReviewHandoff ([string]$proof.response_sha256-eq$responseSha) 'proof binds the exact submitted response hash'
    Assert-ReviewHandoff ([string]$proof.record.transport_state-eq'CLEANED' -and $proof.record.consume_ack.review_id-eq$reviewId) 'proof retains durable consumption and cleanup evidence'
    Assert-ReviewHandoff (-not(Test-Path -LiteralPath (Join-Path $reviewRoot 'RESPONSE.json'))) 'proof does not require the intentionally cleaned canonical response file'

    Assert-Throws {Get-AidosRepositoryReviewResultProof -ProjectRoot $temp -ReviewId $reviewId -ResponseSha256 ('b'*64)|Out-Null} 'submitted response hash' 'a different submitted response hash fails closed'
    $record.transport_state='DECIDED';$record.consumed_at=$null;$record.consume_ack=$null;$record.cleaned_at=$null
    $record|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $reviewRoot 'REVIEW.json') -Encoding utf8NoBOM
    Assert-Throws {Get-AidosRepositoryReviewResultProof -ProjectRoot $temp -ReviewId $reviewId -ResponseSha256 $responseSha|Out-Null} 'consumption and cleanup' 'an accepted but unconsumed response fails closed'

    Write-Output "PASS: $passed repository review handoff assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
