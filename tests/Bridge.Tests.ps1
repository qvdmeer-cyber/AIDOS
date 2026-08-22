Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosBridge.psm1'
Import-Module $modulePath -Force
$desktopAdapterModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosDesktopChatGPT.psm1'
Import-Module $desktopAdapterModulePath -Force -DisableNameChecking
$script:Passed = 0

function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition){throw "ASSERTION FAILED: $Message"};$script:Passed++ }
function Assert-Throws([scriptblock]$Action,[string]$Pattern) { try{&$Action;throw 'Expected an exception.'}catch{if($_.Exception.Message -eq 'Expected an exception.'){throw};Assert-True ($_.Exception.Message -match $Pattern) "Expected error /$Pattern/, got: $($_.Exception.Message)"} }
function Write-Json($Path,$Value) { $dir=Split-Path -Parent $Path;if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding utf8NoBOM }
function Get-PwshExecutable {
    $command=Get-Command pwsh -ErrorAction SilentlyContinue
    if($command -and $command.Source){return $command.Source}
    return (Join-Path $PSHOME 'pwsh')
}
function Invoke-ExternalReviewWorker {
    param([string]$AssignmentPath,[ValidateSet('PASS','REPAIR','BLOCKER','DISCOVERY_REFRESH_REQUIRED','WAITING_INTERACTIVE_SESSION')][string]$Outcome='PASS',[string]$Reason='external worker stub review')
    $workerScript=Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/Invoke-AidosReviewWorker.ps1'
    $pwshExe=Get-PwshExecutable
    $response=& $pwshExe -NoLogo -NoProfile -File $workerScript -AssignmentPath $AssignmentPath -Outcome $Outcome -Reason $Reason
    if($LASTEXITCODE -ne 0){throw "Worker stub failed with exit code $LASTEXITCODE."}
    [string]::Join([Environment]::NewLine, @($response))
}
$desktopAdapterPublicCommands = @(
    'Test-AidosDesktopChatGPTInteractiveSession',
    'Invoke-AidosDesktopChatGPTEnroll',
    'Invoke-AidosDesktopChatGPTReview'
)
foreach($commandName in $desktopAdapterPublicCommands){
    Assert-True ([bool](Get-Command $commandName -ErrorAction SilentlyContinue)) "desktop adapter exports $commandName"
}
if($IsWindows){
    Assert-True (Test-AidosDesktopChatGPTInteractiveSession) 'desktop adapter detects the interactive Windows session'
    Assert-True (Test-AidosDesktopChatGPTInteractiveSession) 'desktop adapter can initialize its versioned native helper repeatedly'
    Assert-True ([bool]([type]'AidosNativeDesktopV3')) 'versioned native helper type is available after repeated initialization'
}
$desktopAdapterSource=Get-Content -LiteralPath $desktopAdapterModulePath -Raw -Encoding UTF8
Assert-True ($desktopAdapterSource -match 'GetWindowTextW\(IntPtr hWnd, System\.Text\.StringBuilder lpString, int nMaxCount\)' -and $desktopAdapterSource -match 'GetClassNameW\(IntPtr hWnd, System\.Text\.StringBuilder lpString, int nMaxCount\)' -and $desktopAdapterSource -match 'CharSet=CharSet\.Unicode') 'native Win32 title/class retrieval declares Unicode StringBuilder marshalling'
function Invoke-DesktopChatGPTAdapter {
    param(
        [ValidateSet('Enroll','Review')][string]$Mode='Review',
        [string]$ProjectRoot,
        [string]$ConversationProofText='',
        [string]$AccountProofText='',
        [string]$AssignmentPath,
        [ValidateSet('Real','Stub')][string]$BackendMode='Stub',
        [bool]$StubInteractiveSession=$true,
        [bool]$StubConversationMatches=$true,
        [bool]$StubNoResponse=$false,
        [string]$StubResponseText,
        [string]$ProcessName='ChatGPT',
        [int]$ResponseTimeoutSeconds=30
    )
    $adapterScript=Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/Invoke-AidosDesktopChatGPT.ps1'
    $pwshExe=Get-PwshExecutable
    $args=@('-NoLogo','-NoProfile','-File',$adapterScript,'-ProjectRoot',$ProjectRoot,'-Mode',$Mode,'-ProcessName',$ProcessName,'-BackendMode',$BackendMode,'-StubInteractiveSession',([string]$StubInteractiveSession),'-StubConversationMatches',([string]$StubConversationMatches),'-StubNoResponse',([string]$StubNoResponse),'-ResponseTimeoutSeconds',([string]$ResponseTimeoutSeconds))
    if($ConversationProofText){ $args += @('-ConversationProofText',$ConversationProofText) }
    if($AccountProofText){ $args += @('-AccountProofText',$AccountProofText) }
    if($AssignmentPath){ $args += @('-AssignmentPath',$AssignmentPath) }
    if($StubResponseText){ $args += @('-StubResponseText',$StubResponseText) }
    $response=& $pwshExe @args
    if($LASTEXITCODE -ne 0){throw "Desktop adapter failed with exit code $LASTEXITCODE."}
    [string]::Join([Environment]::NewLine, @($response))
}

$selectorHelperProcesses=@(
    [pscustomobject]@{present=$true;process_id=10676;process_name='ChatGPT Classic';session_id=1;main_window_handle='0';window_handle='657871';window_title='';window_class_name='Chrome_RenderWidgetHostHWND';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$true;window_source='helper';usable_application_window=$false;proof_reason='internal render helper'}
    [pscustomobject]@{present=$true;process_id=10677;process_name='ChatGPT Classic';session_id=1;main_window_handle='0';window_handle='781234';window_title='';window_class_name='IME';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$true;window_source='helper';usable_application_window=$false;proof_reason='IME window'}
    [pscustomobject]@{present=$true;process_id=17376;process_name='ChatGPT Classic';session_id=1;main_window_handle='657418';window_handle='657418';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$true;window_source='MainWindowHandle';uia_process_id=17376;uia_native_window_handle='657418';uia_class_name='Chrome_WidgetWin_1';uia_control_type='System.Windows.Automation.ControlType.Window';uia_name='ChatGPT Classic';usable_application_window=$true;proof_reason='Accepted application shell candidate.'}
)
$selectedSelectorProcess=Select-AidosDesktopChatGPTProcessContext $selectorHelperProcesses
Assert-True ($selectedSelectorProcess.process_id -eq 17376 -and $selectedSelectorProcess.window_handle -eq '657418') 'selector chooses the actual usable visible ChatGPT top-level window over helper processes'

