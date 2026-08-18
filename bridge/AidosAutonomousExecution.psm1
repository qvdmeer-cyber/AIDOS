Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking

function Get-AidosAcceptedDefinitionPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $state=Get-AidosState $root
    if([string]::IsNullOrWhiteSpace([string]$state.definition_id)-or$null-eq$state.definition_version){throw 'Execution planning requires exact Definition binding.'}
    Join-Path $root ('.aidos/definitions/{0}/v{1}/DEFINITION.json' -f [string]$state.definition_id,[int]$state.definition_version)
}

function Get-AidosExecutionArtifactPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/executions/{0}/revision-{1}/EXECUTION.json' -f $ExecutionId,$Revision)
}

function Get-AidosDependencyNetworkAuthority {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $engineeringPath=Join-Path $root 'docs/ENGINEERING.md'
    if(-not(Test-Path -LiteralPath $engineeringPath -PathType Leaf)){return [pscustomobject][ordered]@{allowed=$false;source_ref=$null;reason='No canonical engineering source grants dependency-network use.'}}
    $text=Get-Content -LiteralPath $engineeringPath -Raw -Encoding UTF8
    $hasExactRestore=$text.IndexOf('npm ci',[StringComparison]::OrdinalIgnoreCase)-ge0
    $hasOnlineRegistry=$text.IndexOf('online from the configured npm registry',[StringComparison]::OrdinalIgnoreCase)-ge0
    if($hasExactRestore-and$hasOnlineRegistry){return [pscustomobject][ordered]@{allowed=$true;source_ref='docs/ENGINEERING.md';reason='Canonical project engineering policy explicitly permits online npm registry restore through npm ci.'}}
    [pscustomobject][ordered]@{allowed=$false;source_ref='docs/ENGINEERING.md';reason='Canonical engineering source does not explicitly authorize online dependency restore.'}
}

function Resolve-AidosAutonomousExecutionProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $profilePath=Join-Path $root '.aidos/profile/PROJECT_APPLICABILITY.json'
    if(-not(Test-Path -LiteralPath $profilePath -PathType Leaf)){throw 'Autonomous execution requires Project Applicability.'}
    $profile=Read-AidosJson $profilePath
    $presetIds=@($profile.selected_presets|ForEach-Object {[string]$_.preset_id})
    if($presetIds -contains 'WEB_APPLICATION' -and $presetIds -contains 'REACT'){
        $network=Get-AidosDependencyNetworkAuthority -ProjectRoot $root
        return [pscustomobject][ordered]@{
            profile_id='WEB_APPLICATION_REACT';filesystem_write=@('.');network=[bool]$network.allowed
            authority_source_refs=@($network.source_ref|Where-Object {-not[string]::IsNullOrWhiteSpace([string]$_)});authority_reason=[string]$network.reason
            validators=@('npm run validate');evidence_requirements=@([ordered]@{type='PATH_EXISTS';path='package.json'})
        }
    }
    [pscustomobject][ordered]@{profile_id='UNSUPPORTED';filesystem_write=@();network=$false;authority_source_refs=@();authority_reason='No autonomous execution profile matches current verified Project Applicability.';validators=@();evidence_requirements=@()}
}

function New-AidosExecutionFromAcceptedDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$state=Get-AidosState $root
    if([string]$state.state-ne'TASK_READY'){throw "Execution planning requires TASK_READY, found '$($state.state)'."}
    if(-not[string]::IsNullOrWhiteSpace([string]$state.execution_id)){
        $path=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision)
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'State references an execution artifact that does not exist.'}
        return [pscustomobject][ordered]@{status='ALREADY_PLANNED';execution_path=$path;execution=Read-AidosJson $path}
    }
    $definitionPath=Get-AidosAcceptedDefinitionPath -ProjectRoot $root
    if(-not(Test-Path -LiteralPath $definitionPath -PathType Leaf)){throw 'Accepted canonical Definition is unavailable.'}
    $definition=Read-AidosJson $definitionPath
    if([string]$definition.status-ne'ACCEPTED'){throw "Execution planning requires ACCEPTED Definition, found '$($definition.status)'."}
    if([string]$definition.definition_id-ne[string]$state.definition_id -or [int]$definition.version-ne[int]$state.definition_version){throw 'Canonical Definition binding mismatch.'}
    $executionProfile=Resolve-AidosAutonomousExecutionProfile -ProjectRoot $root
    if([string]$executionProfile.profile_id-eq'UNSUPPORTED'){return [pscustomobject][ordered]@{status='PROFILE_ADAPTER_REQUIRED';profile=$executionProfile}}
    $prep=Get-AidosPreparationSnapshot $root;$executionId='EXEC-'+[guid]::NewGuid().ToString();$revision=1
    $execution=[ordered]@{
        schema_version='0.1';execution_id=$executionId;revision=$revision;project_id=[string]$Project.project_id;project_mode=[string]$prep.project_mode;workstream=$null
        preparation=[ordered]@{baseline_commit=[string]$prep.baseline_commit;access_sha256=[string]$prep.access_sha256;evidence_inventory_sha256=[string]$prep.evidence_inventory_sha256;current_product_state_id=$prep.current_product_state_id;current_product_state_commit=$prep.current_product_state_commit;current_product_state_contract_version=$prep.current_product_state_contract_version;discovery_catalog_version=$prep.discovery_catalog_version}
        definition=[ordered]@{id=[string]$definition.definition_id;version=[int]$definition.version};goal=[string]$definition.goal
        scope=[ordered]@{definition_ref=[IO.Path]::GetRelativePath($root,$definitionPath).Replace('\','/');canonical_source_refs=@($definition.sources|ForEach-Object {[string]$_});authority_source_refs=@($executionProfile.authority_source_refs);implementation_policy='Implement only accepted Definition scope. Technical decomposition is autonomous; material product/risk decisions return through AIDOS Human Input.'}
        acceptance=@($definition.acceptance)
        authority=[ordered]@{filesystem_write=@($executionProfile.filesystem_write);git_commit=$false;git_push=$false;network=[bool]$executionProfile.network}
        knowledge_selection=@('AIDOS/agents/EXECUTION_AGENT.md','AIDOS/protocols/EXECUTION_PROTOCOL.md');validators=@($executionProfile.validators)
        validation=[ordered]@{mode='ALL';requirements=@($executionProfile.evidence_requirements)};executor_profile=[ordered]@{model='codex-cli-default';reasoning_effort='medium'}
        stop_conditions=@('TER_REVIEW','REQUIREMENT_CONTRADICTION','CONTROLLED_GATE','BLOCKER','RUNTIME_STOP')
    }
    $path=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId $executionId -Revision $revision;Write-AidosJsonAtomic $path $execution
    Set-AidosExecutionDispatchBinding -ProjectRoot $root -ExecutionId $executionId -Revision $revision|Out-Null
    Add-AidosEvent -ProjectRoot $root -EventType 'EXECUTION_PLANNED' -Actor SYSTEM -Payload @{execution_id=$executionId;revision=$revision;definition_id=[string]$definition.definition_id;definition_version=[int]$definition.version;profile=[string]$executionProfile.profile_id;network=[bool]$executionProfile.network;authority_source_refs=@($executionProfile.authority_source_refs)}|Out-Null
    $persist=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS plan execution $executionId revision $revision") -Push:$Push
    [pscustomobject][ordered]@{status='PLANNED';execution_path=$path;execution=[pscustomobject]$execution;persistence=$persist}
}

function Resolve-AidosAutonomousCodexRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $gitRuntime=Get-AidosGitRuntime (Resolve-AidosFileSystemPath $ProjectRoot)
    switch([string]$gitRuntime.kind){
        'WINDOWS_WSL' {[pscustomobject][ordered]@{kind='WINDOWS_WSL';distribution=[string]$gitRuntime.distribution;project_root=[string]$gitRuntime.project_root;codex_path='codex'}}
        'NATIVE' {[pscustomobject][ordered]@{kind='WSL_LOCAL';project_root=(Resolve-AidosFileSystemPath $ProjectRoot);codex_path='codex'}}
        default {throw "Autonomous Codex execution does not support Git runtime '$($gitRuntime.kind)'."}
    }
}

