[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorTransport.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryWorkerHandoff.psm1') -Force -DisableNameChecking

$script:passed=0
$script:GitExecutable=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
function Assert-Worker([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-WorkerThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}
function Invoke-TestGit([string]$Repo,[string[]]$Arguments){$output=@(& $script:GitExecutable -C $Repo @Arguments 2>&1);if($LASTEXITCODE-ne0){throw "git $($Arguments-join' ') failed: $($output-join'; ')"};@($output)}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-worker-handoff-'+[guid]::NewGuid().ToString('N'))
$repo=Join-Path $temp 'repo';$registry=Join-Path $temp 'registry'
New-Item -ItemType Directory -Path $repo,$registry -Force|Out-Null
try{
    & $script:GitExecutable init $repo|Out-Null
    Invoke-TestGit $repo @('config','user.email','aidos@example.invalid')|Out-Null;Invoke-TestGit $repo @('config','user.name','AIDOS Tests')|Out-Null;Invoke-TestGit $repo @('remote','add','origin','https://github.com/example/worker.git')|Out-Null
    $executionId='EXEC-1';$revision=1
    $executionDir=Join-Path $repo ".aidos/executions/$executionId/revision-$revision"
    New-Item -ItemType Directory -Path $executionDir,(Join-Path $repo '.aidos/events') -Force|Out-Null
    [ordered]@{schema_version='0.1';project_id='P1'}|ConvertTo-Json|Set-Content (Join-Path $repo '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='P1';state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id=$executionId;revision=$revision;review_id=$null}|ConvertTo-Json|Set-Content (Join-Path $repo '.aidos/STATE.json') -Encoding utf8NoBOM
    $execution=[ordered]@{schema_version='0.1';project_id='P1';execution_id=$executionId;revision=$revision;definition=[ordered]@{id='DEF-1';version=1};authority=[ordered]@{filesystem_write=@('src');git_commit=$false;git_push=$false;network=$false};validation=[ordered]@{mode='ALL';requirements=@([ordered]@{type='PATH_EXISTS';path='product.txt'})}}
    $execution|ConvertTo-Json -Depth 30|Set-Content (Join-Path $executionDir 'EXECUTION.json') -Encoding utf8NoBOM
    Set-Content (Join-Path $repo 'product.txt') 'initial' -Encoding utf8NoBOM
    $previous=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id='P1';kind='RESULT';from_actor='THINKER';to_actor='CORE';status='READY';parent_handoff_id=[guid]::NewGuid().ToString();created_at=[DateTimeOffset]::UtcNow.ToString('o');action='START_DEFINITION_RESULT';payload_ref='.aidos/definitions/DEF-1/v1/PROGRESS.json';payload_sha256=$null;binding=[pscustomobject][ordered]@{project_state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id=$executionId;revision=$revision;review_id=$null};source_refs=@()}
    Write-AidosRepositoryHandoff -ProjectRoot $repo -Metadata $previous -Body 'Definition result.'|Out-Null
    Invoke-TestGit $repo @('add','.')|Out-Null;Invoke-TestGit $repo @('commit','-m','fixture')|Out-Null
    $project=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'P1' -Repository 'https://github.com/example/worker.git' -LocalRoot $repo -AllowedPersistencePaths @('.aidos')

    $published=Publish-AidosRepositoryWorkerAssignment -Project $project -ExecutionPath (Join-Path $executionDir 'EXECUTION.json')
    Assert-Worker ([string]$published.status-eq'PUBLISHED') 'Core publishes Worker assignment handoff'
    Assert-Worker ([string]$published.handoff.metadata.to_actor-eq'WORKER' -and [string]$published.handoff.metadata.from_actor-eq'CORE') 'Worker assignment preserves Core authority'
    Assert-Worker ([string]$published.handoff.metadata.parent_handoff_id-eq[string]$previous.handoff_id) 'Worker assignment links to prior Thinker result'
    Assert-Worker ([string]$published.handoff.metadata.payload_ref-eq'.aidos/executions/EXEC-1/revision-1/EXECUTION.json') 'Worker assignment binds canonical execution payload'
    $assignmentCommitSubject=[string](Invoke-TestGit $repo @('log','-1','--pretty=%s')|Select-Object -First 1)
    Assert-Worker ($assignmentCommitSubject-match'publish Worker handoff') ("Worker assignment is committed immediately; subject='$assignmentCommitSubject'; persistence="+($published.persistence|ConvertTo-Json -Depth 30 -Compress))

    Set-Content (Join-Path $repo 'product.txt') 'implemented' -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='P1';state='REVIEW_READY';definition_id='DEF-1';definition_version=1;execution_id=$executionId;revision=$revision;review_id=$null;terminal_result=".aidos/executions/$executionId/revision-$revision/RESULT.json";validation_result=".aidos/executions/$executionId/revision-$revision/VALIDATION.json"}|ConvertTo-Json|Set-Content (Join-Path $repo '.aidos/STATE.json') -Encoding utf8NoBOM
    $workerResult=[pscustomobject][ordered]@{schema_version='0.1';project_id='P1';execution_id=$executionId;revision=$revision;terminal_type='turn.completed';validation_status='PASS';process_succeeded=$true}
    $workerResult|ConvertTo-Json -Depth 20|Set-Content (Join-Path $executionDir 'RESULT.json') -Encoding utf8NoBOM
    [ordered]@{status='PASS'}|ConvertTo-Json|Set-Content (Join-Path $executionDir 'VALIDATION.json') -Encoding utf8NoBOM

    $result=Publish-AidosRepositoryWorkerResult -Project $project -WorkerResult $workerResult
    Assert-Worker ([string]$result.status-eq'PUBLISHED') 'Worker completion publishes result handoff to Core'
    Assert-Worker ([string]$result.handoff.metadata.from_actor-eq'WORKER' -and [string]$result.handoff.metadata.to_actor-eq'CORE') 'Worker result never assigns Thinker directly'
    Assert-Worker ([string]$result.handoff.metadata.parent_handoff_id-eq[string]$published.handoff.metadata.handoff_id) 'Worker result links to exact Worker assignment'
    Assert-Worker (@($result.persistence.uncommitted_paths)-contains'product.txt') 'product implementation remains uncommitted for review'
    $show=@(Invoke-TestGit $repo @('show','--pretty=format:','--name-only','HEAD')|Where-Object {-not[string]::IsNullOrWhiteSpace($_)})
    Assert-Worker (-not($show-contains'product.txt')) 'Worker result commit excludes implementation source'
    Assert-Worker ((Get-Content (Join-Path $repo 'product.txt') -Raw).Trim()-eq'implemented') 'implementation remains available to review in worktree'

    $staleRepo=Join-Path $temp 'stale-repo';$staleRegistry=Join-Path $temp 'stale-registry'
    New-Item -ItemType Directory -Path $staleRepo,$staleRegistry -Force|Out-Null
    & $script:GitExecutable init $staleRepo|Out-Null
    Invoke-TestGit $staleRepo @('config','user.email','aidos@example.invalid')|Out-Null;Invoke-TestGit $staleRepo @('config','user.name','AIDOS Tests')|Out-Null;Invoke-TestGit $staleRepo @('remote','add','origin','https://github.com/example/stale-worker.git')|Out-Null
    $staleExecutionId='EXEC-STALE';$staleRevision=1;$staleDefinitionId='DEF-STALE';$staleAssignmentId=[guid]::NewGuid().ToString()
    $staleExecutionDir=Join-Path $staleRepo ".aidos/executions/$staleExecutionId/revision-$staleRevision"
    $staleAssignmentDir=Join-Path $staleRepo '.aidos/runtime/actor-assignments'
    New-Item -ItemType Directory -Path $staleExecutionDir,$staleAssignmentDir,(Join-Path $staleRepo '.aidos/events') -Force|Out-Null
    [ordered]@{schema_version='0.1';project_id='P2';project_mode='NEW_PROJECT';repository='https://github.com/example/stale-worker.git';official_root=$staleRepo;git_runtime=[ordered]@{kind='NATIVE';project_root=$staleRepo;git_path=$script:GitExecutable}}|ConvertTo-Json -Depth 20|Set-Content (Join-Path $staleRepo '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='P2';state='TASK_READY';definition_id=$staleDefinitionId;definition_version=1;execution_id=$staleExecutionId;revision=$staleRevision;review_id=$null}|ConvertTo-Json|Set-Content (Join-Path $staleRepo '.aidos/STATE.json') -Encoding utf8NoBOM
    $staleExecution=[ordered]@{schema_version='0.1';project_id='P2';execution_id=$staleExecutionId;revision=$staleRevision;definition=[ordered]@{id=$staleDefinitionId;version=1};authority=[ordered]@{filesystem_write=@('src');git_commit=$false;git_push=$false;network=$false};validation=[ordered]@{mode='ALL';requirements=@()}}
    $staleExecutionPath=Join-Path $staleExecutionDir 'EXECUTION.json';$staleExecution|ConvertTo-Json -Depth 30|Set-Content $staleExecutionPath -Encoding utf8NoBOM
    $staleBinding=[ordered]@{project_state='WAITING_DEFINITION';definition_id=$staleDefinitionId;definition_version=1;execution_id=$null;revision=$null;review_id=$null}
    $staleAssignment=[ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_ASSIGNMENT';assignment_id=$staleAssignmentId;project_id='P2';actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='START_DEFINITION';binding=$staleBinding;requested_at=[DateTimeOffset]::UtcNow.AddMinutes(-2).ToString('o')}
    $staleAssignmentPath=Join-Path $staleAssignmentDir ($staleAssignmentId+'.json');$staleAssignment|ConvertTo-Json -Depth 30|Set-Content $staleAssignmentPath -Encoding utf8NoBOM
    $staleAssignmentSha=(Get-FileHash -LiteralPath $staleAssignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $staleResult=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=$staleAssignmentId;assignment_sha256=$staleAssignmentSha;project_id='P2';actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='START_DEFINITION';binding=[pscustomobject]$staleBinding;outcome='COMPLETED';result=[pscustomobject][ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='done';applicability_resolutions=@();surface_resolutions=@();human_input_request=$null};responded_at=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')}
    Save-AidosRuntimeActorResult -ProjectRoot $staleRepo -Result $staleResult|Out-Null
    $staleResultRef='.aidos/runtime/actor-results/'+$staleAssignmentId+'.json'
    Set-AidosRuntimeActorTransportState -ProjectRoot $staleRepo -AssignmentId $staleAssignmentId -Status CONSUMED -TransportType REPOSITORY_HANDOFF -ResultRef $staleResultRef|Out-Null
    $staleHandoff=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id='P2';kind='ASSIGNMENT';from_actor='CORE';to_actor='THINKER';status='READY';parent_handoff_id=[guid]::NewGuid().ToString();created_at=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o');action='START_DEFINITION';payload_ref='.aidos/runtime/actor-assignments/'+$staleAssignmentId+'.json';payload_sha256=$staleAssignmentSha;binding=[pscustomobject]$staleBinding;source_refs=@()}
    Write-AidosRepositoryHandoff -ProjectRoot $staleRepo -Metadata $staleHandoff -Body 'Stale duplicate Thinker assignment.'|Out-Null
    Invoke-TestGit $staleRepo @('add','.')|Out-Null;Invoke-TestGit $staleRepo @('commit','-m','stale-fixture')|Out-Null
    $staleProject=Register-AidosPreparationProject -RegistryRoot $staleRegistry -ProjectId 'P2' -Repository 'https://github.com/example/stale-worker.git' -LocalRoot $staleRepo -AllowedPersistencePaths @('.aidos')

    $stalePublished=Publish-AidosRepositoryWorkerAssignment -Project $staleProject -ExecutionPath $staleExecutionPath -DeferPersistence
    Assert-Worker ([string]$stalePublished.status-eq'PUBLISHED' -and [string]$stalePublished.handoff.metadata.to_actor-eq'WORKER') 'consumed stale Thinker assignment is reconciled before Worker publication'
    $staleEvents=@(Get-Content -LiteralPath (Join-Path $staleRepo ('.aidos/events/'+(Get-Date).ToUniversalTime().ToString('yyyy-MM')+'.jsonl')) -Encoding UTF8|ForEach-Object {$_|ConvertFrom-Json -Depth 50})
    $reconciliations=@($staleEvents|Where-Object {$_.event_type-eq'REPOSITORY_STALE_ASSIGNMENT_RECONCILED'})
    Assert-Worker ($reconciliations.Count-eq1) 'stale assignment reconciliation is durably evented exactly once'
    Assert-Worker ([string]$reconciliations[0].payload.stale_handoff_id-eq[string]$staleHandoff.handoff_id -and [string]$reconciliations[0].payload.result_handoff_id-eq[string]$stalePublished.handoff.metadata.parent_handoff_id) 'Worker assignment is parented by the reconstructed exact result handoff'
    Assert-Worker ([string](Read-AidosRuntimeActorTransportState -ProjectRoot $staleRepo -AssignmentId $staleAssignmentId).status-eq'CONSUMED') 'reconciliation does not reopen consumed runtime actor transport'

    $activeAssignmentId=[guid]::NewGuid().ToString();$activeAssignmentPath=Join-Path $staleAssignmentDir ($activeAssignmentId+'.json')
    $activeAssignment=[ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_ASSIGNMENT';assignment_id=$activeAssignmentId;project_id='P2';actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='RESUME_DEFINITION';binding=$staleBinding;requested_at=[DateTimeOffset]::UtcNow.ToString('o')};$activeAssignment|ConvertTo-Json -Depth 30|Set-Content $activeAssignmentPath -Encoding utf8NoBOM
    $activeSha=(Get-FileHash -LiteralPath $activeAssignmentPath -Algorithm SHA256).Hash.ToLowerInvariant();Initialize-AidosRuntimeActorTransportState -ProjectRoot $staleRepo -AssignmentId $activeAssignmentId|Out-Null;Set-AidosRuntimeActorTransportState -ProjectRoot $staleRepo -AssignmentId $activeAssignmentId -Status ACTIVATED -TransportType REPOSITORY_HANDOFF|Out-Null
    $activeHandoff=[pscustomobject][ordered]@{metadata=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id='P2';kind='ASSIGNMENT';from_actor='CORE';to_actor='THINKER';status='READY';parent_handoff_id=[guid]::NewGuid().ToString();created_at=[DateTimeOffset]::UtcNow.ToString('o');action='RESUME_DEFINITION';payload_ref='.aidos/runtime/actor-assignments/'+$activeAssignmentId+'.json';payload_sha256=$activeSha;binding=[pscustomobject]$staleBinding;source_refs=@()}}
    Assert-WorkerThrows {Resolve-AidosRepositoryWorkerStaleConsumedThinkerAssignment -Project $staleProject -Handoff $activeHandoff|Out-Null} 'Another repository actor assignment is already active' 'active Thinker assignment remains a hard Worker blocker'

    Write-Output "PASS: $passed repository Worker handoff assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
