[CmdletBinding()]
param(
    [string]$Distribution='Ubuntu',
    [string]$WslReposRoot='/home/aidos/repos',
    [string]$StateRoot,
    [string]$AuthorizedUser='AIDOS\qvdm'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not$IsWindows){throw 'AIDOS host self-update must run from Windows PowerShell 7.'}
if([string]::IsNullOrWhiteSpace($StateRoot)){$StateRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'}
if(-not(Test-Path -LiteralPath $StateRoot -PathType Container)){New-Item -ItemType Directory -Path $StateRoot -Force|Out-Null}
$statusPath=Join-Path $StateRoot 'SELF_UPDATE_STATUS.json'
$reloadMarkerPath=Join-Path $StateRoot 'SELF_UPDATE_RELOAD_REQUIRED.json'
$lockPath=Join-Path $StateRoot 'self-update.lock'

function Write-SelfUpdateStatus([string]$Status,[hashtable]$Detail=@{}){
    $o=[ordered]@{schema_version='0.1';status=$Status;observed_at=[DateTimeOffset]::UtcNow.ToString('o')}
    foreach($k in $Detail.Keys){$o[$k]=$Detail[$k]}
    $tmp=$statusPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $o|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
    Move-Item -LiteralPath $tmp -Destination $statusPath -Force
    [pscustomobject]$o
}
function Invoke-Wsl([string[]]$Arguments){
    $output=@(& wsl.exe --distribution $Distribution -- @Arguments 2>&1);$code=$LASTEXITCODE
    [pscustomobject]@{exit_code=$code;output=@($output|ForEach-Object {[string]$_})}
}
function Require-WslSuccess([string]$Step,$Result){if([int]$Result.exit_code-ne0){throw "$Step failed: $($Result.output -join [Environment]::NewLine)"};$Result}
function Convert-WslPathToUnc([Parameter(Mandatory)][string]$Path){
    $relative=$Path.TrimStart('/').Replace('/','\')
    "\\wsl.localhost\$Distribution\$relative"
}
function Invoke-HostCoreValidation([Parameter(Mandatory)][string]$CandidateWslPath){
    $candidateUnc=Convert-WslPathToUnc $CandidateWslPath
    $sourceValidator=Join-Path $candidateUnc 'tools\Test-AidosCorePortable.ps1'
    if(-not(Test-Path -LiteralPath $sourceValidator -PathType Leaf)){throw "Candidate Core validator is unavailable: $sourceValidator"}
    $engine=Join-Path $PSHOME 'pwsh.exe'
    if(-not(Test-Path -LiteralPath $engine -PathType Leaf)){throw 'Windows PowerShell 7 engine is unavailable for candidate validation.'}

    # Windows treats \\wsl.localhost paths as a network security zone and may
    # display an interactive Open File warning when PowerShell modules/scripts
    # are executed from that UNC surface. Candidate identity remains bound by
    # the Git worktree SHA; validation executes an ephemeral local mirror so the
    # unattended watchdog never depends on an interactive security prompt.
    $validationParent=Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-core-validation'
    if(-not(Test-Path -LiteralPath $validationParent -PathType Container)){New-Item -ItemType Directory -Path $validationParent -Force|Out-Null}
    $validationRoot=Join-Path $validationParent ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $validationRoot -Force|Out-Null
    try {
        Get-ChildItem -LiteralPath $candidateUnc -Force|Copy-Item -Destination $validationRoot -Recurse -Force
        $validator=Join-Path $validationRoot 'tools\Test-AidosCorePortable.ps1'
        if(-not(Test-Path -LiteralPath $validator -PathType Leaf)){throw "Localized candidate Core validator is unavailable: $validator"}
        $output=@(& $engine -NoLogo -NoProfile -ExecutionPolicy Bypass -File $validator -RepoRoot $validationRoot 2>&1)
        $code=$LASTEXITCODE
        [pscustomobject]@{exit_code=$code;output=@($output|ForEach-Object {[string]$_});candidate_root=$candidateUnc;validation_root=$validationRoot;engine=$engine}
    } finally {
        if(Test-Path -LiteralPath $validationRoot){Remove-Item -LiteralPath $validationRoot -Recurse -Force}
    }
}
function Clear-AidosValidationWorktree {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$CandidateRoot,
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Commit
    )
    if($Commit -notmatch '^[0-9a-f]{40}$'){throw 'Validation worktree cleanup requires an exact lowercase SHA-1 commit id.'}
    $prefix=$CandidateRoot.TrimEnd('/')+'/'
    if(-not$Candidate.StartsWith($prefix,[StringComparison]::Ordinal) -or -not[string]::Equals($Candidate,($prefix+$Commit),[StringComparison]::Ordinal)){
        throw "Refusing validation worktree cleanup outside the exact AIDOS-owned candidate path: $Candidate"
    }

    # Registered worktrees are removed through Git first. A prior interrupted
    # validation may leave only the directory behind, so prune metadata before
    # checking for that known AIDOS-owned stale directory.
    Invoke-Wsl @('git','-C',$Repo,'worktree','remove','--force',$Candidate)|Out-Null
    Require-WslSuccess 'prune validation worktrees' (Invoke-Wsl @('git','-C',$Repo,'worktree','prune'))|Out-Null

    $absent=Invoke-Wsl @('test','!','-e',$Candidate)
    if([int]$absent.exit_code-ne0){
        Require-WslSuccess 'remove stale validation worktree directory' (Invoke-Wsl @('rm','-rf','--',$Candidate))|Out-Null
        $absent=Invoke-Wsl @('test','!','-e',$Candidate)
        if([int]$absent.exit_code-ne0){throw "AIDOS validation worktree path remains after bounded cleanup: $Candidate"}
        Require-WslSuccess 'prune validation worktrees after stale-directory cleanup' (Invoke-Wsl @('git','-C',$Repo,'worktree','prune'))|Out-Null
    }
}

$lock=$null
try{$lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
catch [IO.IOException]{Write-SelfUpdateStatus -Status 'ALREADY_RUNNING'|Out-Null;exit 0}
try {
    $repo="$WslReposRoot/AIDOS"
    $dirty=Require-WslSuccess 'git status' (Invoke-Wsl @('git','-C',$repo,'status','--porcelain=v1'))
    if(@($dirty.output|Where-Object {-not[string]::IsNullOrWhiteSpace($_)}).Count){Write-SelfUpdateStatus -Status 'BLOCKED_DIRTY_CORE' -Detail @{paths=@($dirty.output)}|Out-Null;exit 0}

    Require-WslSuccess 'git fetch' (Invoke-Wsl @('git','-C',$repo,'fetch','origin','main'))|Out-Null
    $local=(Require-WslSuccess 'read local HEAD' (Invoke-Wsl @('git','-C',$repo,'rev-parse','HEAD'))).output[0]
    $remote=(Require-WslSuccess 'read origin/main' (Invoke-Wsl @('git','-C',$repo,'rev-parse','origin/main'))).output[0]

    if(Test-Path -LiteralPath $reloadMarkerPath -PathType Leaf){
        $marker=Get-Content -LiteralPath $reloadMarkerPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
        if([string]$marker.commit -ne [string]$local){Write-SelfUpdateStatus -Status 'RELOAD_MARKER_MISMATCH' -Detail @{local=$local;marker_commit=[string]$marker.commit}|Out-Null;exit 1}
        $reloadScript="\\wsl.localhost\$Distribution\$($WslReposRoot.TrimStart('/').Replace('/','\'))\AIDOS\tools\Reload-AidosAutonomousPreparation.ps1"
        try{& $reloadScript -StateRoot $StateRoot -Distribution $Distribution -WslReposRoot $WslReposRoot -AuthorizedUser $AuthorizedUser -PreserveSelfUpdateTask|Out-Null;Remove-Item -LiteralPath $reloadMarkerPath -Force;Write-SelfUpdateStatus -Status 'RELOADED' -Detail @{commit=$local}|Out-Null;exit 0}
        catch{Write-SelfUpdateStatus -Status 'RELOAD_RETRY_REQUIRED' -Detail @{commit=$local;error=$_.Exception.Message}|Out-Null;exit 1}
    }

    if([string]$local-eq[string]$remote){Write-SelfUpdateStatus -Status 'CURRENT' -Detail @{commit=$local}|Out-Null;exit 0}
    $ancestor=Invoke-Wsl @('git','-C',$repo,'merge-base','--is-ancestor',$local,$remote)
    if([int]$ancestor.exit_code-ne0){Write-SelfUpdateStatus -Status 'BLOCKED_NON_FAST_FORWARD' -Detail @{local=$local;remote=$remote}|Out-Null;exit 1}
    if($remote -notmatch '^[0-9a-f]{40}$'){throw "Remote Core revision is not an exact lowercase SHA-1 commit id: $remote"}

    $candidateRoot="$WslReposRoot/.aidos-core-update"
    $candidate="$candidateRoot/$remote"
    Clear-AidosValidationWorktree -Repo $repo -CandidateRoot $candidateRoot -Candidate $candidate -Commit $remote
    Require-WslSuccess 'create validation worktree' (Invoke-Wsl @('git','-C',$repo,'worktree','add','--detach',$candidate,$remote))|Out-Null
    try {
        $validation=Invoke-HostCoreValidation -CandidateWslPath $candidate
        if([int]$validation.exit_code-ne0){Write-SelfUpdateStatus -Status 'VALIDATION_FAILED' -Detail @{remote=$remote;candidate_root=[string]$validation.candidate_root;engine=[string]$validation.engine;output=@($validation.output)}|Out-Null;exit 1}
    } finally {
        Clear-AidosValidationWorktree -Repo $repo -CandidateRoot $candidateRoot -Candidate $candidate -Commit $remote
    }

    Require-WslSuccess 'fast-forward Core update' (Invoke-Wsl @('git','-C',$repo,'merge','--ff-only',$remote))|Out-Null
    [ordered]@{schema_version='0.1';commit=$remote;previous_commit=$local;validated_at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $reloadMarkerPath -Encoding utf8NoBOM
    Write-SelfUpdateStatus -Status 'UPDATED_RELOAD_REQUIRED' -Detail @{previous_commit=$local;commit=$remote}|Out-Null

    $reloadScript="\\wsl.localhost\$Distribution\$($WslReposRoot.TrimStart('/').Replace('/','\'))\AIDOS\tools\Reload-AidosAutonomousPreparation.ps1"
    try{& $reloadScript -StateRoot $StateRoot -Distribution $Distribution -WslReposRoot $WslReposRoot -AuthorizedUser $AuthorizedUser -PreserveSelfUpdateTask|Out-Null;Remove-Item -LiteralPath $reloadMarkerPath -Force;Write-SelfUpdateStatus -Status 'UPDATED_AND_RELOADED' -Detail @{previous_commit=$local;commit=$remote}|Out-Null}
    catch{Write-SelfUpdateStatus -Status 'UPDATED_RELOAD_RETRY_REQUIRED' -Detail @{previous_commit=$local;commit=$remote;error=$_.Exception.Message}|Out-Null;exit 1}
} catch {
    Write-SelfUpdateStatus -Status 'ERROR' -Detail @{error=$_.Exception.Message}|Out-Null
    exit 1
} finally {if($lock){$lock.Dispose()}}
