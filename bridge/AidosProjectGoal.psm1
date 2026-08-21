Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDefinitionRuntime.psm1') -DisableNameChecking

function Get-AidosProjectGoalRoot {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/goals'
}
function Get-AidosProjectGoalPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$GoalId)
    Join-Path (Get-AidosProjectGoalRoot -ProjectRoot $ProjectRoot) ($GoalId+'.json')
}
function Get-AidosDefinitionProjectGoal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$DefinitionId,[Parameter(Mandatory)][int]$DefinitionVersion)
    $goalRoot=Get-AidosProjectGoalRoot -ProjectRoot $ProjectRoot
    if(-not(Test-Path -LiteralPath $goalRoot -PathType Container)){return $null}
    $matches=@(Get-ChildItem -LiteralPath $goalRoot -Filter '*.json' -File|ForEach-Object {
        try{$goal=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50}catch{throw "Project goal record is invalid JSON: $($_.FullName)"}
        if([string]$goal.definition_id-eq$DefinitionId -and [int]$goal.definition_version-eq$DefinitionVersion){[pscustomobject]@{path=$_.FullName;goal=$goal}}
    })
    if($matches.Count-gt1){throw 'Multiple project goals bind the same Definition.'}
    if($matches.Count-eq0){return $null}
    $matches[0]
}
function Submit-AidosProjectGoal {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$Goal,[ValidateSet('CHATGPT_OPERATOR','HUMAN')][string]$SubmittedBy='CHATGPT_OPERATOR',[switch]$Push)
    Test-AidosRegistryProjectBinding -Project $Project|Out-Null
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$text=$Goal.Trim()
    if($text.Length-lt10){throw 'Project goal must contain at least 10 non-whitespace characters.'}
    if($text.Length-gt12000){throw 'Project goal exceeds the 12000-character limit.'}
    if($text.IndexOf([char]0)-ge0){throw 'Project goal contains a forbidden NUL character.'}
    $state=Get-AidosState -ProjectRoot $root
    if([string]$state.state-ne'IDLE'){throw "A new project goal requires IDLE state; current state is '$($state.state)'."}
    if([string]::IsNullOrWhiteSpace([string]$state.definition_id)){throw 'Initial project Definition must be started by the existing onboarding lifecycle.'}
    $controlPath=Join-Path $root '.aidos/runtime/operator-control.json'
    if(Test-Path -LiteralPath $controlPath -PathType Leaf){$control=Get-Content -LiteralPath $controlPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20;if([string]$control.mode-ne'RUNNING'){throw "Project control mode is '$($control.mode)'; submit START before a new goal."}}
    if(Test-Path -LiteralPath (Join-Path $root '.aidos/runtime/lease.json') -PathType Leaf){throw 'A new project goal is blocked by an active execution lease.'}
    $goalId=('GOAL-'+[guid]::NewGuid().ToString());$definitionId=('DEF-'+[guid]::NewGuid().ToString());$now=[DateTimeOffset]::UtcNow.ToString('o')
    $record=[ordered]@{schema_version='0.1';goal_id=$goalId;project_id=[string]$Project.project_id;status='ACTIVE';goal=$text;submitted_by=$SubmittedBy;channel=if($SubmittedBy-eq'CHATGPT_OPERATOR'){'CHATGPT'}else{'LOCAL'};submitted_at=$now;previous_definition_id=[string]$state.definition_id;previous_definition_version=[int]$state.definition_version;definition_id=$definitionId;definition_version=1}
    $goalPath=Get-AidosProjectGoalPath -ProjectRoot $root -GoalId $goalId;Write-AidosJsonAtomic -Path $goalPath -Value $record
    try{
        $newState=Set-AidosState -ProjectRoot $root -NewState WAITING_DEFINITION -Actor HUMAN -Patch @{definition_id=$definitionId;definition_version=1;execution_id=$null;revision=$null;codex_session_id=$null;review_id=$null;lease_id=$null;terminal_result=$null;validation_result=$null}
        $workspace=Ensure-AidosDefinitionWorkspace -ProjectRoot $root
        Add-AidosEvent -ProjectRoot $root -EventType 'PROJECT_GOAL_ACCEPTED' -Actor HUMAN -Payload @{goal_id=$goalId;goal_ref=[IO.Path]::GetRelativePath($root,$goalPath).Replace('\','/');definition_id=$definitionId;definition_version=1;submitted_by=$SubmittedBy}|Out-Null
        $persistence=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS accept project goal $goalId") -Push:$Push
    }catch{
        $current=Get-AidosState -ProjectRoot $root
        if([string]$current.definition_id-ne$definitionId -and(Test-Path -LiteralPath $goalPath -PathType Leaf)){Remove-Item -LiteralPath $goalPath -Force}
        throw
    }
    [pscustomobject][ordered]@{status='ACCEPTED';project_id=[string]$Project.project_id;goal_id=$goalId;goal_ref=[IO.Path]::GetRelativePath($root,$goalPath).Replace('\','/');definition_id=$definitionId;definition_version=1;project_state=[string]$newState.state;acknowledgement=("AIDOS_GOAL_ACCEPTED::$goalId");persistence=$persistence;workspace=$workspace}
}
Export-ModuleMember -Function Get-AidosProjectGoalRoot,Get-AidosProjectGoalPath,Get-AidosDefinitionProjectGoal,Submit-AidosProjectGoal
