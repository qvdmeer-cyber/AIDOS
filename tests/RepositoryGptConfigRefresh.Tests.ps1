[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$refresh=Join-Path $root 'bridge/Refresh-AidosRepositoryHandoffGptConfig.ps1'
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffInstallation.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Refresh([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-RefreshThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-gpt-refresh-'+[guid]::NewGuid().ToString('N'))
$host=Join-Path $temp 'host';$bridge=Join-Path $temp 'bridge'
New-Item -ItemType Directory -Path $host,$bridge -Force|Out-Null
try{
    $openapi=Join-Path $host 'OPENAPI.json';$instructions=Join-Path $host 'GPT_INSTRUCTIONS.md'
    [ordered]@{schema_version='0.2';public_url='https://aidos.tail1234.ts.net';openapi_path=$openapi;instructions_path=$instructions;bridge_state_root=$bridge;process_name='ChatGPT Classic Test'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $host 'CONFIG.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.3';registry_root=$temp;state_root=$bridge;process_name='OLD'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $bridge 'CONFIG.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';status='RUNNING'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $host 'STATUS.json') -Encoding utf8NoBOM
    Assert-RefreshThrows {& $refresh -StateRoot $host|Out-Null} 'Stop the AIDOS Repository Handoff Host' 'refresh refuses to race a running host'

    [ordered]@{schema_version='0.1';status='STOPPED'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $host 'STATUS.json') -Encoding utf8NoBOM
    $result=(& $refresh -StateRoot $host)|ConvertFrom-Json -Depth 50
    Assert-Refresh ([string]$result.status-eq'REFRESHED') 'stopped host GPT configuration refresh succeeds'
    Assert-Refresh (-not[bool]$result.api_key_rotated) 'GPT configuration refresh never rotates the gateway key'
    $schema=Get-Content -LiteralPath $openapi -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    Assert-Refresh ([string]$schema.paths.'/v1/projects/{projectId}/human-input'.get.operationId-eq'getAidosHumanInput') 'refreshed OpenAPI contains Human Input read action'
    Assert-Refresh ([string]$schema.paths.'/v1/projects/{projectId}/human-input/{requestId}/response'.post.operationId-eq'submitAidosHumanInputResponse') 'refreshed OpenAPI contains Human Input submit action'
    $text=Get-Content -LiteralPath $instructions -Raw -Encoding UTF8
    Assert-Refresh ($text.Contains('AIDOS_HUMAN_INPUT_REQUIRED') -and $text.Contains('AIDOS_HUMAN_INPUT_AWAITING')) 'refreshed GPT instructions contain Human Input two-turn protocol'
    $bridgeConfig=Get-Content -LiteralPath (Join-Path $bridge 'CONFIG.json') -Raw -Encoding UTF8|ConvertFrom-Json -Depth 30
    Assert-Refresh ([string]$bridgeConfig.schema_version-eq'0.4' -and [string]$bridgeConfig.process_name-eq'ChatGPT Classic Test') 'refresh upgrades bridge transport configuration without reinstall'

    Write-Output "PASS: $passed repository GPT config refresh assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
