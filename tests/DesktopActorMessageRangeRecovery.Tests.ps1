[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-MessageRange([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

$assignmentId='ecb5b567-9513-4f06-8efa-4f6c076448cc'
$assignmentSha='a443fb06606602e8951e600be84526c7ed585647da4447f79ce5db052689c8a4'
$bound=[pscustomobject]@{
    assignment=[pscustomobject]@{assignment_id=$assignmentId}
    sha256=$assignmentSha
}
$summary=('Evidence-backed response text. ' * 30).Trim()
$response=[ordered]@{
    schema_version='0.1'
    envelope_type='RUNTIME_ACTOR_RESULT'
    assignment_id=$assignmentId
    assignment_sha256=$assignmentSha
    project_id='AIDOS-INTERFACE'
    actor_role='THINKER'
    actor_identity='DEFINITION_AGENT'
    action='RESOLVE_PROJECT_APPLICABILITY'
    binding=[ordered]@{project_state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;review_id=$null}
    outcome='COMPLETED'
    result=[ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary=$summary;proposed_artifacts=@();human_input_request=$null}
    responded_at='2026-08-19T01:28:00+02:00'
}|ConvertTo-Json -Depth 20 -Compress

Assert-MessageRange ($response.Length-gt385) 'fixture is longer than the observed Classic leaf truncation boundary'
$leaf=$response.Substring(0,385)
$direct=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts @($leaf) -Assignment $bound
Assert-MessageRange ($null-eq$direct) 'truncated leaf text is never accepted as a complete actor response'

$recovered=Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts -ElementTexts @($leaf) -AncestorRangeTexts @($response) -Assignment $bound
Assert-MessageRange ($recovered-eq$response) 'complete parent message range recovers an actor response whose leaf text is truncated'

$wrongBound=[pscustomobject]@{assignment=[pscustomobject]@{assignment_id=$assignmentId};sha256=(('f'*64)-join'')}
$wrong=Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts -ElementTexts @($leaf) -AncestorRangeTexts @($response) -Assignment $wrongBound
Assert-MessageRange ($null-eq$wrong) 'ancestor-range recovery preserves exact assignment-hash binding'

$missing=Select-AidosDesktopChatGPTResolvedActorResponseFromHierarchyTexts -ElementTexts @($leaf) -AncestorRangeTexts @() -Assignment $bound
Assert-MessageRange ($null-eq$missing) 'truncated leaf remains unresolved when no complete ancestor range is available'

Write-Output "PASS: $passed desktop actor message-range recovery assertions"
