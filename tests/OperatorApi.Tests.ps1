[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosOperator.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPersistentLocalDesktopAgent.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Operator([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function New-OperatorSessionSnapshot {
    [pscustomobject]@{
        observed_at='2026-08-17T20:00:00Z';session_id=8;process_session_id=8;active_console_session_id=8;
        connection_state='ACTIVE';lock_state='UNLOCKED';session_kind='CONSOLE';protocol_type=0;input_desktop_available=$true;
        user_name='qvdm';domain_name='AIDOS';winstation_name='Console';observation_status='OK';error=$null
    }
}

$projectRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-operator-test-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/workstreams') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/human-input') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/progress') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/events') -Force|Out-Null

    [ordered]@{schema_version='0.1';project_id='OPERATOR-SMOKE';project_mode='NEW_PROJECT';official_root=$projectRoot;repository='https://example.invalid/operator-smoke.git'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=0;review_id=$null;updated_at='2026-08-17T20:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';workstream_id='frontend';status='ACTIVE';current_actor_role='WORKER';blockers=@([ordered]@{blocker_id='b1';status='OPEN'})}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/workstreams/frontend.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';request_id='hir-1';workstream_id='frontend';status='WAITING'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/human-input/hir-1.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='OPERATOR-SMOKE';percent_complete=25}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/progress/current.json') -Encoding utf8NoBOM
    '{"event_type":"STATE_TRANSITION","timestamp":"2026-08-17T20:00:01Z"}'|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/events/2026-08.jsonl') -Encoding utf8NoBOM

    $status=Get-AidosRuntimeStatusProjection -ProjectRoot $projectRoot
    Assert-Operator ($status.schema_version -eq '0.1') 'runtime status uses schema version 0.1'
    Assert-Operator ($status.projects.Count -eq 1 -and $status.projects[0].project_id -eq 'OPERATOR-SMOKE') 'runtime status projects the bound project'
    Assert-Operator ($status.projects[0].state -eq 'IDLE' -and -not $status.projects[0].recovery_required) 'runtime status projects current project state'
    Assert-Operator ($status.projects[0].blocker_count -eq 1) 'runtime status aggregates open workstream blockers'
    Assert-Operator (@($status.projects[0].open_human_input_request_ids) -contains 'hir-1') 'runtime status exposes waiting human input'
    Assert-Operator ($status.projects[0].workstreams.Count -eq 1 -and $status.projects[0].workstreams[0].current_actor_role -eq 'WORKER') 'runtime status exposes workstream and actor role'
    Assert-Operator (-not[string]::IsNullOrWhiteSpace([string]$status.projects[0].progress_estimate_ref)) 'runtime status exposes progress estimate reference'

    $snapshot=Get-AidosOperatorSnapshot -ProjectRoot $projectRoot -EventLimit 5
    Assert-Operator ($snapshot.control.mode -eq 'RUNNING') 'operator default control mode is RUNNING'
    Assert-Operator ($snapshot.recent_events.Count -eq 1) 'operator snapshot exposes recent durable events'

    $pause=Submit-AidosControlIntent -ProjectRoot $projectRoot -Command PAUSE -RequestedBy TEST
    Assert-Operator ($pause.intent.status -eq 'APPLIED') 'PAUSE control intent is durably applied'
    Assert-Operator ((Get-AidosOperatorControlState $projectRoot).mode -eq 'PAUSED') 'PAUSE sets safe-boundary desired mode'
    Assert-Operator (Test-Path -LiteralPath (Join-Path $projectRoot $pause.path)) 'PAUSE persists a durable control-intent record'
    $global:AidosOperatorReviewTouched=$false
    $pausedTick=Invoke-AidosHostAgentTick -ProjectRoot $projectRoot -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-OperatorSessionSnapshot} -ShellHealthProvider {[pscustomobject]@{status='HEALTHY'}} -ReviewReconciler {$global:AidosOperatorReviewTouched=$true;throw 'paused runtime must not reconcile review'} -DesktopReviewInvoker {throw 'paused runtime must not activate desktop Worker'}
    Assert-Operator ($pausedTick.status -eq 'PAUSED' -and $pausedTick.reason -eq 'OPERATOR_CONTROL' -and -not $global:AidosOperatorReviewTouched) 'PAUSE gates persistent Worker before reconciliation or desktop activation'
    Remove-Variable -Name AidosOperatorReviewTouched -Scope Global -ErrorAction SilentlyContinue

    $query=Submit-AidosControlIntent -ProjectRoot $projectRoot -Command QUERY_STATUS -RequestedBy TEST
    Assert-Operator ($query.intent.status -eq 'APPLIED' -and $query.intent.result.runtime_status.projects[0].project_id -eq 'OPERATOR-SMOKE') 'QUERY_STATUS returns runtime projection through durable intent lifecycle'

    $resume=Submit-AidosControlIntent -ProjectRoot $projectRoot -Command RESUME -RequestedBy TEST
    Assert-Operator ($resume.intent.status -eq 'APPLIED' -and (Get-AidosOperatorControlState $projectRoot).mode -eq 'RUNNING') 'RESUME returns desired mode to RUNNING'

    $stop=Submit-AidosControlIntent -ProjectRoot $projectRoot -Command SAFE_STOP -RequestedBy TEST
    Assert-Operator ($stop.intent.status -eq 'APPLIED' -and (Get-AidosOperatorControlState $projectRoot).mode -eq 'SAFE_STOPPED') 'SAFE_STOP persists safe stopped desired mode'
    $global:AidosOperatorReviewTouched=$false
    $stoppedTick=Invoke-AidosHostAgentTick -ProjectRoot $projectRoot -AuthorizedUser 'AIDOS\qvdm' -SnapshotProvider {New-OperatorSessionSnapshot} -ShellHealthProvider {[pscustomobject]@{status='HEALTHY'}} -ReviewReconciler {$global:AidosOperatorReviewTouched=$true;throw 'safe-stopped runtime must not reconcile review'} -DesktopReviewInvoker {throw 'safe-stopped runtime must not activate desktop Worker'}
    Assert-Operator ($stoppedTick.status -eq 'SAFE_STOPPED' -and $stoppedTick.reason -eq 'OPERATOR_CONTROL' -and -not $global:AidosOperatorReviewTouched) 'SAFE_STOP gates persistent Worker before reconciliation or desktop activation'
    Remove-Variable -Name AidosOperatorReviewTouched -Scope Global -ErrorAction SilentlyContinue

    $unsupported=Submit-AidosControlIntent -ProjectRoot $projectRoot -Command SUBMIT_HUMAN_INPUT -RequestedBy TEST
    Assert-Operator ($unsupported.intent.status -eq 'REJECTED' -and $unsupported.intent.result.reason -match 'not implemented') 'unimplemented mutating processor fails closed rather than fabricating application'

    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20
    $state.state='RECOVERY_REQUIRED'
    $state|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    $run=Submit-AidosControlIntent -ProjectRoot $projectRoot -Command RUN -RequestedBy TEST
    Assert-Operator ($run.intent.status -eq 'REJECTED' -and $run.intent.result.reason -match 'RECOVERY_REQUIRED') 'RUN fails closed while recovery is required'
} finally {
    if(Test-Path -LiteralPath $projectRoot){Remove-Item -LiteralPath $projectRoot -Recurse -Force}
}

Write-Output "PASS: $passed operator API assertions"
