Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AllowedTransitions = @{
    IDLE=@('WAITING_DEFINITION','TASK_READY'); WAITING_DEFINITION=@('TASK_READY','WAITING_USER')
    DISCOVERY_REFRESH_REQUIRED=@('WAITING_DEFINITION','TASK_READY','RECOVERY_REQUIRED'); TASK_READY=@('QUEUED','CODEX_RUNNING','RECOVERY_REQUIRED')
    QUEUED=@('CODEX_RUNNING','RECOVERY_REQUIRED'); CODEX_RUNNING=@('TERMINAL_PENDING','CONTEXT_ROTATION_REQUIRED','RECOVERY_REQUIRED')
    TERMINAL_PENDING=@('REVIEW_READY','EXECUTION_VALIDATION_FAILED','WAITING_USER','WAITING_DEFINITION','RECOVERY_REQUIRED'); EXECUTION_VALIDATION_FAILED=@('TASK_READY','RECOVERY_REQUIRED','WAITING_USER'); REVIEW_READY=@('GPT_REVIEWING','WAITING_INTERACTIVE_SESSION','RECOVERY_REQUIRED')
    WAITING_INTERACTIVE_SESSION=@('GPT_REVIEWING','RECOVERY_REQUIRED'); GPT_REVIEWING=@('IDLE','TASK_READY','WAITING_DEFINITION','WAITING_USER','DISCOVERY_REFRESH_REQUIRED','RELEASE_READY','CONTEXT_ROTATION_REQUIRED','RECOVERY_REQUIRED')
    RELEASE_READY=@('RECOVERY_REQUIRED'); WAITING_USER=@('WAITING_DEFINITION','TASK_READY','IDLE','RECOVERY_REQUIRED')
    CONTEXT_ROTATION_REQUIRED=@('TASK_READY','REVIEW_READY','RECOVERY_REQUIRED'); RECOVERY_REQUIRED=@('IDLE','WAITING_DEFINITION','TASK_READY','QUEUED','CODEX_RUNNING','REVIEW_READY','WAITING_USER')
}

