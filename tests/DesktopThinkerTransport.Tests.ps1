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
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed desktop Thinker transport assertions"
