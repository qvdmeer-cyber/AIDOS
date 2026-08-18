[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDesktopChatGPTWindowDiscovery.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-ActorResponse([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

$assignmentId='6f2b07a8-c8ef-4f51-b771-14862a733c48'
$assignmentSha='ceeda5122513c3a56e086697bd711e9636add1ba24d0491a86083e2a4f20b9c6'
$bound=[pscustomobject]@{
    assignment=[pscustomobject]@{assignment_id=$assignmentId}
    sha256=$assignmentSha
}
$template=@"
{"schema_version":"0.1","envelope_type":"RUNTIME_ACTOR_RESULT","assignment_id":"$assignmentId","assignment_sha256":"$assignmentSha","outcome":"COMPLETED","result":{"summary":"REQUIRED: resolve this value"},"responded_at":"REQUIRED: ISO-8601 completion timestamp"}
"@.Trim()
$response1=@"
{"schema_version":"0.1","envelope_type":"RUNTIME_ACTOR_RESULT","assignment_id":"$assignmentId","assignment_sha256":"$assignmentSha","project_id":"AIDOS-INTERFACE","actor_role":"THINKER","actor_identity":"DEFINITION_AGENT","action":"RESOLVE_PROJECT_APPLICABILITY","binding":{"project_state":"IDLE","definition_id":null,"definition_version":null,"execution_id":null,"revision":null,"review_id":null},"outcome":"COMPLETED","result":{"result_type":"DEFINITION_THINKER_OUTPUT","summary":"Resolved object with escaped quote: \"browser\" and literal brace text {ok}.","proposed_artifacts":[{"artifact_type":"PROJECT_APPLICABILITY_PROPOSAL","authority_classification":"REPO_VERIFIABLE","preset_ids":["WEB_APPLICATION"],"selection_source":"BASELINE_DERIVED","overrides":[],"source_refs":["docs/PRODUCT.md"]}],"human_input_request":null},"responded_at":"2026-08-18T22:20:00Z"}
"@.Trim()
$response2=$response1.Replace('Resolved object with escaped quote: \"browser\" and literal brace text {ok}.','Resolved corrected response.').Replace('2026-08-18T22:20:00Z','2026-08-18T22:21:00Z')

$objects=@(Get-AidosDesktopChatGPTJsonObjectCandidates -Text ("prefix`n$template`nassistant`n```json`n$response1`n```"))
Assert-ActorResponse ($objects.Count-ge2) 'balanced JSON extraction finds template and response objects inside mixed conversation text'
Assert-ActorResponse ($objects[-1]-eq$response1) 'balanced JSON extraction preserves the final resolved actor-response object exactly'

$mixed="You are the AIDOS Definition Thinker.`nRUNTIME_ACTOR_RESULT_TEMPLATE:`n$template`nAssistant response:`n```json`n$response1`n```"
$selected=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts @($mixed) -Assignment $bound
Assert-ActorResponse ($selected-eq$response1) 'resolved response selector rejects the unresolved prompt template and returns the actor response'

$splitAt1=[int]($response1.Length/3)
$splitAt2=[int](2*$response1.Length/3)
$fragments=@(
    'RootWebArea URL value',
    $response1.Substring(0,$splitAt1),
    $response1.Substring($splitAt1,$splitAt2-$splitAt1),
    $response1.Substring($splitAt2)
)
$selectedSplit=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts $fragments -Assignment $bound
Assert-ActorResponse ($selectedSplit-eq$response1) 'response selector reconstructs a JSON response split across adjacent UIA text controls'

$templateOnly=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts @($template) -Assignment $bound
Assert-ActorResponse ($null-eq$templateOnly) 'unresolved response template is never accepted as an actor response'

$wrongBound=[pscustomobject]@{assignment=[pscustomobject]@{assignment_id=$assignmentId};sha256=('f'*64)}
$wrongHash=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts @($response1) -Assignment $wrongBound
Assert-ActorResponse ($null-eq$wrongHash) 'assignment-hash mismatch is rejected when the bound hash is available'

$latest=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts @("$template`n$response1`n$response2") -Assignment $bound
Assert-ActorResponse ($latest-eq$response2) 'when multiple bound completed responses exist, the latest rendered response is selected'

$otherAssignment=$response1.Replace($assignmentId,[guid]::NewGuid().ToString())
$wrongAssignment=Select-AidosDesktopChatGPTResolvedActorResponseText -Texts @($otherAssignment) -Assignment $bound
Assert-ActorResponse ($null-eq$wrongAssignment) 'response for another assignment is rejected'

Write-Output "PASS: $passed desktop actor-response extraction assertions"
