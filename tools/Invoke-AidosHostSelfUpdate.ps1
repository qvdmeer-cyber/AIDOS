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
        try{& $reloadScript -StateRoot $StateRoot -Distribution $Distribution -WslReposRoot $WslReposRoot -AuthorizedUser $AuthorizedUser|Out-Null;Remove-Item -LiteralPath $reloadMarkerPath -Force;Write-SelfUpdateStatus -Status 'RELOADED' -Detail @{commit=$local}|Out-Null;exit 0}
        catch{Write-SelfUpdateStatus -Status 'RELOAD_RETRY_REQUIRED' -Detail @{commit=$local;error=$_.Exception.Message}|Out-Null;exit 1}
    }

    if([string]$local-eq[string]$remote){Write-SelfUpdateStatus -Status 'CURRENT' -Detail @{commit=$local}|Out-Null;exit 0}
    $ancestor=Invoke-Wsl @('git','-C',$repo,'merge-base','--is-ancestor',$local,$remote)
    if([int]$ancestor.exit_code-ne0){Write-SelfUpdateStatus -Status 'BLOCKED_NON_FAST_FORWARD' -Detail @{local=$local;remote=$remote}|Out-Null;exit 1}

    $candidate="$WslReposRoot/.aidos-core-update/$remote"
    Invoke-Wsl @('git','-C',$repo,'worktree','remove','--force',$candidate)|Out-Null
    $added=Require-WslSuccess 'create validation worktree' (Invoke-Wsl @('git','-C',$repo,'worktree','add','--detach',$candidate,$remote))
    try {
        $hasPwsh=Invoke-Wsl @('bash','-lc','command -v pwsh >/dev/null 2>&1')
        if([int]$hasPwsh.exit_code-ne0){Write-SelfUpdateStatus -Status 'VALIDATION_ENVIRONMENT_REQUIRED' -Detail @{remote=$remote;requirement='pwsh inside WSL is required for autonomous pre-update regression validation.'}|Out-Null;exit 1}
        $validation=Invoke-Wsl @('pwsh','-NoLogo','-NoProfile','-File',"$candidate/tools/Test-AidosCorePortable.ps1",'-RepoRoot',$candidate)
        if([int]$validation.exit_code-ne0){Write-SelfUpdateStatus -Status 'VALIDATION_FAILED' -Detail @{remote=$remote;output=@($validation.output)}|Out-Null;exit 1}
    } finally {Invoke-Wsl @('git','-C',$repo,'worktree','remove','--force',$candidate)|Out-Null}

    Require-WslSuccess 'fast-forward Core update' (Invoke-Wsl @('git','-C',$repo,'merge','--ff-only',$remote))|Out-Null
    [ordered]@{schema_version='0.1';commit=$remote;previous_commit=$local;validated_at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $reloadMarkerPath -Encoding utf8NoBOM
    Write-SelfUpdateStatus -Status 'UPDATED_RELOAD_REQUIRED' -Detail @{previous_commit=$local;commit=$remote}|Out-Null

    $reloadScript="\\wsl.localhost\$Distribution\$($WslReposRoot.TrimStart('/').Replace('/','\'))\AIDOS\tools\Reload-AidosAutonomousPreparation.ps1"
    try{& $reloadScript -StateRoot $StateRoot -Distribution $Distribution -WslReposRoot $WslReposRoot -AuthorizedUser $AuthorizedUser|Out-Null;Remove-Item -LiteralPath $reloadMarkerPath -Force;Write-SelfUpdateStatus -Status 'UPDATED_AND_RELOADED' -Detail @{previous_commit=$local;commit=$remote}|Out-Null}
    catch{Write-SelfUpdateStatus -Status 'UPDATED_RELOAD_RETRY_REQUIRED' -Detail @{previous_commit=$local;commit=$remote;error=$_.Exception.Message}|Out-Null;exit 1}
} catch {
    Write-SelfUpdateStatus -Status 'ERROR' -Detail @{error=$_.Exception.Message}|Out-Null
    exit 1
} finally {if($lock){$lock.Dispose()}}
