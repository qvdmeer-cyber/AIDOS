Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosOperator.psm1') -DisableNameChecking

function Get-AidosRuntimeRegistryProjects {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects'
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $record=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
            if([string]$record.stage -eq 'RUNTIME' -and [string]$record.status -eq 'PROMOTED'){$record}
        }
    )
}

function Get-AidosRuntimeNextActor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    Test-AidosProjectBinding $root|Out-Null
    $state=Get-AidosState $root
    $control=Get-AidosOperatorControlState -ProjectRoot $root

    if([string]$control.mode -in @('PAUSED','SAFE_STOPPED')){
        return [pscustomobject][ordered]@{
            project_root=$root;project_state=[string]$state.state;control_mode=[string]$control.mode;
            actor_role=$null;actor_identity=$null;action='CONTROL_BLOCKED';priority=0;activatable=$false
        }
    }

    $selection=switch([string]$state.state){
        'IDLE' {[ordered]@{actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='START_DEFINITION';priority=100;activatable=$true}}
        'WAITING_DEFINITION' {[ordered]@{actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='RESUME_DEFINITION';priority=100;activatable=$true}}
        'WAITING_USER' {[ordered]@{actor_role='HUMAN';actor_identity='HUMAN';action='WAIT_HUMAN_INPUT';priority=10;activatable=$false}}
        'TASK_READY' {[ordered]@{actor_role='WORKER';actor_identity='EXECUTION_AGENT';action='DISPATCH_EXECUTION';priority=80;activatable=$true}}
        'QUEUED' {[ordered]@{actor_role='WORKER';actor_identity='EXECUTION_AGENT';action='RECONCILE_EXECUTION';priority=80;activatable=$true}}
        'CODEX_RUNNING' {[ordered]@{actor_role='WORKER';actor_identity='EXECUTION_AGENT';action='RECONCILE_EXECUTION';priority=80;activatable=$true}}
        'TERMINAL_PENDING' {[ordered]@{actor_role='THINKER';actor_identity='WORKER_AGENT';action='VALIDATE_AND_REVIEW';priority=90;activatable=$true}}
        'EXECUTION_VALIDATION_FAILED' {[ordered]@{actor_role='THINKER';actor_identity='WORKER_AGENT';action='PLAN_REPAIR';priority=90;activatable=$true}}
        'REVIEW_READY' {[ordered]@{actor_role='THINKER';actor_identity='WORKER_AGENT';action='REVIEW';priority=90;activatable=$true}}
        'WAITING_INTERACTIVE_SESSION' {[ordered]@{actor_role='THINKER';actor_identity='WORKER_AGENT';action='REVIEW';priority=90;activatable=$true}}
        'GPT_REVIEWING' {[ordered]@{actor_role='THINKER';actor_identity='WORKER_AGENT';action='RECONCILE_REVIEW';priority=90;activatable=$true}}
        'CONTEXT_ROTATION_REQUIRED' {[ordered]@{actor_role='THINKER';actor_identity='WORKER_AGENT';action='ROTATE_CONTEXT';priority=85;activatable=$true}}
        'DISCOVERY_REFRESH_REQUIRED' {[ordered]@{actor_role='THINKER';actor_identity='BUILDER';action='ROUTE_DISCOVERY_REFRESH';priority=95;activatable=$false}}
        'RECOVERY_REQUIRED' {[ordered]@{actor_role='THINKER';actor_identity='RECOVERY';action='REQUEST_RECOVERY';priority=100;activatable=$false}}
        'RELEASE_READY' {[ordered]@{actor_role=$null;actor_identity=$null;action='RELEASE_READY';priority=5;activatable=$false}}
        default {[ordered]@{actor_role=$null;actor_identity=$null;action='UNSUPPORTED_STATE';priority=0;activatable=$false}}
    }
    [pscustomobject][ordered]@{
        project_root=$root;project_state=[string]$state.state;control_mode=[string]$control.mode;
        actor_role=$selection.actor_role;actor_identity=$selection.actor_identity;action=$selection.action;
        priority=[int]$selection.priority;activatable=[bool]$selection.activatable
    }
}

function Invoke-AidosRuntimeProjectManagerTick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [int]$MaxProjects=1,
        [scriptblock]$ActorActivator
    )
    if($MaxProjects -lt 1){throw 'MaxProjects must be at least 1.'}
    $projects=@(Get-AidosRuntimeRegistryProjects -RegistryRoot $RegistryRoot)
    $candidates=[System.Collections.Generic.List[object]]::new()
    foreach($project in $projects){
        try {
            $null=Test-AidosRegistryProjectBinding $project
            $selection=Get-AidosRuntimeNextActor -ProjectRoot ([string]$project.local_root)
            $candidates.Add([pscustomobject][ordered]@{project=$project;selection=$selection})
        } catch {
            $candidates.Add([pscustomobject][ordered]@{project=$project;selection=[pscustomobject][ordered]@{project_root=[string]$project.local_root;project_state='UNKNOWN';control_mode='UNKNOWN';actor_role=$null;actor_identity=$null;action='BINDING_ERROR';priority=1000;activatable=$false;error=$_.Exception.Message}})
        }
    }
    $ordered=@($candidates|Sort-Object @{Expression={[int]$_.selection.priority};Descending=$true}, @{Expression={[string]$_.project.project_id};Descending=$false})
    $results=[System.Collections.Generic.List[object]]::new();$processed=0
    foreach($candidate in $ordered){
        if($processed -ge $MaxProjects){break}
        $selection=$candidate.selection
        $activation=$null
        $status='OBSERVED'
        if([bool]$selection.activatable){
            if($ActorActivator){
                try{$activation=& $ActorActivator $candidate.project $selection;$status='ACTIVATED'}catch{$status='ACTIVATION_ERROR';$activation=[pscustomobject]@{error=$_.Exception.Message}}
            }else{$status='ACTOR_ADAPTER_REQUIRED'}
            $processed++
        }
        $results.Add([pscustomobject][ordered]@{project_id=[string]$candidate.project.project_id;status=$status;selection=$selection;activation=$activation})
    }
    [pscustomobject][ordered]@{
        schema_version='0.1';registry_root=[IO.Path]::GetFullPath($RegistryRoot);observed_at=[DateTimeOffset]::UtcNow.ToString('o');
        runtime_project_count=$projects.Count;processed=$processed;results=@($results);
        status=if(@($results|Where-Object {$_.status -eq 'ACTIVATION_ERROR'}).Count){'ERROR'}elseif($processed -gt 0){'ACTIONABLE'}elseif($projects.Count -gt 0){'IDLE'}else{'EMPTY'}
    }
}

Export-ModuleMember -Function Get-AidosRuntimeRegistryProjects,Get-AidosRuntimeNextActor,Invoke-AidosRuntimeProjectManagerTick
