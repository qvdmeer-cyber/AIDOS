Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-AidosRepositoryHandoffBridgeDefaultStateRoot {
    if([OperatingSystem]::IsWindows()){return (Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-bridge')}
    Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-repository-handoff-bridge'
}
function Get-AidosRepositoryHandoffWakePath {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot))
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) 'WAKE.json'
}
function Signal-AidosRepositoryHandoffBridge {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),[string]$Reason='EXTERNAL_RESULT',[string]$ProjectId,[string]$HandoffId)
    $path=Get-AidosRepositoryHandoffWakePath -StateRoot $StateRoot
    $dir=Split-Path -Parent $path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $value=[pscustomobject][ordered]@{schema_version='0.1';reason=$Reason;project_id=if([string]::IsNullOrWhiteSpace($ProjectId)){$null}else{$ProjectId};handoff_id=if([string]::IsNullOrWhiteSpace($HandoffId)){$null}else{$HandoffId};signaled_at=[DateTimeOffset]::UtcNow.ToString('o');nonce=[guid]::NewGuid().ToString()}
    $tmp="$path.$([guid]::NewGuid().ToString('N')).tmp"
    $value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
    Move-Item -LiteralPath $tmp -Destination $path -Force
    $value
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffBridgeDefaultStateRoot,Get-AidosRepositoryHandoffWakePath,Signal-AidosRepositoryHandoffBridge