function Get-AidosAutonomousCodexArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Runtime,[Parameter(Mandatory)]$Execution,[Parameter(Mandatory)][string]$PromptText)
    $args=[Collections.Generic.List[string]]::new();$args.Add('exec');$args.Add('--json');$args.Add('--sandbox');$args.Add('workspace-write');$args.Add('--config');$args.Add('approval_policy="never"'.Replace('\',''))
    if([bool]$Execution.authority.network){$args.Add('--config');$args.Add('sandbox_workspace_write.network_access=true')}
    $args.Add('--cd');$args.Add([string]$Runtime.project_root);$args.Add($PromptText);@($args)
}

function Invoke-AidosRegisteredValidator {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Validator)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    if($Validator-ne'npm run validate'){throw "Unsupported registered execution validator '$Validator'."}
    $gitRuntime=Get-AidosGitRuntime $root;$output=@();$exitCode=$null
    if([string]$gitRuntime.kind-eq'WINDOWS_WSL'){$output=@(& wsl.exe --distribution ([string]$gitRuntime.distribution) --cd ([string]$gitRuntime.project_root) --exec npm run validate 2>&1);$exitCode=$LASTEXITCODE}
    else{Push-Location $root;try{$output=@(& npm run validate 2>&1);$exitCode=$LASTEXITCODE}finally{Pop-Location}}
    [pscustomobject][ordered]@{validator=$Validator;passed=($exitCode-eq0);exit_code=$exitCode;output=@($output|ForEach-Object {[string]$_})}
}

function Invoke-AidosAutonomousExecutionValidation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Execution)
    $evidence=try{Test-AidosExecutionEvidence -ProjectRoot $ProjectRoot -Execution $Execution}catch{[pscustomobject]@{status='FAIL';checked_at=[DateTimeOffset]::UtcNow.ToString('o');requirements=@();error=$_.Exception.Message}}
    $validators=@();foreach($validator in @($Execution.validators)){try{$validators+=Invoke-AidosRegisteredValidator -ProjectRoot $ProjectRoot -Validator ([string]$validator)}catch{$validators+=[pscustomobject][ordered]@{validator=[string]$validator;passed=$false;exit_code=$null;output=@($_.Exception.Message)}}}
    $pass=([string]$evidence.status-eq'PASS' -and @($validators|Where-Object {-not[bool]$_.passed}).Count-eq0)
    [pscustomobject][ordered]@{status=if($pass){'PASS'}else{'FAIL'};checked_at=[DateTimeOffset]::UtcNow.ToString('o');requirements=@($evidence.requirements);validators=@($validators);error=$evidence.error}
}

