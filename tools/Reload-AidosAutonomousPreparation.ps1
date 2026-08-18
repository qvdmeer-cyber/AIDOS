[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$Distribution='Ubuntu',
    [string]$WslReposRoot='/home/aidos/repos',
    [string]$PreparationProjectId='AIDOS-INTERFACE',
    [string]$PreparationRepository='https://github.com/qvdmeer-cyber/AIDOS-interface.git',
    [string]$PreparationProjectName='AIDOS-interface',
    [string]$RuntimeProjectRoot,
    [string]$AuthorizedUser='AIDOS\qvdm'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'This reload must run with PowerShell 7 on the Windows AIDOS host.'}
if([string]::IsNullOrWhiteSpace($StateRoot)){$StateRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'}

function Test-AidosLeaseProcessIdentity {
    param([Parameter(Mandatory)]$Lease,[Parameter(Mandatory)]$Process)
    if([int]$Lease.pid -ne [int]$Process.Id){return $false}
    # ConvertFrom-Json materializes ISO timestamps as DateTime.  Stringifying that
    # value is culture-dependent, so compare the stable UTC tick identity instead.
    $expected=([DateTimeOffset]$Lease.process_started_at).UtcDateTime.Ticks
    $actual=$Process.StartTime.ToUniversalTime().Ticks
    $expected -eq $actual
}

function Stop-AidosLeasedHostAgentProcess {
    param([Parameter(Mandatory)][string]$Root)
    $leasePath=Join-Path $Root 'LEASE.json'
    if(-not(Test-Path -LiteralPath $leasePath -PathType Leaf)){return [pscustomobject]@{status='NO_LEASE';pid=$null}}
    $lease=Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
    if($null-eq$lease.pid -or [string]::IsNullOrWhiteSpace([string]$lease.process_started_at)){throw 'AIDOS host-agent lease is malformed; refusing to terminate any process.'}
    $process=Get-Process -Id ([int]$lease.pid) -ErrorAction SilentlyContinue
    if($process){
        if(-not(Test-AidosLeaseProcessIdentity -Lease $lease -Process $process)){throw 'AIDOS host-agent lease PID identity no longer matches the live process; refusing force termination.'}
        if([string]$process.ProcessName -notin @('pwsh','pwsh.exe')){throw "AIDOS host-agent lease points to unexpected process '$($process.ProcessName)'; refusing force termination."}
        Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
        for($attempt=0;$attempt -lt40;$attempt++){
            Start-Sleep -Milliseconds 250
            if(-not(Get-Process -Id ([int]$process.Id) -ErrorAction SilentlyContinue)){break}
        }
        if(Get-Process -Id ([int]$process.Id) -ErrorAction SilentlyContinue){throw 'AIDOS leased host-agent process did not terminate within the bounded reload window.'}
    }
    if(Test-Path -LiteralPath $leasePath -PathType Leaf){
        $current=Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
        if([string]$current.owner_id -ne [string]$lease.owner_id -or [int]$current.pid -ne [int]$lease.pid){throw 'AIDOS host-agent lease changed ownership during reload; refusing cleanup.'}
        Remove-Item -LiteralPath $leasePath -Force
    }
    [pscustomobject]@{status='LEASED_AGENT_STOPPED';pid=[int]$lease.pid;owner_id=[string]$lease.owner_id}
}

# The scheduled task is a stable bootstrap. Reloads terminate only the exactly
# leased AIDOS child; task registration/ACLs are never changed during upgrades.
$stopped=Stop-AidosLeasedHostAgentProcess -Root $StateRoot

$enable=Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Enable-AidosAutonomousPreparation.ps1'
if(-not(Test-Path -LiteralPath $enable -PathType Leaf)){throw "AIDOS enable script is unavailable: $enable"}
& $enable -Distribution $Distribution -WslReposRoot $WslReposRoot -PreparationProjectId $PreparationProjectId -PreparationRepository $PreparationRepository -PreparationProjectName $PreparationProjectName -RuntimeProjectRoot $RuntimeProjectRoot -AuthorizedUser $AuthorizedUser
