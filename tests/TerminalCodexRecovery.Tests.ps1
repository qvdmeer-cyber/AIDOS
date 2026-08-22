[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
$passed=0
function Assert-Recovery([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Write-Json($Path,$Value){$dir=Split-Path -Parent $Path;New-Item -ItemType Directory -Path $dir -Force|Out-Null;$Value|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $Path -Encoding utf8NoBOM}
$projectRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-terminal-recovery-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $projectRoot -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email test@example.invalid
    & git -C $projectRoot config user.name 'AIDOS Test'
    & git -C $projectRoot remote add origin https://github.com/test/recovery.git
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/events') -Force|Out-Null
    Write-Json (Join-Path $projectRoot '.aidos/PROJECT.json') ([ordered]@{schema_version='0.1';project_id='RECOVERY-TEST';project_mode='NEW_PROJECT';repository='test/recovery';official_root=$projectRoot;git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}})
    Write-Json (Join-Path $projectRoot '.aidos/STATE.json') ([ordered]@{schema_version='0.1';project_id='RECOVERY-TEST';state='CODEX_RUNNING';definition_id=$null;definition_version=$null;execution_id='EXEC-RECOVERY';revision=1;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at=[DateTimeOffset]::UtcNow.ToString('o')})
    $executionDir=Join-Path $projectRoot '.aidos/executions/EXEC-RECOVERY/revision-1';New-Item -ItemType Directory -Path $executionDir -Force|Out-Null
    @('{"type":"thread.started","thread_id":"33333333-3333-3333-3333-333333333333"}','{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}')|Set-Content -LiteralPath (Join-Path $executionDir 'codex-events.jsonl') -Encoding utf8NoBOM
    $startup=Invoke-AidosStartupReconciliation $projectRoot
    $state=Get-AidosState $projectRoot
    $artifactPath=Join-Path $projectRoot '.aidos/executions/EXEC-RECOVERY/revision-1/RECOVERY.json';$artifact=Read-AidosJson $artifactPath
    Assert-Recovery ($startup.status -eq 'RECOVERY_REQUIRED' -and $state.codex_session_id -eq '33333333-3333-3333-3333-333333333333' -and $artifact.execution_outcome -eq 'UNKNOWN' -and $artifact.validation_status -eq 'NOT_RUN') 'startup reconciliation binds the recovered session and stays fail-closed'
    $again=Invoke-AidosStartupReconciliation $projectRoot
    Assert-Recovery ($again.status -eq 'CLEAN' -and (Test-Path $artifactPath)) 'recovery remains durable after restart reconciliation'
    Write-Output "PASS: $passed terminal Codex recovery assertions"
} finally {if(Test-Path $projectRoot){Remove-Item -LiteralPath $projectRoot -Recurse -Force}}