function Read-AidosJson { param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required AIDOS file not found: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
}
function Write-AidosJsonAtomic { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $dir=Split-Path -Parent $Path; if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp=Join-Path $dir ('.'+[IO.Path]::GetFileName($Path)+'.'+[guid]::NewGuid().ToString('N')+'.tmp')
    try { $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 100)+[Environment]::NewLine)
        $fs=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()};[IO.File]::Move($tmp,$Path,$true)
    } finally { if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force} }
}
function Invoke-AidosExclusive { param([string]$ProjectRoot,[scriptblock]$ScriptBlock,[int]$TimeoutSeconds=15)
    $dir=Join-Path $ProjectRoot '.aidos/runtime';if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds);$lock=$null
    while($null -eq $lock){try{$lock=[IO.FileStream]::new((Join-Path $dir 'bridge.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{if([DateTimeOffset]::UtcNow-ge$deadline){throw 'Timed out acquiring AIDOS project lock.'};Start-Sleep -Milliseconds 50}}
    try{&$ScriptBlock}finally{$lock.Dispose()}
}
function Resolve-AidosFileSystemPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem') { throw "AIDOS path '$Path' uses provider '$($item.PSProvider.Name)'; FileSystem is required." }
    $nativePath = [string]$item.FullName
    if ([string]::IsNullOrWhiteSpace($nativePath)) { throw "AIDOS path '$Path' has no native filesystem path." }
    $nativePath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}
function Test-AidosSameFileSystemPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Left,[Parameter(Mandatory)][string]$Right)
    $leftPath = Resolve-AidosFileSystemPath $Left
    $rightPath = Resolve-AidosFileSystemPath $Right
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    [string]::Equals($leftPath, $rightPath, $comparison)
}
function Get-AidosProjectRoot { param([string]$StartPath)
    $item=Get-Item -LiteralPath $StartPath;if(-not$item.PSIsContainer){$item=$item.Directory};while($item){if(Test-Path (Join-Path $item.FullName '.aidos/PROJECT.json')){return $item.FullName};$item=$item.Parent};throw 'No .aidos/PROJECT.json found.'
}
function Get-AidosProjectProfile { param([string]$ProjectRoot) Read-AidosJson (Join-Path $ProjectRoot '.aidos/PROJECT.json') }
function ConvertTo-AidosRepositoryIdentity { param([string]$Repository)
    $v=$Repository.Trim().TrimEnd('/');if($v-match'^https?://[^/]+/(.+)$'){$v=$Matches[1]}elseif($v-match'^ssh://[^/]+/(.+)$'){$v=$Matches[1]}elseif($v-match'^[^@]+@[^:]+:(.+)$'){$v=$Matches[1]};if($v.EndsWith('.git',[StringComparison]::OrdinalIgnoreCase)){$v=$v.Substring(0,$v.Length-4)};$v.ToLowerInvariant()
}
function Get-AidosGitRuntime { param([string]$ProjectRoot)
    $profile=Get-AidosProjectProfile $ProjectRoot;if($profile.PSObject.Properties['git_runtime']){return $profile.git_runtime};if(-not$IsWindows){return [pscustomobject]@{kind='NATIVE';project_root=(Resolve-AidosFileSystemPath $ProjectRoot);git_path='git'}};throw 'Project has no registered git_runtime. Register NATIVE or WINDOWS_WSL Git execution before binding.'
}
function Get-AidosGitCommand { param($Runtime,[string[]]$GitArguments)
    if($Runtime.kind-eq'NATIVE'){$gitPath=if($Runtime.git_path){[string]$Runtime.git_path}else{'git'};return [pscustomobject]@{FileName=$gitPath;Arguments=@('-C',[string]$Runtime.project_root)+$GitArguments}};if($Runtime.kind-eq'WINDOWS_WSL'){if(-not$Runtime.distribution-or-not$Runtime.project_root){throw 'WINDOWS_WSL Git runtime requires distribution and project_root.'};$gitPath=if($Runtime.git_path){[string]$Runtime.git_path}else{'git'};return [pscustomobject]@{FileName='wsl.exe';Arguments=@('--distribution',[string]$Runtime.distribution,'--cd',[string]$Runtime.project_root,'--exec',$gitPath,'-C',[string]$Runtime.project_root)+$GitArguments}};throw "Unsupported Git runtime '$($Runtime.kind)'."
}
function Invoke-AidosGit { param([string]$ProjectRoot,[string[]]$Arguments)
    $runtime=Get-AidosGitRuntime $ProjectRoot;$command=Get-AidosGitCommand $runtime $Arguments;$output=(&$command.FileName @($command.Arguments) 2>$null);$exitCode=$LASTEXITCODE;[pscustomobject]@{Output=@($output);ExitCode=$exitCode;Runtime=$runtime;Command=$command}
}
function Register-AidosGitRuntime { [CmdletBinding(SupportsShouldProcess)]param([string]$ProjectRoot,[ValidateSet('NATIVE','WINDOWS_WSL')][string]$Kind,[string]$WslDistribution,[string]$WslProjectRoot,[string]$GitPath='git')
    $resolved=Resolve-AidosFileSystemPath $ProjectRoot;$profilePath=Join-Path $resolved '.aidos/PROJECT.json';$profile=Read-AidosJson $profilePath;$runtime=if($Kind-eq'NATIVE'){[ordered]@{kind='NATIVE';project_root=$resolved;git_path=$GitPath}}else{if(-not$WslDistribution-or-not$WslProjectRoot){throw 'WINDOWS_WSL registration requires WslDistribution and WslProjectRoot.'};[ordered]@{kind='WINDOWS_WSL';distribution=$WslDistribution;project_root=$WslProjectRoot;git_path=$GitPath}};$updated=[ordered]@{};foreach($property in $profile.PSObject.Properties){$updated[$property.Name]=$property.Value};$updated.git_runtime=$runtime;if($PSCmdlet.ShouldProcess($profilePath,"Register $Kind Git runtime")){Write-AidosJsonAtomic $profilePath $updated;try{$binding=Test-AidosProjectBinding $resolved}catch{Write-AidosJsonAtomic $profilePath $profile;throw};Add-AidosEvent $resolved 'GIT_RUNTIME_REGISTERED' 'SYSTEM' @{kind=$Kind;project_root=$runtime.project_root;distribution=$runtime.distribution};$binding}
}
function Get-AidosCodexRuntimeCommand { param($Runtime,[string[]]$CodexArguments)
    if($Runtime.kind-eq'WSL_LOCAL'){
        if(-not$Runtime.codex_path){throw 'WSL_LOCAL Codex runtime requires codex_path.'}
        return [pscustomobject]@{FileName=[string]$Runtime.codex_path;Arguments=$CodexArguments}
    }
    if($Runtime.kind-eq'WINDOWS_WSL'){
        if(-not$Runtime.distribution-or-not$Runtime.project_root-or-not$Runtime.codex_path){throw 'WINDOWS_WSL Codex runtime requires distribution, project_root, and codex_path.'}
        return [pscustomobject]@{FileName='wsl.exe';Arguments=@('--distribution',[string]$Runtime.distribution,'--cd',[string]$Runtime.project_root,'--exec',[string]$Runtime.codex_path)+$CodexArguments}
    }
    throw "Unsupported Codex runtime '$($Runtime.kind)'."
}
function Get-AidosCodexCliCapabilities { param($Runtime)
    if($Runtime.PSObject.Properties.Name -contains 'codex_capabilities'){return $Runtime.codex_capabilities}
    $versionCommand=Get-AidosCodexRuntimeCommand $Runtime @('--version')
    $execHelpCommand=Get-AidosCodexRuntimeCommand $Runtime @('exec','--help')
    $resumeHelpCommand=Get-AidosCodexRuntimeCommand $Runtime @('exec','resume','--help')
    $version=(&$versionCommand.FileName @($versionCommand.Arguments) 2>&1|Select-Object -First 1)
    $execHelp=@(&$execHelpCommand.FileName @($execHelpCommand.Arguments) 2>&1)
    $resumeHelp=@(&$resumeHelpCommand.FileName @($resumeHelpCommand.Arguments) 2>&1)
    [pscustomobject]@{version=[string]$version;exec_has_approve_for_me=($execHelp -match '--approve-for-me');exec_has_sandbox=($execHelp -match '--sandbox <SANDBOX_MODE>');resume_has_json=($resumeHelp -match '--json')}
}
function Assert-AidosCodexAuthorityRepresentable { param($Execution)
    if(-not$Execution.authority){throw 'Execution authority is missing.'}
    $unsupported=@();foreach($name in @('git_commit','git_push','network')){if($Execution.authority.PSObject.Properties[$name] -and $Execution.authority.$name){$unsupported+=$name}}
    if($unsupported.Count){throw "Codex CLI authority policy cannot represent: $($unsupported -join ', ')."}
    [bool]@($Execution.authority.filesystem_write).Count
}
function Assert-AidosCodexCliSupport { param($Runtime,$Execution,[switch]$Resume)
    $caps=Get-AidosCodexCliCapabilities $Runtime
    if(-not$caps.resume_has_json){throw "Codex CLI '$($caps.version)' does not expose 'codex exec resume --json'."}
    $filesystemWrite=Assert-AidosCodexAuthorityRepresentable $Execution
    if($Resume){return}
    if($filesystemWrite){if(-not$caps.exec_has_approve_for_me){throw "Codex CLI '$($caps.version)' does not expose '--approve-for-me' for filesystem-write authority."}}
    else{if(-not$caps.exec_has_sandbox){throw "Codex CLI '$($caps.version)' does not expose '--sandbox <SANDBOX_MODE>' for read-only authority."}}
}
function Get-AidosCodexLaunchArguments { param($Runtime,$Execution,[string]$PromptText,[switch]$Resume,[string]$SessionId)
    if($Resume){return @('exec','resume','--json',[string]$SessionId,[string]$PromptText)}
    if(@($Execution.authority.filesystem_write).Count){return @('exec','--approve-for-me','--json','--cd',[string]$Runtime.project_root,[string]$PromptText)}
    @('exec','--sandbox','read-only','--json','--cd',[string]$Runtime.project_root,[string]$PromptText)
}
function Test-AidosProjectBinding { param([string]$ProjectRoot)
    $resolved=Resolve-AidosFileSystemPath $ProjectRoot;$p=Get-AidosProjectProfile $resolved
    $expected=Resolve-AidosFileSystemPath ([string]$p.official_root);$cmp=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not[string]::Equals($resolved,$expected,$cmp)){throw "AIDOS project-root mismatch. Expected '$expected'; actual '$resolved'."}
    $runtime=Get-AidosGitRuntime $resolved;$rootResult=Invoke-AidosGit $resolved @('rev-parse','--show-toplevel');$gitRoot=($rootResult.Output|Select-Object -First 1);if($rootResult.ExitCode-ne0-or-not$gitRoot){throw "Not a readable Git worktree through '$($runtime.kind)' runtime."}
    if($runtime.kind-eq'NATIVE'){$gitRoot=Resolve-AidosFileSystemPath ([string]$gitRoot);if(-not[string]::Equals($gitRoot,$expected,$cmp)){throw "Git root '$gitRoot' does not equal official_root '$expected'."}}else{if(-not[string]::Equals(([string]$gitRoot).TrimEnd('/'),([string]$runtime.project_root).TrimEnd('/'),[StringComparison]::Ordinal)){throw "WSL Git root '$gitRoot' does not equal registered WSL project_root '$($runtime.project_root)'."}}
    $originResult=Invoke-AidosGit $resolved @('remote','get-url','origin');$origin=($originResult.Output|Select-Object -First 1);if($originResult.ExitCode-ne0-or-not$origin){throw 'Git origin unavailable.'}
    if((ConvertTo-AidosRepositoryIdentity $origin)-ne(ConvertTo-AidosRepositoryIdentity ([string]$p.repository))){throw "Git origin '$origin' does not exactly match '$($p.repository)'."}
    [pscustomobject]@{ProjectId=[string]$p.project_id;Repository=[string]$p.repository;Root=$expected;GitRuntime=[string]$runtime.kind;GitRoot=[string]$gitRoot;Origin=$origin.Trim();Valid=$true}
}
function Get-AidosPreparationSnapshot { param([string]$ProjectRoot)
    $p=Get-AidosProjectProfile $ProjectRoot;$baseline=Read-AidosJson (Join-Path $ProjectRoot ([string]$p.project_baseline));$accessPath=Join-Path $ProjectRoot ([string]$p.project_access);$null=Read-AidosJson $accessPath;$evidencePath=Join-Path $ProjectRoot ([string]$p.evidence_inventory);$evidence=Read-AidosJson $evidencePath
    foreach($f in @('accepted_at','accepted_by','accepted_commit')){if([string]::IsNullOrWhiteSpace([string]$baseline.$f)){throw "Project Baseline missing $f."}};if($evidence.contract_version-ne'0.2.0'){throw 'Evidence Inventory must be 0.2.0.'}
    $s=[ordered]@{project_id=[string]$p.project_id;project_mode=[string]$p.project_mode;baseline_commit=[string]$baseline.accepted_commit;access_sha256=(Get-FileHash $accessPath -Algorithm SHA256).Hash.ToLowerInvariant();evidence_inventory_sha256=(Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant();current_product_state_id=$null;current_product_state_commit=$null;current_product_state_contract_version=$null;discovery_catalog_version=$null}
    if($p.project_mode-eq'EXISTING_PROJECT'){$cps=Read-AidosJson (Join-Path $ProjectRoot ([string]$p.current_product_state));$discovery=Read-AidosJson (Join-Path $ProjectRoot ([string]$p.discovery_state));$authority=Read-AidosJson (Join-Path $ProjectRoot ([string]$p.discovery_authority));if($discovery.status-ne'ACCEPTED'){throw "Discovery state is '$($discovery.status)'."};if($discovery.contract_version-ne'0.2.0'-or$discovery.discovery_catalog_version-ne'0.2.0'){throw 'Discovery state must be 0.2.0/0.2.0.'};if($authority.contract_version-ne'0.1.0'){throw 'Discovery Authority must be 0.1.0.'};if($cps.contract_version-ne'0.2.0'-or$cps.discovery_catalog_version-ne'0.2.0'){throw 'CPS must be 0.2.0/0.2.0.'};if(@($cps.discovery_blockers|Where-Object status -eq 'OPEN').Count){throw 'CPS has an open discovery blocker.'};$id=if($cps.PSObject.Properties['current_product_state_id']){$cps.current_product_state_id}elseif($cps.PSObject.Properties['cps_id']){$cps.cps_id}else{$null};if(-not$id){throw 'CPS identity missing.'};foreach($f in @('accepted_at','accepted_by','accepted_commit')){if(-not$cps.$f){throw "CPS missing $f."}};$s.current_product_state_id=[string]$id;$s.current_product_state_commit=[string]$cps.accepted_commit;$s.current_product_state_contract_version=[string]$cps.contract_version;$s.discovery_catalog_version=[string]$cps.discovery_catalog_version}
    [pscustomobject]$s
}
function Assert-AidosExecutionBinding { param([string]$ProjectRoot,$Execution)
    $b=Test-AidosProjectBinding $ProjectRoot;$s=Get-AidosPreparationSnapshot $ProjectRoot;if($Execution.project_id-ne$b.ProjectId-or$Execution.project_mode-ne$s.project_mode){throw 'Execution project identity/mode mismatch.'};foreach($n in @('baseline_commit','access_sha256','evidence_inventory_sha256','current_product_state_id','current_product_state_commit','current_product_state_contract_version','discovery_catalog_version')){if([string]$Execution.preparation.$n-cne[string]$s.$n){throw "Execution preparation binding '$n' is stale or mismatched."}};$s
}
function Get-AidosState { param([string]$ProjectRoot) Read-AidosJson (Join-Path $ProjectRoot '.aidos/STATE.json') }
function New-AidosEventObject { param($ProjectRoot,$Type,$Actor,[hashtable]$Payload)
    $p=Get-AidosProjectProfile $ProjectRoot;$s=Get-AidosState $ProjectRoot;[ordered]@{schema_version='0.1';event_id=[guid]::NewGuid().ToString();timestamp=[DateTimeOffset]::UtcNow.ToString('o');project_id=[string]$p.project_id;definition_id=$s.definition_id;definition_version=$s.definition_version;execution_id=$s.execution_id;revision=$s.revision;review_id=$s.review_id;event_type=$Type;actor=$Actor;payload=$Payload}
}
function Add-AidosEventUnlocked { param($ProjectRoot,$Event)
    $dir=Join-Path $ProjectRoot '.aidos/events';if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$path=Join-Path $dir ((Get-Date).ToUniversalTime().ToString('yyyy-MM')+'.jsonl');$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Event|ConvertTo-Json -Depth 100 -Compress)+[Environment]::NewLine);$fs=[IO.FileStream]::new($path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
}
function Add-AidosEvent { param([string]$ProjectRoot,[string]$EventType,[ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor,[hashtable]$Payload)
    Invoke-AidosExclusive $ProjectRoot {$e=New-AidosEventObject $ProjectRoot $EventType $Actor $Payload;Add-AidosEventUnlocked $ProjectRoot $e;[pscustomobject]$e}
}
function Set-AidosState { [CmdletBinding(SupportsShouldProcess)]param([string]$ProjectRoot,[string]$NewState,[ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor,[hashtable]$Patch=@{})
    Test-AidosProjectBinding $ProjectRoot|Out-Null;if(-not$PSCmdlet.ShouldProcess((Join-Path $ProjectRoot '.aidos/STATE.json'),$NewState)){return};Invoke-AidosExclusive $ProjectRoot {$s=Get-AidosState $ProjectRoot;$old=[string]$s.state;if(-not$script:AllowedTransitions.ContainsKey($old)-or$NewState-notin$script:AllowedTransitions[$old]){throw "Illegal AIDOS state transition: $old -> $NewState"};$o=[ordered]@{};foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value};foreach($k in $Patch.Keys){$o[$k]=$Patch[$k]};$o.state=$NewState;$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');$e=New-AidosEventObject $ProjectRoot 'STATE_TRANSITION' $Actor @{from=$old;to=$NewState;patch_keys=@($Patch.Keys)};foreach($n in @('definition_id','definition_version','execution_id','revision','review_id')){if($o.Contains($n)){$e[$n]=$o[$n]}};Add-AidosEventUnlocked $ProjectRoot $e;Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o;[pscustomobject]$o}
}
function Set-AidosExecutionDispatchBinding { [CmdletBinding(SupportsShouldProcess)]param([string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision,[ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor='BRIDGE')
    Test-AidosProjectBinding $ProjectRoot|Out-Null
    if(-not$PSCmdlet.ShouldProcess((Join-Path $ProjectRoot '.aidos/STATE.json'),"Bind dispatch to $ExecutionId/revision $Revision")){return}
    Invoke-AidosExclusive $ProjectRoot {
        $s=Get-AidosState $ProjectRoot
        if($s.state-ne'TASK_READY'){throw 'Dispatch binding requires TASK_READY.'}
        $previousExecutionId=[string]$s.execution_id
        $previousRevision=[int]$s.revision
        $o=[ordered]@{}
        foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value}
        $o.execution_id=$ExecutionId
        $o.revision=$Revision
        $o.codex_session_id=$null
        $o.lease_id=$null
        $o.terminal_result=$null
        $o.git_head=$null
        $o.validation_result=$null
        $o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        $e=New-AidosEventObject $ProjectRoot 'EXECUTION_DISPATCH_BOUND' $Actor @{from_execution_id=$previousExecutionId;from_revision=$previousRevision;execution_id=$ExecutionId;revision=$Revision}
        foreach($n in @('definition_id','definition_version','execution_id','revision','review_id')){if($o.Contains($n)){$e[$n]=$o[$n]}}
        Add-AidosEventUnlocked $ProjectRoot $e
        Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
        [pscustomobject]$o
    }
}
function Acquire-AidosExecutionLease { param([string]$ProjectRoot,[string]$ExecutionId,[int]$Revision)
    Invoke-AidosExclusive $ProjectRoot {$path=Join-Path $ProjectRoot '.aidos/runtime/lease.json';if(Test-Path $path){$x=Read-AidosJson $path;throw "Execution lease already exists: $($x.lease_id)."};$l=[ordered]@{schema_version='0.1';project_id=(Get-AidosProjectProfile $ProjectRoot).project_id;execution_id=$ExecutionId;revision=$Revision;runner_id=[Environment]::MachineName;lease_id=[guid]::NewGuid().ToString();acquired_at=[DateTimeOffset]::UtcNow.ToString('o');orchestrator_pid=$PID;orchestrator_started_at=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');codex_runtime=$null};Write-AidosJsonAtomic $path $l;Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'EXECUTION_LEASE_ACQUIRED' 'BRIDGE' @{lease_id=$l.lease_id;execution_id=$ExecutionId;revision=$Revision});[pscustomobject]$l}
}
function Release-AidosExecutionLease { param([string]$ProjectRoot,[string]$LeaseId,[string]$Reason='TERMINAL')
    Invoke-AidosExclusive $ProjectRoot {$path=Join-Path $ProjectRoot '.aidos/runtime/lease.json';$l=Read-AidosJson $path;if($l.lease_id-ne$LeaseId){throw 'Lease ID mismatch.'};Remove-Item $path -Force;Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'EXECUTION_LEASE_RELEASED' 'BRIDGE' @{lease_id=$LeaseId;reason=$Reason})}
}
function Get-AidosCodexCommand { param($Runtime,[string]$ProjectRoot,[string[]]$CodexArguments)
    $command=Get-AidosCodexRuntimeCommand $Runtime $CodexArguments
    [pscustomobject]@{FileName=$command.FileName;WorkingDirectory=$ProjectRoot;Arguments=$command.Arguments}
}
function Test-AidosExecutionEvidence { param([string]$ProjectRoot,$Execution)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal};$prefix=$root+[IO.Path]::DirectorySeparatorChar;$results=@();$requirements=@($Execution.validation.requirements)
    if($Execution.validation.mode-ne'ALL'-or$requirements.Count-eq0){return [pscustomobject]@{status='FAIL';checked_at=[DateTimeOffset]::UtcNow.ToString('o');requirements=@();error='Execution has no supported ALL validation requirements.'}}
    foreach($requirement in $requirements){$relative=[string]$requirement.path;if([IO.Path]::IsPathRooted($relative)){throw "Validation path must be project-relative: $relative"};$candidate=[IO.Path]::GetFullPath((Join-Path $root $relative));if(-not$candidate.StartsWith($prefix,$comparison)){throw "Validation path escapes project root: $relative"};$passed=$false;$actual=$null;$error=$null
        if($requirement.type-eq'PATH_EXISTS'){$passed=Test-Path -LiteralPath $candidate}
        elseif($requirement.type-eq'FILE_CONTENT_EXACT'){if(Test-Path -LiteralPath $candidate -PathType Leaf){$actual=[IO.File]::ReadAllText($candidate,[Text.Encoding]::UTF8);$expected=[string]$requirement.expected;if($requirement.trim_trailing_newline){$actual=$actual.TrimEnd("`r","`n");$expected=$expected.TrimEnd("`r","`n")};$passed=$actual-ceq$expected}else{$error='Required file does not exist.'}}
        else{$error="Unsupported validation requirement '$($requirement.type)'."}
        $results+=[pscustomobject]@{type=[string]$requirement.type;path=$relative;passed=$passed;actual=$actual;error=$error}
    }
    [pscustomobject]@{status=if(@($results|Where-Object{-not$_.passed}).Count){'FAIL'}else{'PASS'};checked_at=[DateTimeOffset]::UtcNow.ToString('o');requirements=$results;error=$null}
}
function Invoke-AidosCodexExecution {
    param([string]$ProjectRoot,[string]$ExecutionPath,$Runtime,[string]$Prompt,[switch]$Resume)
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot;$ExecutionPath=Resolve-AidosFileSystemPath $ExecutionPath;$execution=Read-AidosJson $ExecutionPath
    $null=Assert-AidosExecutionBinding $ProjectRoot $execution
    if($Runtime.kind-eq'WSL_LOCAL'-and-not(Test-AidosSameFileSystemPath ([string]$Runtime.project_root) $ProjectRoot)){throw 'WSL Codex project root does not exactly match the registered project root.'}
    $state=Get-AidosState $ProjectRoot;if($state.state-ne'TASK_READY'){throw 'Dispatch requires TASK_READY.'};if($Resume-and-not$state.codex_session_id){throw 'Resume requested without session ID.'}
    if($state.execution_id-ne$execution.execution_id-or[int]$state.revision-ne[int]$execution.revision){$null=Set-AidosExecutionDispatchBinding $ProjectRoot $execution.execution_id $execution.revision}
    $state=Get-AidosState $ProjectRoot;if($state.execution_id-ne$execution.execution_id-or[int]$state.revision-ne[int]$execution.revision){throw 'Execution/revision mismatch.'}
    Assert-AidosCodexCliSupport $Runtime $execution -Resume:$Resume
    $lease=Acquire-AidosExecutionLease $ProjectRoot $execution.execution_id $execution.revision
    $directory=Join-Path $ProjectRoot ('.aidos/executions/{0}/revision-{1}'-f$execution.execution_id,$execution.revision);New-Item -ItemType Directory -Path $directory -Force|Out-Null
    $eventsPath=Join-Path $directory 'codex-events.jsonl';$stderrPath=Join-Path $directory 'codex-stderr.log';$resultPath=Join-Path $directory 'RESULT.json';$validationPath=Join-Path $directory 'VALIDATION.json'
    $relativeExecution=[IO.Path]::GetRelativePath($ProjectRoot,$ExecutionPath).Replace('\','/');$runtimeExecution=([string]$Runtime.project_root).TrimEnd('/')+'/'+$relativeExecution
    $promptText=if($Prompt){$Prompt}else{"Execute accepted AIDOS execution $runtimeExecution inside its exact authority."}
    $arguments=Get-AidosCodexLaunchArguments $Runtime $execution $promptText -Resume:$Resume -SessionId ([string]$state.codex_session_id)
    $command=Get-AidosCodexCommand $Runtime $ProjectRoot $arguments;$null=Set-AidosState $ProjectRoot 'CODEX_RUNNING' 'BRIDGE' @{lease_id=$lease.lease_id}
    $started=[DateTimeOffset]::UtcNow;$exitCode=$null;$sessionId=if($Resume){[string]$state.codex_session_id}else{$null};$terminalType='process_error';$errorText=$null;$finalMessage=$null
    try {
        $startInfo=[Diagnostics.ProcessStartInfo]::new();$startInfo.FileName=$command.FileName;$startInfo.WorkingDirectory=$command.WorkingDirectory;$startInfo.UseShellExecute=$false;$startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true
        foreach($argument in $command.Arguments){$null=$startInfo.ArgumentList.Add([string]$argument)}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$startInfo;if(-not$process.Start()){throw 'Codex did not start.'};$processId=$process.Id;$processStarted=try{$process.StartTime.ToUniversalTime().ToString('o')}catch{[DateTimeOffset]::UtcNow.ToString('o')};$stderrTask=$process.StandardError.ReadToEndAsync()
        Invoke-AidosExclusive $ProjectRoot {$currentLease=Read-AidosJson (Join-Path $ProjectRoot '.aidos/runtime/lease.json');$currentLease.codex_runtime=[ordered]@{kind=$Runtime.kind;supervisor_pid=$processId;started_at=$processStarted};Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/runtime/lease.json') $currentLease}
        $writer=[IO.StreamWriter]::new($eventsPath,$false,[Text.UTF8Encoding]::new($false));try{while(-not$process.StandardOutput.EndOfStream){$line=$process.StandardOutput.ReadLine();$writer.WriteLine($line);$writer.Flush();try{$event=$line|ConvertFrom-Json -Depth 100;if($event.type-eq'thread.started'-and$event.thread_id){$sessionId=[string]$event.thread_id};if($event.type-eq'turn.completed'){$terminalType='turn.completed'};if($event.type -in @('turn.failed','error')){$terminalType=[string]$event.type};if($event.type-eq'item.completed'-and$event.item.type-eq'agent_message'){$finalMessage=[string]$event.item.text}}catch{}}}finally{$writer.Dispose()}
        $process.WaitForExit();$stderr=$stderrTask.GetAwaiter().GetResult();[IO.File]::WriteAllText($stderrPath,$stderr,[Text.UTF8Encoding]::new($false));$exitCode=$process.ExitCode;if($exitCode-ne0-and$terminalType-eq'turn.completed'){$terminalType='process_error'}
    } catch {$errorText="$($_.Exception.Message) [line $($_.InvocationInfo.ScriptLineNumber)]";$terminalType='process_error'}
    $headResult=Invoke-AidosGit $ProjectRoot @('rev-parse','HEAD');$head=if($headResult.ExitCode-eq0){$headResult.Output|Select-Object -First 1}else{$null}
    $result=[ordered]@{schema_version='0.1';project_id=$execution.project_id;execution_id=$execution.execution_id;revision=$execution.revision;lease_id=$lease.lease_id;codex_session_id=$sessionId;resumed=[bool]$Resume;started_at=$started.ToString('o');finished_at=[DateTimeOffset]::UtcNow.ToString('o');exit_code=$exitCode;terminal_type=$terminalType;process_succeeded=($terminalType-eq'turn.completed'-and$exitCode-eq0);validation_status='NOT_RUN';validation_path=$null;final_message=$finalMessage;prompt_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($promptText))).ToLowerInvariant();error=$errorText;git_head=$head;events_path=[IO.Path]::GetRelativePath($ProjectRoot,$eventsPath);stderr_path=[IO.Path]::GetRelativePath($ProjectRoot,$stderrPath)}
    $statePatch=@{codex_session_id=$sessionId;terminal_result=[IO.Path]::GetRelativePath($ProjectRoot,$resultPath);git_head=$head}
    if($result.process_succeeded-and$sessionId){
        $null=Set-AidosState $ProjectRoot 'TERMINAL_PENDING' 'BRIDGE' $statePatch
        try{$validation=Test-AidosExecutionEvidence $ProjectRoot $execution}catch{$validation=[pscustomobject]@{status='FAIL';checked_at=[DateTimeOffset]::UtcNow.ToString('o');requirements=@();error=$_.Exception.Message}}
        Write-AidosJsonAtomic $validationPath $validation;$result.validation_status=$validation.status;$result.validation_path=[IO.Path]::GetRelativePath($ProjectRoot,$validationPath);Write-AidosJsonAtomic $resultPath $result
        if($validation.status-eq'PASS'){$null=Set-AidosState $ProjectRoot 'REVIEW_READY' 'BRIDGE' @{validation_result=$result.validation_path};Release-AidosExecutionLease $ProjectRoot $lease.lease_id 'VALIDATED'}else{$null=Set-AidosState $ProjectRoot 'EXECUTION_VALIDATION_FAILED' 'BRIDGE' @{validation_result=$result.validation_path};Release-AidosExecutionLease $ProjectRoot $lease.lease_id 'VALIDATION_FAILED'}
    } else {Write-AidosJsonAtomic $resultPath $result;$null=Set-AidosState $ProjectRoot 'RECOVERY_REQUIRED' 'BRIDGE' $statePatch;Release-AidosExecutionLease $ProjectRoot $lease.lease_id 'FAILED'}
    [pscustomobject]$result
}
function Repair-AidosStateProjection { param($ProjectRoot)
    $s=Get-AidosState $ProjectRoot;$last=$null;foreach($f in (Get-ChildItem (Join-Path $ProjectRoot '.aidos/events') -Filter '*.jsonl' -File -ErrorAction SilentlyContinue|Sort-Object Name)){foreach($line in (Get-Content $f.FullName)){try{$e=$line|ConvertFrom-Json -Depth 100;if($e.event_type-eq'STATE_TRANSITION'){$last=$e}}catch{throw "Invalid event JSONL in '$($f.FullName)'."}}};if($last-and$s.state-ne$last.payload.to){$o=[ordered]@{};foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state=$last.payload.to;$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o;return $true};$false
}
function Invoke-AidosStartupReconciliation { param([string]$ProjectRoot)
    Test-AidosProjectBinding $ProjectRoot|Out-Null;Invoke-AidosExclusive $ProjectRoot {$repaired=Repair-AidosStateProjection $ProjectRoot;$path=Join-Path $ProjectRoot '.aidos/runtime/lease.json';if(-not(Test-Path $path)){$s=Get-AidosState $ProjectRoot;if($s.state-eq'CODEX_RUNNING'){$o=[ordered]@{};foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'RECOVERY_RECONCILED' 'BRIDGE' @{reason='CODEX_RUNNING_WITHOUT_LEASE';next_state='RECOVERY_REQUIRED'});Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o;return [pscustomobject]@{status='RECOVERY_REQUIRED';projection_repaired=$repaired}};return [pscustomobject]@{status='CLEAN';projection_repaired=$repaired}};$l=Read-AidosJson $path;$alive=$false;if($l.codex_runtime-and$l.codex_runtime.supervisor_pid){$p=Get-Process -Id ([int]$l.codex_runtime.supervisor_pid) -ErrorAction SilentlyContinue;if($p){$alive=$p.StartTime.ToUniversalTime().ToString('o')-eq[string]$l.codex_runtime.started_at}};if($alive){return [pscustomobject]@{status='RUNNING';lease_id=$l.lease_id;projection_repaired=$repaired}};$s=Get-AidosState $ProjectRoot;if($s.state-eq'CODEX_RUNNING'){$o=[ordered]@{};foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'EXECUTION_INTERRUPTED' 'BRIDGE' @{lease_id=$l.lease_id;execution_id=$l.execution_id;revision=$l.revision});Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o};Remove-Item $path -Force;Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'RECOVERY_RECONCILED' 'BRIDGE' @{stale_lease_id=$l.lease_id;next_state=(Get-AidosState $ProjectRoot).state});[pscustomobject]@{status='RECOVERY_REQUIRED';stale_lease_id=$l.lease_id;projection_repaired=$repaired}}
}
Export-ModuleMember -Function Resolve-AidosFileSystemPath,Test-AidosSameFileSystemPath,Get-AidosProjectRoot,Read-AidosJson,Write-AidosJsonAtomic,Get-AidosProjectProfile,Get-AidosGitRuntime,Get-AidosGitCommand,Invoke-AidosGit,Register-AidosGitRuntime,Get-AidosCodexRuntimeCommand,Get-AidosCodexCliCapabilities,Assert-AidosCodexAuthorityRepresentable,Assert-AidosCodexCliSupport,Get-AidosCodexLaunchArguments,Test-AidosProjectBinding,Get-AidosPreparationSnapshot,Assert-AidosExecutionBinding,Get-AidosState,Add-AidosEvent,Set-AidosState,Set-AidosExecutionDispatchBinding,Acquire-AidosExecutionLease,Release-AidosExecutionLease,Get-AidosCodexCommand,Test-AidosExecutionEvidence,Invoke-AidosCodexExecution,Invoke-AidosStartupReconciliation
