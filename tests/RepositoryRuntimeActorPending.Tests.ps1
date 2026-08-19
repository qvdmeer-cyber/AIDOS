[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorAssignments.psm1') -Force -DisableNameChecking

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-actor-pending-'+[guid]::NewGuid().ToString('N'))
$assignmentRoot=Join-Path $temp '.aidos/runtime/actor-assignments'
$transportRoot=Join-Path $temp '.aidos/runtime/actor-transport'
New-Item -ItemType Directory -Path $assignmentRoot,$transportRoot -Force|Out-Null
try {
    $cases=[ordered]@{
        no_transport=$null
        pending='PENDING'
        waiting='WAITING_TRANSPORT'
        activated='ACTIVATED'
        completed='COMPLETED'
        consumed='CONSUMED'
        failed='FAILED'
        abandoned='ABANDONED'
    }
    foreach($name in $cases.Keys){
        $id="assignment-$name"
        [ordered]@{schema_version='0.1';assignment_id=$id;project_id='TEST';actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='RESUME_DEFINITION';binding=[ordered]@{definition_id='DEF-1';definition_version=1}}|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $assignmentRoot "$id.json") -Encoding utf8NoBOM
        $status=$cases[$name]
        if($null-ne$status){
            [ordered]@{schema_version='0.1';assignment_id=$id;status=$status}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $transportRoot "$id.json") -Encoding utf8NoBOM
        }
    }

    $pending=@(Get-AidosPendingRuntimeActorAssignments -ProjectRoot $temp|ForEach-Object {[string]$_.assignment_id})
    $expected=@('assignment-activated','assignment-no_transport','assignment-pending','assignment-waiting')|Sort-Object
    $actual=@($pending|Sort-Object)
    if(($actual -join '|') -ne ($expected -join '|')){throw "ASSERTION FAILED: pending assignments were '$($actual -join ',')', expected '$($expected -join ',')'."}
    if($pending -contains 'assignment-completed'){throw 'ASSERTION FAILED: COMPLETED assignment must not be redispatched.'}
    Write-Output 'PASS: completed actor result is excluded from pending dispatch'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
