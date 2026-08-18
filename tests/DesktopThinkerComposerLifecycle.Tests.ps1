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

function New-ThinkerLifecycleBackend {
    param(
        [Parameter(Mandatory)][string]$AssignmentSha256,
        [string]$InitialComposerText,
        [bool[]]$SendCommitQueue
    )
        $state=[pscustomobject]@{
            send_count=0
            compose_count=0
            inspect_count=0
            successful_commit_count=0
            proof_text=$null
            composer_text=$InitialComposerText
            last_prompt_text=$null
            last_prompt_sha256=$null
        assignment_sha256=$AssignmentSha256
        send_commit_queue=[System.Collections.Generic.Queue[bool]]::new()
    }
    foreach($item in @($SendCommitQueue)){ $state.send_commit_queue.Enqueue([bool]$item) }
    $responseJson=$null
    [pscustomobject]@{
        State=$state
        AssertInteractiveSession=({param();$true}).GetNewClosure()
        GetProcessContext=({param([string]$ExpectedProcessName);[pscustomobject]@{present=$true;process_id=1111;process_name=$ExpectedProcessName;session_id=1;main_window_handle='42';window_handle='42';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$true;window_is_visible=$true;window_source='stub'}}).GetNewClosure()
        LocateConversation=({
            param($Context,[string]$ProofText,$Enrollment)
            [pscustomobject]@{
                conversation_fingerprint=[ordered]@{
                    process_name=$Context.process_name
                    session_id=$Context.session_id
                    window_title=$Context.window_title
                    window_class_name=$Context.window_class_name
                    account_proof_text=$Enrollment.account_proof_text
                    conversation_proof_text=$ProofText
                    conversation_path=@([ordered]@{name='root';control_type='Window'})
                }
                conversation_fingerprint_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(([ordered]@{
                    process_name=$Context.process_name
                    session_id=$Context.session_id
                    window_title=$Context.window_title
                    window_class_name=$Context.window_class_name
                    account_proof_text=$Enrollment.account_proof_text
                    conversation_proof_text=$ProofText
                    conversation_path=@([ordered]@{name='root';control_type='Window'})
                } | ConvertTo-Json -Depth 100 -Compress)))).ToLowerInvariant()
            }
        }).GetNewClosure()
        FocusConversation=({param($Context,$Enrollment);$Context.window_is_foreground=$true;$Context.window_is_minimized=$false;$Context}).GetNewClosure()
        InspectComposer=({
            param($Context,$Enrollment)
            $state.inspect_count++
            [pscustomobject]@{
                present=$true
                composer_text=$state.composer_text
                composer_text_sha256=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){$null}else{[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$state.composer_text))).ToLowerInvariant()}
                composer_text_length=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){0}else{([string]$state.composer_text).Length}
            }
        }).GetNewClosure()
        SendPrompt=({
            param($Context,$Enrollment,[string]$PromptText,$Assignment)
            $isEnrollmentMarker=([string]$PromptText).IndexOf('AIDOS_THINKER_TRANSPORT_ENROLLMENT::',[StringComparison]::OrdinalIgnoreCase) -ge 0
            if($isEnrollmentMarker){
                if($PromptText -match 'AIDOS_THINKER_TRANSPORT_ENROLLMENT::(?<id>[0-9a-f-]+)'){
                    $state.proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::'+$Matches.id
                }
                return [pscustomobject]@{
                    schema_version='0.1'
                    assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}elseif($Assignment -and $Assignment.PSObject.Properties['assignment'] -and $Assignment.assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment.assignment_id}else{$null}
                    assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['sha256']){[string]$Assignment.sha256}else{$null}
                    conversation_fingerprint_sha256=if($Enrollment){[string]$Enrollment.conversation_fingerprint_sha256}else{$null}
                    composer_state='COMMITTED'
                    composer_result='EMPTY'
                    mutation_occurred=$false
                    send_invocation_state='INVOKED'
                    committed_message_proof_state='PROVEN'
                    failure_reason=$null
                    committed=$true
                }
            }
            $state.send_count++
            $before=[string]$state.composer_text
            $mutationOccurred=([string]::IsNullOrWhiteSpace($before) -or $before -ne [string]$PromptText)
            if($mutationOccurred){
                $state.compose_count++
                $state.composer_text=$PromptText
            }
            $state.last_prompt_text=$PromptText
            $state.last_prompt_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($PromptText))).ToLowerInvariant()
            $committed=$true
            if($state.send_commit_queue.Count -gt 0){ $committed=$state.send_commit_queue.Dequeue() }
            if($committed){ $state.successful_commit_count++ }
            $composerResult=if([string]::IsNullOrWhiteSpace($before)){'EMPTY'}elseif($before -eq $PromptText){'MATCHING_EXACT'}elseif(($before).IndexOf($PromptText,[StringComparison]::Ordinal) -ge 0){'DUPLICATE'}else{'MISMATCH'}
            [pscustomobject]@{
                schema_version='0.1'
                assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}elseif($Assignment -and $Assignment.PSObject.Properties['assignment'] -and $Assignment.assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment.assignment_id}else{$null}
                assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['sha256']){[string]$Assignment.sha256}else{$null}
                conversation_fingerprint_sha256=if($Enrollment){[string]$Enrollment.conversation_fingerprint_sha256}else{$null}
                composer_state=if($committed){'COMMITTED'}else{'FAILED'}
                composer_result=$composerResult
                mutation_occurred=$mutationOccurred
                send_invocation_state=if($committed){'INVOKED'}else{'FAILED'}
                committed_message_proof_state=if($committed){'PROVEN'}else{'NOT_PROVEN'}
                failure_reason=if($committed){$null}else{'Simulated committed-send proof failure.'}
                committed=[bool]$committed
            }
        }).GetNewClosure()
        ReadActorResponseText=({
            param($Context,$Enrollment,[int]$Attempt,$Assignment)
            if($state.successful_commit_count -lt 1){ return $null }
            [ordered]@{
                schema_version='0.1'
                envelope_type='RUNTIME_ACTOR_RESULT'
                assignment_id=[string]$Assignment.assignment_id
                assignment_sha256=[string]$state.assignment_sha256
                project_id=[string]$Assignment.project_id
                actor_role=[string]$Assignment.actor_role
                actor_identity=[string]$Assignment.actor_identity
                action=[string]$Assignment.action
                binding=$Assignment.binding
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
                responded_at='2026-08-18T00:00:00Z'
            }|ConvertTo-Json -Depth 100 -Compress
        }).GetNewClosure()
    }
}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-thinker-lifecycle-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
$stateRoot=Join-Path $base 'host'
try {
    New-ThinkerProject -ProjectRoot $projectRoot
    $project=[pscustomobject]@{project_id='THINKER-PROJECT';local_root=$projectRoot}
    $selection=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    $created=New-AidosRuntimeActorAssignment -Project $project -Selection $selection
    $assignmentSha=[string]$created.assignment_sha256
    $assignmentId=[string]$created.assignment.assignment_id

    $backend1=New-ThinkerLifecycleBackend -AssignmentSha256 $assignmentSha -SendCommitQueue @($false,$true)
    $first=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $projectRoot -AssignmentId $assignmentId -StateRoot $stateRoot -Backend $backend1 -ResponseTimeoutSeconds 1
    Assert-Thinker ($first.status -eq 'WAITING_TRANSPORT') 'failed send remains resumable without activating transport'
    Assert-Thinker ($backend1.State.compose_count -eq 1 -and $backend1.State.send_count -eq 1) 'first compose writes exactly one payload'
    $composer1=Read-AidosDesktopThinkerComposerState -StateRoot $stateRoot -AssignmentId $assignmentId
    Assert-Thinker ($composer1.composer_state -eq 'FAILED' -and $composer1.send_invocation_state -eq 'FAILED' -and $composer1.committed_message_proof_state -eq 'NOT_PROVEN' -and $composer1.failure_reason) 'failed send stores deterministic non-activated composer contract'
    Assert-Thinker ([bool]$composer1.mutation_occurred) 'failed send preserves the first compose mutation flag'
    Assert-Thinker ($composer1.assignment_id -eq $assignmentId -and $composer1.assignment_sha256 -eq $assignmentSha -and $composer1.conversation_fingerprint_sha256) 'composer contract keeps assignment and binding identity'
    Assert-Thinker ($composer1.composer_result -eq 'EMPTY') 'first compose classifies an empty composer as EMPTY'

    $restartBackend=New-ThinkerLifecycleBackend -AssignmentSha256 $assignmentSha -InitialComposerText $backend1.State.composer_text -SendCommitQueue @($true)
    Assert-Thinker ([string]$restartBackend.State.composer_text -eq [string]$backend1.State.composer_text) 'restart backend receives the exact staged composer payload'
    $restarted=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $projectRoot -AssignmentId $assignmentId -StateRoot $stateRoot -Backend $restartBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($restartBackend.State.compose_count -eq 0 -and $restartBackend.State.send_count -eq 1) ("repeat tick does not append; compose_count={0}; send_count={1}" -f $restartBackend.State.compose_count,$restartBackend.State.send_count)
    Assert-Thinker ($restarted.status -eq 'HANDOFF_COMPLETE' -and -not $restarted.idempotent) 'restart reconciles the intermediate state and completes the handoff'
    $composer2=Read-AidosDesktopThinkerComposerState -StateRoot $stateRoot -AssignmentId $assignmentId
    Assert-Thinker ($composer2.composer_state -eq 'COMMITTED' -and $composer2.committed_message_proof_state -eq 'PROVEN' -and $composer2.send_invocation_state -eq 'INVOKED') 'successful commit advances exactly once'
    Assert-Thinker ([bool]$composer2.mutation_occurred) 'successful commit retains the one-time compose mutation flag'
    $repeatAfterCommit=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $projectRoot -AssignmentId $assignmentId -StateRoot $stateRoot -Backend $restartBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($repeatAfterCommit.status -eq 'HANDOFF_COMPLETE' -and $repeatAfterCommit.idempotent) 'post-commit restart is idempotent'
    Assert-Thinker ($restartBackend.State.send_count -eq 1 -and $restartBackend.State.compose_count -eq 0) 'successful commit only advances once'

    $classifierRoot=Join-Path $base 'classifier-project'
    $classifierState=Join-Path $base 'classifier-host'
    New-ThinkerProject -ProjectRoot $classifierRoot
    $classifierProject=[pscustomobject]@{project_id='THINKER-PROJECT';local_root=$classifierRoot}
    $classifierSelection=Get-AidosRuntimeNextActor -ProjectRoot $classifierRoot
    $classifierCreated=New-AidosRuntimeActorAssignment -Project $classifierProject -Selection $classifierSelection
    $classifierSha=[string]$classifierCreated.assignment_sha256
    $classifierId=[string]$classifierCreated.assignment.assignment_id
    $classifierBound=Read-AidosRuntimeActorAssignment -ProjectRoot $classifierRoot -AssignmentId $classifierId
    $classifierDocuments=Get-AidosDesktopThinkerAuthorizedDocuments -ProjectRoot $classifierRoot -BoundAssignment $classifierBound
    $classifierPrompt=New-AidosDesktopThinkerPrompt -BoundAssignment $classifierBound -Documents $classifierDocuments

    $duplicateBackend=New-ThinkerLifecycleBackend -AssignmentSha256 $classifierSha -InitialComposerText ($classifierPrompt + $classifierPrompt) -SendCommitQueue @($true)
    $duplicate=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $classifierRoot -AssignmentId $classifierId -StateRoot $classifierState -Backend $duplicateBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($duplicate.status -eq 'WAITING_TRANSPORT') 'duplicate staged content does not become activated'
    Assert-Thinker ($duplicate.composer.composer_result -eq 'DUPLICATE') 'duplicate staged content is classified explicitly'
    Assert-Thinker ($duplicateBackend.State.send_count -eq 0 -and $duplicateBackend.State.compose_count -eq 0) 'duplicate staged content never reaches send'

    $mismatchBackend=New-ThinkerLifecycleBackend -AssignmentSha256 $classifierSha -InitialComposerText 'stale composer content' -SendCommitQueue @($true)
    $mismatch=Invoke-AidosDesktopThinkerAssignment -ProjectRoot $classifierRoot -AssignmentId $classifierId -StateRoot $classifierState -Backend $mismatchBackend -ResponseTimeoutSeconds 1
    Assert-Thinker ($mismatch.status -eq 'WAITING_TRANSPORT') 'stale staged content remains non-activated'
    Assert-Thinker ($mismatch.composer.composer_result -eq 'MISMATCH') 'stale staged content is classified explicitly'
    Assert-Thinker ($mismatchBackend.State.send_count -eq 0 -and $mismatchBackend.State.compose_count -eq 0) 'stale staged content never reaches send'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed desktop Thinker composer lifecycle assertions"
