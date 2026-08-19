[CmdletBinding()]
param(
    [ValidateSet('Install','Start','StartBridge','StartGateway','Stop','Status','BindThinker','UnbindThinker','ResetThinkerTrigger','RotateKey','ShowApiKey','ShowOpenApi','ShowInstructions','FunnelStatus','Tick','Uninstall')]
    [string]$Command='Status',
    [string]$StateRoot,
    [string]$RegistryRoot,
    [string]$BuilderRoot,
    [string]$ContractsRoot,
    [string]$AidosRoot,
    [string]$AuthorizedUser='AIDOS\qvdm',
    [string]$ProcessName='ChatGPT Classic',
    [string]$ProjectId,
    [string]$ConversationTitle,
    [string]$HandoffId,
    [string]$PublicUrl,
    [int]$GatewayPort=47831,
    [ValidateSet(443,8443,10000)][int]$PublicPort=443,
    [int]$RecoveryIntervalSeconds=30,
    [int]$MaxProjectsPerTick=6,
    [bool]$Push=$true,
    [switch]$RetireClassicTransport,
    [switch]$SkipFunnel,
    [switch]$RepairUrlAcl,
    [switch]$CopyToClipboard,
    [switch]$KeepFunnel,
    [switch]$RemoveState
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not$IsWindows){throw 'The AIDOS repository handoff host bootstrap must run with PowerShell 7 in Windows.'}

$original=Join-Path $PSScriptRoot 'Invoke-AidosRepositoryHandoffHost.ps1'
if(-not(Test-Path -LiteralPath $original -PathType Leaf)){throw "Repository handoff host entrypoint is unavailable: $original"}

# The operator machine has proven that unqualified module-export lookup is not
# reliable across the Windows/UNC script scopes used by this host. Do not try
# to repair that with import-scope tricks. Materialize one temporary runtime
# copy beside the canonical host and make the two Windows-session calls
# explicitly module-qualified. Keeping the runtime copy in this directory
# preserves the canonical host's PSScriptRoot-relative imports.
$source=Get-Content -LiteralPath $original -Raw -Encoding UTF8
$replacements=[ordered]@{
    "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -DisableNameChecking" = "Import-Module (Join-Path `$PSScriptRoot 'AidosWindowsSession.psm1') -Force -Global -DisableNameChecking"
    '`$snapshot=Get-AidosInteractiveSessionSnapshot' = '`$snapshot=AidosWindowsSession\Get-AidosInteractiveSessionSnapshot'
    '`$authorization=Test-AidosAuthorizedInteractiveSession -Snapshot `$snapshot -AuthorizedUser `$ExpectedUser' = '`$authorization=AidosWindowsSession\Test-AidosAuthorizedInteractiveSession -Snapshot `$snapshot -AuthorizedUser `$ExpectedUser'
}
foreach($pair in $replacements.GetEnumerator()){
    $matches=[regex]::Matches($source,[regex]::Escape([string]$pair.Key)).Count
    if($matches-ne1){throw "Repository host bootstrap expected exactly one source match for: $($pair.Key); found $matches."}
    $source=$source.Replace([string]$pair.Key,[string]$pair.Value)
}

$runtimeHost=Join-Path $PSScriptRoot ('Invoke-AidosRepositoryHandoffHost.runtime.'+[guid]::NewGuid().ToString('N')+'.ps1')
$runtimeBytes=[Text.UTF8Encoding]::new($false).GetBytes($source)
$runtimeStream=[IO.FileStream]::new($runtimeHost,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
    $runtimeStream.Write($runtimeBytes,0,$runtimeBytes.Length)
    $runtimeStream.Flush($true)
}finally{
    $runtimeStream.Dispose()
}

try{
    $output=& $runtimeHost @PSBoundParameters

    if($Command-eq'Install'){
        $resolvedStateRoot=if([string]::IsNullOrWhiteSpace($StateRoot)){
            Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-host'
        }else{
            [IO.Path]::GetFullPath($StateRoot)
        }
        $configPath=Join-Path $resolvedStateRoot 'CONFIG.json'
        if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){
            throw 'Repository handoff host installation completed without durable CONFIG.json.'
        }

        # The canonical installer initially persists its own runtime path and
        # starts the task. Stop that task while the temporary runtime copy still
        # exists, atomically replace the durable entrypoint with this bootstrap,
        # then restart. Every later host/bridge/gateway command therefore passes
        # through the same module-qualified runtime materialization.
        $taskName='AIDOS Repository Handoff Host'
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

        $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
        $updated=[ordered]@{}
        foreach($property in $config.PSObject.Properties){$updated[$property.Name]=$property.Value}
        $updated.entry_point=$PSCommandPath
        $updated.bootstrap_entry_point=$PSCommandPath
        $updated.bootstrap_updated_at=[DateTimeOffset]::UtcNow.ToString('o')

        $temporary="$configPath.$([guid]::NewGuid().ToString('N')).tmp"
        try{
            $updated|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $temporary -Encoding utf8NoBOM
            Move-Item -LiteralPath $temporary -Destination $configPath -Force
        }finally{
            if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}
        }

        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
    }

    $output
}finally{
    if(Test-Path -LiteralPath $runtimeHost){Remove-Item -LiteralPath $runtimeHost -Force}
}
