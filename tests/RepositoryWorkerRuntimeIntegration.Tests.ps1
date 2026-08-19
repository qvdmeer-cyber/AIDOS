[CmdletBinding()
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosWorkerDispatchGuard.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryWorkerHandoff.psm1') -Force -DisableNameChecking

$script:passed=0
$script:GitExecutable=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
function Assert-WorkerRuntime([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-WorkerRuntimeThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}
function Invoke-TestGit([string]$Repo,[string[]]$Arguments){$output=@(& $script:GitExecutable -C $Repo @Arguments 2>&1);if($LASTEXITCODE-ne0){throw "git $($Arguments-join' ') failed: $($output-join'; ')"};@($output)}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-worker-runtime-'+[guid]::NewGuid().ToString('N'))
$repo=Join-Path $temp 'repo'
$registry=Join-Path $temp 'registry'
New-Item -ItemType Directory -Path $repo,$registry -Force|Out-Null
try{
    & $script:GitExecutable init $repo|Out-Null
    Invoke-TestGit $repo @('config','user.email','aidos@example.invalid')|Out-Null
    Invoke-TestGit $repo @('config','user.name','AIDOS Tests')|Out-Null
    Invoke-TestGit $repo @('remote','add','origin','https://github.com/example/worker-runtime.git')|Out-Null

    $executionId='EXEC-RUNTIME-1'
    $revision=1
    $executionDir=Join-Path $repo ".aidos/executions/$executionId/revision-$revision"
    New-Item -ItemType Directory -Path (Join-Path $repo '.aidos/events'),(Join-Path $repo '.aidos/runtime/worker-dispatch'),$executionDir -Force|Out-Null
    [ordered]@{
        schema_version='0.1';project_id='WORKER-RUNTIME';project_mode='NEW_PROJECT';repository='https://github.com/example/worker-runtime.git';official_root=$repo
        git_runtime=[ordered]@{kind='NATIVE';project_root=$repo;git_path=$script:GitExecutable}
    }|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $repo '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{
        schema_version='0.1';project_id='WORKER-RUNTIME';state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id=$executionId;revision=$revision
        codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    }|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $repo '.aidos/STATE.json') -Encoding utf8NoBOM
    $execution=[ordered]@{
        schema_version='0.1';project_id='WORKER-RUNTIME';execution_id=$executionId;revision=$revision;definition=[ordered]@{id='DEF-1';version=1}
        scope=[ordered]@{definition_ref='.aidos/definitions/DEF-1/v1/DEFINITION.json';implementation_policy='fixture'}
        authority=[ordered]@{filesystem_write=@('product.txt');git_commit=$false;git_push=$false;network=$false}
        validation=[ordered]@{mode='ALL';requirements=@([ordered]@{type='PATH_EXISTS';path='product.txt'})}
    }
    $executionPath=Join-Path $executionDir 'EXECUTION.json'
    $execution|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $executionPath -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $repo 'product.txt') -Value 'initial' -Encoding utf8NoBOM

    $previous=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id='WORKER-RUNTIME'
        kind='RESULT';from_actor='THINKER';to_actor='CORE';status='READY';parent_handoff_id=[guid]::NewGuid().ToString();created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action='START_DEFINITION_RESULT';payload_ref='.aidos/definitions/DEF-1/v1/PROGRESS.json';payload_sha256=$null
        binding=[pscustomobject][ordered]@{project_state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id=$executionId;revision=$revision;review_id=$null}
        source_refs=@()
    }
    Write-AidosRepositoryHandoff -ProjectRoot $repo -Metadata $previous -Body 'Thinker completed Definition.'|Out-Null
    Invoke-TestGit $repo @('add','.')|Out-Null
    Invoke-TestGit $repo @('commit','-m','fixture')|Out-Null
    $headBefore=[string](Invoke-TestGit $repo @('rev-parse','HEAD')|Select-Object -First 1)

    $project=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'WORKER-RUNTIME' -Repository 'https://github.com/example/worker-runtime.git' -LocalRoot $repo -ProjectMode NEW_PROJECT -AllowedPersistencePaths @('.aidos')
    $guard=New-AidosWorkerDispatchGuard -ProjectRoot $repo
    Assert-WorkerRuntime ([string]$guard.git_head_before-eq$headBefore) 'dispatch guard binds the pre-Worker Git HEAD'

    $eventPath=Join-Path $repo ('.aidos/events/'+(Get-Date).ToUniversalTime().ToString('yyyy-MM')+'.jsonl')
    $eventCountBefore=@(Get-Content -LiteralPath $eventPath -Encoding UTF8).Count
    $retryGuard=New-AidosWorkerDispatchGuard -ProjectRoot $repo
    Assert-WorkerRuntime ([string]$retryGuard.status-eq'BOUND' -and [string]$retryGuard.git_head_before-eq$headBefore) 'same TASK_READY execution reuses an existing BOUND initial dispatch guard'
    Assert-WorkerRuntime (@(Get-Content -LiteralPath $eventPath -Encoding UTF8).Count-eq$eventCountBefore) 'guard retry does not append a duplicate guard-bound event'

    $roguePath=Join-Path $repo 'rogue.txt'
    Set-Content -LiteralPath $roguePath -Value 'unexpected' -Encoding utf8NoBOM
    Assert-WorkerRuntimeThrows {New-AidosWorkerDispatchGuard -ProjectRoot $repo|Out-Null} 'unrelated worktree changes' 'guard retry remains fail-closed when any non-Core delta appears'
    Remove-Item -LiteralPath $roguePath -Force
    $retryGuard=New-AidosWorkerDispatchGuard -ProjectRoot $repo
    Assert-WorkerRuntime ([string]$retryGuard.git_head_before-eq$headBefore) 'guard remains reusable after unrelated retry delta is removed'

    $codexInvoker={
        param($Project,$ExecutionPath,$Prompt)
        $boundExecution=Read-AidosJson -Path $ExecutionPath
        Set-Content -LiteralPath (Join-Path ([string]$Project.local_root) 'product.txt') -Value 'implemented' -Encoding utf8NoBOM
        $result=[pscustomobject][ordered]@{
            schema_version='0.1';project_id=[string]$Project.project_id;execution_id=[string]$boundExecution.execution_id;revision=[int]$boundExecution.revision
            lease_id='LEASE-TEST';codex_session_id='SESSION-TEST';resumed=$false;started_at=[DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('o');finished_at=[DateTimeOffset]::UtcNow.ToString('o')
            exit_code=0;terminal_type='turn.completed';process_succeeded=$true;validation_status='PASS'
            validation_path=('.aidos/executions/{0}/revision-{1}/VALIDATION.json' -f [string]$boundExecution.execution_id,[int]$boundExecution.revision)
            final_message='done';prompt_sha256=('a'*64);error=$null;git_head=$headBefore
            events_path=('.aidos/executions/{0}/revision-{1}/codex-events.jsonl' -f [string]$boundExecution.execution_id,[int]$boundExecution.revision)
            stderr_path=('.aidos/executions/{0}/revision-{1}/codex-stderr.log' -f [string]$boundExecution.execution_id,[int]$boundExecution.revision)
        }
        $resultPath=Join-Path (Split-Path -Parent $ExecutionPath) 'RESULT.json'
        $validationPath=Join-Path (Split-Path -Parent $ExecutionPath) 'VALIDATION.json'
        Write-AidosJsonAtomic -Path $resultPath -Value $result
        Write-AidosJsonAtomic -Path $validationPath -Value ([ordered]@{status='PASS';checked_at=[DateTimeOffset]::UtcNow.ToString('o');requirements=@();validators=@()})
        $state=Get-AidosState -ProjectRoot ([string]$Project.local_root)
        $state.state='REVIEW_READY'
        $state.terminal_result=[IO.Path]::GetRelativePath([string]$Project.local_root,$resultPath).Replace('\','/')
        $state.validation_result=[IO.Path]::GetRelativePath([string]$Project.local_root,$validationPath).Replace('\','/')
        $state.codex_session_id='SESSION-TEST';$state.git_head=$headBefore;$state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosJsonAtomic -Path (Join-Path ([string]$Project.local_root) '.aidos/STATE.json') -Value $state
        [pscustomobject][ordered]@{status='REVIEW_READY';execution=$boundExecution;result=$result;validation=[pscustomobject][ordered]@{status='PASS'}}
    }.GetNewClosure()

    $outcome=Invoke-AidosRepositoryWorkerHandoff -Project $project -ExecutionPath $executionPath -CodexInvoker $codexInvoker
    Assert-WorkerRuntime ([string]$outcome.status-eq'REVIEW_READY') 'repository Worker adapter preserves the existing autonomous Worker status shape'
    Assert-WorkerRuntime ([string]$outcome.terminal_result.execution_id-eq$executionId) 'repository Worker adapter extracts the canonical terminal result from the Codex wrapper'
    Assert-WorkerRuntime ([string]$outcome.assignment_handoff.persistence.status-eq'DEFERRED_UNTIL_WORKER_GUARD') 'Worker assignment commit is deferred during the Git authority window'
    Assert-WorkerRuntime ([string]$outcome.result_handoff.persistence.status-eq'DEFERRED_UNTIL_WORKER_GUARD') 'Worker result commit is deferred during the Git authority window'
    $headDuring=[string](Invoke-TestGit $repo @('rev-parse','HEAD')|Select-Object -First 1)
    Assert-WorkerRuntime ($headDuring-eq$headBefore) 'Core makes no Git commit while Codex is inside the guarded execution window'
    $current=Read-AidosRepositoryHandoff -ProjectRoot $repo -ExpectedProjectId 'WORKER-RUNTIME'
    Assert-WorkerRuntime ([string]$current.metadata.kind-eq'RESULT' -and [string]$current.metadata.from_actor-eq'WORKER' -and [string]$current.metadata.to_actor-eq'CORE') 'Worker publishes its local repository RESULT before returning to Core'

    $guardResult=Test-AidosWorkerDispatchGuard -ProjectRoot $repo -ExecutionId $executionId -Revision $revision
    Assert-WorkerRuntime ([string]$guardResult.status-eq'PASS') 'existing Worker Git authority guard passes before Core lifecycle persistence'
    $finalized=Complete-AidosRepositoryWorkerHandoffPersistence -Project $project
    Assert-WorkerRuntime ([string]$finalized.status-eq'FINALIZED') 'Core commits deferred Worker handoff lifecycle files after guard PASS'
    Assert-WorkerRuntime ([string]$finalized.persistence.status-eq'PERSISTED') 'deferred lifecycle commit is persisted through the scoped handoff writer'
    $headAfter=[string](Invoke-TestGit $repo @('rev-parse','HEAD')|Select-Object -First 1)
    Assert-WorkerRuntime ($headAfter-ne$headBefore) 'Core lifecycle finalization advances Git HEAD only after guard PASS'
    $committed=@(Invoke-TestGit $repo @('show','--pretty=format:','--name-only','HEAD')|Where-Object {-not[string]::IsNullOrWhiteSpace([string]$_)})
    Assert-WorkerRuntime (-not($committed-contains'product.txt')) 'Core lifecycle finalization never commits the Worker source delta'
    $remaining=@(Invoke-TestGit $repo @('status','--porcelain=v1','--untracked-files=all'))
    Assert-WorkerRuntime (@($remaining|Where-Object {$_ -match'product\.txt'}).Count-eq1) 'Worker source delta remains uncommitted for Thinker review'
    $again=Complete-AidosRepositoryWorkerHandoffPersistence -Project $project
    Assert-WorkerRuntime ([string]$again.status-eq'ALREADY_FINALIZED') 'Worker handoff finalization is idempotent'

    Write-Output "PASS: $passed repository Worker runtime integration assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
