[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeProjectManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorTransport.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Transport([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-actor-transport-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $base 'project'
try {
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime') -Force|Out-Null
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'aidos-tests@example.invalid'
    & git -C $projectRoot config user.name 'AIDOS Tests'
    & git -C $projectRoot remote add origin 'https://example.invalid/runtime-transport.git'
    [ordered]@{schema_version='0.1';project_id='RUNTIME-TRANSPORT';project_mode='NEW_PROJECT';repository='https://example.invalid/runtime-transport.git';official_root=$projectRoot;runner_policy='UNATTENDED_ALLOWED';git_runtime=[ordered]@{kind='NATIVE';project_root=$projectRoot;git_path='git'}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='RUNTIME-TRANSPORT';state='IDLE';definition_id=$null;definition_version=$null;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;git_head=$null;validation_result=$null;updated_at='2026-08-18T00:00:00Z'}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    & git -C $projectRoot add .
    & git -C $projectRoot commit -q -m init

    $project=[pscustomobject]@{project_id='RUNTIME-TRANSPORT';local_root=$projectRoot}
    $selection=Get-AidosRuntimeNextActor -ProjectRoot $projectRoot
    $created=New-AidosRuntimeActorAssignment -Project $project -Selection $selection
    $assignment=$created.assignment
    $sha=[string]$created.assignment_sha256

    $transport=Initialize-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$assignment.assignment_id)
    Assert-Transport ($transport.status -eq 'PENDING' -and $transport.assignment_sha256 -eq $sha) 'transport state binds immutable assignment hash'
    $waiting=Set-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$assignment.assignment_id) -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError 'WINDOWS_LOCKED_OR_SESSION_UNAVAILABLE'
    Assert-Transport ($waiting.status -eq 'WAITING_TRANSPORT') 'assignment may wait for a transport adapter without changing assignment'
    $statePath=Get-AidosRuntimeActorTransportStatePath -ProjectRoot $projectRoot -AssignmentId ([string]$assignment.assignment_id)
    $waitingHash=(Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
    Start-Sleep -Milliseconds 20
    $null=Set-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$assignment.assignment_id) -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError 'WINDOWS_LOCKED_OR_SESSION_UNAVAILABLE'
    $waitingReplayHash=(Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
    Assert-Transport ($waitingReplayHash -eq $waitingHash) 'identical WAITING_TRANSPORT replay is a semantic no-op'
    $activated=Set-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$assignment.assignment_id) -Status ACTIVATED -TransportType TEST
    Assert-Transport ($activated.status -eq 'ACTIVATED' -and $activated.transport_type -eq 'TEST') 'transport activation is explicit'

    $result=[pscustomobject][ordered]@{
        schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$assignment.assignment_id;assignment_sha256=$sha;
        project_id=[string]$assignment.project_id;actor_role=[string]$assignment.actor_role;actor_identity=[string]$assignment.actor_identity;action=[string]$assignment.action;
        binding=$assignment.binding;outcome='COMPLETED';result=[pscustomobject]@{kind='TEST_RESULT'};responded_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    $saved=Save-AidosRuntimeActorResult -ProjectRoot $projectRoot -Result $result
    Assert-Transport ($saved.status -eq 'SAVED') 'exact-bound actor result is saved'
    $completed=Read-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$assignment.assignment_id)
    Assert-Transport ($completed.status -eq 'COMPLETED' -and -not[string]::IsNullOrWhiteSpace([string]$completed.result_ref)) 'saved result reaches completed transport state'
    Assert-Transport (@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $projectRoot).Count -eq 0) 'COMPLETED result is excluded from the pending dispatch scheduler before Core consumption'
    $again=Save-AidosRuntimeActorResult -ProjectRoot $projectRoot -Result $result
    Assert-Transport ($again.status -eq 'ALREADY_SAVED') 'identical actor result replay is idempotent'

    $badHash=$result|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $badHash.assignment_sha256=('0'*64)
    $threw=$false
    try{Test-AidosRuntimeActorResultBinding -ProjectRoot $projectRoot -Result $badHash|Out-Null}catch{$threw=$true}
    Assert-Transport $threw 'assignment hash mismatch fails closed'

    $badBinding=$result|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
    $badBinding.binding.definition_id='DEF-WRONG'
    $threw=$false
    try{Test-AidosRuntimeActorResultBinding -ProjectRoot $projectRoot -Result $badBinding|Out-Null}catch{$threw=$true}
    Assert-Transport $threw 'Definition binding mismatch fails closed'

    $consumed=Set-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId ([string]$assignment.assignment_id) -Status CONSUMED
    Assert-Transport ($consumed.status -eq 'CONSUMED') 'Core may explicitly close completed result as consumed'
    Assert-Transport (@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $projectRoot).Count -eq 0) 'CONSUMED keeps assignment out of pending scheduler set'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed runtime actor transport assertions"