$selectorMinimizedWindow=@([pscustomobject]@{present=$true;process_id=17376;process_name='ChatGPT Classic';session_id=1;main_window_handle='657418';window_handle='657418';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$true;window_is_foreground=$false;window_is_visible=$true;window_source='MainWindowHandle';uia_process_id=17376;uia_native_window_handle='657418';uia_class_name='Chrome_WidgetWin_1';uia_control_type='System.Windows.Automation.ControlType.Window';uia_name='ChatGPT Classic';usable_application_window=$true;proof_reason='Accepted application shell candidate.'})
$selectedMinimizedProcess=Select-AidosDesktopChatGPTProcessContext $selectorMinimizedWindow
Assert-True ($selectedMinimizedProcess.window_is_minimized -and $selectedMinimizedProcess.window_handle -eq '657418') 'selector preserves an identifiable minimized ChatGPT window'

$selectorHelperOnly=@(
    [pscustomobject]@{present=$true;process_id=10676;process_name='ChatGPT Classic';session_id=1;main_window_handle='0';window_handle='657871';window_title='';window_class_name='Chrome_RenderWidgetHostHWND';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$true;window_source='helper';usable_application_window=$false;proof_reason='internal render helper'}
    [pscustomobject]@{present=$true;process_id=10677;process_name='ChatGPT Classic';session_id=1;main_window_handle='0';window_handle='781234';window_title='';window_class_name='IME';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$true;window_source='helper';usable_application_window=$false;proof_reason='IME window'}
)
Assert-Throws { Select-AidosDesktopChatGPTProcessContext $selectorHelperOnly } 'No usable ChatGPT application shell window was discovered'

$selectorNoWindow=@([pscustomobject]@{present=$true;process_id=17376;process_name='ChatGPT Classic';session_id=1;main_window_handle='0';window_handle='0';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$false;window_source='EnumWindows';usable_application_window=$false;proof_reason='Window handle is zero.'})
Assert-Throws { Select-AidosDesktopChatGPTProcessContext $selectorNoWindow } 'No usable ChatGPT application shell window was discovered'

Assert-Throws {
    Select-AidosDesktopChatGPTProcessContext @(
        [pscustomobject]@{present=$true;process_id=17376;process_name='ChatGPT Classic';session_id=1;main_window_handle='657418';window_handle='657418';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$true;window_source='MainWindowHandle';uia_process_id=17376;uia_native_window_handle='657418';uia_class_name='Chrome_WidgetWin_1';uia_control_type='System.Windows.Automation.ControlType.Window';uia_name='ChatGPT Classic';usable_application_window=$true;proof_reason='Accepted application shell candidate.'}
        [pscustomobject]@{present=$true;process_id=17377;process_name='ChatGPT Classic';session_id=1;main_window_handle='657419';window_handle='657419';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$false;window_is_visible=$true;window_source='MainWindowHandle';uia_process_id=17377;uia_native_window_handle='657419';uia_class_name='Chrome_WidgetWin_1';uia_control_type='System.Windows.Automation.ControlType.Window';uia_name='ChatGPT Classic';usable_application_window=$true;proof_reason='Accepted application shell candidate.'}
    )
} 'Multiple usable ChatGPT top-level windows'

