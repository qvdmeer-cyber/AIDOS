[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffPersistence.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Persist([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-PersistThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}
function Git([string]$Repo,[string[]]$Args){$o=@(&git -C $Repo @Args 2>&1);if($LASTEXITCODE-ne0){throw "git $($Args-join' ') failed: $($o-join'; ')"};@($o)}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-handoff-persist-'+[guid]::NewGuid().ToString('N'))
$repo=Join-Path $temp 'repo';$registry=Join-Path $temp 'registry'
New-Item -ItemType Directory -Path $repo,$registry -Force|Out-Null
try{
    &git init $repo|Out-Null
    Git $repo @('config','user.email','aidos@example.invalid')|Out-Null
    Git $repo @('config','user.name','AIDOS Tests')|Out-Null
    Git $repo @('remote','add','origin','https://github.com/example/repo.git')|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo '.aidos') -Force|Out-Null
    Set-Content (Join-Path $repo '.aidos/HANDOFF.md') 'initial' -Encoding utf8NoBOM
    Set-Content (Join-Path $repo 'product.txt') 'initial' -Encoding utf8NoBOM
    Git $repo @('add','.')|Out-Null;Git $repo @('commit','-m','initial')|Out-Null
    $project=Register-AidosPreparationProject -RegistryRoot $registry -ProjectId 'P1' -Repository 'https://github.com/example/repo.git' -LocalRoot $repo -AllowedPersistencePaths @('.aidos')

    Set-Content (Join-Path $repo '.aidos/HANDOFF.md') 'handoff 1' -Encoding utf8NoBOM
    Set-Content (Join-Path $repo 'product.txt') 'worker change' -Encoding utf8NoBOM
    $persist=Invoke-AidosRepositoryHandoffGitPersistence -Project $project -Paths @('.aidos/HANDOFF.md') -CommitMessage 'handoff'
    Assert-Persist ([string]$persist.status-eq'PERSISTED') 'handoff path is committed from dirty Worker worktree'
    Assert-Persist (@($persist.paths)-contains'.aidos/HANDOFF.md') 'commit contains canonical handoff'
    Assert-Persist (@($persist.uncommitted_paths)-contains'product.txt') 'Worker product mutation remains uncommitted'
    $show=@(Git $repo @('show','--pretty=format:','--name-only','HEAD')|Where-Object {-not[string]::IsNullOrWhiteSpace($_)})
    Assert-Persist ($show.Count-eq1 -and $show[0]-eq'.aidos/HANDOFF.md') 'scoped commit excludes product mutations'
    Assert-Persist ((Get-Content (Join-Path $repo 'product.txt') -Raw).Trim()-eq'worker change') 'product mutation remains in worktree after handoff commit'

    $none=Invoke-AidosRepositoryHandoffGitPersistence -Project $project -Paths @('.aidos/HANDOFF.md') -CommitMessage 'none'
    Assert-Persist ([string]$none.status-eq'NO_CHANGES') 'unchanged handoff is idempotent'

    Set-Content (Join-Path $repo '.aidos/HANDOFF.md') 'handoff 2' -Encoding utf8NoBOM
    Git $repo @('add','product.txt')|Out-Null
    Assert-PersistThrows {Invoke-AidosRepositoryHandoffGitPersistence -Project $project -Paths @('.aidos/HANDOFF.md') -CommitMessage 'blocked'} 'Pre-staged non-handoff' 'pre-staged Worker source blocks scoped commit'
    Git $repo @('reset','--','product.txt')|Out-Null
    Assert-PersistThrows {Invoke-AidosRepositoryHandoffGitPersistence -Project $project -Paths @('product.txt') -CommitMessage 'unauthorized'} 'Unauthorized handoff persistence' 'scoped persistence cannot commit product source'

    Write-Output "PASS: $passed repository handoff persistence assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
