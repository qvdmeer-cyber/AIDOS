[CmdletBinding()]
param([string]$StateRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffInstallation.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffOpenApi.psm1') -Force -DisableNameChecking

if([string]::IsNullOrWhiteSpace($StateRoot)){$StateRoot=Get-AidosRepositoryHandoffHostDefaultStateRoot}
$StateRoot=[IO.Path]::GetFullPath($StateRoot)
$configPath=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind config
if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw 'Repository handoff host is not installed.'}
$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
$statusPath=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind status
if(Test-Path -LiteralPath $statusPath -PathType Leaf){
    $status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    if([string]$status.status-in@('RUNNING','STARTING','STOPPING')){throw 'Stop the AIDOS Repository Handoff Host before refreshing GPT configuration.'}
}
foreach($name in @('public_url','openapi_path','instructions_path','bridge_state_root','process_name')){
    if(-not$config.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$config.$name)){throw "Repository handoff host configuration is missing '$name'."}
}

function Write-AidosRepositoryGptConfigTextAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
    $full=[IO.Path]::GetFullPath($Path);$dir=Split-Path -Parent $full
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$full.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        Set-Content -LiteralPath $tmp -Value $Text -Encoding utf8NoBOM -NoNewline
        [IO.File]::Move($tmp,$full,$true)
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}

$instructions=New-AidosRepositoryThinkerGptInstructions
Write-AidosRepositoryGptConfigTextAtomic -Path ([string]$config.instructions_path) -Text $instructions
$openapi=Write-AidosRepositoryHandoffOpenApiDocument -ServerUrl ([string]$config.public_url) -Path ([string]$config.openapi_path)
$bridge=Sync-AidosRepositoryHandoffBridgeHostConfiguration -Configuration $config

[pscustomobject][ordered]@{
    status='REFRESHED'
    openapi_path=[string]$openapi.path
    instructions_path=[string]$config.instructions_path
    bridge_configuration=$bridge
    api_key_rotated=$false
    required_action='Update the existing private GPT Instructions and Action schema before restarting the host.'
}|ConvertTo-Json -Depth 30
