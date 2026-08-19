[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffBridge.psm1') -Force -DisableNameChecking

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-bridge-atomic-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $path=Join-Path $temp 'STATUS.json'
    foreach($i in 1..250){
        Write-AidosRepositoryHandoffBridgeJsonAtomic -Path $path -Value ([ordered]@{schema_version='0.3';status='RUNNING';pid=1234;heartbeat_at=$i})
    }
    $status=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if([int]$status.heartbeat_at-ne250){throw 'ASSERTION FAILED: bridge atomic status overwrite did not preserve latest heartbeat.'}
    if(@(Get-ChildItem -LiteralPath $temp -Filter 'STATUS.json.*.tmp' -ErrorAction SilentlyContinue).Count-ne0){throw 'ASSERTION FAILED: bridge atomic status overwrite left temporary files behind.'}
    Write-Output 'PASS: bridge atomic status overwrite assertions'
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
