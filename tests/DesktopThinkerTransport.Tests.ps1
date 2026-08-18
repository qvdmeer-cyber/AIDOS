[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorTransport.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Thinker([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$thinkerSource=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1') -Raw -Encoding UTF8
Assert-Thinker ($thinkerSource -match 'MaximumDocumentBytes=262144' -and $thinkerSource -match 'MaximumTotalBytes=786432') 'Thinker source pack admits a complete accepted Project Baseline within bounded transport limits'
Assert-Thinker ($thinkerSource -match 'Get-AidosDesktopThinkerCommittedPromptProof' -and $thinkerSource -match 'BOUND_ACTOR_RESPONSE_VISIBLE_IN_ENROLLED_CONVERSATION') 'delayed committed-send recovery requires prompt or resolved-response evidence from the enrolled conversation'
Assert-Thinker ($thinkerSource -match "PSObject.Properties\['ProveCommittedPrompt'\]" -and $thinkerSource -match 'without resending') 'restart recovery exposes a testable proof seam and resumes response polling without another send'

function New-ThinkerProject {
    param([string]$ProjectRoot)
    New-Item -ItemType Directory -Path (Join-Path $ProjectRoot '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ProjectRoot '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ProjectRoot '.aidos/runtime') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ProjectRoot 'docs') -Force|Out-Null
    & git -C $ProjectRoot init -q
    & git -C $ProjectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $ProjectRoot config user.name 'AIDOS Tests'
    & git -C $ProjectRoot remote add origin 'https://example.invalid/thinker.git'
    [ordered]@{schema_version='0.1';project_id='THINKER-PROJECT';project_mode='NEW_PROJECT';repository='https://example.invalid/thinker.git';official_root=$ProjectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$ProjectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $ProjectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='THINKER-PROJECT';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $ProjectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.3.0';catalog_version='0.2.0';project_id='THINKER-PROJECT';baseline_version=1;accepted_at='2026-08-18T00:00:00Z';accepted_by='TEST';accepted_commit='abc';items=[ordered]@{}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $ProjectRoot '.aidos/documentation/PROJECT_BASELINE.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.1.0';project_id='THINKER-PROJECT'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $ProjectRoot '.aidos/documentation/PROJECT_ACCESS.json') -Encoding utf8NoBOM
    [ordered]@{contract_version='0.2.0';project_id='THINKER-PROJECT'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $ProjectRoot '.aidos/evidence/EVIDENCE_INVENTORY.json') -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $ProjectRoot 'docs/PRODUCT.md') -Value '# Product`nDefinition transport test product.' -Encoding utf8NoBOM
    & git -C $ProjectRoot add .
    & git -C $ProjectRoot commit -q -m init
}

function New-ThinkerApplicabilityResultText {
    param([Parameter(Mandatory)]$Created,[string]$RespondedAt='2026-08-18T00:00:01Z')
    $assignment=$Created.assignment
    [ordered]@{
        schema_version='0.1'
        envelope_type='RUNTIME_ACTOR_RESULT'
        assignment_id=[string]$assignment.assignment_id
        assignment_sha256=[string]$Created.assignment_sha256
        project_id=[string]$assignment.project_id
        actor_role=[string]$assignment.actor_role
        actor_identity=[string]$assignment.actor_identity
        action=[string]$assignment.action
        binding=$assignment.binding
        outcome='COMPLETED'
        result=[ordered]@{
            result_type='DEFINITION_THINKER_OUTPUT'
            summary='Applicability resolved from bounded authorized evidence.'
            proposed_artifacts=@([ordered]@{
                artifact_type='PROJECT_APPLICABILITY_PROPOSAL'
                authority_classification='REPO_VERIFIABLE'
                preset_ids=@('WEB_APPLICATION')
                selection_source='BASELINE_DERIVED'
                overrides=@()
                source_refs=@('.aidos/PROJECT.json','docs/PRODUCT.md','AGENTS.md')
            })
            human_input_request=$null
        }
        responded_at=$RespondedAt
    }|ConvertTo-Json -Depth 100 -Compress
}

function New-DelayedThinkerCommitBackend {
    param(
        [Parameter(Mandatory)][string]$AssignmentSha256,
        [Parameter(Mandatory)][string]$ResponseText,
        [bool]$CommittedPromptVisible=$true
    )
    $fingerprint=('f'*64)
    $state=[pscustomobject]@{
        enrollment_send_count=0
        actor_send_count=0
        proof_count=0
        proof_text=$null
        composer_text=$null
        prompt_visible=$false
        last_prompt=$null
        assignment_sha256=$AssignmentSha256
    }
    [pscustomobject]@{
        State=$state
        AssertInteractiveSession=({param();$true}).GetNewClosure()
        GetProcessContext=({param([string]$ProcessName);[pscustomobject]@{present=$true;process_id=42;process_name=$ProcessName;session_id=1;main_window_handle='99';window_handle='99';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$true;window_is_visible=$true;window_source='stub'}}).GetNewClosure()
        FocusConversation=({param($Context,$Enrollment);$Context.window_is_foreground=$true;$Context}).GetNewClosure()
        InspectComposer=({
            param($Context,$Enrollment)
            [pscustomobject]@{
                present=$true
                composer_text=$state.composer_text
                composer_text_sha256=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){$null}else{[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$state.composer_text))).ToLowerInvariant()}
                composer_text_length=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){0}else{([string]$state.composer_text).Length}
            }
        }).GetNewClosure()
        SendPrompt=({
            param($Context,$Enrollment,[string]$PromptText,$BoundAssignment)
            $isEnrollmentMarker=$PromptText.IndexOf('AIDOS_THINKER_TRANSPORT_ENROLLMENT::',[StringComparison]::OrdinalIgnoreCase)-ge0
            if($isEnrollmentMarker){
                $state.enrollment_send_count++
                if($PromptText-match'AIDOS_THINKER_TRANSPORT_ENROLLMENT::(?<id>[0-9a-f-]+)'){$state.proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::'+$Matches.id}
                return [pscustomobject]@{schema_version='0.1';assignment_id='ENROLLMENT';assignment_sha256=('0'*64);conversation_fingerprint_sha256=$fingerprint;composer_state='COMMITTED';composer_result='EMPTY';mutation_occurred=$false;send_invocation_state='INVOKED';committed_message_proof_state='PROVEN';failure_reason=$null;committed=$true}
            }
            $state.actor_send_count++
            $state.last_prompt=$PromptText
            $state.composer_text=$PromptText
            throw 'Fresh ChatGPT composer still contains the exact outbound payload after bounded submit observation; committed-send proof is absent.'
        }).GetNewClosure()
        LocateConversation=({
            param($Context,[string]$ProofText,$Enrollment)
            if([string]::IsNullOrWhiteSpace([string]$state.proof_text)-or[string]$state.proof_text-ne$ProofText){throw 'Stub Thinker conversation proof is not present.'}
            [pscustomobject]@{conversation_fingerprint=[ordered]@{window_title=$Context.window_title;window_class_name=$Context.window_class_name;conversation_proof_text=$ProofText;path=@([ordered]@{name='stub';control_type='Window'})};conversation_fingerprint_sha256=$fingerprint}
        }).GetNewClosure()
        ProveCommittedPrompt=({
            param($Context,$Enrollment,$BoundAssignment,[string]$PromptText)
            $state.proof_count++
            $proven=([bool]$state.prompt_visible -and [bool]$CommittedPromptVisible)
            [pscustomobject][ordered]@{
                schema_version='0.1'
                assignment_id=[string]$BoundAssignment.assignment.assignment_id
                assignment_sha256=[string]$BoundAssignment.sha256
                conversation_fingerprint_sha256=[string]$Enrollment.conversation_fingerprint_sha256
                prompt_sha256=([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($PromptText))).ToLowerInvariant())
                proof_state=if($proven){'PROVEN'}else{'NOT_PROVEN'}
                proof_source=if($proven){'EXACT_BOUND_PROMPT_VISIBLE_IN_ENROLLED_CONVERSATION'}else{'BOUND_PROMPT_NOT_VISIBLE_IN_ENROLLED_CONVERSATION'}
                missing_fragments=if($proven){@()}else{@('runtime_assignment_heading')}
            }
        }).GetNewClosure()
        ReadActorResponseText=({
            param($Context,$Enrollment,[int]$Attempt,$Assignment)
            if(-not[bool]$state.prompt_visible-or-not[bool]$CommittedPromptVisible){return $null}
            $ResponseText
        }).GetNewClosure()
    }
}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-desktop-thinker-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$stateRoot=Join-Path $base 'host'
try {
    New-ThinkerProject -ProjectRoot $projectRoot
    $project=[pscustomobject]@{project_id='THINKER-PROJECT';local_root=$projectRoot}
    $selection=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    $created=New-AidosRuntimeActorAssignment -Project $project -Selection $selection
    $a=$created.assignment
    $result=[ordered]@{
        schema_version='0.1'
        envelope_type='RUNTIME_ACTOR_RESULT'
        assignment_id=[string]$a.assignment_id
        assignment_sha256=[string]$created.assignment_sha256
        project_id=[string]$a.project_id
        actor_role=[string]$a.actor_role
        actor_identity=[string]$a.actor_identity
        action=[string]$a.action
        binding=$a.binding
        outcome='COMPLETED'
        result=[ordered]@{
            result_type='DEFINITION_THINKER_OUTPUT'
            summary='Applicability resolved from bounded authorized evidence.'
            proposed_artifacts=@([ordered]@{
                artifact_type='PROJECT_APPLICABILITY_PROPOSAL'
                authority_classification='REPO_VERIFIABLE'
                preset_ids=@('WEB_APPLICATION')
                selection_source='BASELINE_DERIVED'
                overrides=@()
                source_refs=@('.aidos/PROJECT.json','docs/PRODUCT.md','AGENTS.md')
            })
            human_input_request=$null
        }
        responded_at='2026-08-18T00:00:01Z'
    }
    $backend=New-AidosDesktopThinkerStubBackend -ResponseText ($result|ConvertTo-Json -Depth 100 -Compress)
    $handoff=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $projectRoot -AssignmentId ([string]$a.assignment_id) -StateRoot $stateRoot -Backend $backend -ResponseTimeoutSeconds 1
    $handoffTransportSummary=if($handoff.PSObject.Properties.Name -contains 'transport' -and $null -ne $handoff.transport){$handoff.transport | ConvertTo-Json -Depth 20 -Compress}else{'<no transport payload on completed handoff>'}
    Assert-Thinker ($handoff.status -eq 'HANDOFF_COMPLETE') ("desktop Thinker handoff completes with exact-bound result; actual status: {0}; details: {1}" -f [string]$handoff.status, $handoffTransportSummary)
    $enrollment=Read-AidosDesktopThinkerEnrollment -StateRoot $stateRoot
    Assert-Thinker ($enrollment.transport_type -eq 'DESKTOP_CHATGPT_THINKER' -and $enrollment.status -eq 'ENROLLED') 'Thinker conversation is auto-enrolled durably'
    Assert-Thinker ($backend.State.send_count -eq 2) 'enrollment marker and actor assignment are each sent exactly once'
    Assert-Thinker ($backend.State.last_prompt -match 'AUTHORIZED_SOURCE_DOCUMENTS' -and $backend.State.last_prompt -match 'docs/PRODUCT.md') 'actor prompt carries authorized project source pack'
    $transport=Read-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$a.assignment_id)
    Assert-Thinker ($transport.status -eq 'COMPLETED') 'Thinker result closes transport state'
    $composer=Read-AidosDesktopThinkerComposerState -StateRoot $stateRoot -AssignmentId ([string]$a.assignment_id)
    Assert-Thinker ($composer.assignment_sha256 -eq $created.assignment_sha256 -and $composer.composer_state -eq 'COMMITTED' -and $composer.committed_message_proof_state -eq 'PROVEN') 'composer state records exact assignment-bound committed-message proof before activation'

    $staged=[pscustomobject][ordered]@{schema_version='0.1';assignment_id='restart-assignment';assignment_sha256=('c'*64);conversation_fingerprint_sha256=('d'*64);prompt_sha256=('e'*64);composer_state='STAGED';mutation_occurred=$false;send_invocation_state='NOT_INVOKED';committed_message_proof_state='NOT_PROVEN';failure_reason=$null;updated_at='2026-08-18T00:00:00Z'}
    Write-AidosDesktopThinkerComposerState -StateRoot $stateRoot -State $staged|Out-Null
    $stagedRead=Read-AidosDesktopThinkerComposerState -StateRoot $stateRoot -AssignmentId 'restart-assignment'
    Assert-Thinker ($stagedRead.composer_state -eq 'STAGED' -and -not$stagedRead.mutation_occurred -and $stagedRead.send_invocation_state -eq 'NOT_INVOKED') 'staged composer state survives restart inspection without implying a send'
    $stagedRead.send_invocation_state='INVOKED';$stagedRead.updated_at='2026-08-18T00:00:01Z';Write-AidosDesktopThinkerComposerState -StateRoot $stateRoot -State $stagedRead|Out-Null
    $restarted=Read-AidosDesktopThinkerComposerState -StateRoot $stateRoot -AssignmentId 'restart-assignment'
    Assert-Thinker ($restarted.send_invocation_state -eq 'INVOKED' -and $restarted.committed_message_proof_state -eq 'NOT_PROVEN') 'restart preserves unresolved send invocation for reconciliation instead of duplicate send'

    $replay=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $projectRoot -AssignmentId ([string]$a.assignment_id) -StateRoot $stateRoot -Backend $backend -ResponseTimeoutSeconds 1
    Assert-Thinker ($replay.status -eq 'HANDOFF_COMPLETE' -and $replay.idempotent) 'completed Thinker handoff replays idempotently'
    Assert-Thinker ($backend.State.send_count -eq 2) 'completed replay does not send again'

    $secondRoot=Join-Path $base 'locked-project'
    New-ThinkerProject -ProjectRoot $secondRoot
    $project2=[pscustomobject]@{project_id='THINKER-PROJECT';local_root=$secondRoot}
    $selection2=Get-AidosRuntimeNextActor -ProjectRoot $secondRoot
    $created2=New-AidosRuntimeActorAssignment -Project $project2 -Selection $selection2
    $lockedBackend=New-AidosDesktopThinkerStubBackend -InteractiveSession:$false
    $waiting=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $secondRoot -AssignmentId ([string]$created2.assignment.assignment_id) -StateRoot (Join-Path $base 'locked-host') -Backend $lockedBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($waiting.status -eq 'WAITING_TRANSPORT') 'locked desktop leaves assignment durably waiting for transport'

    $proofRoot=Join-Path $base 'proof-project'
    $proofState=Join-Path $base 'proof-host'
    New-ThinkerProject -ProjectRoot $proofRoot
    $project3=[pscustomobject]@{project_id='THINKER-PROJECT';local_root=$proofRoot}
    $selection3=Get-AidosRuntimeNextActor -ProjectRoot $proofRoot
    $created3=New-AidosRuntimeActorAssignment -Project $project3 -Selection $selection3
    $proofBackend=New-AidosDesktopThinkerStubBackend -ConversationProofAvailable:$false
    $firstPending=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $proofRoot -AssignmentId ([string]$created3.assignment.assignment_id) -StateRoot $proofState -Backend $proofBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($firstPending.status -eq 'WAITING_TRANSPORT') 'unavailable conversation proof leaves enrollment pending instead of failing open'
    $pendingEnrollment=Read-AidosDesktopThinkerEnrollment -StateRoot $proofState
    $pendingMarker=[string]$pendingEnrollment.conversation_proof_text
    Assert-Thinker ($pendingEnrollment.status -eq 'PENDING_ENROLLMENT' -and -not[string]::IsNullOrWhiteSpace($pendingMarker)) 'pending enrollment marker is durable before proof succeeds'
    Assert-Thinker ($proofBackend.State.send_count -eq 1) 'first proof failure sends exactly one enrollment marker'
    $secondPending=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $proofRoot -AssignmentId ([string]$created3.assignment.assignment_id) -StateRoot $proofState -Backend $proofBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($secondPending.status -eq 'WAITING_TRANSPORT') 'replayed proof failure remains waiting'
    $pendingReplay=Read-AidosDesktopThinkerEnrollment -StateRoot $proofState
    Assert-Thinker ([string]$pendingReplay.conversation_proof_text -eq $pendingMarker) 'replayed proof failure reuses the same enrollment marker'
    Assert-Thinker ($proofBackend.State.send_count -eq 1) 'replayed proof failure never sends another enrollment marker'

    $delayedRoot=Join-Path $base 'delayed-commit-project'
    $delayedState=Join-Path $base 'delayed-commit-host'
    New-ThinkerProject -ProjectRoot $delayedRoot
    $delayedProject=[pscustomobject]@{project_id='THINKER-PROJECT';local_root=$delayedRoot}
    $delayedSelection=Get-AidosRuntimeNextActor -ProjectRoot $delayedRoot
    $delayedCreated=New-AidosRuntimeActorAssignment -Project $delayedProject -Selection $delayedSelection
    $delayedResponse=New-ThinkerApplicabilityResultText -Created $delayedCreated -RespondedAt '2026-08-18T00:00:02Z'
    $delayedBackend=New-DelayedThinkerCommitBackend -AssignmentSha256 ([string]$delayedCreated.assignment_sha256) -ResponseText $delayedResponse
    $delayedFirst=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $delayedRoot -AssignmentId ([string]$delayedCreated.assignment.assignment_id) -StateRoot $delayedState -Backend $delayedBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($delayedFirst.status -eq 'WAITING_TRANSPORT') 'bounded submit timeout remains waiting before delayed commit evidence appears'
    Assert-Thinker ($delayedBackend.State.actor_send_count -eq 1) 'initial delayed commit invokes the actor send exactly once'
    $delayedComposer1=Read-AidosDesktopThinkerComposerState -StateRoot $delayedState -AssignmentId ([string]$delayedCreated.assignment.assignment_id)
    Assert-Thinker ($delayedComposer1.send_invocation_state -eq 'FAILED' -and $delayedComposer1.failure_reason -match 'bounded submit observation') 'bounded submit timeout is persisted as unresolved committed-send proof'
    $delayedBackend.State.composer_text=$null
    $delayedBackend.State.prompt_visible=$true
    $delayedRecovered=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $delayedRoot -AssignmentId ([string]$delayedCreated.assignment.assignment_id) -StateRoot $delayedState -Backend $delayedBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($delayedRecovered.status -eq 'HANDOFF_COMPLETE') 'visible bound prompt reconciles the delayed commit and resumes actor-result capture'
    Assert-Thinker ($delayedBackend.State.actor_send_count -eq 1 -and $delayedBackend.State.proof_count -eq 1) 'delayed commit recovery proves once and never resends the assignment'
    $delayedComposer2=Read-AidosDesktopThinkerComposerState -StateRoot $delayedState -AssignmentId ([string]$delayedCreated.assignment.assignment_id)
    Assert-Thinker ($delayedComposer2.composer_state -eq 'COMMITTED' -and $delayedComposer2.send_invocation_state -eq 'INVOKED' -and $delayedComposer2.committed_message_proof_state -eq 'PROVEN') 'reconciled composer state records a committed bound message'
    Assert-Thinker ($delayedComposer2.committed_message_proof_source -eq 'EXACT_BOUND_PROMPT_VISIBLE_IN_ENROLLED_CONVERSATION') 'reconciled composer state records the durable proof source'
    $delayedTransport=Read-AidosRuntimeActorTransportState -ProjectRoot $delayedRoot -AssignmentId ([string]$delayedCreated.assignment.assignment_id)
    Assert-Thinker ($delayedTransport.status -eq 'COMPLETED') 'delayed committed assignment closes transport after the recovered actor result'

    $unprovenRoot=Join-Path $base 'unproven-commit-project'
    $unprovenState=Join-Path $base 'unproven-commit-host'
    New-ThinkerProject -ProjectRoot $unprovenRoot
    $unprovenProject=[pscustomobject]@{project_id='THINKER-PROJECT';local_root=$unprovenRoot}
    $unprovenSelection=Get-AidosRuntimeNextActor -ProjectRoot $unprovenRoot
    $unprovenCreated=New-AidosRuntimeActorAssignment -Project $unprovenProject -Selection $unprovenSelection
    $unprovenResponse=New-ThinkerApplicabilityResultText -Created $unprovenCreated -RespondedAt '2026-08-18T00:00:03Z'
    $unprovenBackend=New-DelayedThinkerCommitBackend -AssignmentSha256 ([string]$unprovenCreated.assignment_sha256) -ResponseText $unprovenResponse -CommittedPromptVisible:$false
    $unprovenFirst=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $unprovenRoot -AssignmentId ([string]$unprovenCreated.assignment.assignment_id) -StateRoot $unprovenState -Backend $unprovenBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($unprovenFirst.status -eq 'WAITING_TRANSPORT') 'unproven delayed send starts in waiting transport'
    $unprovenBackend.State.composer_text=$null
    $unprovenBackend.State.prompt_visible=$true
    $unprovenRetry=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $unprovenRoot -AssignmentId ([string]$unprovenCreated.assignment.assignment_id) -StateRoot $unprovenState -Backend $unprovenBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($unprovenRetry.status -eq 'WAITING_TRANSPORT') 'empty composer without enrolled-conversation proof remains fail-closed'
    Assert-Thinker ($unprovenBackend.State.actor_send_count -eq 1 -and $unprovenBackend.State.proof_count -eq 1) 'unproven delayed send is neither resent nor activated'
    $unprovenComposer=Read-AidosDesktopThinkerComposerState -StateRoot $unprovenState -AssignmentId ([string]$unprovenCreated.assignment.assignment_id)
    Assert-Thinker ($unprovenComposer.committed_message_proof_state -eq 'NOT_PROVEN' -and $unprovenComposer.failure_reason -match 'not visible') 'unproven delayed send preserves explicit fail-closed evidence'
    $unprovenTransport=Read-AidosRuntimeActorTransportState -ProjectRoot $unprovenRoot -AssignmentId ([string]$unprovenCreated.assignment.assignment_id)
    Assert-Thinker ($unprovenTransport.status -eq 'WAITING_TRANSPORT') 'unproven delayed send remains durably waiting'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed desktop Thinker transport assertions"
