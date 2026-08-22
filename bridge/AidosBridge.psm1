Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AllowedTransitions = @{
    IDLE=@('WAITING_DEFINITION','TASK_READY'); WAITING_DEFINITION=@('TASK_READY','WAITING_USER')
    DISCOVERY_REFRESH_REQUIRED=@('WAITING_DEFINITION','TASK_READY','RECOVERY_REQUIRED'); TASK_READY=@('QUEUED','CODEX_RUNNING','RECOVERY_REQUIRED')
    QUEUED=@('CODEX_RUNNING','RECOVERY_REQUIRED'); CODEX_RUNNING=@('TERMINAL_PENDING','CONTEXT_ROTATION_REQUIRED','RECOVERY_REQUIRED')
    TERMINAL_PENDING=@('REVIEW_READY','EXECUTION_VALIDATION_FAILED','WAITING_USER','WAITING_DEFINITION','RECOVERY_REQUIRED'); EXECUTION_VALIDATION_FAILED=@('TASK_READY','RECOVERY_REQUIRED','WAITING_USER'); REVIEW_READY=@('GPT_REVIEWING','WAITING_INTERACTIVE_SESSION','RECOVERY_REQUIRED')
    WAITING_INTERACTIVE_SESSION=@('GPT_REVIEWING','RECOVERY_REQUIRED'); GPT_REVIEWING=@('IDLE','TASK_READY','WAITING_DEFINITION','WAITING_USER','DISCOVERY_REFRESH_REQUIRED','RELEASE_READY','CONTEXT_ROTATION_REQUIRED','WAITING_INTERACTIVE_SESSION','RECOVERY_REQUIRED')
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
function Get-AidosTextSha256 { param([Parameter(Mandatory)][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}
function Invoke-AidosExclusive { param([string]$ProjectRoot,[scriptblock]$ScriptBlock,[int]$TimeoutSeconds=15)
    if(-not(Get-Variable -Scope Script -Name AidosExclusivePaths -ErrorAction SilentlyContinue)){$script:AidosExclusivePaths=@{}}
    $key=[IO.Path]::GetFullPath($ProjectRoot)
    if($script:AidosExclusivePaths.ContainsKey($key)){return & $ScriptBlock}
    $dir=Join-Path $ProjectRoot '.aidos/runtime';if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds);$lock=$null
    while($null -eq $lock){try{$lock=[IO.FileStream]::new((Join-Path $dir 'bridge.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{if([DateTimeOffset]::UtcNow-ge$deadline){throw 'Timed out acquiring AIDOS project lock.'};Start-Sleep -Milliseconds 50}}
    $script:AidosExclusivePaths[$key]=$true
    try{&$ScriptBlock}finally{$script:AidosExclusivePaths.Remove($key);$lock.Dispose()}
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
function Resolve-AidosRecordBoundPath {
    # Current records store project-relative paths.  Older Windows-published
    # records may retain a UNC assignment path; preserve that exact bound path
    # rather than accidentally prefixing it with the project root during safe
    # recovery/consumption.
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$Path)
    if([IO.Path]::IsPathRooted($Path)){ return $Path }
    Join-Path $ProjectRoot $Path
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
    $profile=Get-AidosProjectProfile $ProjectRoot
    if($profile.PSObject.Properties['git_runtime']){return $profile.git_runtime}
    return [pscustomobject]@{kind='NATIVE';project_root=(Resolve-AidosFileSystemPath $ProjectRoot);git_path='git'}
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
    $officialRoot=if($p.PSObject.Properties['official_root'] -and -not[string]::IsNullOrWhiteSpace([string]$p.official_root)){[string]$p.official_root}else{$resolved}
    $expected=Resolve-AidosFileSystemPath $officialRoot;$cmp=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not[string]::Equals($resolved,$expected,$cmp)){throw "AIDOS project-root mismatch. Expected '$expected'; actual '$resolved'."}
    $runtime=Get-AidosGitRuntime $resolved;$rootResult=Invoke-AidosGit $resolved @('rev-parse','--show-toplevel');$gitRoot=($rootResult.Output|Select-Object -First 1);if($rootResult.ExitCode-ne0-or-not$gitRoot){throw "Not a readable Git worktree through '$($runtime.kind)' runtime."}
    if($runtime.kind-eq'NATIVE'){$gitRoot=Resolve-AidosFileSystemPath ([string]$gitRoot);if(-not[string]::Equals($gitRoot,$expected,$cmp)){throw "Git root '$gitRoot' does not equal official_root '$expected'."}}else{if(-not[string]::Equals(([string]$gitRoot).TrimEnd('/'),([string]$runtime.project_root).TrimEnd('/'),[StringComparison]::Ordinal)){throw "WSL Git root '$gitRoot' does not equal registered WSL project_root '$($runtime.project_root)'."}}
    $originResult=Invoke-AidosGit $resolved @('remote','get-url','origin');$origin=($originResult.Output|Select-Object -First 1);if($originResult.ExitCode-ne0-or-not$origin){throw 'Git origin unavailable.'}
    $projectRepository=if($p.PSObject.Properties['repository'] -and -not[string]::IsNullOrWhiteSpace([string]$p.repository)){[string]$p.repository}else{[string]$origin}
    if((ConvertTo-AidosRepositoryIdentity $origin)-ne(ConvertTo-AidosRepositoryIdentity $projectRepository)){throw "Git origin '$origin' does not exactly match '$projectRepository'."}
    [pscustomobject]@{ProjectId=[string]$p.project_id;Repository=$projectRepository;Root=$expected;GitRuntime=[string]$runtime.kind;GitRoot=[string]$gitRoot;Origin=$origin.Trim();Valid=$true}
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
        $o.review_id=$null
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
function Get-AidosReviewRoot { param([string]$ProjectRoot) Join-Path $ProjectRoot '.aidos/reviews' }
function Get-AidosReviewPackageRoot { param([string]$ProjectRoot,[string]$ReviewId) Join-Path $ProjectRoot ('.aidos/runtime/reviews/{0}' -f $ReviewId) }
function Get-AidosReviewRecordPath { param([string]$ProjectRoot,[string]$ReviewId) Join-Path (Join-Path $ProjectRoot ('.aidos/reviews/{0}' -f $ReviewId)) 'REVIEW.json' }
function Get-AidosReviewManifestPath { param([string]$ProjectRoot,[string]$ReviewId) Join-Path (Get-AidosReviewPackageRoot $ProjectRoot $ReviewId) 'MANIFEST.json' }
function Get-AidosReviewAckPath { param([string]$ProjectRoot,[string]$ReviewId) Join-Path (Get-AidosReviewPackageRoot $ProjectRoot $ReviewId) 'ACK.json' }
function Get-AidosReviewPackagePath { param([string]$ProjectRoot,[string]$ReviewId) Get-AidosReviewPackageRoot $ProjectRoot $ReviewId }
function Get-AidosReviewDecisionState { param([string]$Outcome)
    switch ($Outcome) {
        'PASS' { 'IDLE' }
        'REPAIR' { 'TASK_READY' }
        'BLOCKER' { 'WAITING_USER' }
        'DISCOVERY_REFRESH_REQUIRED' { 'DISCOVERY_REFRESH_REQUIRED' }
        'WAITING_INTERACTIVE_SESSION' { 'WAITING_INTERACTIVE_SESSION' }
        default { throw "Unsupported review outcome '$Outcome'." }
    }
}
function Get-AidosReviewReviewerBinding { param([string]$ProjectRoot)
    $profile=Get-AidosProjectProfile $ProjectRoot
    $agentProfilePath=if($profile.PSObject.Properties['agent_profile']){[string]$profile.agent_profile}else{'.aidos/AGENT_PROFILE.json'}
    $agentProfile=Read-AidosJson (Join-Path $ProjectRoot $agentProfilePath)
    $workerIdentity=if($agentProfile.PSObject.Properties['reviewer_identity']){[string]$agentProfile.reviewer_identity}elseif($agentProfile.PSObject.Properties['aidos_agents'] -and $agentProfile.aidos_agents.worker){[string]$agentProfile.aidos_agents.worker}else{throw 'Project agent profile does not declare a reviewer identity.'}
    [pscustomobject]@{role='WORKER_AGENT';identity=$workerIdentity}
}
function Get-AidosReviewAssignmentPath { param([string]$ProjectRoot,[string]$ReviewId) Join-Path (Get-AidosReviewPackageRoot $ProjectRoot $ReviewId) 'REVIEW_ASSIGNMENT.json' }
function Get-AidosReviewLegacyAssignmentPath { param([string]$ProjectRoot,[string]$ReviewId) Join-Path (Get-AidosReviewPackageRoot $ProjectRoot $ReviewId) 'ASSIGNMENT.json' }
function Test-AidosReviewAssignmentBinding { param([string]$ProjectRoot,$Assignment,$Manifest,[string]$ManifestSha256,$ReviewerBinding)
    $profile=Get-AidosProjectProfile $ProjectRoot
    $expectedPackagePath=[IO.Path]::GetRelativePath($ProjectRoot,(Get-AidosReviewPackageRoot $ProjectRoot $Assignment.review_id))
    $expectedManifestPath=[IO.Path]::GetRelativePath($ProjectRoot,(Get-AidosReviewManifestPath $ProjectRoot $Assignment.review_id))
    $expectedRecordPath=[IO.Path]::GetRelativePath($ProjectRoot,(Get-AidosReviewRecordPath $ProjectRoot $Assignment.review_id))
    $binding=@(
        @{name='project_id';actual=[string]$Assignment.project_id;expected=[string]$Manifest.project_id},
        @{name='project_root';actual=[string]$Assignment.project_root;expected=[string]$Manifest.project_root},
        @{name='project_mode';actual=[string]$Assignment.project_mode;expected=[string]$profile.project_mode},
        @{name='definition_id';actual=[string]$Assignment.definition_id;expected=[string]$Manifest.definition_id},
        @{name='definition_version';actual=[int]$Assignment.definition_version;expected=[int]$Manifest.definition_version},
        @{name='execution_id';actual=[string]$Assignment.execution_id;expected=[string]$Manifest.execution_id},
        @{name='revision';actual=[int]$Assignment.revision;expected=[int]$Manifest.revision},
        @{name='review_id';actual=[string]$Assignment.review_id;expected=[string]$Manifest.review_id},
        @{name='package_path';actual=[string]$Assignment.package_path;expected=[string]$expectedPackagePath},
        @{name='package_manifest_path';actual=[string]$Assignment.package_manifest_path;expected=[string]$expectedManifestPath},
        @{name='review_record_path';actual=[string]$Assignment.review_record_path;expected=[string]$expectedRecordPath},
        @{name='package_manifest_sha256';actual=[string]$Assignment.package_manifest_sha256;expected=[string]$ManifestSha256},
        @{name='reviewer_role';actual=[string]$Assignment.reviewer_role;expected=[string]$ReviewerBinding.role},
        @{name='reviewer_identity';actual=[string]$Assignment.reviewer_identity;expected=[string]$ReviewerBinding.identity}
    )
    foreach($item in $binding){if($item.actual-ne$item.expected){throw "Review binding '$($item.name)' is stale or mismatched."}}
    $expectedAssignmentPath=Join-Path (Resolve-AidosFileSystemPath (Get-AidosReviewPackageRoot $ProjectRoot $Assignment.review_id)) 'REVIEW_ASSIGNMENT.json'
    $actualAssignmentPath=$expectedAssignmentPath
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not[string]::Equals($expectedAssignmentPath,$actualAssignmentPath,$comparison)){throw "Assignment path '$actualAssignmentPath' does not equal expected '$expectedAssignmentPath'."}
    [pscustomobject]@{Valid=$true}
}
function Test-AidosReviewBinding { param([string]$ProjectRoot,$Review,$Manifest)
    $binding=@(
        @{name='project_id';actual=[string]$Review.project_id;expected=[string]$Manifest.project_id},
        @{name='definition_id';actual=[string]$Review.definition_id;expected=[string]$Manifest.definition_id},
        @{name='definition_version';actual=[int]$Review.definition_version;expected=[int]$Manifest.definition_version},
        @{name='execution_id';actual=[string]$Review.execution_id;expected=[string]$Manifest.execution_id},
        @{name='revision';actual=[int]$Review.revision;expected=[int]$Manifest.revision},
        @{name='review_id';actual=[string]$Review.review_id;expected=[string]$Manifest.review_id}
    )
    foreach($item in $binding){if($item.actual-ne$item.expected){throw "Review binding '$($item.name)' is stale or mismatched."}}
    $recordRoot=Resolve-AidosFileSystemPath (Get-AidosReviewRoot $ProjectRoot)
    $expectedRecordRoot=Resolve-AidosFileSystemPath (Join-Path $ProjectRoot '.aidos/reviews')
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not[string]::Equals($recordRoot,$expectedRecordRoot,$comparison)){throw "Review record root '$recordRoot' does not equal expected '$expectedRecordRoot'."}
    [pscustomobject]@{Valid=$true}
}
function Get-AidosReviewEvidenceRefs { param([string]$ProjectRoot,$Execution,$State,$Result,$Validation,$ExecutionPath)
    $items=@(
        @{kind='EXECUTION';path=([IO.Path]::GetRelativePath($ProjectRoot,$ExecutionPath));source=$ExecutionPath},
        @{kind='TERMINAL_RESULT';path=[string]($State.terminal_result);source=(Join-Path $ProjectRoot ([string]$State.terminal_result))},
        @{kind='VALIDATION_RESULT';path=[string]($Result.validation_path);source=(Join-Path $ProjectRoot ([string]$Result.validation_path))},
        @{kind='EVENTS_JSONL';path=[string]($Result.events_path);source=(Join-Path $ProjectRoot ([string]$Result.events_path))},
        @{kind='STDERR_LOG';path=[string]($Result.stderr_path);source=(Join-Path $ProjectRoot ([string]$Result.stderr_path))}
    )
    $refs=@()
    foreach($item in $items){
        $source=[string]$item.source
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Required review evidence not found: $source"}
        $refs+=[ordered]@{kind=[string]$item.kind;path=[string]$item.path;sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $refs
}
function New-AidosReviewAssignmentObject { param([string]$ProjectRoot,[string]$ReviewId,$Execution,$State,$Result,[string]$PackagePath,[string]$ManifestPath,[string]$ManifestSha256,[object[]]$EvidenceRefs,$ReviewerBinding)
    [ordered]@{
        schema_version='0.1'
        envelope_type='REVIEW_ASSIGNMENT'
        review_id=$ReviewId
        project_id=[string]$Execution.project_id
        project_root=(Resolve-AidosFileSystemPath $ProjectRoot)
        project_mode=[string]$Execution.project_mode
        definition_id=[string]($Execution.definition.id)
        definition_version=[int]($Execution.definition.version)
        execution_id=[string]$Execution.execution_id
        revision=[int]$Execution.revision
        package_path=$PackagePath
        package_manifest_path=$ManifestPath
        package_manifest_sha256=$ManifestSha256
        review_record_path=[IO.Path]::GetRelativePath($ProjectRoot,(Get-AidosReviewRecordPath $ProjectRoot $ReviewId))
        reviewer_role=[string]$ReviewerBinding.role
        reviewer_identity=[string]$ReviewerBinding.identity
        allowed_outcomes=@('PASS','REPAIR','BLOCKER','DISCOVERY_REFRESH_REQUIRED','WAITING_INTERACTIVE_SESSION')
        instructions=[ordered]@{
            may_inspect=@('assignment','manifest','referenced_evidence')
            may_not=@('chat_history','unbound_files','secrets')
            must_return=@('outcome','reason','evidence_refs')
        }
        evidence_refs=@($EvidenceRefs)
        issued_at=[DateTimeOffset]::UtcNow.ToString('o')
        issued_by='BRIDGE'
    }
}
function New-AidosReviewResponseObject { param([string]$ProjectRoot,[string]$ReviewId,$Assignment,[string]$Outcome,[string]$Reason,[string[]]$RepairGuidance,[object[]]$EvidenceRefs)
    [ordered]@{
        schema_version='0.1'
        envelope_type='REVIEW_RESPONSE'
        review_id=$ReviewId
        project_id=[string]$Assignment.project_id
        project_root=[string]$Assignment.project_root
        project_mode=[string]$Assignment.project_mode
        definition_id=[string]$Assignment.definition_id
        definition_version=[int]$Assignment.definition_version
        execution_id=[string]$Assignment.execution_id
        revision=[int]$Assignment.revision
        reviewer_role=[string]$Assignment.reviewer_role
        reviewer_identity=[string]$Assignment.reviewer_identity
        assignment_sha256=[string]$Assignment.assignment_sha256
        package_manifest_sha256=[string]$Assignment.package_manifest_sha256
        outcome=[string]$Outcome
        reason=[string]$Reason
        evidence_refs=@($EvidenceRefs)
        repair_guidance=@($RepairGuidance)
        responded_at=[DateTimeOffset]::UtcNow.ToString('o')
        responded_by=[string]$Assignment.reviewer_identity
    }
}
function Write-AidosReviewAssignmentAtomic { param([string]$ProjectRoot,[string]$ReviewId,$Value)
    Write-AidosJsonAtomic (Get-AidosReviewAssignmentPath $ProjectRoot $ReviewId) $Value
}
function Read-AidosReviewAssignment { param([string]$ProjectRoot,[string]$ReviewId) Read-AidosJson (Get-AidosReviewAssignmentPath $ProjectRoot $ReviewId) }
function Test-AidosReviewAssignmentIntegrity { param([string]$ProjectRoot,[string]$ReviewId,$Record)
    $assignmentPath=if($Record.assignment_path){Resolve-AidosRecordBoundPath $ProjectRoot ([string]$Record.assignment_path)}else{Get-AidosReviewAssignmentPath $ProjectRoot $ReviewId}
    if(-not(Test-Path -LiteralPath $assignmentPath -PathType Leaf)){throw "Review assignment not found: $assignmentPath"}
    $actualSha=(Get-FileHash -LiteralPath $assignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($Record.assignment_sha256 -and [string]($Record.assignment_sha256) -ne $actualSha){throw 'Review assignment hash mismatch.'}
    [pscustomobject]@{assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);assignment_sha256=$actualSha}
}
function Test-AidosReviewEvidenceRefsMatch { param([object[]]$Actual,[object[]]$Expected)
    $actualList=@($Actual)
    $expectedList=@($Expected)
    if($actualList.Count -ne $expectedList.Count){throw 'Review assignment evidence refs are stale or mismatched.'}
    for($i=0;$i -lt $expectedList.Count;$i++){
        $actual=$actualList[$i]
        $expected=$expectedList[$i]
        foreach($name in @('kind','path','sha256')){
            if([string]$actual.$name -ne [string]$expected.$name){throw 'Review assignment evidence refs are stale or mismatched.'}
        }
    }
}
function Test-AidosReviewAssignmentEquivalent { param($Actual,$Expected)
    if(-not $Actual){throw 'Review assignment record is missing canonical assignment content.'}
    foreach($name in @(
        'schema_version','envelope_type','review_id','project_id','project_root','project_mode',
        'definition_id','definition_version','execution_id','revision','package_path','package_manifest_path',
        'package_manifest_sha256','review_record_path','reviewer_role','reviewer_identity','issued_at','issued_by'
    )){
        if([string]$Actual.$name -ne [string]$Expected.$name){throw 'Review assignment content is stale or mismatched.'}
    }
    $actualAllowed=@($Actual.allowed_outcomes)
    $expectedAllowed=@($Expected.allowed_outcomes)
    if($actualAllowed.Count -ne $expectedAllowed.Count){throw 'Review assignment content is stale or mismatched.'}
    for($i=0;$i -lt $expectedAllowed.Count;$i++){if([string]$actualAllowed[$i] -ne [string]$expectedAllowed[$i]){throw 'Review assignment content is stale or mismatched.'}}
    Test-AidosReviewEvidenceRefsMatch -Actual @($Actual.evidence_refs) -Expected @($Expected.evidence_refs)
    if((@($Actual.instructions.may_inspect) -join '|') -ne (@($Expected.instructions.may_inspect) -join '|')){throw 'Review assignment content is stale or mismatched.'}
    if((@($Actual.instructions.may_not) -join '|') -ne (@($Expected.instructions.may_not) -join '|')){throw 'Review assignment content is stale or mismatched.'}
    if((@($Actual.instructions.must_return) -join '|') -ne (@($Expected.instructions.must_return) -join '|')){throw 'Review assignment content is stale or mismatched.'}
}
function Write-AidosReviewResponseAtomic { param([string]$ProjectRoot,[string]$ReviewId,$Value)
    $recordDir=Join-Path (Get-AidosReviewRoot $ProjectRoot) $ReviewId
    if(-not(Test-Path -LiteralPath $recordDir)){New-Item -ItemType Directory -Path $recordDir -Force|Out-Null}
    Write-AidosJsonAtomic (Join-Path $recordDir 'RESPONSE.json') $Value
}
function Read-AidosReviewResponse { param([string]$ProjectRoot,[string]$ReviewId) Read-AidosJson (Join-Path (Join-Path (Get-AidosReviewRoot $ProjectRoot) $ReviewId) 'RESPONSE.json') }
function New-AidosReviewRecordObject { param([string]$ProjectRoot,[string]$ReviewId,$Execution,$State,$Result,[string]$PackagePath,[string]$ManifestPath,[string]$ManifestSha256,[object[]]$EvidenceRefs,$Assignment,$AssignmentSha256)
    $p=Get-AidosProjectProfile $ProjectRoot
    [ordered]@{
        schema_version='0.1'
        review_id=$ReviewId
        project_id=[string]$p.project_id
        project_root=(Resolve-AidosFileSystemPath $ProjectRoot)
        definition_id=[string]($Execution.definition.id)
        definition_version=[int]($Execution.definition.version)
        execution_id=[string]$Execution.execution_id
        revision=[int]$Execution.revision
        transport_state='PUBLISHED'
        package_path=$PackagePath
        package_manifest_path=$ManifestPath
        package_manifest_sha256=$ManifestSha256
        assignment_path=(Get-AidosReviewAssignmentPath $ProjectRoot $ReviewId)
        assignment=$Assignment
        assignment_sha256=$AssignmentSha256
        response=$null
        response_sha256=$null
        response_received_at=$null
        response_received_by=$null
        response_accepted_at=$null
        response_accepted_by=$null
        evidence_refs=@($EvidenceRefs)
        published_at=[DateTimeOffset]::UtcNow.ToString('o')
        published_by='BRIDGE'
        decision=$null
        consume_ack=$null
        consumed_at=$null
        consumed_by=$null
        cleaned_at=$null
        abandonment=$null
        updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
}
function Write-AidosReviewRecordAtomic { param([string]$ProjectRoot,[string]$ReviewId,$Value)
    $recordDir=Join-Path (Get-AidosReviewRoot $ProjectRoot) $ReviewId
    if(-not(Test-Path -LiteralPath $recordDir)){New-Item -ItemType Directory -Path $recordDir -Force|Out-Null}
    Write-AidosJsonAtomic (Join-Path $recordDir 'REVIEW.json') $Value
}
function Read-AidosReviewRecord { param([string]$ProjectRoot,[string]$ReviewId) Read-AidosJson (Get-AidosReviewRecordPath $ProjectRoot $ReviewId) }
function Resolve-AidosReviewDecisionTargetState { param([string]$Outcome)
    Get-AidosReviewDecisionState $Outcome
}
function Publish-AidosReviewPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot,[string]$ExecutionPath,[string]$ReviewId)
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $ExecutionPath=Resolve-AidosFileSystemPath $ExecutionPath
    $execution=Read-AidosJson $ExecutionPath
    $state=Get-AidosState $ProjectRoot
    $reviewerBinding=Get-AidosReviewReviewerBinding $ProjectRoot
    $null=Assert-AidosExecutionBinding $ProjectRoot $execution
    if($state.state-ne'REVIEW_READY'){throw "Review package publish requires REVIEW_READY, not '$($state.state)'. If a legacy review is already GPT_REVIEWING, use Repair-AidosReviewPackage."}
    if(-not[string]::IsNullOrWhiteSpace([string]($state.review_id))){throw "Review package publish requires a clear review_id in REVIEW_READY, not '$($state.review_id)'."}
    $effectiveReviewId=if([string]::IsNullOrWhiteSpace($ReviewId)){[guid]::NewGuid().ToString()}else{[string]$ReviewId}
    $resultPath=Join-Path $ProjectRoot ([string]($state.terminal_result))
    $result=Read-AidosJson $resultPath
    $validationPath=Join-Path $ProjectRoot ([string]($result.validation_path))
    $validation=Read-AidosJson $validationPath
    if($validation.status-ne'PASS'){throw "Review package publish requires PASS validation, not '$($validation.status)'."}
    $packageRoot=Get-AidosReviewPackageRoot $ProjectRoot $effectiveReviewId
    $manifestPath=Get-AidosReviewManifestPath $ProjectRoot $effectiveReviewId
    $recordPath=Get-AidosReviewRecordPath $ProjectRoot $effectiveReviewId
    $assignmentPath=Get-AidosReviewAssignmentPath $ProjectRoot $effectiveReviewId
    $evidenceRefs=Get-AidosReviewEvidenceRefs $ProjectRoot $execution $state $result $validation $ExecutionPath
    $manifest=[ordered]@{
        schema_version='0.1'
        package_type='REVIEW_PACKAGE'
        review_id=$effectiveReviewId
        project_id=[string]$execution.project_id
        project_root=(Resolve-AidosFileSystemPath $ProjectRoot)
        definition_id=[string]($execution.definition.id)
        definition_version=[int]($execution.definition.version)
        execution_id=[string]$execution.execution_id
        revision=[int]$execution.revision
        assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath)
        review_record_path=[IO.Path]::GetRelativePath($ProjectRoot,$recordPath)
        terminal_result_path=[string]$state.terminal_result
        validation_result_path=[string]$result.validation_path
        events_path=[string]$result.events_path
        stderr_path=[string]$result.stderr_path
        git_head=[string]$state.git_head
        evidence_refs=@($evidenceRefs)
        published_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    if($PSCmdlet.ShouldProcess($packageRoot,'Publish AIDOS review package')){
        if(-not(Test-Path -LiteralPath $packageRoot)){New-Item -ItemType Directory -Path $packageRoot -Force|Out-Null}
        Write-AidosJsonAtomic $manifestPath $manifest
        $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $assignment=New-AidosReviewAssignmentObject $ProjectRoot $effectiveReviewId $execution $state $result ([IO.Path]::GetRelativePath($ProjectRoot,$packageRoot)) ([IO.Path]::GetRelativePath($ProjectRoot,$manifestPath)) $manifestSha $evidenceRefs $reviewerBinding
        Write-AidosReviewAssignmentAtomic $ProjectRoot $effectiveReviewId $assignment
        $assignmentSha=(Get-FileHash -LiteralPath $assignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $record=New-AidosReviewRecordObject $ProjectRoot $effectiveReviewId $execution $state $result ([IO.Path]::GetRelativePath($ProjectRoot,$packageRoot)) ([IO.Path]::GetRelativePath($ProjectRoot,$manifestPath)) $manifestSha $evidenceRefs $assignment $assignmentSha
        Write-AidosReviewRecordAtomic $ProjectRoot $effectiveReviewId $record
        $null=Set-AidosState $ProjectRoot 'GPT_REVIEWING' 'BRIDGE' @{review_id=$effectiveReviewId}
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_ASSIGNMENT_PUBLISHED' 'BRIDGE' @{review_id=$effectiveReviewId;assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);assignment_sha256=$assignmentSha;manifest_sha256=$manifestSha;reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity}
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_PACKAGE_PUBLISHED' 'BRIDGE' @{review_id=$effectiveReviewId;package_path=[IO.Path]::GetRelativePath($ProjectRoot,$packageRoot);manifest_path=[IO.Path]::GetRelativePath($ProjectRoot,$manifestPath);manifest_sha256=$manifestSha;evidence_refs=@($evidenceRefs)}
        [pscustomobject]@{review_id=$effectiveReviewId;package_path=[IO.Path]::GetRelativePath($ProjectRoot,$packageRoot);manifest_path=[IO.Path]::GetRelativePath($ProjectRoot,$manifestPath);manifest_sha256=$manifestSha;assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);assignment_sha256=$assignmentSha;record_path=[IO.Path]::GetRelativePath($ProjectRoot,$recordPath);reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity}
    }
}
function Repair-AidosReviewPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot,[string]$ExecutionPath,[string]$ReviewId)
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $ExecutionPath=Resolve-AidosFileSystemPath $ExecutionPath
    $execution=Read-AidosJson $ExecutionPath
    $state=Get-AidosState $ProjectRoot
    $reviewerBinding=Get-AidosReviewReviewerBinding $ProjectRoot
    $null=Assert-AidosExecutionBinding $ProjectRoot $execution
    if($state.state-ne'GPT_REVIEWING' -and $state.state-ne'RECOVERY_REQUIRED'){throw "Review package recovery requires GPT_REVIEWING or RECOVERY_REQUIRED, not '$($state.state)'."}
    if([string]::IsNullOrWhiteSpace([string]($state.review_id))){throw 'GPT_REVIEWING review requires an existing review_id.'}
    if(-not[string]::IsNullOrWhiteSpace($ReviewId) -and [string]($state.review_id) -ne [string]$ReviewId){throw "Review ID mismatch: state has '$($state.review_id)' but recovery requested '$ReviewId'."}
    $effectiveReviewId=[string]($state.review_id)
    $record=Read-AidosReviewRecord $ProjectRoot $effectiveReviewId
    if($record.review_id -ne $effectiveReviewId){throw "Review record mismatch: state has '$effectiveReviewId' but record has '$($record.review_id)'."}
    if($record.transport_state -ne 'PUBLISHED' -and $record.transport_state -ne 'DECIDED'){throw "Review recovery requires a published legacy review, not '$($record.transport_state)'."}
    if($record.response -or $record.response_sha256 -or $record.decision){throw 'Review recovery requires a legacy review without a recorded response or decision.'}
    $resultPath=Join-Path $ProjectRoot ([string]($state.terminal_result))
    $result=Read-AidosJson $resultPath
    $validationPath=Join-Path $ProjectRoot ([string]($result.validation_path))
    $validation=Read-AidosJson $validationPath
    if($validation.status-ne'PASS'){throw "Review package recovery requires PASS validation, not '$($validation.status)'."}
    $packageRoot=Get-AidosReviewPackageRoot $ProjectRoot $effectiveReviewId
    $manifestPath=Get-AidosReviewManifestPath $ProjectRoot $effectiveReviewId
    $recordPath=Get-AidosReviewRecordPath $ProjectRoot $effectiveReviewId
    $assignmentPath=Get-AidosReviewAssignmentPath $ProjectRoot $effectiveReviewId
    if(-not(Test-Path -LiteralPath $packageRoot -PathType Container)){throw "Review package recovery requires an existing review package root: $packageRoot"}
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Review package recovery requires an existing manifest: $manifestPath"}
    $manifest=Read-AidosJson $manifestPath
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Test-AidosReviewBinding $ProjectRoot $record $manifest|Out-Null
    if($manifestSha-ne[string]$record.package_manifest_sha256){throw 'Review manifest hash mismatch.'}
    $packagePath=[IO.Path]::GetRelativePath($ProjectRoot,$packageRoot)
    $legacyAssignmentPath=Get-AidosReviewLegacyAssignmentPath $ProjectRoot $effectiveReviewId
    $assignmentExists=Test-Path -LiteralPath $assignmentPath -PathType Leaf
    $legacyExists=Test-Path -LiteralPath $legacyAssignmentPath -PathType Leaf
    $assignment=$null
    $wroteCanonical=$false
    if($assignmentExists){
        $assignment=Read-AidosJson $assignmentPath
        Test-AidosReviewAssignmentBinding $ProjectRoot $assignment $manifest $manifestSha $reviewerBinding|Out-Null
        $assignmentIntegrity=Test-AidosReviewAssignmentIntegrity $ProjectRoot $effectiveReviewId $record
        $assignmentSha=[string]$assignmentIntegrity.assignment_sha256
        if([string]($record.assignment_sha256) -and [string]($record.assignment_sha256) -ne $assignmentSha){throw 'Review assignment hash mismatch.'}
        if([string]($record.assignment_path) -eq [string]$assignmentIntegrity.assignment_path -and [string]($record.assignment_sha256) -eq $assignmentSha){
            return [pscustomobject]@{review_id=$effectiveReviewId;package_path=$packagePath;manifest_path=[IO.Path]::GetRelativePath($ProjectRoot,$manifestPath);manifest_sha256=$manifestSha;assignment_path=$assignmentIntegrity.assignment_path;assignment_sha256=$assignmentSha;record_path=[IO.Path]::GetRelativePath($ProjectRoot,$recordPath);reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity;recovered=$true;idempotent=$true}
        }
    } elseif($legacyExists) {
        $assignment=Read-AidosJson $legacyAssignmentPath
        Test-AidosReviewAssignmentBinding $ProjectRoot $assignment $manifest $manifestSha $reviewerBinding|Out-Null
        if($PSCmdlet.ShouldProcess($assignmentPath,'Write canonical review assignment')){Write-AidosReviewAssignmentAtomic $ProjectRoot $effectiveReviewId $assignment}
        $wroteCanonical=$true
    } else {
        $assignment=New-AidosReviewAssignmentObject $ProjectRoot $effectiveReviewId $execution $state $result $packagePath ([IO.Path]::GetRelativePath($ProjectRoot,$manifestPath)) $manifestSha (Get-AidosReviewEvidenceRefs $ProjectRoot $execution $state $result $validation $ExecutionPath) $reviewerBinding
        if($PSCmdlet.ShouldProcess($assignmentPath,'Write canonical review assignment')){Write-AidosReviewAssignmentAtomic $ProjectRoot $effectiveReviewId $assignment}
        $wroteCanonical=$true
    }
    $assignmentSha=(Get-FileHash -LiteralPath $assignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace([string]($record.assignment_sha256)) -or [string]($record.assignment_sha256) -eq [string]$assignmentSha -or $wroteCanonical){
        $updated=[ordered]@{}
        foreach($p in $record.PSObject.Properties){$updated[$p.Name]=$p.Value}
        $updated.assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath)
        $updated.assignment=$assignment
        $updated.assignment_sha256=$assignmentSha
        $updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $ProjectRoot $effectiveReviewId $updated
        $record=[pscustomobject]$updated
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_ASSIGNMENT_RECOVERED' 'BRIDGE' @{review_id=$effectiveReviewId;assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);assignment_sha256=$assignmentSha;manifest_sha256=$manifestSha;reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity;recovered_from='LEGACY_PUBLISH'}
    } else {
        throw 'Review assignment hash mismatch.'
    }
    [pscustomobject]@{review_id=$effectiveReviewId;package_path=$packagePath;manifest_path=[IO.Path]::GetRelativePath($ProjectRoot,$manifestPath);manifest_sha256=$manifestSha;assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);assignment_sha256=$assignmentSha;record_path=[IO.Path]::GetRelativePath($ProjectRoot,$recordPath);reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity;recovered=$true}
}
function Repair-AidosLegacyReviewAssignmentCorrelation {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot,[string]$ExecutionPath,[string]$ReviewId)
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $ExecutionPath=Resolve-AidosFileSystemPath $ExecutionPath
    $execution=Read-AidosJson $ExecutionPath
    $state=Get-AidosState $ProjectRoot
    $reviewerBinding=Get-AidosReviewReviewerBinding $ProjectRoot
    $null=Assert-AidosExecutionBinding $ProjectRoot $execution
    if($state.state-ne'GPT_REVIEWING'){throw "Legacy review assignment correlation repair requires GPT_REVIEWING, not '$($state.state)'."}
    if([string]::IsNullOrWhiteSpace([string]($state.review_id))){throw 'GPT_REVIEWING review requires an existing review_id.'}
    if(-not[string]::IsNullOrWhiteSpace($ReviewId) -and [string]($state.review_id) -ne [string]$ReviewId){throw "Review ID mismatch: state has '$($state.review_id)' but repair requested '$ReviewId'."}
    $effectiveReviewId=[string]($state.review_id)
    $record=Read-AidosReviewRecord $ProjectRoot $effectiveReviewId
    if($record.review_id -ne $effectiveReviewId){throw "Review record mismatch: state has '$effectiveReviewId' but record has '$($record.review_id)'."}
    if($record.transport_state -eq 'CONSUMED' -or $record.transport_state -eq 'CLEANED' -or $record.consumed_at -or $record.consume_ack -or $record.decision -or $record.response_accepted_at){throw 'Legacy review assignment correlation repair requires an unconsumed review without a durable decision.'}
    $resultPath=Join-Path $ProjectRoot ([string]($state.terminal_result))
    $result=Read-AidosJson $resultPath
    $validationPath=Join-Path $ProjectRoot ([string]($result.validation_path))
    $validation=Read-AidosJson $validationPath
    if($validation.status-ne'PASS'){throw "Legacy review assignment correlation repair requires PASS validation, not '$($validation.status)'."}
    $packageRoot=Get-AidosReviewPackageRoot $ProjectRoot $effectiveReviewId
    $manifestPath=Get-AidosReviewManifestPath $ProjectRoot $effectiveReviewId
    $recordPath=Get-AidosReviewRecordPath $ProjectRoot $effectiveReviewId
    $assignmentPath=Get-AidosReviewAssignmentPath $ProjectRoot $effectiveReviewId
    if(-not(Test-Path -LiteralPath $packageRoot -PathType Container)){throw "Legacy review assignment correlation repair requires an existing review package root: $packageRoot"}
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Legacy review assignment correlation repair requires an existing manifest: $manifestPath"}
    if(-not(Test-Path -LiteralPath $assignmentPath -PathType Leaf)){throw "Legacy review assignment correlation repair requires an existing canonical assignment: $assignmentPath"}
    $manifest=Read-AidosJson $manifestPath
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Test-AidosReviewBinding $ProjectRoot $record $manifest|Out-Null
    if([string]$record.package_manifest_sha256 -ne $manifestSha){throw 'Review manifest hash mismatch.'}
    $assignment=Read-AidosJson $assignmentPath
    Test-AidosReviewAssignmentBinding $ProjectRoot $assignment $manifest $manifestSha $reviewerBinding|Out-Null
    $expectedEvidenceRefs=Get-AidosReviewEvidenceRefs $ProjectRoot $execution $state $result $validation $ExecutionPath
    Test-AidosReviewEvidenceRefsMatch -Actual @($assignment.evidence_refs) -Expected @($expectedEvidenceRefs)
    if([string]$record.assignment_path -ne [IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath)){throw 'Review assignment path is stale or mismatched.'}
    if([string]$record.package_manifest_path -ne [IO.Path]::GetRelativePath($ProjectRoot,$manifestPath)){throw 'Review manifest path is stale or mismatched.'}
    Test-AidosReviewEvidenceRefsMatch -Actual @($record.evidence_refs) -Expected @($expectedEvidenceRefs)
    if($record.assignment){Test-AidosReviewAssignmentEquivalent $record.assignment $assignment}
    $actualAssignmentSha=(Get-FileHash -LiteralPath $assignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if([string]$record.assignment_sha256 -eq $actualAssignmentSha){
        return [pscustomobject]@{review_id=$effectiveReviewId;package_path=[IO.Path]::GetRelativePath($ProjectRoot,$packageRoot);manifest_path=[IO.Path]::GetRelativePath($ProjectRoot,$manifestPath);manifest_sha256=$manifestSha;assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);assignment_sha256=$actualAssignmentSha;record_path=[IO.Path]::GetRelativePath($ProjectRoot,$recordPath);reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity;recovered=$true;idempotent=$true}
    }
    if($PSCmdlet.ShouldProcess($recordPath,'Repair legacy review assignment correlation')){
        $updated=[ordered]@{}
        foreach($p in $record.PSObject.Properties){$updated[$p.Name]=$p.Value}
        $oldSha=[string]$record.assignment_sha256
        $updated.assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath)
        $updated.assignment=$assignment
        $updated.assignment_sha256=$actualAssignmentSha
        $updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $ProjectRoot $effectiveReviewId $updated
        $record=[pscustomobject]$updated
        $null=Add-AidosEvent $ProjectRoot 'LEGACY_REVIEW_ASSIGNMENT_CORRELATION_REPAIRED' 'BRIDGE' @{review_id=$effectiveReviewId;assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);old_assignment_sha256=$oldSha;new_assignment_sha256=$actualAssignmentSha;manifest_sha256=$manifestSha;reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity}
    }
    [pscustomobject]@{review_id=$effectiveReviewId;package_path=[IO.Path]::GetRelativePath($ProjectRoot,$packageRoot);manifest_path=[IO.Path]::GetRelativePath($ProjectRoot,$manifestPath);manifest_sha256=$manifestSha;assignment_path=[IO.Path]::GetRelativePath($ProjectRoot,$assignmentPath);assignment_sha256=$actualAssignmentSha;record_path=[IO.Path]::GetRelativePath($ProjectRoot,$recordPath);reviewer_role=$reviewerBinding.role;reviewer_identity=$reviewerBinding.identity;recovered=$true;idempotent=$false}
}
function Set-AidosReviewDecision {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId,[Parameter(Mandatory)][ValidateSet('PASS','REPAIR','BLOCKER','DISCOVERY_REFRESH_REQUIRED','WAITING_INTERACTIVE_SESSION')][string]$Outcome,[string]$Reason='',[ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor='WORKER_AGENT')
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $state=Get-AidosState $ProjectRoot
    if($state.review_id-ne$ReviewId){throw "Review ID mismatch: state has '$($state.review_id)' but decision targets '$ReviewId'."}
    if($state.state-ne'GPT_REVIEWING'){throw "Review decision requires GPT_REVIEWING, not '$($state.state)'."}
    $record=Read-AidosReviewRecord $ProjectRoot $ReviewId
    $manifestPath=Join-Path $ProjectRoot ([string]($record.package_manifest_path))
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Review manifest not found: $manifestPath"}
    $manifest=Read-AidosJson $manifestPath
    Test-AidosReviewBinding $ProjectRoot $record $manifest|Out-Null
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($manifestSha-ne[string]$record.package_manifest_sha256){throw 'Review manifest hash mismatch.'}
    if($record.transport_state-ne'PUBLISHED' -and $record.transport_state-ne'DECIDED'){throw "Review transport is not publishable for decision (state: $($record.transport_state))."}
    $targetState=Resolve-AidosReviewDecisionTargetState $Outcome
    if($PSCmdlet.ShouldProcess((Join-Path $ProjectRoot '.aidos/STATE.json'),"Record review decision $Outcome -> $targetState")){
        $updated=[ordered]@{}
        foreach($p in $record.PSObject.Properties){$updated[$p.Name]=$p.Value}
        $updated.transport_state='DECIDED'
        $updated.decision=[ordered]@{outcome=$Outcome;target_state=$targetState;reason=$Reason;decided_by=$Actor;decided_at=[DateTimeOffset]::UtcNow.ToString('o')}
        $updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $ProjectRoot $ReviewId $updated
        $null=Set-AidosState $ProjectRoot $targetState $Actor @{review_id=$null}
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_DECISION_RECORDED' $Actor @{review_id=$ReviewId;outcome=$Outcome;target_state=$targetState;reason=$Reason;package_manifest_sha256=$manifestSha}
        [pscustomobject]$updated
    }
}
function Confirm-AidosReviewConsumed {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId,[ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor='WORKER_AGENT')
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $record=Read-AidosReviewRecord $ProjectRoot $ReviewId
    if($record.transport_state-ne'DECIDED' -and $record.transport_state-ne'CONSUMED'){throw "Review consumption requires a recorded decision, not '$($record.transport_state)'."}
    if($PSCmdlet.ShouldProcess((Join-Path (Get-AidosReviewRoot $ProjectRoot) $ReviewId),'Confirm AIDOS review consumption')){
        $updated=[ordered]@{}
        foreach($p in $record.PSObject.Properties){$updated[$p.Name]=$p.Value}
        $updated.transport_state='CONSUMED'
        $updated.consumed_at=[DateTimeOffset]::UtcNow.ToString('o')
        $updated.consumed_by=$Actor
        $updated.consume_ack=[ordered]@{acknowledged_at=$updated.consumed_at;acknowledged_by=$Actor;review_id=$ReviewId;package_path=$updated.package_path;manifest_sha256=$updated.package_manifest_sha256}
        $updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $ProjectRoot $ReviewId $updated
        $ackPath=Get-AidosReviewAckPath $ProjectRoot $ReviewId
        Write-AidosJsonAtomic $ackPath $updated.consume_ack
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_PACKAGE_CONSUMED' $Actor @{review_id=$ReviewId;package_path=$updated.package_path;manifest_sha256=$updated.package_manifest_sha256}
        [pscustomobject]$updated
    }
}
function Invoke-AidosReviewCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot,[Parameter(Mandatory)][string]$ReviewId,[ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor='BRIDGE')
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $record=Read-AidosReviewRecord $ProjectRoot $ReviewId
    if($record.transport_state-ne'CONSUMED'){throw "Review cleanup requires CONSUMED transport state, not '$($record.transport_state)'."}
    $packagePath=Join-Path $ProjectRoot ([string]($record.package_path))
    if($PSCmdlet.ShouldProcess($packagePath,'Cleanup AIDOS review package')){
        if(Test-Path -LiteralPath $packagePath){Remove-Item -LiteralPath $packagePath -Recurse -Force}
        $updated=[ordered]@{}
        foreach($p in $record.PSObject.Properties){$updated[$p.Name]=$p.Value}
        $updated.transport_state='CLEANED'
        $updated.cleaned_at=[DateTimeOffset]::UtcNow.ToString('o')
        $updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $ProjectRoot $ReviewId $updated
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_CLEANUP_CONFIRMED' $Actor @{review_id=$ReviewId;package_path=$record.package_path}
        [pscustomobject]$updated
    }
}
function Test-AidosReviewAbandonmentClosure {
    param([string]$ProjectRoot,$Record)
    if([string]$Record.transport_state -ne 'ABANDONED'){throw 'Review transport is not abandoned.'}
    $closure=$Record.abandonment
    if(-not $closure){throw 'Abandoned review is missing its durable abandonment closure.'}
    foreach($name in @('review_id','project_id','definition_id','execution_id','revision','reason','abandoned_at','abandoned_by','package_manifest_sha256')){
        if([string]::IsNullOrWhiteSpace([string]$closure.$name)){throw "Abandoned review closure is missing '$name'."}
    }
    foreach($name in @('review_id','project_id','definition_id','execution_id','revision')){
        if([string]$closure.$name -ne [string]$Record.$name){throw "Abandoned review closure '$name' is stale or mismatched."}
    }
    if([string]$closure.package_manifest_sha256 -ne [string]$Record.package_manifest_sha256){throw 'Abandoned review closure manifest hash is stale or mismatched.'}
    $manifestPath=Join-Path $ProjectRoot ([string]$Record.package_manifest_path)
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Abandoned review manifest is missing: $manifestPath"}
    $manifest=Read-AidosJson $manifestPath
    Test-AidosReviewBinding $ProjectRoot $Record $manifest|Out-Null
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($manifestSha -ne [string]$Record.package_manifest_sha256){throw 'Abandoned review manifest hash mismatch.'}
    [pscustomobject]@{Valid=$true;manifest_sha256=$manifestSha}
}
function Abandon-AidosReview {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ReviewId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
        [ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor='WORKER_AGENT'
    )
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    Test-AidosProjectBinding $ProjectRoot|Out-Null
    $state=Get-AidosState $ProjectRoot
    if([string]$state.review_id -eq $ReviewId){throw 'An active project review cannot be abandoned; first reconcile it to an explicit non-active recovery state.'}
    $record=Read-AidosReviewRecord $ProjectRoot $ReviewId
    if([string]$record.review_id -ne $ReviewId){throw "Review record identity mismatch: requested '$ReviewId' but record has '$($record.review_id)'."}
    $profile=Get-AidosProjectProfile $ProjectRoot
    if([string]$record.project_id -ne [string]$profile.project_id){throw 'Review project identity is stale or mismatched.'}
    if([string]::IsNullOrWhiteSpace([string]$record.definition_id) -or [string]::IsNullOrWhiteSpace([string]$record.execution_id) -or [int]$record.revision -lt 1){throw 'Review record is missing exact definition/execution/revision binding.'}
    if($record.response_accepted_at -or $record.decision -or $record.consume_ack -or $record.consumed_at -or $record.cleaned_at -or $record.transport_state -in @('DECIDED','CONSUMED','CLEANED')){throw 'Review abandonment requires no accepted durable response, decision, consume acknowledgement, or cleanup.'}
    if($record.response -or $record.response_sha256){throw 'Review abandonment requires no bridge-persisted review response.'}
    if($record.transport_state -eq 'ABANDONED'){
        Test-AidosReviewAbandonmentClosure $ProjectRoot $record|Out-Null
        if([string]$record.abandonment.reason -ne $Reason){throw 'Conflicting review abandonment reason detected for this review.'}
        return [pscustomobject]@{review_id=$ReviewId;transport_state='ABANDONED';idempotent=$true;abandonment=$record.abandonment}
    }
    if($record.transport_state -ne 'PUBLISHED'){throw "Review abandonment requires PUBLISHED transport state, not '$($record.transport_state)'."}
    $manifestPath=Join-Path $ProjectRoot ([string]$record.package_manifest_path)
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw "Review manifest not found: $manifestPath"}
    $manifest=Read-AidosJson $manifestPath
    Test-AidosReviewBinding $ProjectRoot $record $manifest|Out-Null
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($manifestSha -ne [string]$record.package_manifest_sha256){throw 'Review manifest hash mismatch.'}
    if($PSCmdlet.ShouldProcess((Get-AidosReviewRecordPath $ProjectRoot $ReviewId),'Record explicit review abandonment')){
        $updated=[ordered]@{}
        foreach($p in $record.PSObject.Properties){$updated[$p.Name]=$p.Value}
        $now=[DateTimeOffset]::UtcNow.ToString('o')
        $updated.transport_state='ABANDONED'
        $updated.abandonment=[ordered]@{
            reason=$Reason
            abandoned_at=$now
            abandoned_by=$Actor
            review_id=[string]$record.review_id
            project_id=[string]$record.project_id
            definition_id=[string]$record.definition_id
            definition_version=[int]$record.definition_version
            execution_id=[string]$record.execution_id
            revision=[int]$record.revision
            package_manifest_sha256=$manifestSha
            assignment_sha256=[string]$record.assignment_sha256
        }
        $updated.updated_at=$now
        Write-AidosReviewRecordAtomic $ProjectRoot $ReviewId $updated
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_TRANSPORT_ABANDONED' $Actor @{review_id=$ReviewId;project_id=$updated.project_id;definition_id=$updated.definition_id;definition_version=$updated.definition_version;execution_id=$updated.execution_id;revision=$updated.revision;reason=$Reason;package_manifest_sha256=$manifestSha;assignment_sha256=$updated.assignment_sha256}
        [pscustomobject]@{review_id=$ReviewId;transport_state='ABANDONED';idempotent=$false;abandonment=$updated.abandonment}
    }
}
function Test-AidosReviewResponseBinding { param([string]$ProjectRoot,$Response,$Assignment,$Manifest,$Record,$ResponseSha256)
    $binding=@(
        @{name='review_id';actual=[string]$Response.review_id;expected=[string]$Assignment.review_id},
        @{name='project_id';actual=[string]$Response.project_id;expected=[string]$Assignment.project_id},
        @{name='project_root';actual=[string]$Response.project_root;expected=[string]$Assignment.project_root},
        @{name='project_mode';actual=[string]$Response.project_mode;expected=[string]$Assignment.project_mode},
        @{name='definition_id';actual=[string]$Response.definition_id;expected=[string]$Assignment.definition_id},
        @{name='definition_version';actual=[int]$Response.definition_version;expected=[int]$Assignment.definition_version},
        @{name='execution_id';actual=[string]$Response.execution_id;expected=[string]$Assignment.execution_id},
        @{name='revision';actual=[int]$Response.revision;expected=[int]$Assignment.revision},
        @{name='reviewer_role';actual=[string]$Response.reviewer_role;expected=[string]$Assignment.reviewer_role},
        @{name='reviewer_identity';actual=[string]$Response.reviewer_identity;expected=[string]$Assignment.reviewer_identity},
        @{name='assignment_sha256';actual=[string]$Response.assignment_sha256;expected=[string]$Record.assignment_sha256},
        @{name='package_manifest_sha256';actual=[string]$Response.package_manifest_sha256;expected=[string]$Assignment.package_manifest_sha256}
    )
    foreach($item in $binding){if($item.actual-ne$item.expected){throw "Review response binding '$($item.name)' is stale or mismatched."}}
    if($Response.outcome -notin @('PASS','REPAIR','BLOCKER','DISCOVERY_REFRESH_REQUIRED','WAITING_INTERACTIVE_SESSION')){throw "Unsupported review response outcome '$($Response.outcome)'."}
    if([string]::IsNullOrWhiteSpace([string]$Response.reason)){throw 'Review response reason is required.'}
    if([string]::IsNullOrWhiteSpace([string]$Response.responded_at)){throw 'Review response responded_at is required.'}
    $allowedEvidence=@{}
    foreach($ref in @($Assignment.evidence_refs)){$allowedEvidence[[string]$ref.path]=[string]$ref.sha256}
    $recordEvidence=@{}
    foreach($ref in @($Record.evidence_refs)){$recordEvidence[[string]$ref.path]=[string]$ref.sha256}
    if(-not@($Response.evidence_refs).Count){throw 'Review response must include evidence refs.'}
    foreach($ref in @($Response.evidence_refs)){
        if(-not$allowedEvidence.ContainsKey([string]$ref.path)){throw "Review response evidence ref '$([string]$ref.path)' is not bound by the assignment."}
        if([string]$allowedEvidence[[string]$ref.path] -ne [string]$ref.sha256){throw "Review response evidence ref hash mismatch for '$([string]$ref.path)'."}
        $source=Join-Path $ProjectRoot ([string]$ref.path)
        if(Test-Path -LiteralPath $source -PathType Leaf){
            $actualHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
            if($actualHash-ne[string]$ref.sha256){throw "Review response evidence hash mismatch for '$([string]$ref.path)'."}
        } elseif($Record.transport_state -eq 'CLEANED'){
            if(-not$recordEvidence.ContainsKey([string]$ref.path)){throw "Review response evidence not found in durable record: $([string]$ref.path)"}
            if([string]$recordEvidence[[string]$ref.path] -ne [string]$ref.sha256){throw "Review response evidence hash mismatch in durable record for '$([string]$ref.path)'."}
        } else {
            throw "Review response evidence not found: $source"
        }
    }
    if($Record.assignment_sha256 -and [string]($Record.assignment_sha256) -ne [string]$Response.assignment_sha256){throw 'Review assignment hash mismatch.'}
    if($Record.package_manifest_sha256 -and [string]($Record.package_manifest_sha256) -ne [string]$Response.package_manifest_sha256){throw 'Review package manifest hash mismatch.'}
    $reviewerBinding=Get-AidosReviewReviewerBinding $ProjectRoot
    if([string]$Response.reviewer_identity -ne [string]$reviewerBinding.identity){throw "Review response reviewer identity '$($Response.reviewer_identity)' is not bridge-bound to '$($reviewerBinding.identity)'."}
    if([string]$Response.reviewer_role -ne [string]$reviewerBinding.role){throw "Review response reviewer role '$($Response.reviewer_role)' is not bridge-bound to '$($reviewerBinding.role)'."}
    if($Record.response_sha256 -and [string]($Record.response_sha256) -ne [string]$ResponseSha256){throw 'Conflicting review response detected for this review.'}
    [pscustomobject]@{Valid=$true}
}
function Invoke-AidosReviewConsumer {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ProjectRoot,[string]$ResponseJson,[string]$ResponsePath,[ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor='WORKER_AGENT')
    $ProjectRoot=Resolve-AidosFileSystemPath $ProjectRoot
    $responseText=if($ResponsePath){Get-Content -LiteralPath $ResponsePath -Raw -Encoding UTF8}else{$ResponseJson}
    if([string]::IsNullOrWhiteSpace([string]$responseText)){throw 'Review response JSON is required.'}
    $responseSha=Get-AidosTextSha256 $responseText
    $response=$responseText|ConvertFrom-Json -Depth 100
    $reviewId=[string]$response.review_id
    $record=Read-AidosReviewRecord $ProjectRoot $reviewId
    if($record.response_sha256){
        if([string]($record.response_sha256)-ne$responseSha){throw 'Conflicting review response detected for this review.'}
        if([string]($record.response.outcome) -ne [string]$response.outcome -or [string]($record.response.reason) -ne [string]$response.reason){throw 'Conflicting review response payload detected for this review.'}
        if($record.response_accepted_at -and $record.transport_state -eq 'CLEANED'){return [pscustomobject]@{decision=$record.decision;consumed=$record;review_id=$reviewId;response_sha256=$responseSha;final_record=$record}}
    } else {
        $assignmentPath=if($record.assignment_path){Resolve-AidosRecordBoundPath $ProjectRoot ([string]($record.assignment_path))}else{Join-Path (Join-Path $ProjectRoot ([string]($record.package_path))) 'REVIEW_ASSIGNMENT.json'}
        $legacyAssignmentPath=Get-AidosReviewLegacyAssignmentPath $ProjectRoot $reviewId
        $assignment=if(Test-Path -LiteralPath $assignmentPath -PathType Leaf){Read-AidosJson $assignmentPath}elseif(Test-Path -LiteralPath $legacyAssignmentPath -PathType Leaf){Read-AidosJson $legacyAssignmentPath}elseif($record.assignment){$record.assignment}else{throw "Review assignment not found and no durable assignment record is available for '$reviewId'."}
        if((Test-Path -LiteralPath $assignmentPath -PathType Leaf) -or (Test-Path -LiteralPath $legacyAssignmentPath -PathType Leaf)){
            $assignmentIntegrity=Test-AidosReviewAssignmentIntegrity $ProjectRoot $reviewId $record
            if([string]$record.assignment_sha256 -and [string]($assignmentIntegrity.assignment_sha256) -ne [string]$record.assignment_sha256){throw 'Review assignment hash mismatch.'}
        }
        $manifestPath=Join-Path $ProjectRoot ([string]($record.package_manifest_path))
        if(Test-Path -LiteralPath $manifestPath -PathType Leaf){
            $manifest=Read-AidosJson $manifestPath
            $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        } else {
            if(-not $record.package_manifest_sha256){throw "Review manifest not found and no durable manifest hash is available for '$reviewId'."}
            $manifest=[ordered]@{
                schema_version='0.1'
                package_type='REVIEW_PACKAGE'
                review_id=[string]$record.review_id
                project_id=[string]$record.project_id
                project_root=[string]$record.project_root
                definition_id=[string]$record.definition_id
                definition_version=[int]$record.definition_version
                execution_id=[string]$record.execution_id
                revision=[int]$record.revision
            }
            $manifestSha=[string]$record.package_manifest_sha256
        }
        Test-AidosReviewAssignmentBinding $ProjectRoot $assignment $manifest $manifestSha (Get-AidosReviewReviewerBinding $ProjectRoot)|Out-Null
        Test-AidosReviewResponseBinding $ProjectRoot $response $assignment $manifest $record $responseSha|Out-Null
        $updated=[ordered]@{}
        foreach($p in $record.PSObject.Properties){$updated[$p.Name]=$p.Value}
        $updated.response=$response
        $updated.response_sha256=$responseSha
        $updated.response_received_at=[DateTimeOffset]::UtcNow.ToString('o')
        $updated.response_received_by=$response.reviewer_identity
        $updated.response_accepted_at=[DateTimeOffset]::UtcNow.ToString('o')
        $updated.response_accepted_by=$Actor
        $updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosReviewRecordAtomic $ProjectRoot $reviewId $updated
        $record=[pscustomobject]$updated
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_RESPONSE_RECEIVED' $Actor @{review_id=$reviewId;response_sha256=$responseSha;assignment_sha256=[string]$record.assignment_sha256;reviewer_identity=$response.reviewer_identity;outcome=$response.outcome}
        $null=Add-AidosEvent $ProjectRoot 'REVIEW_RESPONSE_ACCEPTED' $Actor @{review_id=$reviewId;response_sha256=$responseSha;outcome=$response.outcome;target_state=(Resolve-AidosReviewDecisionTargetState $response.outcome);reviewer_identity=$response.reviewer_identity}
    }
    $targetState=Resolve-AidosReviewDecisionTargetState $response.outcome
    if(-not $record.decision){
        $decision=Set-AidosReviewDecision $ProjectRoot $reviewId $response.outcome $response.reason -Actor $Actor
    } else {
        $decision=$record.decision
        if([string]$decision.outcome -ne [string]$response.outcome -or [string]$decision.target_state -ne [string]$targetState){throw 'Conflicting review decision detected for this review.'}
    }
    $freshRecord=Read-AidosReviewRecord $ProjectRoot $reviewId
    $consumed=if($freshRecord.transport_state -in @('CONSUMED','CLEANED')){$freshRecord}else{Confirm-AidosReviewConsumed $ProjectRoot $reviewId -Actor $Actor}
    if($consumed.transport_state -ne 'CLEANED'){Invoke-AidosReviewCleanup $ProjectRoot $reviewId -Actor 'BRIDGE'|Out-Null}
    $finalRecord=Read-AidosReviewRecord $ProjectRoot $reviewId
    [pscustomobject]@{decision=$decision;consumed=$consumed;review_id=$reviewId;response_sha256=$responseSha;final_record=$finalRecord}
}
function Invoke-AidosReviewReconciliation {
    [CmdletBinding()]
    param([string]$ProjectRoot)
    Test-AidosProjectBinding $ProjectRoot|Out-Null
    Invoke-AidosExclusive $ProjectRoot {
        $reviewRoot=Get-AidosReviewRoot $ProjectRoot
        if(-not(Test-Path -LiteralPath $reviewRoot)){return [pscustomobject]@{status='CLEAN';review_id=$null}}
        $state=Get-AidosState $ProjectRoot
        $records=@()
        foreach($dir in (Get-ChildItem -LiteralPath $reviewRoot -Directory -ErrorAction SilentlyContinue)){
            $recordPath=Join-Path $dir.FullName 'REVIEW.json'
            if(Test-Path -LiteralPath $recordPath -PathType Leaf){
                try{$records+=Read-AidosReviewRecord $ProjectRoot $dir.Name}catch{throw "Invalid review record JSON in '$recordPath'."}
            }
        }
        if(-not$records){
            if($state.review_id){$o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o;Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$state.review_id;reason='REVIEW_RECORD_MISSING';next_state='RECOVERY_REQUIRED'});return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$state.review_id}}
            return [pscustomobject]@{status='CLEAN';review_id=$null}
        }
        foreach($abandoned in @($records|Where-Object transport_state -eq 'ABANDONED')){
            try{Test-AidosReviewAbandonmentClosure $ProjectRoot $abandoned|Out-Null}catch{
                $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$abandoned.review_id;reason=$_.Exception.Message;next_state='RECOVERY_REQUIRED'})
                return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$abandoned.review_id}
            }
        }
        $nonCleaned=@($records|Where-Object {$_.transport_state -notin @('CLEANED','ABANDONED')})
        if($state.review_id){
            $active=@($nonCleaned|Where-Object review_id -eq $state.review_id|Sort-Object updated_at -Descending|Select-Object -First 1)
            if(-not$active){
                $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$state.review_id;reason='REVIEW_ID_RECORD_MISSING';next_state='RECOVERY_REQUIRED'})
                return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$state.review_id}
            }
        }else{
            $active=@($nonCleaned|Sort-Object updated_at -Descending|Select-Object -First 1)
            if(-not$active){return [pscustomobject]@{status='CLEAN';review_id=$null}}
        }
        $active=$active[0]
        $manifestPath=Join-Path $ProjectRoot ([string]($active.package_manifest_path))
        $packagePath=Join-Path $ProjectRoot ([string]($active.package_path))
        if($state.review_id -and [string]($state.review_id) -ne [string]($active.review_id)){
            $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
            Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$active.review_id;reason='STATE_REVIEW_ID_MISMATCH';next_state='RECOVERY_REQUIRED'})
            return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$active.review_id}
        }
        if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){
            if($active.transport_state -in @('PUBLISHED','DECIDED')){
                $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$active.review_id;reason='MANIFEST_MISSING';next_state='RECOVERY_REQUIRED'})
                return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$active.review_id}
            }
            return [pscustomobject]@{status='CLEAN';review_id=$active.review_id}
        }
        $manifest=Read-AidosJson $manifestPath
        try{Test-AidosReviewBinding $ProjectRoot $active $manifest|Out-Null}catch{
            $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
            Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$active.review_id;reason=$_.Exception.Message;next_state='RECOVERY_REQUIRED'})
            return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$active.review_id}
        }
        $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($manifestSha-ne[string]($active.package_manifest_sha256)){
            $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
            Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$active.review_id;reason='MANIFEST_HASH_MISMATCH';next_state='RECOVERY_REQUIRED'})
            return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$active.review_id}
        }
        $assignmentPath=if($active.assignment_path){Resolve-AidosRecordBoundPath $ProjectRoot ([string]($active.assignment_path))}else{Join-Path (Join-Path $ProjectRoot ([string]($active.package_path))) 'REVIEW_ASSIGNMENT.json'}
        $legacyAssignmentPath=Get-AidosReviewLegacyAssignmentPath $ProjectRoot $active.review_id
        if($active.response -and -not $active.decision){
            if(-not(Test-Path -LiteralPath $assignmentPath -PathType Leaf) -and -not(Test-Path -LiteralPath $legacyAssignmentPath -PathType Leaf)){
                $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECOVERY_REQUIRED' 'BRIDGE' @{review_id=$active.review_id;reason='ASSIGNMENT_MISSING';next_state='RECOVERY_REQUIRED'})
                return [pscustomobject]@{status='RECOVERY_REQUIRED';review_id=$active.review_id}
            }
            $assignment=if(Test-Path -LiteralPath $assignmentPath -PathType Leaf){Read-AidosJson $assignmentPath}else{Read-AidosJson $legacyAssignmentPath}
            if((Test-Path -LiteralPath $assignmentPath -PathType Leaf) -or (Test-Path -LiteralPath $legacyAssignmentPath -PathType Leaf)){
                $assignmentIntegrity=Test-AidosReviewAssignmentIntegrity $ProjectRoot $active.review_id $active
                if([string]$active.assignment_sha256 -and [string]($assignmentIntegrity.assignment_sha256) -ne [string]$active.assignment_sha256){throw 'Review assignment hash mismatch.'}
            }
            Test-AidosReviewAssignmentBinding $ProjectRoot $assignment $manifest $manifestSha (Get-AidosReviewReviewerBinding $ProjectRoot)|Out-Null
            Test-AidosReviewResponseBinding $ProjectRoot $active.response $assignment $manifest $active ([string]($active.response_sha256))|Out-Null
            if(-not $active.response_accepted_at){
                $updated=[ordered]@{};foreach($p in $active.PSObject.Properties){$updated[$p.Name]=$p.Value};$updated.response_accepted_at=[DateTimeOffset]::UtcNow.ToString('o');$updated.response_accepted_by='BRIDGE';$updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosReviewRecordAtomic $ProjectRoot $active.review_id $updated
                $active=[pscustomobject]$updated
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RESPONSE_ACCEPTED' 'BRIDGE' @{review_id=$active.review_id;response_sha256=$active.response_sha256;outcome=$active.response.outcome;target_state=(Resolve-AidosReviewDecisionTargetState $active.response.outcome);reviewer_identity=$active.response.reviewer_identity})
            }
            $decision=Set-AidosReviewDecision $ProjectRoot $active.review_id $active.response.outcome $active.response.reason -Actor 'BRIDGE'
            $active=Read-AidosReviewRecord $ProjectRoot $active.review_id
        }
        if($active.decision){
            $target=[string]$active.decision.target_state
            if($state.state-ne$target -or [string]($state.review_id) -eq [string]($active.review_id)){
                $o=[ordered]@{};foreach($p in $state.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state=$target;$o.review_id=$null;$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_RECONCILED' 'BRIDGE' @{review_id=$active.review_id;target_state=$target;action='STATE_APPLIED'})
                $state=[pscustomobject]$o
            }
            if($active.transport_state-ne'CONSUMED' -and $active.transport_state-ne'CLEANED'){
                $updated=[ordered]@{};foreach($p in $active.PSObject.Properties){$updated[$p.Name]=$p.Value};$updated.transport_state='CONSUMED';$updated.consumed_at=[DateTimeOffset]::UtcNow.ToString('o');$updated.consumed_by='BRIDGE';$updated.consume_ack=[ordered]@{acknowledged_at=$updated.consumed_at;acknowledged_by='BRIDGE';review_id=$active.review_id;package_path=$updated.package_path;manifest_sha256=$updated.package_manifest_sha256};$updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosReviewRecordAtomic $ProjectRoot $active.review_id $updated
                Write-AidosJsonAtomic (Get-AidosReviewAckPath $ProjectRoot $active.review_id) $updated.consume_ack
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_PACKAGE_CONSUMED' 'BRIDGE' @{review_id=$active.review_id;package_path=$updated.package_path;manifest_sha256=$updated.package_manifest_sha256})
                $active=[pscustomobject]$updated
            }
            if(Test-Path -LiteralPath $packagePath){Remove-Item -LiteralPath $packagePath -Recurse -Force}
            if($active.transport_state-ne'CLEANED'){
                $updated=[ordered]@{};foreach($p in $active.PSObject.Properties){$updated[$p.Name]=$p.Value};$updated.transport_state='CLEANED';$updated.cleaned_at=[DateTimeOffset]::UtcNow.ToString('o');$updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosReviewRecordAtomic $ProjectRoot $active.review_id $updated
                Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_CLEANUP_CONFIRMED' 'BRIDGE' @{review_id=$active.review_id;package_path=$updated.package_path})
            }
            return [pscustomobject]@{status='CLEANED';review_id=$active.review_id}
        }
        if($active.transport_state-eq'PUBLISHED'){return [pscustomobject]@{status='PUBLISHED';review_id=$active.review_id}}
        if($active.transport_state-eq'DECIDED'){return [pscustomobject]@{status='DECIDED';review_id=$active.review_id}}
        if($active.transport_state-eq'CONSUMED'){
            if(Test-Path -LiteralPath $packagePath){Remove-Item -LiteralPath $packagePath -Recurse -Force}
            $updated=[ordered]@{};foreach($p in $active.PSObject.Properties){$updated[$p.Name]=$p.Value};$updated.transport_state='CLEANED';$updated.cleaned_at=[DateTimeOffset]::UtcNow.ToString('o');$updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosReviewRecordAtomic $ProjectRoot $active.review_id $updated
            Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'REVIEW_CLEANUP_CONFIRMED' 'BRIDGE' @{review_id=$active.review_id;package_path=$updated.package_path})
            return [pscustomobject]@{status='CLEANED';review_id=$active.review_id}
        }
        [pscustomobject]@{status='CLEAN';review_id=$active.review_id}
    }
}
function Repair-AidosStateProjection { param($ProjectRoot)
    $s=Get-AidosState $ProjectRoot;$last=$null;foreach($f in (Get-ChildItem (Join-Path $ProjectRoot '.aidos/events') -Filter '*.jsonl' -File -ErrorAction SilentlyContinue|Sort-Object Name)){foreach($line in (Get-Content $f.FullName)){try{$e=$line|ConvertFrom-Json -Depth 100;if($e.event_type-eq'STATE_TRANSITION'){$last=$e}}catch{throw "Invalid event JSONL in '$($f.FullName)'."}}};if($last-and$s.state-ne$last.payload.to){$o=[ordered]@{};foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state=$last.payload.to;$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o;return $true};$false
}
function Get-AidosCodexRecoveryArtifactPath {
    param([string]$ProjectRoot,[string]$ExecutionId,[int]$Revision)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/executions/{0}/revision-{1}/RECOVERY.json' -f $ExecutionId,$Revision)
}
function Invoke-AidosCodexTerminalEventRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $directory=Join-Path $root ('.aidos/executions/{0}/revision-{1}' -f $ExecutionId,$Revision)
    $eventsPath=Join-Path $directory 'codex-events.jsonl';$resultPath=Join-Path $directory 'RESULT.json';$recoveryPath=Get-AidosCodexRecoveryArtifactPath $root $ExecutionId $Revision
    if(Test-Path -LiteralPath $resultPath -PathType Leaf){return [pscustomobject][ordered]@{status='RESULT_PRESENT';recovery_artifact=$null}}
    if(-not(Test-Path -LiteralPath $eventsPath -PathType Leaf)){return [pscustomobject][ordered]@{status='NO_TERMINAL_EVENT';recovery_artifact=$null}}
    $lines=@(Get-Content -LiteralPath $eventsPath -Encoding UTF8);$events=@()
    for($i=0;$i-lt$lines.Count;$i++){if([string]::IsNullOrWhiteSpace([string]$lines[$i])){continue};try{$events+=[pscustomobject][ordered]@{index=$i;raw=[string]$lines[$i];event=($lines[$i]|ConvertFrom-Json -Depth 100)}}catch{throw "Invalid Codex event JSON at '$eventsPath' line $($i+1)."}}
    $threads=@($events|Where-Object {$_.event.type-eq'thread.started' -and $_.event.thread_id}|ForEach-Object {[string]$_.event.thread_id}|Select-Object -Unique);$terminal=@($events|Where-Object {$_.event.type-in@('turn.completed','turn.failed','error')})
    if($threads.Count-ne1 -or $terminal.Count-eq0){return [pscustomobject][ordered]@{status='NO_RECOVERABLE_TERMINAL_EVENT';recovery_artifact=$null;thread_ids=$threads}}
    $last=$terminal[-1];$eventHash=Get-AidosTextSha256 ([string]$last.raw)
    if(Test-Path -LiteralPath $recoveryPath -PathType Leaf){$existing=Read-AidosJson $recoveryPath;if([string]$existing.event_sha256-ne$eventHash -or [string]$existing.codex_session_id-ne[string]$threads[0]){throw 'Codex recovery artifact does not match terminal event evidence.'};return [pscustomobject][ordered]@{status='RECOVERED';recovery_artifact=$recoveryPath;codex_session_id=[string]$threads[0];terminal_type=[string]$last.event.type;event_sha256=$eventHash;idempotent=$true}}
    $state=Get-AidosState $root
    $artifact=[ordered]@{schema_version='0.1';artifact_type='CODEX_TERMINAL_EVENT_RECOVERY';project_id=[string]$state.project_id;execution_id=$ExecutionId;revision=$Revision;codex_session_id=[string]$threads[0];terminal_type=[string]$last.event.type;terminal_event_index=[int]$last.index;event_sha256=$eventHash;events_path=[IO.Path]::GetRelativePath($root,$eventsPath).Replace('\','/');result_path=[IO.Path]::GetRelativePath($root,$resultPath).Replace('\','/');recovered_at=[DateTimeOffset]::UtcNow.ToString('o');recovery_reason='Terminal Codex event exists but durable RESULT.json and VALIDATION.json were absent.';execution_outcome='UNKNOWN';validation_status='NOT_RUN';resume_authorized=$true}
    Write-AidosJsonAtomic $recoveryPath $artifact
    [pscustomobject][ordered]@{status='RECOVERED';recovery_artifact=$recoveryPath;codex_session_id=[string]$threads[0];terminal_type=[string]$last.event.type;event_sha256=$eventHash;idempotent=$false}
}
function Invoke-AidosStartupReconciliation { param([string]$ProjectRoot)
    Test-AidosProjectBinding $ProjectRoot|Out-Null;Invoke-AidosExclusive $ProjectRoot {$repaired=Repair-AidosStateProjection $ProjectRoot;$path=Join-Path $ProjectRoot '.aidos/runtime/lease.json';if(-not(Test-Path $path)){$s=Get-AidosState $ProjectRoot;if($s.state-eq'CODEX_RUNNING'){$recovery=if($s.execution_id-and$s.revision){Invoke-AidosCodexTerminalEventRecovery $ProjectRoot ([string]$s.execution_id) ([int]$s.revision)}else{$null};if($recovery.status-eq'RECOVERED'){$null=Set-AidosState $ProjectRoot 'RECOVERY_REQUIRED' 'BRIDGE' @{lease_id=$null;codex_session_id=$recovery.codex_session_id};Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'CODEX_TERMINAL_EVENT_RECOVERED' 'BRIDGE' @{reason='CODEX_RUNNING_WITHOUT_LEASE';next_state='RECOVERY_REQUIRED';execution_id=$s.execution_id;revision=$s.revision;recovery_artifact=$recovery.recovery_artifact});return [pscustomobject]@{status='RECOVERY_REQUIRED';projection_repaired=$repaired;recovery=$recovery}};$o=[ordered]@{};foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'RECOVERY_RECONCILED' 'BRIDGE' @{reason='CODEX_RUNNING_WITHOUT_LEASE';next_state='RECOVERY_REQUIRED'});Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o;return [pscustomobject]@{status='RECOVERY_REQUIRED';projection_repaired=$repaired}};return [pscustomobject]@{status='CLEAN';projection_repaired=$repaired}};$l=Read-AidosJson $path;$alive=$false;if($l.codex_runtime-and$l.codex_runtime.supervisor_pid){$p=Get-Process -Id ([int]$l.codex_runtime.supervisor_pid) -ErrorAction SilentlyContinue;if($p){$alive=$p.StartTime.ToUniversalTime().ToString('o')-eq[string]$l.codex_runtime.started_at}};if($alive){return [pscustomobject]@{status='RUNNING';lease_id=$l.lease_id;projection_repaired=$repaired}};$s=Get-AidosState $ProjectRoot;if($s.state-eq'CODEX_RUNNING'){$recovery=if($s.execution_id-and$s.revision){Invoke-AidosCodexTerminalEventRecovery $ProjectRoot ([string]$s.execution_id) ([int]$s.revision)}else{$null};if($recovery.status-eq'RECOVERED'){$null=Set-AidosState $ProjectRoot 'RECOVERY_REQUIRED' 'BRIDGE' @{lease_id=$null;codex_session_id=$recovery.codex_session_id};Remove-Item $path -Force;Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'CODEX_TERMINAL_EVENT_RECOVERED' 'BRIDGE' @{reason='STALE_CODEX_LEASE';next_state='RECOVERY_REQUIRED';execution_id=$s.execution_id;revision=$s.revision;recovery_artifact=$recovery.recovery_artifact});return [pscustomobject]@{status='RECOVERY_REQUIRED';stale_lease_id=$l.lease_id;projection_repaired=$repaired;recovery=$recovery}};$o=[ordered]@{};foreach($p in $s.PSObject.Properties){$o[$p.Name]=$p.Value};$o.state='RECOVERY_REQUIRED';$o.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'EXECUTION_INTERRUPTED' 'BRIDGE' @{lease_id=$l.lease_id;execution_id=$l.execution_id;revision=$l.revision});Write-AidosJsonAtomic (Join-Path $ProjectRoot '.aidos/STATE.json') $o};Remove-Item $path -Force;Add-AidosEventUnlocked $ProjectRoot (New-AidosEventObject $ProjectRoot 'RECOVERY_RECONCILED' 'BRIDGE' @{stale_lease_id=$l.lease_id;next_state=(Get-AidosState $ProjectRoot).state});[pscustomobject]@{status='RECOVERY_REQUIRED';stale_lease_id=$l.lease_id;projection_repaired=$repaired}}
}
Export-ModuleMember -Function Resolve-AidosFileSystemPath,Resolve-AidosRecordBoundPath,Test-AidosSameFileSystemPath,Get-AidosProjectRoot,Read-AidosJson,Write-AidosJsonAtomic,Get-AidosProjectProfile,Get-AidosGitRuntime,Get-AidosGitCommand,Invoke-AidosGit,Register-AidosGitRuntime,Get-AidosCodexRuntimeCommand,Get-AidosCodexCliCapabilities,Assert-AidosCodexAuthorityRepresentable,Assert-AidosCodexCliSupport,Get-AidosCodexLaunchArguments,Test-AidosProjectBinding,Get-AidosPreparationSnapshot,Assert-AidosExecutionBinding,Get-AidosState,Add-AidosEvent,Set-AidosState,Set-AidosExecutionDispatchBinding,Acquire-AidosExecutionLease,Release-AidosExecutionLease,Get-AidosCodexCommand,Test-AidosExecutionEvidence,Invoke-AidosCodexExecution,Get-AidosReviewRoot,Get-AidosReviewPackageRoot,Get-AidosReviewRecordPath,Get-AidosReviewManifestPath,Get-AidosReviewAckPath,Get-AidosReviewDecisionState,Get-AidosReviewReviewerBinding,Get-AidosReviewAssignmentPath,Test-AidosReviewAssignmentBinding,Test-AidosReviewBinding,Test-AidosReviewResponseBinding,Get-AidosReviewEvidenceRefs,New-AidosReviewAssignmentObject,New-AidosReviewResponseObject,New-AidosReviewRecordObject,Write-AidosReviewAssignmentAtomic,Read-AidosReviewAssignment,Write-AidosReviewResponseAtomic,Read-AidosReviewResponse,Write-AidosReviewRecordAtomic,Read-AidosReviewRecord,Resolve-AidosReviewDecisionTargetState,Publish-AidosReviewPackage,Repair-AidosReviewPackage,Repair-AidosLegacyReviewAssignmentCorrelation,Set-AidosReviewDecision,Confirm-AidosReviewConsumed,Invoke-AidosReviewCleanup,Abandon-AidosReview,Invoke-AidosReviewConsumer,Invoke-AidosReviewReconciliation,Invoke-AidosStartupReconciliation
