Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosBridge.psm1'
Import-Module $modulePath -Force
$script:Passed = 0

function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition){throw "ASSERTION FAILED: $Message"};$script:Passed++ }
function Assert-Throws([scriptblock]$Action,[string]$Pattern) { try{&$Action;throw 'Expected an exception.'}catch{if($_.Exception.Message -eq 'Expected an exception.'){throw};Assert-True ($_.Exception.Message -match $Pattern) "Expected error /$Pattern/, got: $($_.Exception.Message)"} }
function Write-Json($Path,$Value) { $dir=Split-Path -Parent $Path;if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding utf8NoBOM }
function New-TestProject {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('aidos-bridge-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
    &git -C $root init -q;&git -C $root config user.email test@example.invalid;&git -C $root config user.name 'AIDOS Test';&git -C $root remote add origin https://github.com/test-owner/test-project.git
    New-Item -ItemType Directory -Path (Join-Path $root '.aidos/documentation'),(Join-Path $root '.aidos/evidence'),(Join-Path $root '.aidos/events') -Force|Out-Null
    Write-Json (Join-Path $root '.aidos/documentation/PROJECT_BASELINE.json') ([ordered]@{accepted_at='2026-01-01T00:00:00Z';accepted_by='human';accepted_commit='abcdef1234567890'})
    Write-Json (Join-Path $root '.aidos/documentation/PROJECT_ACCESS.json') ([ordered]@{contract_version='0.1.0';project_id='TEST'})
    Write-Json (Join-Path $root '.aidos/evidence/EVIDENCE_INVENTORY.json') ([ordered]@{contract_version='0.2.0';project_id='TEST'})
    Write-Json (Join-Path $root '.aidos/PROJECT.json') ([ordered]@{schema_version='0.1';project_id='TEST';project_mode='NEW_PROJECT';repository='test-owner/test-project';official_root=$root;project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';git_runtime=[ordered]@{kind='NATIVE';project_root=$root;git_path='git'}})
    Write-Json (Join-Path $root '.aidos/STATE.json') ([ordered]@{schema_version='0.1';project_id='TEST';state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=1;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;updated_at='2026-01-01T00:00:00Z'})
    Set-Content (Join-Path $root 'tracked.txt') 'initial' -Encoding utf8NoBOM;&git -C $root add .;&git -C $root commit -qm initial
    $snapshot=Get-AidosPreparationSnapshot $root
    $execution=[ordered]@{schema_version='0.1';execution_id='EXEC-1';revision=1;project_id='TEST';project_mode='NEW_PROJECT';preparation=[ordered]@{baseline_commit='abcdef1234567890';access_sha256=$snapshot.access_sha256;evidence_inventory_sha256=$snapshot.evidence_inventory_sha256;current_product_state_id=$null;current_product_state_commit=$null;current_product_state_contract_version=$null;discovery_catalog_version=$null};definition=@{id='DEF-1';version=1};goal='Test';scope=@{};acceptance=@(@{criterion='passes'});authority=@{filesystem_write=@('SMOKE_RESULT.txt')};knowledge_selection=@();executor_profile=@{model='fake';reasoning_effort='low'};validation=[ordered]@{mode='ALL';requirements=@([ordered]@{type='FILE_CONTENT_EXACT';path='SMOKE_RESULT.txt';expected='AIDOS_BRIDGE_SMOKE_PASS';trim_trailing_newline=$true})}}
    $executionPath=Join-Path $root '.aidos/executions/EXEC-1/revision-1/EXECUTION.json';Write-Json $executionPath $execution
    [pscustomobject]@{Root=$root;Execution=$execution;ExecutionPath=$executionPath}
}

$project=New-TestProject
try {
    $resolvedNormal=Resolve-AidosFileSystemPath $project.Root;Assert-True ($resolvedNormal -eq $project.Root) 'normal local filesystem path resolves without provider text'
    $providerQualified="Microsoft.PowerShell.Core\FileSystem::$($project.Root)";$resolvedProvider=Resolve-AidosFileSystemPath $providerQualified;Assert-True ($resolvedProvider -eq $resolvedNormal) 'provider-qualified FileSystem path resolves to the same native path'
    Assert-True (Test-AidosSameFileSystemPath $project.Root $providerQualified) 'normal and provider-qualified paths compare equal'
    $binding=Test-AidosProjectBinding $project.Root;Assert-True $binding.Valid 'exact registered project binding passes'
    $nativeGitCommand=Get-AidosGitCommand ([pscustomobject]@{kind='NATIVE';project_root=$project.Root;git_path='git'}) @('rev-parse','HEAD');Assert-True ($nativeGitCommand.FileName -eq 'git' -and $nativeGitCommand.Arguments[0] -eq '-C' -and $nativeGitCommand.Arguments[1] -eq $project.Root) 'native project selects native Git command'
    $wslGitCommand=Get-AidosGitCommand ([pscustomobject]@{kind='WINDOWS_WSL';distribution='Ubuntu';project_root='/srv/project';git_path='/usr/bin/git'}) @('rev-parse','HEAD');Assert-True ($wslGitCommand.FileName -eq 'wsl.exe' -and $wslGitCommand.Arguments -contains '/srv/project' -and $wslGitCommand.Arguments -contains '/usr/bin/git') 'Windows WSL project selects WSL Git command'
    $providerBinding=Test-AidosProjectBinding $providerQualified;Assert-True $providerBinding.Valid 'provider-qualified project binding passes'
    $differentRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-different-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $differentRoot|Out-Null;&git -C $differentRoot init -q;&git -C $differentRoot remote add origin https://github.com/test-owner/test-project.git
    try { Assert-True (-not(Test-AidosSameFileSystemPath $project.Root $differentRoot)) 'genuinely different roots compare unequal';$profile=Read-AidosJson (Join-Path $project.Root '.aidos/PROJECT.json');$profile.official_root=$differentRoot;Write-Json (Join-Path $project.Root '.aidos/PROJECT.json') $profile;Assert-Throws {Test-AidosProjectBinding $project.Root} 'project-root mismatch';$profile.official_root=$project.Root;$profile.git_runtime.project_root=$differentRoot;Write-Json (Join-Path $project.Root '.aidos/PROJECT.json') $profile;Assert-Throws {Test-AidosProjectBinding $project.Root} 'Git root.*does not equal';$profile.git_runtime.project_root=$project.Root;Write-Json (Join-Path $project.Root '.aidos/PROJECT.json') $profile } finally { Remove-Item -LiteralPath $differentRoot -Recurse -Force }
    $profile=Read-AidosJson (Join-Path $project.Root '.aidos/PROJECT.json');$profile.repository='test-owner/test-project-extra';Write-Json (Join-Path $project.Root '.aidos/PROJECT.json') $profile
    Assert-Throws {Test-AidosProjectBinding $project.Root} 'exactly match';$profile.repository='test-owner/test-project';Write-Json (Join-Path $project.Root '.aidos/PROJECT.json') $profile

    $stale=$project.Execution|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$stale.preparation.baseline_commit='0000000'
    Assert-Throws {Assert-AidosExecutionBinding $project.Root $stale} 'stale or mismatched'

    $workspaceWriteArgs=Get-AidosCodexLaunchArguments ([pscustomobject]@{project_root=$project.Root}) $project.Execution 'workspace-write prompt'
    Assert-True ($workspaceWriteArgs -contains '--approve-for-me' -and -not($workspaceWriteArgs -contains '--sandbox')) 'filesystem-write authority maps to approve-for-me without sandbox flag'
    $readOnlyExecution=$project.Execution|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$readOnlyExecution.authority.filesystem_write=@()
    $readOnlyArgs=Get-AidosCodexLaunchArguments ([pscustomobject]@{project_root=$project.Root}) $readOnlyExecution 'read-only prompt'
    Assert-True ($readOnlyArgs -contains '--sandbox' -and $readOnlyArgs -contains 'read-only' -and -not($readOnlyArgs -contains '--approve-for-me')) 'read-only authority maps to read-only sandbox'
    $resumeArgs=Get-AidosCodexLaunchArguments ([pscustomobject]@{project_root=$project.Root}) $project.Execution 'resume prompt' -Resume -SessionId '11111111-1111-1111-1111-111111111111'
    Assert-True ($resumeArgs[0] -eq 'exec' -and $resumeArgs[1] -eq 'resume' -and -not($resumeArgs -contains '--approve-for-me') -and -not($resumeArgs -contains '--sandbox')) 'resume reuses the session policy without re-emitting sandbox flags'

    $atomic=Join-Path $project.Root '.aidos/runtime/atomic.json';1..20|ForEach-Object{Write-AidosJsonAtomic $atomic ([ordered]@{value=$_})};Assert-True ((Read-AidosJson $atomic).value -eq 20) 'atomic write leaves complete JSON';Assert-True (@(Get-ChildItem (Split-Path $atomic) -Filter '*.tmp').Count -eq 0) 'atomic write cleans temporary files'

    $lease=Acquire-AidosExecutionLease $project.Root 'EXEC-1' 1;Assert-Throws {Acquire-AidosExecutionLease $project.Root 'EXEC-1' 1} 'already exists';Release-AidosExecutionLease $project.Root $lease.lease_id

    $jobs=1..8|ForEach-Object{Start-Job -ScriptBlock {param($m,$r,$i)Import-Module $m -Force;Add-AidosEvent $r 'CONTENTION_TEST' 'SYSTEM' @{index=$i}|Out-Null} -ArgumentList $modulePath,$project.Root,$_};$jobs|Wait-Job|Receive-Job;$jobs|Remove-Job
    $eventLines=@(Get-ChildItem (Join-Path $project.Root '.aidos/events') -Filter '*.jsonl'|ForEach-Object{Get-Content $_.FullName}|Where-Object{($_|ConvertFrom-Json).event_type -eq 'CONTENTION_TEST'});Assert-True ($eventLines.Count -eq 8) 'event appends are mutually exclusive and lossless'

    $fake=Join-Path $project.Root 'fake-codex';@'
#!/usr/bin/env bash
args="$*"
case " $args " in
  *" --version "*)
    printf '%s\n' '0.147.0'
    exit 0
    ;;
esac
case " $args " in
  *" exec --help "*)
    printf '%s\n' 'Run Codex non-interactively'
    printf '%s\n' '  --sandbox <SANDBOX_MODE>'
    printf '%s\n' '  --approve-for-me'
    printf '%s\n' '  --json'
    exit 0
    ;;
esac
case " $args " in
  *" exec resume --help "*)
    printf '%s\n' 'Resume a previous session by id or pick the most recent with --last'
    printf '%s\n' '  --json'
    exit 0
    ;;
esac
if printf '%s\n' "$@" | grep -qx resume; then
    printf '%s\n' "$@" > codex-resume-args.txt
else
    printf '%s\n' "$@" > codex-start-args.txt
fi
printf '%s\n' 'AIDOS_BRIDGE_SMOKE_PASS' > SMOKE_RESULT.txt
printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-1111-1111-111111111111"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
'@|Set-Content -LiteralPath $fake -Encoding utf8NoBOM;&chmod +x $fake
    Assert-Throws {Invoke-AidosCodexExecution $project.Root $project.ExecutionPath ([pscustomobject]@{kind='WSL_LOCAL';project_root='/wrong/root';codex_path=$fake}) 'wrong root'} 'does not exist|does not exactly match'
    $runtime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$project.Root;codex_path=$fake;codex_capabilities=[pscustomobject]@{version='0.147.0';exec_has_approve_for_me=$true;exec_has_sandbox=$true;resume_has_json=$true}}
    $result=Invoke-AidosCodexExecution $project.Root $project.ExecutionPath $runtime 'fixture start'
    Assert-True ($result.terminal_type -eq 'turn.completed' -and $result.exit_code -eq 0) "Codex start captures terminal result (terminal=$($result.terminal_type), exit=$($result.exit_code), error=$($result.error))";$state=Get-AidosState $project.Root;Assert-True ($state.state -eq 'REVIEW_READY') 'successful run reaches REVIEW_READY';Assert-True ($state.codex_session_id -eq '11111111-1111-1111-1111-111111111111') 'session ID persisted';Assert-True ($state.git_head -eq (&git -C $project.Root rev-parse HEAD)) 'Git HEAD persisted';Assert-True (Test-Path (Join-Path $project.Root $state.terminal_result)) 'terminal result persisted'
    Assert-True ($result.process_succeeded -and $result.validation_status -eq 'PASS') 'process success and execution validation are persisted separately';$codexArgs=Get-Content (Join-Path $project.Root 'codex-start-args.txt');Assert-True ($codexArgs -contains '--approve-for-me' -and -not($codexArgs -contains '--sandbox')) 'filesystem authority selects workspace-write approval without sandbox flag'

    $null=Set-AidosState $project.Root 'GPT_REVIEWING' 'WORKER_AGENT';$null=Set-AidosState $project.Root 'TASK_READY' 'WORKER_AGENT' @{revision=2};$project.Execution.revision=2;$execution2=Join-Path $project.Root '.aidos/executions/EXEC-1/revision-2/EXECUTION.json';Write-Json $execution2 $project.Execution
    $resumed=Invoke-AidosCodexExecution $project.Root $execution2 $runtime 'fixture resume' -Resume;Assert-True $resumed.resumed 'resume mode recorded';Assert-True ($resumed.codex_session_id -eq $state.codex_session_id) 'resume retains session identity'
    $resumeCodexArgs=Get-Content (Join-Path $project.Root 'codex-resume-args.txt');Assert-True ($resumeCodexArgs[0] -eq 'exec' -and $resumeCodexArgs[1] -eq 'resume' -and -not($resumeCodexArgs -contains '--approve-for-me') -and -not($resumeCodexArgs -contains '--sandbox')) 'resume command shape omits policy flags'

    $rebindProject=New-TestProject
    try {
        Write-Json (Join-Path $rebindProject.Root '.aidos/STATE.json') ([ordered]@{schema_version='0.1';project_id='TEST';state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=3;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;updated_at='2026-01-01T00:00:00Z'})
        $null=Set-AidosExecutionDispatchBinding $rebindProject.Root 'EXEC-1' 4
        $rebindState=Get-AidosState $rebindProject.Root
        Assert-True ($rebindState.state -eq 'TASK_READY' -and $rebindState.revision -eq 4 -and $rebindState.execution_id -eq 'EXEC-1') 'dedicated dispatch binding updates revision while remaining TASK_READY'
        $rebindExecution=$rebindProject.Execution|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$rebindExecution.revision=4
        $rebindExecutionPath=Join-Path $rebindProject.Root '.aidos/executions/EXEC-1/revision-4/EXECUTION.json';Write-Json $rebindExecutionPath $rebindExecution
        $rebindRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$rebindProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $rebindResult=Invoke-AidosCodexExecution $rebindProject.Root $rebindExecutionPath $rebindRuntime 'revision 4 dispatch'
        Assert-True ($rebindResult.process_succeeded -and (Get-AidosState $rebindProject.Root).revision -eq 4) 'dispatch can proceed after explicit revision rebind'
    } finally { Remove-Item -LiteralPath $rebindProject.Root -Recurse -Force }

    $windowsLaunch=New-TestProject
    try {
        $fakeWslDir=Join-Path $windowsLaunch.Root 'fake-wsl-bin';New-Item -ItemType Directory -Path $fakeWslDir -Force|Out-Null
        $fakeWsl=Join-Path $fakeWslDir 'wsl.exe';@'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
    printf '%s\n' '0.147.0'
    exit 0
fi
if [ "$1" = "exec" ] && [ "${2:-}" = "--help" ]; then
    printf '%s\n' 'Run Codex non-interactively'
    printf '%s\n' '  --sandbox <SANDBOX_MODE>'
    printf '%s\n' '  --approve-for-me'
    printf '%s\n' '  --json'
    exit 0
fi
if [ "$1" = "exec" ] && [ "${2:-}" = "resume" ] && [ "${3:-}" = "--help" ]; then
    printf '%s\n' 'Resume a previous session by id or pick the most recent with --last'
    printf '%s\n' '  --json'
    exit 0
fi
if printf '%s\n' "$@" | grep -qx resume; then
    printf '%s\n' "$@" > windows-wsl-resume-args.txt
else
    printf '%s\n' "$@" > windows-wsl-start-args.txt
fi
printf '%s\n' 'AIDOS_BRIDGE_SMOKE_PASS' > SMOKE_RESULT.txt
printf '%s\n' '{"type":"thread.started","thread_id":"33333333-3333-3333-3333-333333333333"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
'@|Set-Content -LiteralPath $fakeWsl -Encoding utf8NoBOM;&chmod +x $fakeWsl
        $originalPath=$env:PATH
        $env:PATH=$fakeWslDir+[IO.Path]::PathSeparator+$env:PATH
        $windowsRuntime=[pscustomobject]@{kind='WINDOWS_WSL';distribution='Ubuntu';project_root='/home/aidos/repos/AIDOS-BRIDGE-SMOKE';codex_path='/home/aidos/.local/bin/codex';codex_capabilities=[pscustomobject]@{version='0.147.0';exec_has_approve_for_me=$true;exec_has_sandbox=$true;resume_has_json=$true}}
        $windowsLaunchExecution=$windowsLaunch.Execution|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        Write-Json $windowsLaunch.ExecutionPath $windowsLaunchExecution
        $windowsResult=Invoke-AidosCodexExecution $windowsLaunch.Root $windowsLaunch.ExecutionPath $windowsRuntime 'windows launch smoke'
        Assert-True ($windowsResult.process_succeeded -and $windowsResult.validation_status -eq 'PASS') 'WINDOWS_WSL launch succeeds through the live launch function'
        $startArgs=Get-Content (Join-Path $windowsLaunch.Root 'windows-wsl-start-args.txt')
        Assert-True ($startArgs -contains '--distribution' -and $startArgs -contains 'Ubuntu' -and $startArgs -contains '--exec' -and $startArgs -contains '/home/aidos/.local/bin/codex') 'WINDOWS_WSL start reaches wsl.exe with the Linux Codex path as an argument'
        $windowsState=Get-AidosState $windowsLaunch.Root
        Assert-True ($windowsState.codex_session_id -eq '33333333-3333-3333-3333-333333333333') 'WINDOWS_WSL session ID is persisted'
        $null=Set-AidosState $windowsLaunch.Root 'GPT_REVIEWING' 'WORKER_AGENT';$null=Set-AidosState $windowsLaunch.Root 'TASK_READY' 'WORKER_AGENT' @{revision=2};$windowsLaunch.Execution.revision=2;Write-Json (Join-Path $windowsLaunch.Root '.aidos/executions/EXEC-1/revision-2/EXECUTION.json') $windowsLaunch.Execution
        $windowsResume=Invoke-AidosCodexExecution $windowsLaunch.Root (Join-Path $windowsLaunch.Root '.aidos/executions/EXEC-1/revision-2/EXECUTION.json') $windowsRuntime 'windows resume smoke' -Resume
        Assert-True $windowsResume.resumed 'WINDOWS_WSL resume recorded'
        $resumeArgs=Get-Content (Join-Path $windowsLaunch.Root 'windows-wsl-resume-args.txt')
        Assert-True ($resumeArgs -contains 'resume' -and $resumeArgs -contains '--exec' -and $resumeArgs -contains '/home/aidos/.local/bin/codex') 'WINDOWS_WSL resume uses the same WSL dispatch boundary'
    } finally {
        if($originalPath){$env:PATH=$originalPath}
        Remove-Item -LiteralPath $windowsLaunch.Root -Recurse -Force
    }

    $blockedProject=New-TestProject
    try {
        $blockedExecution=$blockedProject.Execution|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $blockedExecution.authority|Add-Member -NotePropertyName network -NotePropertyValue $true -Force
        Write-Json $blockedProject.ExecutionPath $blockedExecution
        $blockedRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$blockedProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        Assert-Throws {Invoke-AidosCodexExecution $blockedProject.Root $blockedProject.ExecutionPath $blockedRuntime 'blocked authority'} 'cannot represent'
        Assert-True (-not(Test-Path (Join-Path $blockedProject.Root 'codex-start-args.txt')) -and -not(Test-Path (Join-Path $blockedProject.Root 'codex-resume-args.txt'))) 'preflight failure happens before a new launch'
    } finally { Remove-Item -LiteralPath $blockedProject.Root -Recurse -Force }

    $windowsCommand=Get-AidosCodexCommand ([pscustomobject]@{kind='WINDOWS_WSL';distribution='Ubuntu';project_root='/srv/project';codex_path='/usr/local/bin/codex'}) 'C:\\Projects\\Project' @('exec','--json','prompt')
    Assert-True ($windowsCommand.FileName -eq 'wsl.exe' -and $windowsCommand.Arguments[0] -eq '--distribution' -and $windowsCommand.Arguments -contains '/srv/project') 'Windows orchestrator uses explicit WSL runtime and path'

    $null=Set-AidosState $project.Root 'GPT_REVIEWING' 'WORKER_AGENT';$null=Set-AidosState $project.Root 'TASK_READY' 'WORKER_AGENT' @{revision=3};$l=Acquire-AidosExecutionLease $project.Root 'EXEC-1' 3;$null=Set-AidosState $project.Root 'CODEX_RUNNING' 'BRIDGE' @{lease_id=$l.lease_id};$leasePath=Join-Path $project.Root '.aidos/runtime/lease.json';$staleLease=Read-AidosJson $leasePath;$staleLease.codex_runtime=[ordered]@{kind='WSL_LOCAL';supervisor_pid=2147483000;started_at='2026-01-01T00:00:00Z'};Write-AidosJsonAtomic $leasePath $staleLease
    $recovery=Invoke-AidosStartupReconciliation $project.Root;Assert-True ($recovery.status -eq 'RECOVERY_REQUIRED') 'stale execution reconciles safely';Assert-True ((Get-AidosState $project.Root).state -eq 'RECOVERY_REQUIRED') 'interruption never infers completion';Assert-True (-not(Test-Path $leasePath)) 'stale lease released after recovery event'

    $validationFailure=New-TestProject
    try {
        $cleanExit=Join-Path $validationFailure.Root 'fake-clean-exit';@'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
    printf '%s\n' '0.147.0'
    exit 0
fi
if [ "$1" = "exec" ] && [ "${2:-}" = "--help" ]; then
    printf '%s\n' 'Run Codex non-interactively'
    printf '%s\n' '  --sandbox <SANDBOX_MODE>'
    printf '%s\n' '  --approve-for-me'
    printf '%s\n' '  --json'
    exit 0
fi
if [ "$1" = "exec" ] && [ "${2:-}" = "resume" ] && [ "${3:-}" = "--help" ]; then
    printf '%s\n' 'Resume a previous session by id or pick the most recent with --last'
    printf '%s\n' '  --json'
    exit 0
fi
printf '%s\n' '{"type":"thread.started","thread_id":"22222222-2222-2222-2222-222222222222"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"Could not produce required output."}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
'@|Set-Content -LiteralPath $cleanExit -Encoding utf8NoBOM;&chmod +x $cleanExit
        $failedResult=Invoke-AidosCodexExecution $validationFailure.Root $validationFailure.ExecutionPath ([pscustomobject]@{kind='WSL_LOCAL';project_root=$validationFailure.Root;codex_path=$cleanExit}) 'clean process, missing output'
        $failedState=Get-AidosState $validationFailure.Root
        Assert-True ($failedResult.exit_code -eq 0 -and $failedResult.terminal_type -eq 'turn.completed' -and $failedResult.process_succeeded) 'clean Codex process completion is recorded'
        Assert-True ($failedResult.validation_status -eq 'FAIL' -and $failedState.state -eq 'EXECUTION_VALIDATION_FAILED') 'missing required output cannot reach REVIEW_READY'
        Assert-True ($failedState.codex_session_id -eq '22222222-2222-2222-2222-222222222222' -and -not(Test-Path (Join-Path $validationFailure.Root '.aidos/runtime/lease.json'))) 'failed validation preserves session and releases lease'
        Assert-True ((Read-AidosJson (Join-Path $validationFailure.Root $failedState.validation_result)).requirements[0].passed -eq $false) 'validation failure evidence is durable'
    } finally { Remove-Item -LiteralPath $validationFailure.Root -Recurse -Force }

    $partial=New-TestProject
    try {
        Add-AidosEvent $partial.Root 'STATE_TRANSITION' 'BRIDGE' @{from='TASK_READY';to='CODEX_RUNNING';patch_keys=@('lease_id')}|Out-Null
        $partialRecovery=Invoke-AidosStartupReconciliation $partial.Root
        Assert-True $partialRecovery.projection_repaired 'event-first partial state write is replayed'
        Assert-True ((Get-AidosState $partial.Root).state -eq 'RECOVERY_REQUIRED') 'CODEX_RUNNING without a lease fails safely to recovery'
    } finally { Remove-Item -LiteralPath $partial.Root -Recurse -Force }

    Write-Output "PASS: $script:Passed assertions"
} finally { Remove-Item -LiteralPath $project.Root -Recurse -Force }
