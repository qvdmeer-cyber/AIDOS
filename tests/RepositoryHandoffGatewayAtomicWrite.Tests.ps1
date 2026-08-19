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

    $source=Join-Path $temp 'retry-source.tmp'
    $destination=Join-Path $temp 'retry-destination.json'
    Set-Content -LiteralPath $source -Value '{"status":"RUNNING"}' -Encoding utf8NoBOM -NoNewline
    Set-Content -LiteralPath $destination -Value '{"status":"OLD"}' -Encoding utf8NoBOM -NoNewline
    $script:attempts=0
    $script:sleeps=0
    $move={
        param($from,$to)
        $script:attempts++
        if($script:attempts-lt4){throw [UnauthorizedAccessException]::new('transient reader lock')}
        [IO.File]::Move($from,$to,$true)
    }
    $sleep={param($milliseconds);$script:sleeps++}
    Move-AidosRepositoryHandoffGatewayAtomicFile -SourcePath $source -DestinationPath $destination -MaxAttempts 5 -DelayMilliseconds 1 -MoveAction $move -SleepAction $sleep
    if($script:attempts-ne4 -or $script:sleeps-ne3){throw "Transient replace retry count was unexpected: attempts=$script:attempts sleeps=$script:sleeps"}
    if((Get-Content -LiteralPath $destination -Raw -Encoding UTF8)-ne'{"status":"RUNNING"}'){throw 'Transient replace retry did not publish the source atomically.'}

    $persistentSource=Join-Path $temp 'persistent-source.tmp'
    Set-Content -LiteralPath $persistentSource -Value 'x' -Encoding ascii -NoNewline
    $script:persistentAttempts=0
    $persistentMove={param($from,$to);$script:persistentAttempts++;throw [IO.IOException]::new('persistent lock')}
    $thrown=$false
    try{Move-AidosRepositoryHandoffGatewayAtomicFile -SourcePath $persistentSource -DestinationPath $destination -MaxAttempts 3 -DelayMilliseconds 0 -MoveAction $persistentMove -SleepAction {param($milliseconds)}}catch{$thrown=$true}
    if(-not$thrown -or $script:persistentAttempts-ne3){throw 'Persistent atomic replacement failure did not fail closed after the bounded retry count.'}

    Write-Output 'PASS: gateway atomic overwrite survives repeated replacement and transient reader locks'
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