function Invoke-AidosAutonomousCodexExecution {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionPath,[string]$Prompt)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$executionPathResolved=[IO.Path]::GetFullPath($ExecutionPath);$execution=Read-AidosJson $executionPathResolved
    Assert-AidosExecutionBinding -ProjectRoot $root -Execution $execution|Out-Null;$state=Get-AidosState $root
    if([string]$state.state-ne'TASK_READY'){throw "Codex dispatch requires TASK_READY, found '$($state.state)'."}
    if([string]$state.execution_id-ne[string]$execution.execution_id -or [int]$state.revision-ne[int]$execution.revision){throw 'Codex dispatch execution/revision binding mismatch.'}
    $runtime=Resolve-AidosAutonomousCodexRuntime -ProjectRoot $root;$lease=Acquire-AidosExecutionLease -ProjectRoot $root -ExecutionId ([string]$execution.execution_id) -Revision ([int]$execution.revision)
    $directory=Split-Path -Parent $executionPathResolved;$eventsPath=Join-Path $directory 'codex-events.jsonl';$stderrPath=Join-Path $directory 'codex-stderr.log';$resultPath=Join-Path $directory 'RESULT.json';$validationPath=Join-Path $directory 'VALIDATION.json'
    $runtimeExecution=([string]$runtime.project_root).TrimEnd('/')+'/'+([IO.Path]::GetRelativePath($root,$executionPathResolved).Replace('\','/'))
    $promptText=if([string]::IsNullOrWhiteSpace($Prompt)){"Execute accepted AIDOS execution $runtimeExecution. Read the accepted Definition and canonical project sources. Work autonomously inside the exact authority. Run every registered validator before TER_REVIEW. Do not commit or push; AIDOS owns integration and review."}else{$Prompt}
    $arguments=Get-AidosAutonomousCodexArguments -Runtime $runtime -Execution $execution -PromptText $promptText;$command=Get-AidosCodexCommand -Runtime $runtime -ProjectRoot $root -CodexArguments $arguments
    Set-AidosState -ProjectRoot $root -NewState CODEX_RUNNING -Actor BRIDGE -Patch @{lease_id=$lease.lease_id}|Out-Null
    $started=[DateTimeOffset]::UtcNow;$exitCode=$null;$sessionId=$null;$terminalType='process_error';$errorText=$null;$finalMessage=$null
    try {
        $startInfo=[Diagnostics.ProcessStartInfo]::new();$startInfo.FileName=$command.FileName;$startInfo.WorkingDirectory=$command.WorkingDirectory;$startInfo.UseShellExecute=$false;$startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true
        foreach($argument in $command.Arguments){$null=$startInfo.ArgumentList.Add([string]$argument)}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$startInfo;if(-not$process.Start()){throw 'Codex did not start.'}
        $processId=$process.Id;$processStarted=try{$process.StartTime.ToUniversalTime().ToString('o')}catch{[DateTimeOffset]::UtcNow.ToString('o')};$stderrTask=$process.StandardError.ReadToEndAsync()
        $leasePath=Join-Path $root '.aidos/runtime/lease.json';$currentLease=Read-AidosJson $leasePath;$currentLease.codex_runtime=[ordered]@{kind=[string]$runtime.kind;supervisor_pid=$processId;started_at=$processStarted};Write-AidosJsonAtomic $leasePath $currentLease
        $writer=[IO.StreamWriter]::new($eventsPath,$false,[Text.UTF8Encoding]::new($false));try{while(-not$process.StandardOutput.EndOfStream){$line=$process.StandardOutput.ReadLine();$writer.WriteLine($line);$writer.Flush();try{$event=$line|ConvertFrom-Json -Depth 100;if($event.type-eq'thread.started'-and$event.thread_id){$sessionId=[string]$event.thread_id};if($event.type-eq'turn.completed'){$terminalType='turn.completed'};if($event.type-in@('turn.failed','error')){$terminalType=[string]$event.type};if($event.type-eq'item.completed'-and$event.item.type-eq'agent_message'){$finalMessage=[string]$event.item.text}}catch{}}}finally{$writer.Dispose()}
        $process.WaitForExit();$stderr=$stderrTask.GetAwaiter().GetResult();[IO.File]::WriteAllText($stderrPath,$stderr,[Text.UTF8Encoding]::new($false));$exitCode=$process.ExitCode;if($exitCode-ne0-and$terminalType-eq'turn.completed'){$terminalType='process_error'}
    }catch{$errorText="$($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]";$terminalType='process_error'}
    $headResult=Invoke-AidosGit -ProjectRoot $root -Arguments @('rev-parse','HEAD');$head=if($headResult.ExitCode-eq0){$headResult.Output|Select-Object -First 1}else{$null}
    $result=[ordered]@{schema_version='0.1';project_id=[string]$execution.project_id;execution_id=[string]$execution.execution_id;revision=[int]$execution.revision;lease_id=[string]$lease.lease_id;codex_session_id=$sessionId;resumed=$false;started_at=$started.ToString('o');finished_at=[DateTimeOffset]::UtcNow.ToString('o');exit_code=$exitCode;terminal_type=$terminalType;process_succeeded=($terminalType-eq'turn.completed'-and$exitCode-eq0);validation_status='NOT_RUN';validation_path=$null;final_message=$finalMessage;prompt_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($promptText))).ToLowerInvariant();error=$errorText;git_head=$head;events_path=[IO.Path]::GetRelativePath($root,$eventsPath).Replace('\','/');stderr_path=[IO.Path]::GetRelativePath($root,$stderrPath).Replace('\','/')}
    $statePatch=@{codex_session_id=$sessionId;terminal_result=[IO.Path]::GetRelativePath($root,$resultPath).Replace('\','/');git_head=$head}
    if($result.process_succeeded-and$sessionId){
        Set-AidosState -ProjectRoot $root -NewState TERMINAL_PENDING -Actor BRIDGE -Patch $statePatch|Out-Null;$validation=Invoke-AidosAutonomousExecutionValidation -ProjectRoot $root -Execution $execution
        Write-AidosJsonAtomic $validationPath $validation;$result.validation_status=[string]$validation.status;$result.validation_path=[IO.Path]::GetRelativePath($root,$validationPath).Replace('\','/');Write-AidosJsonAtomic $resultPath $result
        if([string]$validation.status-eq'PASS'){Set-AidosState -ProjectRoot $root -NewState REVIEW_READY -Actor BRIDGE -Patch @{validation_result=$result.validation_path}|Out-Null;Release-AidosExecutionLease -ProjectRoot $root -LeaseId ([string]$lease.lease_id) -Reason VALIDATED}
        else{Set-AidosState -ProjectRoot $root -NewState EXECUTION_VALIDATION_FAILED -Actor BRIDGE -Patch @{validation_result=$result.validation_path}|Out-Null;Release-AidosExecutionLease -ProjectRoot $root -LeaseId ([string]$lease.lease_id) -Reason VALIDATION_FAILED}
    }else{Write-AidosJsonAtomic $resultPath $result;Set-AidosState -ProjectRoot $root -NewState RECOVERY_REQUIRED -Actor BRIDGE -Patch $statePatch|Out-Null;Release-AidosExecutionLease -ProjectRoot $root -LeaseId ([string]$lease.lease_id) -Reason FAILED}
    [pscustomobject][ordered]@{status=if([bool]$result.process_succeeded){[string](Get-AidosState $root).state}else{'RECOVERY_REQUIRED'};execution=$execution;result=[pscustomobject]$result;validation=if(Test-Path -LiteralPath $validationPath){Read-AidosJson $validationPath}else{$null}}
}

function Invoke-AidosAutonomousWorkerDispatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[switch]$Push,[scriptblock]$WorkerInvoker)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$plan=New-AidosExecutionFromAcceptedDefinition -Project $Project -Push:$Push
    if([string]$plan.status-eq'PROFILE_ADAPTER_REQUIRED'){return $plan}
    $executionPath=[string]$plan.execution_path
    $outcome=if($WorkerInvoker){& $WorkerInvoker $Project $executionPath}else{Invoke-AidosAutonomousCodexExecution -ProjectRoot $root -ExecutionPath $executionPath}
    [pscustomobject][ordered]@{status=[string]$outcome.status;plan=$plan;outcome=$outcome;persistence=[pscustomobject][ordered]@{status='DEFERRED_TO_REVIEW';reason='Worker source mutations remain uncommitted until AIDOS review/integration.'}}
}

Export-ModuleMember -Function Get-AidosAcceptedDefinitionPath,Get-AidosExecutionArtifactPath,Get-AidosDependencyNetworkAuthority,Resolve-AidosAutonomousExecutionProfile,New-AidosExecutionFromAcceptedDefinition,Resolve-AidosAutonomousCodexRuntime,Get-AidosAutonomousCodexArguments,Invoke-AidosRegisteredValidator,Invoke-AidosAutonomousExecutionValidation,Invoke-AidosAutonomousCodexExecution,Invoke-AidosAutonomousWorkerDispatch