function New-TestProject {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('aidos-bridge-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
    &git -C $root init -q;&git -C $root config user.email test@example.invalid;&git -C $root config user.name 'AIDOS Test';&git -C $root remote add origin https://github.com/test-owner/test-project.git
    New-Item -ItemType Directory -Path (Join-Path $root '.aidos/documentation'),(Join-Path $root '.aidos/evidence'),(Join-Path $root '.aidos/events') -Force|Out-Null
    Write-Json (Join-Path $root '.aidos/documentation/PROJECT_BASELINE.json') ([ordered]@{accepted_at='2026-01-01T00:00:00Z';accepted_by='human';accepted_commit='abcdef1234567890'})
    Write-Json (Join-Path $root '.aidos/documentation/PROJECT_ACCESS.json') ([ordered]@{contract_version='0.1.0';project_id='TEST'})
    Write-Json (Join-Path $root '.aidos/evidence/EVIDENCE_INVENTORY.json') ([ordered]@{contract_version='0.2.0';project_id='TEST'})
    Write-Json (Join-Path $root '.aidos/PROJECT.json') ([ordered]@{schema_version='0.1';project_id='TEST';project_mode='NEW_PROJECT';repository='test-owner/test-project';official_root=$root;agent_profile='.aidos/AGENT_PROFILE.json';project_baseline='.aidos/documentation/PROJECT_BASELINE.json';project_access='.aidos/documentation/PROJECT_ACCESS.json';evidence_inventory='.aidos/evidence/EVIDENCE_INVENTORY.json';git_runtime=[ordered]@{kind='NATIVE';project_root=$root;git_path='git'}})
    Write-Json (Join-Path $root '.aidos/AGENT_PROFILE.json') ([ordered]@{schema_version='0.1';project_id='TEST';aidos_agents=[ordered]@{definition='agents/DEFINITION_AGENT.md';worker='agents/WORKER_AGENT.md';execution='agents/EXECUTION_AGENT.md'};reviewer_role='WORKER_AGENT';reviewer_identity='agents/WORKER_AGENT.md';project_specific_sources=@();project_constraints=@();executor=[ordered]@{model='fake';reasoning_effort='low'}})
    Write-Json (Join-Path $root '.aidos/STATE.json') ([ordered]@{schema_version='0.1';project_id='TEST';state='TASK_READY';definition_id='DEF-1';definition_version=1;execution_id='EXEC-1';revision=1;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;updated_at='2026-01-01T00:00:00Z'})
    Set-Content (Join-Path $root 'tracked.txt') 'initial' -Encoding utf8NoBOM;&git -C $root add .;&git -C $root commit -qm initial
    $snapshot=Get-AidosPreparationSnapshot $root
    $execution=[ordered]@{schema_version='0.1';execution_id='EXEC-1';revision=1;project_id='TEST';project_mode='NEW_PROJECT';preparation=[ordered]@{baseline_commit='abcdef1234567890';access_sha256=$snapshot.access_sha256;evidence_inventory_sha256=$snapshot.evidence_inventory_sha256;current_product_state_id=$null;current_product_state_commit=$null;current_product_state_contract_version=$null;discovery_catalog_version=$null};definition=@{id='DEF-1';version=1};goal='Test';scope=@{};acceptance=@(@{criterion='passes'});authority=@{filesystem_write=@('SMOKE_RESULT.txt')};knowledge_selection=@();executor_profile=@{model='fake';reasoning_effort='low'};validation=[ordered]@{mode='ALL';requirements=@([ordered]@{type='FILE_CONTENT_EXACT';path='SMOKE_RESULT.txt';expected='AIDOS_BRIDGE_SMOKE_PASS';trim_trailing_newline=$true})}}
    $executionPath=Join-Path $root '.aidos/executions/EXEC-1/revision-1/EXECUTION.json';Write-Json $executionPath $execution
    [pscustomobject]@{Root=$root;Execution=$execution;ExecutionPath=$executionPath}
}

$selectorEnrollmentProject=New-TestProject
try {
    $enrollmentBackend=New-AidosDesktopChatGPTStubBackend -InteractiveSession:$true -ConversationMatches:$true -ProcessName 'ChatGPT Classic' -WindowTitle 'ChatGPT Classic' -WindowClassName 'Chrome_WidgetWin_1'
    $enrollmentResult=Invoke-AidosDesktopChatGPTEnroll -ProjectRoot $selectorEnrollmentProject.Root -ConversationProofText 'Deze chat is vanaf nu de AIDOS Worker.' -AccountProofText 'AIDOS Account Proof' -ProcessName 'ChatGPT Classic' -Backend $enrollmentBackend
    $enrollmentRecord=Read-AidosDesktopChatGPTEnrollment $selectorEnrollmentProject.Root
    Assert-True ($enrollmentResult.status -eq 'ENROLLED' -and $enrollmentRecord.conversation_fingerprint_sha256) 'one usable candidate reaches enrollment'
} finally {
    Remove-Item -LiteralPath $selectorEnrollmentProject.Root -Recurse -Force
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

    $reviewProject=New-TestProject
    try {
        $reviewRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$reviewProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $reviewExecution=Invoke-AidosCodexExecution $reviewProject.Root $reviewProject.ExecutionPath $reviewRuntime 'review transport smoke'
        Assert-True ($reviewExecution.validation_status -eq 'PASS' -and (Get-AidosState $reviewProject.Root).state -eq 'REVIEW_READY') 'review smoke reaches REVIEW_READY before publication'
        $published=Publish-AidosReviewPackage $reviewProject.Root $reviewProject.ExecutionPath
        $reviewState=Get-AidosState $reviewProject.Root
        Assert-True ($reviewState.state -eq 'GPT_REVIEWING' -and $reviewState.review_id -eq $published.review_id) 'publish binds review_id and moves to GPT_REVIEWING'
        $manifest=Read-AidosJson (Join-Path $reviewProject.Root $published.manifest_path)
        $assignment=Read-AidosJson (Join-Path $reviewProject.Root $published.assignment_path)
        Assert-True ($manifest.package_type -eq 'REVIEW_PACKAGE' -and $manifest.review_id -eq $published.review_id -and $manifest.assignment_path -eq $published.assignment_path -and @($manifest.evidence_refs).Count -ge 4) 'review manifest is secret-free and points at durable evidence'
        Assert-True ($assignment.envelope_type -eq 'REVIEW_ASSIGNMENT' -and $assignment.reviewer_identity -eq 'agents/WORKER_AGENT.md' -and $published.assignment_sha256) 'review assignment is canonical and secret-free'
        $packageNames=@(Get-ChildItem (Join-Path $reviewProject.Root $published.package_path) | Select-Object -ExpandProperty Name)
        Assert-True ($packageNames -contains 'MANIFEST.json' -and $packageNames -contains 'REVIEW_ASSIGNMENT.json') 'published review package contains MANIFEST.json and REVIEW_ASSIGNMENT.json'
        Assert-True ($published.assignment_sha256 -eq (Get-FileHash -LiteralPath (Join-Path $reviewProject.Root $published.assignment_path) -Algorithm SHA256).Hash.ToLowerInvariant()) 'durable assignment hash equals exact published file hash'
        $responseJson=Invoke-ExternalReviewWorker -AssignmentPath (Join-Path $reviewProject.Root $published.assignment_path) -Outcome PASS -Reason 'approved'
        $response=$responseJson | ConvertFrom-Json -Depth 100
        Assert-True ($response.envelope_type -eq 'REVIEW_RESPONSE' -and $response.reviewer_identity -eq 'agents/WORKER_AGENT.md' -and $response.assignment_sha256) 'external worker returns a canonical response envelope'
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $reviewProject.Root $published.assignment_path) -Algorithm SHA256).Hash.ToLowerInvariant() -eq $published.assignment_sha256) 'worker does not mutate assignment bytes or hash'
        $consumer=Invoke-AidosReviewConsumer -ProjectRoot $reviewProject.Root -ResponseJson $responseJson
        $cleanState=Get-AidosState $reviewProject.Root
        Assert-True ($cleanState.state -eq 'IDLE' -and $cleanState.review_id -eq $null) 'PASS deterministically returns project to IDLE'
        Assert-True ($cleanState.lease_id -ne $null -and -not(Test-Path (Join-Path $reviewProject.Root '.aidos/runtime/lease.json'))) 'IDLE keeps last execution lease_id as historical context after the physical lease is removed'
        $reviewRecord=Read-AidosJson (Join-Path $reviewProject.Root ".aidos/reviews/$($published.review_id)/REVIEW.json")
        Assert-True ($reviewRecord.transport_state -eq 'CLEANED' -and $reviewRecord.decision.outcome -eq 'PASS' -and $reviewRecord.consume_ack.review_id -eq $published.review_id -and $reviewRecord.response.reviewer_identity -eq 'agents/WORKER_AGENT.md') 'durable review record keeps assignment, response, decision, consume ack, and cleanup evidence'
        Assert-True (-not(Test-Path (Join-Path $reviewProject.Root $published.package_path))) 'ephemeral review package is cleaned after durable consume'
        $replayed=Invoke-AidosReviewConsumer -ProjectRoot $reviewProject.Root -ResponseJson $responseJson
        Assert-True ((Get-AidosState $reviewProject.Root).state -eq 'IDLE' -and (Read-AidosReviewRecord $reviewProject.Root $published.review_id).transport_state -eq 'CLEANED') 'identical response replay is idempotent'
        $tamperedResponse=$response|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $tamperedResponse.reviewer_identity='malicious-reviewer'
        $tamperedResponseJson=$tamperedResponse|ConvertTo-Json -Depth 100
        Assert-Throws { Invoke-AidosReviewConsumer -ProjectRoot $reviewProject.Root -ResponseJson $tamperedResponseJson } 'bridge-bound|mismatched'
        $reviewEvents=@(Get-ChildItem (Join-Path $reviewProject.Root '.aidos/events') -Filter '*.jsonl' | ForEach-Object { Get-Content $_.FullName } | ForEach-Object { ($_ | ConvertFrom-Json).event_type })
        Assert-True ($reviewEvents -contains 'REVIEW_ASSIGNMENT_PUBLISHED' -and $reviewEvents -contains 'REVIEW_RESPONSE_RECEIVED' -and $reviewEvents -contains 'REVIEW_RESPONSE_ACCEPTED' -and $reviewEvents -contains 'REVIEW_DECISION_RECORDED' -and $reviewEvents -contains 'REVIEW_PACKAGE_CONSUMED' -and $reviewEvents -contains 'REVIEW_CLEANUP_CONFIRMED') 'review lifecycle events are emitted'
        Assert-Throws { Abandon-AidosReview -ProjectRoot $reviewProject.Root -ReviewId $published.review_id -Reason 'should not be allowed' -Actor BRIDGE } 'accepted durable response|decision|consume acknowledgement|cleanup'
    } finally { Remove-Item -LiteralPath $reviewProject.Root -Recurse -Force }

    $abandonProject=New-TestProject
    try {
        $abandonRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$abandonProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $abandonExecution=Invoke-AidosCodexExecution $abandonProject.Root $abandonProject.ExecutionPath $abandonRuntime 'abandon review smoke'
        Assert-True ($abandonExecution.validation_status -eq 'PASS') 'abandonment fixture reaches reviewable evidence'
        $abandonPublished=Publish-AidosReviewPackage $abandonProject.Root $abandonProject.ExecutionPath
        $null=Set-AidosState $abandonProject.Root 'RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$null}
        $rejectedEvidence=Join-Path $abandonProject.Root ".aidos/runtime/chatgpt/reviews/$($abandonPublished.review_id)/RESPONSE_REJECTED.json"
        Write-Json $rejectedEvidence ([ordered]@{review_id=$abandonPublished.review_id;reason='strict response validation rejected the external payload'})
        $packageBefore=Join-Path $abandonProject.Root $abandonPublished.package_path
        $abandoned=Abandon-AidosReview -ProjectRoot $abandonProject.Root -ReviewId $abandonPublished.review_id -Reason 'External response was rejected before bridge acceptance.' -Actor BRIDGE
        $abandonedRecord=Read-AidosReviewRecord $abandonProject.Root $abandonPublished.review_id
        Assert-True ($abandoned.transport_state -eq 'ABANDONED' -and -not $abandoned.idempotent -and -not $abandonedRecord.decision -and -not $abandonedRecord.response -and $abandonedRecord.abandonment.reason) 'rejected unconsumed review is explicitly abandoned without a fabricated decision'
        Assert-True ((Test-Path -LiteralPath $packageBefore) -and (Test-Path -LiteralPath $rejectedEvidence)) 'abandonment preserves package and rejected response evidence'
        $abandonedAgain=Abandon-AidosReview -ProjectRoot $abandonProject.Root -ReviewId $abandonPublished.review_id -Reason 'External response was rejected before bridge acceptance.' -Actor BRIDGE
        Assert-True $abandonedAgain.idempotent 'repeated identical abandonment is idempotent'
        Assert-True ((Invoke-AidosReviewReconciliation -ProjectRoot $abandonProject.Root).status -eq 'CLEAN') 'valid abandoned historical review is terminal for reconciliation'
        $abandonEvents=@(Get-ChildItem (Join-Path $abandonProject.Root '.aidos/events') -Filter '*.jsonl' | ForEach-Object { Get-Content $_.FullName } | ForEach-Object { ($_ | ConvertFrom-Json).event_type })
        Assert-True ($abandonEvents -contains 'REVIEW_TRANSPORT_ABANDONED') 'review abandonment emits durable event evidence'
        Assert-True ((@($abandonEvents|Where-Object {$_ -eq 'REVIEW_TRANSPORT_ABANDONED'}).Count -eq 1)) 'idempotent abandonment does not append a second closure event'
    } finally { Remove-Item -LiteralPath $abandonProject.Root -Recurse -Force }

    $recoveryProject=New-TestProject
    try {
        $recoveryRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$recoveryProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $recoveryExecution=Invoke-AidosCodexExecution $recoveryProject.Root $recoveryProject.ExecutionPath $recoveryRuntime 'legacy review recovery smoke'
        Assert-True ($recoveryExecution.validation_status -eq 'PASS') 'legacy recovery smoke reaches publishable evidence'
        $recoveryPublished=Publish-AidosReviewPackage $recoveryProject.Root $recoveryProject.ExecutionPath
        $legacyAssignmentPath=Join-Path $recoveryProject.Root $recoveryPublished.assignment_path
        Remove-Item -LiteralPath $legacyAssignmentPath -Force
        $legacyRecord=Read-AidosJson (Join-Path $recoveryProject.Root ".aidos/reviews/$($recoveryPublished.review_id)/REVIEW.json")
        $legacyRecord.assignment_path=$null
        $legacyRecord.assignment=$null
        $legacyRecord.assignment_sha256=$null
        $legacyRecord.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $recoveryProject.Root $recoveryPublished.review_id $legacyRecord
        $recoveryEntryPoint=Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/Invoke-AidosReview.ps1'
        $recoveredJson=& (Get-PwshExecutable) -NoLogo -NoProfile -File $recoveryEntryPoint -ProjectRoot $recoveryProject.Root -Mode Recover -ExecutionPath $recoveryProject.ExecutionPath
        if($LASTEXITCODE -ne 0){throw "Recovery entrypoint failed with exit code $LASTEXITCODE."}
        $recovered=$recoveredJson | ConvertFrom-Json -Depth 100
        Assert-True ($recovered.recovered -and $recovered.assignment_path -and $recovered.assignment_sha256) 'legacy GPT_REVIEWING recovery creates canonical assignment correlation without a new state transition'
        $recoveryAssignment=Read-AidosJson (Join-Path $recoveryProject.Root $recovered.assignment_path)
        Assert-True ($recoveryAssignment.envelope_type -eq 'REVIEW_ASSIGNMENT' -and $recoveryAssignment.reviewer_identity -eq 'agents/WORKER_AGENT.md') 'recovery writes canonical REVIEW_ASSIGNMENT.json'
        $recoveryPackageNames=@(Get-ChildItem (Join-Path $recoveryProject.Root $recovered.package_path) | Select-Object -ExpandProperty Name)
        Assert-True ($recoveryPackageNames -contains 'MANIFEST.json' -and $recoveryPackageNames -contains 'REVIEW_ASSIGNMENT.json') 'recovered review package contains MANIFEST.json and REVIEW_ASSIGNMENT.json'
        $recoveryRecord=Read-AidosJson (Join-Path $recoveryProject.Root ".aidos/reviews/$($recoveryPublished.review_id)/REVIEW.json")
        Assert-True ($recoveryRecord.assignment_path -eq $recovered.assignment_path -and $recoveryRecord.assignment_sha256 -eq $recovered.assignment_sha256) 'recovery records assignment correlation durably'
        Assert-True ($recovered.assignment_sha256 -eq (Get-FileHash -LiteralPath (Join-Path $recoveryProject.Root $recovered.assignment_path) -Algorithm SHA256).Hash.ToLowerInvariant()) 'recovery durable hash equals exact final file hash'
        $canonicalRecoveryAssignmentHash=$recovered.assignment_sha256
        $recoveryRecord.assignment_sha256='0000000000000000000000000000000000000000000000000000000000000000'
        $recoveryRecord.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $recoveryProject.Root $recoveryPublished.review_id $recoveryRecord
        Assert-Throws { & (Get-PwshExecutable) -NoLogo -NoProfile -File $recoveryEntryPoint -ProjectRoot $recoveryProject.Root -Mode Recover -ExecutionPath $recoveryProject.ExecutionPath } 'hash mismatch'
        $repairedJson=& (Get-PwshExecutable) -NoLogo -NoProfile -File $recoveryEntryPoint -ProjectRoot $recoveryProject.Root -Mode RepairLegacyCorrelation -ExecutionPath $recoveryProject.ExecutionPath
        if($LASTEXITCODE -ne 0){throw "Legacy correlation repair entrypoint failed with exit code $LASTEXITCODE."}
        $repaired=$repairedJson | ConvertFrom-Json -Depth 100
        Assert-True ($repaired.recovered -and -not $repaired.idempotent -and $repaired.assignment_sha256 -eq $canonicalRecoveryAssignmentHash) 'explicit legacy correlation repair fixes durable hash without a state transition'
        $repairedRecord=Read-AidosJson (Join-Path $recoveryProject.Root ".aidos/reviews/$($recoveryPublished.review_id)/REVIEW.json")
        Assert-True ($repairedRecord.assignment_sha256 -eq $canonicalRecoveryAssignmentHash) 'legacy correlation repair updates REVIEW.json.assignment_sha256'
        $repairedAgainJson=& (Get-PwshExecutable) -NoLogo -NoProfile -File $recoveryEntryPoint -ProjectRoot $recoveryProject.Root -Mode RepairLegacyCorrelation -ExecutionPath $recoveryProject.ExecutionPath
        if($LASTEXITCODE -ne 0){throw "Idempotent legacy correlation repair entrypoint failed with exit code $LASTEXITCODE."}
        $repairedAgain=$repairedAgainJson | ConvertFrom-Json -Depth 100
        Assert-True ($repairedAgain.idempotent -and $repairedAgain.assignment_sha256 -eq $canonicalRecoveryAssignmentHash) 'legacy correlation repair is idempotent'
        $recoveryAssignment=Read-AidosJson (Join-Path $recoveryProject.Root $repaired.assignment_path)
        Assert-True ($recoveryAssignment.envelope_type -eq 'REVIEW_ASSIGNMENT' -and $recoveryAssignment.reviewer_identity -eq 'agents/WORKER_AGENT.md') 'recovery writes canonical REVIEW_ASSIGNMENT.json'
        $recoveryPackageNames=@(Get-ChildItem (Join-Path $recoveryProject.Root $repaired.package_path) | Select-Object -ExpandProperty Name)
        Assert-True ($recoveryPackageNames -contains 'MANIFEST.json' -and $recoveryPackageNames -contains 'REVIEW_ASSIGNMENT.json') 'recovered review package contains MANIFEST.json and REVIEW_ASSIGNMENT.json'
        $consumingResponseJson=Invoke-ExternalReviewWorker -AssignmentPath (Join-Path $recoveryProject.Root $repaired.assignment_path) -Outcome PASS -Reason 'approved'
        $null=Invoke-AidosReviewConsumer -ProjectRoot $recoveryProject.Root -ResponseJson $consumingResponseJson
        Assert-Throws { & (Get-PwshExecutable) -NoLogo -NoProfile -File $recoveryEntryPoint -ProjectRoot $recoveryProject.Root -Mode RepairLegacyCorrelation -ExecutionPath $recoveryProject.ExecutionPath } 'GPT_REVIEWING|decision|consumed|CLEANED'
        $recoveryEvents=@(Get-ChildItem (Join-Path $recoveryProject.Root '.aidos/events') -Filter '*.jsonl' | ForEach-Object { Get-Content $_.FullName } | ForEach-Object { ($_ | ConvertFrom-Json).event_type })
        Assert-True ($recoveryEvents -contains 'LEGACY_REVIEW_ASSIGNMENT_CORRELATION_REPAIRED') 'legacy correlation repair event is emitted'
    } finally { Remove-Item -LiteralPath $recoveryProject.Root -Recurse -Force }

    $tamperRecoveryProject=New-TestProject
    try {
        $tamperRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$tamperRecoveryProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $tamperExecution=Invoke-AidosCodexExecution $tamperRecoveryProject.Root $tamperRecoveryProject.ExecutionPath $tamperRuntime 'tamper assignment repair smoke'
        Assert-True ($tamperExecution.validation_status -eq 'PASS') 'tamper assignment repair smoke reaches publishable evidence'
        $tamperPublished=Publish-AidosReviewPackage $tamperRecoveryProject.Root $tamperRecoveryProject.ExecutionPath
        $tamperAssignmentPath=Join-Path $tamperRecoveryProject.Root $tamperPublished.assignment_path
        $tamperedAssignment=Read-AidosJson $tamperAssignmentPath
        $tamperedAssignment.reviewer_identity='malicious-reviewer'
        Write-Json $tamperAssignmentPath $tamperedAssignment
        Assert-Throws { & (Get-PwshExecutable) -NoLogo -NoProfile -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/Invoke-AidosReview.ps1') -ProjectRoot $tamperRecoveryProject.Root -Mode RepairLegacyCorrelation -ExecutionPath $tamperRecoveryProject.ExecutionPath } 'stale or mismatched|bridge-bound|hash mismatch'
    } finally { Remove-Item -LiteralPath $tamperRecoveryProject.Root -Recurse -Force }

    $manifestRecoveryProject=New-TestProject
    try {
        $manifestRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$manifestRecoveryProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $manifestExecution=Invoke-AidosCodexExecution $manifestRecoveryProject.Root $manifestRecoveryProject.ExecutionPath $manifestRuntime 'manifest mismatch repair smoke'
        Assert-True ($manifestExecution.validation_status -eq 'PASS') 'manifest mismatch repair smoke reaches publishable evidence'
        $manifestPublished=Publish-AidosReviewPackage $manifestRecoveryProject.Root $manifestRecoveryProject.ExecutionPath
        $manifestPath=Join-Path $manifestRecoveryProject.Root $manifestPublished.manifest_path
        $manifest=Read-AidosJson $manifestPath
        $manifest.evidence_refs=@()
        Write-Json $manifestPath $manifest
        Assert-Throws { & (Get-PwshExecutable) -NoLogo -NoProfile -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/Invoke-AidosReview.ps1') -ProjectRoot $manifestRecoveryProject.Root -Mode RepairLegacyCorrelation -ExecutionPath $manifestRecoveryProject.ExecutionPath } 'manifest hash mismatch|stale or mismatched'
    } finally { Remove-Item -LiteralPath $manifestRecoveryProject.Root -Recurse -Force }

    $repairProject=New-TestProject
    try {
        $repairRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$repairProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $repairExecution=Invoke-AidosCodexExecution $repairProject.Root $repairProject.ExecutionPath $repairRuntime 'repair review smoke'
        Assert-True ($repairExecution.validation_status -eq 'PASS') 'repair review smoke reaches publishable evidence'
        $repairPublished=Publish-AidosReviewPackage $repairProject.Root $repairProject.ExecutionPath
        $repairResponseJson=Invoke-ExternalReviewWorker -AssignmentPath (Join-Path $repairProject.Root $repairPublished.assignment_path) -Outcome REPAIR -Reason 'needs follow-up'
        $repairOutcome=Invoke-AidosReviewConsumer -ProjectRoot $repairProject.Root -ResponseJson $repairResponseJson
        $repairState=Get-AidosState $repairProject.Root
        Assert-True ($repairState.state -eq 'TASK_READY' -and $repairState.revision -eq 1 -and $repairState.review_id -eq $null) 'REPAIR returns TASK_READY without inventing a new revision'
        $repairRecord=Read-AidosJson (Join-Path $repairProject.Root ".aidos/reviews/$($repairPublished.review_id)/REVIEW.json")
        Assert-True ($repairRecord.decision.target_state -eq 'TASK_READY' -and $repairRecord.transport_state -eq 'CLEANED') 'repair review decision is durable and cleaned'
    } finally { Remove-Item -LiteralPath $repairProject.Root -Recurse -Force }

    $reconcileProject=New-TestProject
    try {
        $reconcileRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$reconcileProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $reconcileExecution=Invoke-AidosCodexExecution $reconcileProject.Root $reconcileProject.ExecutionPath $reconcileRuntime 'reconcile review smoke'
        Assert-True ($reconcileExecution.validation_status -eq 'PASS') 'reconciliation smoke reaches publishable evidence'
        $reconcilePublished=Publish-AidosReviewPackage $reconcileProject.Root $reconcileProject.ExecutionPath
        $reconcileResponseJson=Invoke-ExternalReviewWorker -AssignmentPath (Join-Path $reconcileProject.Root $reconcilePublished.assignment_path) -Outcome PASS -Reason 'approved'
        $reconcileResponse=$reconcileResponseJson | ConvertFrom-Json -Depth 100
        $reconcileRecord=Read-AidosReviewRecord $reconcileProject.Root $reconcilePublished.review_id
        $reconcileRecord.response=$reconcileResponse
        $reconcileRecord.response_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($reconcileResponseJson))).ToLowerInvariant()
        $reconcileRecord.response_received_at=[DateTimeOffset]::UtcNow.ToString('o')
        $reconcileRecord.response_received_by=$reconcileResponse.reviewer_identity
        $reconcileRecord.response_accepted_at=$null
        $reconcileRecord.response_accepted_by=$null
        $reconcileRecord.decision=$null
        $reconcileRecord.transport_state='PUBLISHED'
        Write-AidosReviewRecordAtomic $reconcileProject.Root $reconcilePublished.review_id $reconcileRecord
        $beforeReconcile=Get-AidosState $reconcileProject.Root
        Assert-True ($beforeReconcile.state -eq 'GPT_REVIEWING' -and $beforeReconcile.review_id -eq $reconcilePublished.review_id) 'response stored before reconciliation still leaves project in review state'
        $reconciled=Invoke-AidosReviewReconciliation $reconcileProject.Root
        Assert-True ($reconciled.status -eq 'CLEANED') 'reconciliation completes consume and cleanup after an interrupted review'
        $reconciledRecord=Read-AidosJson (Join-Path $reconcileProject.Root ".aidos/reviews/$($reconcilePublished.review_id)/REVIEW.json")
        Assert-True ($reconciledRecord.transport_state -eq 'CLEANED' -and $reconciledRecord.consume_ack.review_id -eq $reconcilePublished.review_id) 'reconciled review record is canonical after restart'
    } finally { Remove-Item -LiteralPath $reconcileProject.Root -Recurse -Force }

    $tamperProject=New-TestProject
    try {
        $tamperRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$tamperProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $tamperExecution=Invoke-AidosCodexExecution $tamperProject.Root $tamperProject.ExecutionPath $tamperRuntime 'tamper review smoke'
        Assert-True ($tamperExecution.validation_status -eq 'PASS') 'tamper review smoke reaches publishable evidence'
        $tamperPublished=Publish-AidosReviewPackage $tamperProject.Root $tamperProject.ExecutionPath
        $tamperedAssignment=Read-AidosJson (Join-Path $tamperProject.Root $tamperPublished.assignment_path)
        $tamperedAssignment.reviewer_identity='malicious-reviewer'
        $tamperedAssignmentPath=Join-Path $tamperProject.Root 'tampered-assignment.json'
        Write-Json $tamperedAssignmentPath $tamperedAssignment
        Assert-Throws { Invoke-ExternalReviewWorker -AssignmentPath $tamperedAssignmentPath -Outcome PASS -Reason 'tampered' } 'Worker stub failed'
    } finally { Remove-Item -LiteralPath $tamperProject.Root -Recurse -Force }

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

    $terminalEventRecovery=New-TestProject
    try {
        $null=Set-AidosState $terminalEventRecovery.Root 'CODEX_RUNNING' 'BRIDGE' @{codex_session_id=$null}
        $eventDirectory=Split-Path -Parent $terminalEventRecovery.ExecutionPath
        @('{"type":"thread.started","thread_id":"33333333-3333-3333-3333-333333333333"}','{"type":"item.completed","item":{"type":"agent_message","text":"terminal work"}}','{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}')|Set-Content -LiteralPath (Join-Path $eventDirectory 'codex-events.jsonl') -Encoding utf8NoBOM
        $terminalRecovery=Invoke-AidosStartupReconciliation $terminalEventRecovery.Root
        $recoveryArtifact=Get-AidosCodexRecoveryArtifactPath $terminalEventRecovery.Root 'EXEC-1' 1
        $artifact=Read-AidosJson $recoveryArtifact;$recoveredState=Get-AidosState $terminalEventRecovery.Root
        Assert-True ($terminalRecovery.status -eq 'RECOVERY_REQUIRED' -and $terminalRecovery.recovery.status -eq 'RECOVERED') 'terminal Codex event without result artifacts creates explicit recovery evidence'
        Assert-True ($recoveredState.codex_session_id -eq '33333333-3333-3333-3333-333333333333' -and $artifact.execution_outcome -eq 'UNKNOWN' -and $artifact.validation_status -eq 'NOT_RUN') 'terminal event recovery preserves session binding without inferring success'
        $again=Invoke-AidosStartupReconciliation $terminalEventRecovery.Root
        Assert-True ($again.recovery.idempotent -and (Get-Content -LiteralPath $recoveryArtifact -Raw) -eq (Get-Content -LiteralPath $recoveryArtifact -Raw)) 'terminal event recovery is idempotent'
    } finally { Remove-Item -LiteralPath $terminalEventRecovery.Root -Recurse -Force }

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

    $desktopProject=New-TestProject
    try {
        $desktopRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$desktopProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
        $desktopExecution=Invoke-AidosCodexExecution $desktopProject.Root $desktopProject.ExecutionPath $desktopRuntime 'desktop adapter review smoke'
        Assert-True ($desktopExecution.validation_status -eq 'PASS') 'desktop adapter smoke reaches publishable evidence'
        $desktopPublished=Publish-AidosReviewPackage $desktopProject.Root $desktopProject.ExecutionPath
        $assignmentPath=Join-Path $desktopProject.Root $desktopPublished.assignment_path
        $assignment=Read-AidosJson $assignmentPath
        $conversationProofText='desktop adapter smoke conversation'
        $accountProofText='desktop account proof'
        $enrollJson=Invoke-DesktopChatGPTAdapter -Mode Enroll -ProjectRoot $desktopProject.Root -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub
        $enroll=$enrollJson | ConvertFrom-Json -Depth 100
        Assert-True ($enroll.status -eq 'ENROLLED' -and $enroll.idempotent -eq $false) 'desktop adapter enrollment succeeds once'
        $enrollPath=Join-Path $desktopProject.Root '.aidos/runtime/chatgpt/ENROLLMENT.json'
        Assert-True (Test-Path -LiteralPath $enrollPath -PathType Leaf) 'desktop adapter enrollment is durably recorded'
        $enrollAgainJson=Invoke-DesktopChatGPTAdapter -Mode Enroll -ProjectRoot $desktopProject.Root -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub
        $enrollAgain=$enrollAgainJson | ConvertFrom-Json -Depth 100
        Assert-True ($enrollAgain.idempotent -and $enrollAgain.conversation_fingerprint_sha256 -eq $enroll.conversation_fingerprint_sha256) 'desktop adapter enrollment is idempotent for the same conversation'
        $responseObject=[ordered]@{
            schema_version='0.1'
            envelope_type='REVIEW_RESPONSE'
            review_id=$desktopPublished.review_id
            project_id=$assignment.project_id
            project_root=$assignment.project_root
            project_mode=$assignment.project_mode
            definition_id=$assignment.definition_id
            definition_version=$assignment.definition_version
            execution_id=$assignment.execution_id
            revision=$assignment.revision
            reviewer_role=$assignment.reviewer_role
            reviewer_identity=$assignment.reviewer_identity
            assignment_sha256=$desktopPublished.assignment_sha256
            package_manifest_sha256=$desktopPublished.manifest_sha256
            outcome='PASS'
            reason='desktop adapter smoke approved'
            evidence_refs=@($assignment.evidence_refs)
            repair_guidance=@()
            responded_at=[DateTimeOffset]::UtcNow.ToString('o')
            responded_by=$assignment.reviewer_identity
        }
        $responseText=$responseObject | ConvertTo-Json -Depth 100
        $reviewJson=Invoke-DesktopChatGPTAdapter -Mode Review -ProjectRoot $desktopProject.Root -AssignmentPath $assignmentPath -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub -StubResponseText $responseText -ResponseTimeoutSeconds 1
        $review=$reviewJson | ConvertFrom-Json -Depth 100
        Assert-True ($review.envelope_type -eq 'REVIEW_RESPONSE' -and $review.review_id -eq $desktopPublished.review_id -and $review.assignment_sha256 -eq $desktopPublished.assignment_sha256) 'desktop adapter returns a strict REVIEW_RESPONSE envelope'
        Assert-True ((Read-AidosDesktopChatGPTState $desktopProject.Root $desktopPublished.review_id).status -eq 'HANDOFF_COMPLETE') 'desktop adapter durable state reaches HANDOFF_COMPLETE'
        Assert-True ((Read-AidosDesktopChatGPTJson (Get-AidosDesktopChatGPTResponsePath $desktopProject.Root $desktopPublished.review_id)).outcome -eq 'PASS') 'desktop adapter persists the response envelope durably'
        $consumer=Invoke-AidosReviewConsumer -ProjectRoot $desktopProject.Root -ResponseJson $reviewJson
        Assert-True ((Get-AidosState $desktopProject.Root).state -eq 'IDLE') 'desktop adapter response is accepted by the bridge consumer'
        $replayed=Invoke-AidosDesktopChatGPTReview -ProjectRoot $desktopProject.Root -AssignmentPath $assignmentPath -Backend (New-AidosDesktopChatGPTStubBackend -InteractiveSession:$true -ConversationMatches:$true -ResponseText $responseText)
        Assert-True ($replayed.idempotent -and $replayed.status -eq 'HANDOFF_COMPLETE') 'desktop adapter replay is idempotent without resending'
        $resumeProject=New-TestProject
        try {
            $resumeRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$resumeProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
            $resumeExecution=Invoke-AidosCodexExecution $resumeProject.Root $resumeProject.ExecutionPath $resumeRuntime 'desktop adapter resume smoke'
            Assert-True ($resumeExecution.validation_status -eq 'PASS') 'desktop adapter resume smoke reaches publishable evidence'
            $resumePublished=Publish-AidosReviewPackage $resumeProject.Root $resumeProject.ExecutionPath
            $resumeAssignmentPath=Join-Path $resumeProject.Root $resumePublished.assignment_path
            $resumeAssignment=Read-AidosJson $resumeAssignmentPath
            Invoke-DesktopChatGPTAdapter -Mode Enroll -ProjectRoot $resumeProject.Root -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub | Out-Null
            $resumableBackend=New-AidosDesktopChatGPTStubBackend -InteractiveSession:$true -ConversationMatches:$true -NoResponse:$true
            $sentResult=Invoke-AidosDesktopChatGPTReview -ProjectRoot $resumeProject.Root -AssignmentPath $resumeAssignmentPath -Backend $resumableBackend
            Assert-True ($sentResult.status -eq 'SENT' -and $sentResult.waiting_for_response) 'desktop adapter records SENT without a response'
            Assert-True ($resumableBackend.State.send_count -eq 1) 'desktop adapter sends exactly once before a crash'
            $resumeResponseObject=[ordered]@{
                schema_version='0.1'
                envelope_type='REVIEW_RESPONSE'
                review_id=$resumePublished.review_id
                project_id=$resumeAssignment.project_id
                project_root=$resumeAssignment.project_root
                project_mode=$resumeAssignment.project_mode
                definition_id=$resumeAssignment.definition_id
                definition_version=$resumeAssignment.definition_version
                execution_id=$resumeAssignment.execution_id
                revision=$resumeAssignment.revision
                reviewer_role=$resumeAssignment.reviewer_role
                reviewer_identity=$resumeAssignment.reviewer_identity
                assignment_sha256=$resumePublished.assignment_sha256
                package_manifest_sha256=$resumePublished.manifest_sha256
                outcome='PASS'
                reason='desktop adapter crash recovery approved'
                evidence_refs=@($resumeAssignment.evidence_refs)
                repair_guidance=@()
                responded_at=[DateTimeOffset]::UtcNow.ToString('o')
                responded_by=$resumeAssignment.reviewer_identity
            }
            Write-AidosDesktopChatGPTJsonAtomic (Get-AidosDesktopChatGPTResponsePath $resumeProject.Root $resumePublished.review_id) $resumeResponseObject
            $resumed=Invoke-AidosDesktopChatGPTReview -ProjectRoot $resumeProject.Root -AssignmentPath $resumeAssignmentPath -Backend $resumableBackend
            Assert-True ($resumed.idempotent -and $resumed.status -eq 'HANDOFF_COMPLETE') 'desktop adapter resumes by reading the response without resending'
            Assert-True ($resumableBackend.State.send_count -eq 1) 'desktop adapter does not resend after crash recovery'
        } finally { Remove-Item -LiteralPath $resumeProject.Root -Recurse -Force }
        $wrongConversationProject=New-TestProject
        try {
            $wrongRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$wrongConversationProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
            $wrongExecution=Invoke-AidosCodexExecution $wrongConversationProject.Root $wrongConversationProject.ExecutionPath $wrongRuntime 'wrong conversation review smoke'
            Assert-True ($wrongExecution.validation_status -eq 'PASS') 'wrong-conversation smoke reaches publishable evidence'
            $wrongPublished=Publish-AidosReviewPackage $wrongConversationProject.Root $wrongConversationProject.ExecutionPath
            $wrongAssignmentPath=Join-Path $wrongConversationProject.Root $wrongPublished.assignment_path
            Invoke-DesktopChatGPTAdapter -Mode Enroll -ProjectRoot $wrongConversationProject.Root -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub | Out-Null
            Assert-Throws { Invoke-DesktopChatGPTAdapter -Mode Review -ProjectRoot $wrongConversationProject.Root -AssignmentPath $wrongAssignmentPath -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub -StubConversationMatches:$false -StubResponseText $responseText -ResponseTimeoutSeconds 1 } 'not active|not present'
        } finally { Remove-Item -LiteralPath $wrongConversationProject.Root -Recurse -Force }
        $lockedProject=New-TestProject
        try {
            $lockedRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$lockedProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
            $lockedExecution=Invoke-AidosCodexExecution $lockedProject.Root $lockedProject.ExecutionPath $lockedRuntime 'locked session review smoke'
            Assert-True ($lockedExecution.validation_status -eq 'PASS') 'locked-session smoke reaches publishable evidence'
            $lockedPublished=Publish-AidosReviewPackage $lockedProject.Root $lockedProject.ExecutionPath
            $lockedAssignmentPath=Join-Path $lockedProject.Root $lockedPublished.assignment_path
            Invoke-DesktopChatGPTAdapter -Mode Enroll -ProjectRoot $lockedProject.Root -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub | Out-Null
            $lockedJson=Invoke-DesktopChatGPTAdapter -Mode Review -ProjectRoot $lockedProject.Root -AssignmentPath $lockedAssignmentPath -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub -StubInteractiveSession:$false -StubResponseText $responseText -ResponseTimeoutSeconds 1
            $lockedResult=$lockedJson | ConvertFrom-Json -Depth 100
            Assert-True ($lockedResult.status -eq 'WAITING_INTERACTIVE_SESSION' -and (Read-AidosDesktopChatGPTState $lockedProject.Root $lockedPublished.review_id).status -eq 'WAITING_INTERACTIVE_SESSION') 'locked Windows session fails closed without sending'
        } finally { Remove-Item -LiteralPath $lockedProject.Root -Recurse -Force }
        $malformedProject=New-TestProject
        try {
            $malformedRuntime=[pscustomobject]@{kind='WSL_LOCAL';project_root=$malformedProject.Root;codex_path=$fake;codex_capabilities=$runtime.codex_capabilities}
            $malformedExecution=Invoke-AidosCodexExecution $malformedProject.Root $malformedProject.ExecutionPath $malformedRuntime 'malformed response review smoke'
            Assert-True ($malformedExecution.validation_status -eq 'PASS') 'malformed-response smoke reaches publishable evidence'
            $malformedPublished=Publish-AidosReviewPackage $malformedProject.Root $malformedProject.ExecutionPath
            $malformedAssignmentPath=Join-Path $malformedProject.Root $malformedPublished.assignment_path
            Invoke-AidosDesktopChatGPTAdapter -Mode Enroll -ProjectRoot $malformedProject.Root -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub | Out-Null
            Assert-Throws { Invoke-DesktopChatGPTAdapter -Mode Review -ProjectRoot $malformedProject.Root -AssignmentPath $malformedAssignmentPath -ConversationProofText $conversationProofText -AccountProofText $accountProofText -BackendMode Stub -StubResponseText 'extra prose only' -ResponseTimeoutSeconds 1 } 'single JSON object|valid JSON'
        } finally { Remove-Item -LiteralPath $malformedProject.Root -Recurse -Force }
    } finally { Remove-Item -LiteralPath $desktopProject.Root -Recurse -Force }

    $partial=New-TestProject
    try {
        Add-AidosEvent $partial.Root 'STATE_TRANSITION' 'BRIDGE' @{from='TASK_READY';to='CODEX_RUNNING';patch_keys=@('lease_id')}|Out-Null
        $partialRecovery=Invoke-AidosStartupReconciliation $partial.Root
        Assert-True $partialRecovery.projection_repaired 'event-first partial state write is replayed'
        Assert-True ((Get-AidosState $partial.Root).state -eq 'RECOVERY_REQUIRED') 'CODEX_RUNNING without a lease fails safely to recovery'
    } finally { Remove-Item -LiteralPath $partial.Root -Recurse -Force }

    Write-Output "PASS: $script:Passed assertions"
} finally { Remove-Item -LiteralPath $project.Root -Recurse -Force }
