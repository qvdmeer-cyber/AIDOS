[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosPersistentLocalDesktopAgent.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -DisableNameChecking
$script:passed=0
function Assert-Dispatch([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$dispatcherText=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosPreparationDispatcher.psm1') -Raw
Assert-Dispatch (-not($dispatcherText -match '\$IsWindows')) 'runtime actor transport platform gate does not depend on the optional IsWindows automatic variable'
$expectedWindows=[Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
Assert-Dispatch ((Test-AidosWindowsRuntimeHost) -eq $expectedWindows) 'runtime actor transport host detection follows the actual OS runtime'

$projectRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-dispatch-gate-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    [ordered]@{schema_version='0.1';project_id='DISPATCH-SMOKE';project_mode='NEW_PROJECT';official_root=$projectRoot;repository='https://example.invalid/dispatch.git'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=0;review_id=$null;updated_at='2026-08-17T21:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM

    $global:AidosPreparationDispatchTouched=$false
    $locked=[pscustomobject]@{observed_at='2026-08-17T21:00:00Z';session_id=8;process_session_id=8;active_console_session_id=8;connection_state='ACTIVE';lock_state='LOCKED';session_kind='CONSOLE';protocol_type=0;input_desktop_available=$false;user_name='qvdm';domain_name='AIDOS';winstation_name='Console';observation_status='OK';error=$null}
    $tick=Invoke-AidosHostAgentTick -ProjectRoot $projectRoot -AuthorizedUser 'AIDOS\qvdm' -PreparationDispatcher {$global:AidosPreparationDispatchTouched=$true;[pscustomobject]@{status='PROCESSED';processed=1}} -SnapshotProvider {$locked} -ShellHealthProvider {throw 'shell must not be checked for locked session'} -ReviewReconciler {throw 'review must not run for locked session'} -DesktopReviewInvoker {throw 'desktop must not run for locked session'}
    Assert-Dispatch $global:AidosPreparationDispatchTouched 'preparation dispatcher runs before desktop authorization gate'
    Assert-Dispatch ($tick.status -eq 'WAITING_INFRASTRUCTURE' -and $tick.preparation_result.status -eq 'PROCESSED') 'locked desktop does not discard completed preparation work'

    $global:AidosPreparationDispatchTouched=$false
    $unlocked=[pscustomobject]@{observed_at='2026-08-17T21:00:01Z';session_id=8;process_session_id=8;active_console_session_id=8;connection_state='ACTIVE';lock_state='UNLOCKED';session_kind='CONSOLE';protocol_type=0;input_desktop_available=$true;user_name='qvdm';domain_name='AIDOS';winstation_name='Console';observation_status='OK';error=$null}
    [ordered]@{schema_version='0.1';mode='PAUSED';requested_by='TEST';control_id='pause-1';updated_at='2026-08-17T21:00:01Z'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/runtime/operator-control.json') -Encoding utf8NoBOM
    $paused=Invoke-AidosHostAgentTick -ProjectRoot $projectRoot -AuthorizedUser 'AIDOS\qvdm' -PreparationDispatcher {$global:AidosPreparationDispatchTouched=$true;[pscustomobject]@{status='IDLE';processed=0}} -SnapshotProvider {$unlocked} -ShellHealthProvider {[pscustomobject]@{status='HEALTHY'}} -ReviewReconciler {throw 'paused runtime must not review'} -DesktopReviewInvoker {throw 'paused runtime must not use desktop'}
    Assert-Dispatch $global:AidosPreparationDispatchTouched 'preparation dispatch is independent from runtime Worker pause gate'
    Assert-Dispatch ($paused.status -eq 'PAUSED') 'existing runtime pause semantics remain intact'
} finally {
    Remove-Variable -Name AidosPreparationDispatchTouched -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $projectRoot){Remove-Item -LiteralPath $projectRoot -Recurse -Force}
}
Write-Output "PASS: $passed preparation dispatcher assertions"
