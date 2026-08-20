[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bridgePath=Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1'
$text=Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8

$script:passed=0
function Assert-Trigger([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

Assert-Trigger ($text -match 'Invoke-AidosCurrentRepositoryThinkerTriggers') 'current Thinker trigger function exists'
Assert-Trigger ($text -match 'Get-AidosPendingRuntimeActorAssignments -ProjectRoot \$root') 'non-review Thinker trigger still consults pending runtime assignments'
Assert-Trigger ($text -match 'if\(\$pending\.Count-eq0\)\{continue\}') 'non-pending ordinary Thinker assignments remain guarded'
Assert-Trigger ($text -match "if\(\$action-eq'REVIEW'\)") 'review handoffs have an explicit trigger route'
Assert-Trigger ($text -match "Current Thinker review handoff has no review_id binding") 'review handoffs require an exact review binding'
Assert-Trigger ($text -match 'review_id=\$reviewId') 'review trigger result preserves review identity'

Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking
Import-Module $bridgePath -Force -DisableNameChecking

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-current-review-trigger-'+[guid]::NewGuid().ToString('N'))
$registry=Join-Path $temp 'registry'
$projectRoot=Join-Path $temp 'project'
$stateRoot=Join-Path $temp 'bridge-state'
$projectId='REVIEW-TRIGGER'
$reviewId='11111111-1111-4111-8111-111111111111'

try {
    New-Item -ItemType Directory -Path (Join-Path $registry 'projects'),(Join-Path $projectRoot '.aidos'),$stateRoot -Force|Out-Null

    [ordered]@{
        schema_version='0.2'
        project_id=$projectId
        repository='https://example.invalid/review-trigger.git'
        local_root=$projectRoot
        stage='RUNTIME'
        preparation_phase='RUNTIME'
        status='PROMOTED'
        project_mode='NEW_PROJECT'
        default_branch='main'
        runner_policy='UNATTENDED_ALLOWED'
        git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}
        allowed_persistence_paths=@('.aidos')
        registered_at='2026-08-20T00:00:00Z'
        updated_at='2026-08-20T00:00:00Z'
        promoted_at='2026-08-20T00:00:00Z'
    }|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $registry "projects/$projectId.json") -Encoding utf8NoBOM

    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1'
        envelope_type='AIDOS_REPOSITORY_HANDOFF'
        handoff_id=[guid]::NewGuid().ToString()
        project_id=$projectId
        kind='ASSIGNMENT'
        from_actor='CORE'
        to_actor='THINKER'
        status='READY'
        parent_handoff_id=$null
        created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action='REVIEW'
        payload_ref='.aidos/runtime/reviews/11111111-1111-4111-8111-111111111111/REVIEW_ASSIGNMENT.json'
        payload_sha256=('a'*64)
        binding=[pscustomobject][ordered]@{
            project_state='GPT_REVIEWING'
            definition_id='DEF-REVIEW'
            definition_version=1
            execution_id='EXEC-REVIEW'
            revision=4
            review_id=$reviewId
        }
        source_refs=@()
    }
    $handoff=Write-AidosRepositoryHandoff -ProjectRoot $projectRoot -Metadata $metadata -Body '# review assignment'
    Assert-Trigger ([string]$handoff.metadata.action-eq'REVIEW') 'review fixture is a canonical repository assignment'

    $capture=[pscustomobject]@{calls=0;review_id=$null;handoff_id=$null}
    $trigger=({
        param($TriggerStateRoot,$CurrentHandoff,$ProcessName)
        $capture.calls++
        $capture.review_id=[string]$CurrentHandoff.metadata.binding.review_id
        $capture.handoff_id=[string]$CurrentHandoff.metadata.handoff_id
        [pscustomobject][ordered]@{status='TRIGGERED';committed=$true}
    }).GetNewClosure()

    $result=Invoke-AidosCurrentRepositoryThinkerTriggers -RegistryRoot $registry -StateRoot $stateRoot -MaxItems 1 -ThinkerTrigger $trigger
    $entry=@($result.results)[0]

    Assert-Trigger ([string]$result.status-eq'PROCESSED' -and [int]$result.processed-eq1) 'current review handoff is processed without a runtime assignment'
    Assert-Trigger ([string]$entry.status-eq'TRIGGERED') 'review handoff invokes the Thinker trigger callback'
    Assert-Trigger ([string]$entry.review_id-eq$reviewId -and $null-eq$entry.assignment_id) 'review trigger result distinguishes review from runtime assignment identity'
    Assert-Trigger ([int]$capture.calls-eq1 -and [string]$capture.review_id-eq$reviewId) 'callback receives the exact bound review identity once'
    Assert-Trigger ([string]$capture.handoff_id-eq[string]$handoff.metadata.handoff_id) 'callback receives the exact canonical handoff'

    Write-Output "PASS: $passed current Thinker trigger assertions"
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
