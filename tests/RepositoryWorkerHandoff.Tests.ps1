[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryWorkerHandoff.psm1') -Force -DisableNameChecking

$script:passed=0
$script:GitExecutable=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
function Assert-Worker([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
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
    Assert-Worker ((Invoke-TestGit $repo @('log','-1','--pretty=%s'))[0]-match'publish Worker handoff') 'Worker assignment is committed immediately'

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

    Write-Output "PASS: $passed repository Worker handoff assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
