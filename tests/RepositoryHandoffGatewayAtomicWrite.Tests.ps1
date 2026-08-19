[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffGateway.psm1') -Force -DisableNameChecking

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-gateway-atomic-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $path=Join-Path $temp 'STATUS.json'
    for($i=0;$i-lt250;$i++){
        Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $path -Value ([ordered]@{schema_version='0.2';status='RUNNING';pid=1234;heartbeat=$i})
        $current=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        if([int]$current.heartbeat-ne$i){throw "Atomic overwrite lost heartbeat $i."}
    }
    $leftovers=@(Get-ChildItem -LiteralPath $temp -Filter 'STATUS.json.*.tmp' -File -ErrorAction SilentlyContinue)
    if($leftovers.Count-ne0){throw 'Atomic overwrite left temporary files behind.'}
    Write-Output 'PASS: gateway atomic overwrite survives repeated replacement'
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
