Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDefinitionResultConsumer.psm1') -DisableNameChecking

function Get-AidosConsumerRuntimeProjects {
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
function Get-AidosProjectApplicabilityProposal {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ActorResult)
    $payload=$ActorResult.result
    if($null -eq $payload){throw 'Runtime actor result has no result payload.'}
    if([string]$payload.result_type -eq 'PROJECT_APPLICABILITY_PROPOSAL'){return $payload}
    if([string]$payload.result_type -eq 'DEFINITION_THINKER_OUTPUT'){
        $matches=@($payload.proposed_artifacts|Where-Object {[string]$_.artifact_type -eq 'PROJECT_APPLICABILITY_PROPOSAL'})
        if($matches.Count-ne1){throw 'Applicability Thinker output must contain exactly one PROJECT_APPLICABILITY_PROPOSAL artifact.'}
        return $matches[0]
    }
    throw "Unsupported applicability actor result type '$($payload.result_type)'."
}
function Assert-AidosActorSourceRefs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][object[]]$SourceRefs)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    if($SourceRefs.Count-eq0){throw 'Repository-verifiable actor result requires source_refs.'}
    $comparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    $prefix=$root+[IO.Path]::DirectorySeparatorChar
    foreach($ref in $SourceRefs){
        $relative=([string]$ref).Replace('\','/')
        if([string]::IsNullOrWhiteSpace($relative)-or[IO.Path]::IsPathRooted($relative)){throw 'Actor source_ref must be a project-relative path.'}
        $path=[IO.Path]::GetFullPath((Join-Path $root $relative))
        if(-not$path.StartsWith($prefix,$comparison)){throw "Actor source_ref escapes project root: $relative"}
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Actor source_ref does not exist: $relative"}
        $allowed=($relative -eq '.aidos/documentation/PROJECT_BASELINE.json' -or $relative -eq '.aidos/documentation/PROJECT_ACCESS.json' -or $relative -eq '.aidos/evidence/EVIDENCE_INVENTORY.json' -or $relative -eq 'AGENTS.md' -or $relative.StartsWith('docs/',[StringComparison]::Ordinal))
        if(-not$allowed){throw "Actor source_ref is outside the authorized canonical source set: $relative"}
    }
    $true
}
function Test-AidosApplicabilityProfileMatchesProposal {
    param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)][string[]]$PresetIds,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Overrides)
    $actualPresets=@($Profile.selected_presets|ForEach-Object {[string]$_.preset_id}|Sort-Object -Unique)
    $expectedPresets=@($PresetIds|Sort-Object -Unique)
    if(($actualPresets -join "`n") -ne ($expectedPresets -join "`n")){return $false}
    $actualOverrides=@($Profile.overrides|ForEach-Object {[ordered]@{surface_id=[string]$_.surface_id;state=[string]$_.state;reason=[string]$_.reason;source_ref=[string]$_.source_ref}})
    $expectedOverrides=@($Overrides|ForEach-Object {[ordered]@{surface_id=[string]$_.surface_id;state=[string]$_.state;reason=[string]$_.reason;source_ref=[string]$_.source_ref}})
    (ConvertTo-Json $actualOverrides -Depth 20 -Compress) -eq (ConvertTo-Json $expectedOverrides -Depth 20 -Compress)
}
function Invoke-AidosProjectApplicabilityResultConsumer {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$ActorResult,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $binding=Test-AidosRuntimeActorResultBinding -ProjectRoot $root -Result $ActorResult
    $bound=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId ([string]$ActorResult.assignment_id)
    if([string]$bound.assignment.action -ne 'RESOLVE_PROJECT_APPLICABILITY'){throw 'Project Applicability consumer received the wrong actor action.'}
    if([string]$ActorResult.outcome -ne 'COMPLETED'){throw "Project Applicability actor outcome '$($ActorResult.outcome)' requires a different consumer path."}
    $state=Get-AidosState $root
    if([string]$state.state-ne'IDLE' -or -not[string]::IsNullOrWhiteSpace([string]$state.definition_id)){throw 'Project Applicability consumption requires pre-Definition IDLE state.'}
    $proposal=Get-AidosProjectApplicabilityProposal -ActorResult $ActorResult
    if([string]$proposal.authority_classification -ne 'REPO_VERIFIABLE'){throw 'Project Applicability proposal must be REPO_VERIFIABLE or remain a human/auto-decision boundary.'}
    $sourceRefs=@($proposal.source_refs);Assert-AidosActorSourceRefs -ProjectRoot $root -SourceRefs $sourceRefs|Out-Null
    $presetIds=@($proposal.preset_ids|ForEach-Object {[string]$_}|Where-Object {-not[string]::IsNullOrWhiteSpace($_)}|Select-Object -Unique)
    if($presetIds.Count-eq0){throw 'Project Applicability proposal requires at least one preset_id.'}
    $selectionSource=[string]$proposal.selection_source;if([string]::IsNullOrWhiteSpace($selectionSource)){$selectionSource='BASELINE_DERIVED'}
    if($selectionSource-ne'BASELINE_DERIVED'){throw "New-project repository-verifiable applicability must use BASELINE_DERIVED, not '$selectionSource'."}
    $overrides=@($proposal.overrides)
    foreach($override in $overrides){if([string]::IsNullOrWhiteSpace([string]$override.source_ref)){throw 'Every Project Applicability override requires source_ref.'};Assert-AidosActorSourceRefs -ProjectRoot $root -SourceRefs @([string]$override.source_ref)|Out-Null}
    $overridesJson=if($overrides.Count-eq0){'[]'}else{$overrides|ConvertTo-Json -Depth 100 -Compress}
    $profilePath=Join-Path $root '.aidos/profile/PROJECT_APPLICABILITY.json'
    if(Test-Path -LiteralPath $profilePath -PathType Leaf){
        $existingProfile=Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
        if(-not(Test-AidosApplicabilityProfileMatchesProposal -Profile $existingProfile -PresetIds $presetIds -Overrides $overrides)){throw 'Existing Project Applicability does not match completed actor result; refusing idempotent consume.'}
        Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId ([string]$ActorResult.assignment_id) -Status CONSUMED|Out-Null
        $persist=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS consume actor result $($ActorResult.assignment_id)") -Push:$Push
        return [pscustomobject][ordered]@{status='ALREADY_APPLIED';assignment_id=[string]$ActorResult.assignment_id;profile_ref='.aidos/profile/PROJECT_APPLICABILITY.json';persistence=$persist}
    }
    $resolveTool=Join-Path ([IO.Path]::GetFullPath($AidosRoot)) 'tools/Resolve-AidosProjectApplicability.ps1';$catalogTest=Join-Path ([IO.Path]::GetFullPath($AidosRoot)) 'tools/Test-AidosProfileCatalog.ps1'
    if(-not(Test-Path -LiteralPath $resolveTool -PathType Leaf)){throw 'Project Applicability resolver is unavailable.'}
    & $catalogTest -AidosRoot $AidosRoot|Out-Null
    $resolved=& $resolveTool -ProjectRoot $root -ProjectId ([string]$Project.project_id) -PresetIds $presetIds -SelectionSource $selectionSource -OverridesJson $overridesJson -AidosRoot $AidosRoot
    if([string]$resolved.project_id-ne[string]$Project.project_id){throw 'Resolved Project Applicability project binding mismatch.'}
    if(-not(Test-Path -LiteralPath $profilePath -PathType Leaf)){throw 'Project Applicability resolver did not persist its canonical output.'}
    $profile=Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    if([string]$profile.project_id-ne[string]$Project.project_id){throw 'Persisted Project Applicability project_id mismatch.'}
    if(@($profile.selected_presets|Where-Object {$_.category-eq'PRODUCT_ARCHETYPE'}).Count-ne1){throw 'Persisted Project Applicability must contain exactly one product archetype.'}
    if(-not(Test-AidosApplicabilityProfileMatchesProposal -Profile $profile -PresetIds $presetIds -Overrides $overrides)){throw 'Persisted Project Applicability does not match actor proposal.'}
    Add-AidosEvent -ProjectRoot $root -EventType 'PROJECT_APPLICABILITY_RESOLVED' -Actor DEFINITION_AGENT -Payload @{assignment_id=[string]$ActorResult.assignment_id;preset_ids=$presetIds;source_refs=$sourceRefs}|Out-Null
    Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId ([string]$ActorResult.assignment_id) -Status CONSUMED|Out-Null
    $persist=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS consume actor result $($ActorResult.assignment_id)") -Push:$Push
    [pscustomobject][ordered]@{status='APPLIED';assignment_id=[string]$ActorResult.assignment_id;profile_ref='.aidos/profile/PROJECT_APPLICABILITY.json';selected_presets=@($profile.selected_presets);unresolved_count=@($profile.resolved_surfaces|Where-Object {$_.state-eq'UNRESOLVED'}).Count;persistence=$persist;binding=$binding}
}
function Invoke-AidosRuntimeActorResultConsumerTick {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),[string]$ContractsRoot,[int]$MaxItems=1,[switch]$Push)
    $results=[System.Collections.Generic.List[object]]::new();$processed=0
    foreach($project in @(Get-AidosConsumerRuntimeProjects -RegistryRoot $RegistryRoot)){
        if($processed-ge$MaxItems){break}
        $transportRoot=Join-Path ([string]$project.local_root) '.aidos/runtime/actor-transport';if(-not(Test-Path -LiteralPath $transportRoot -PathType Container)){continue}
        foreach($file in @(Get-ChildItem -LiteralPath $transportRoot -Filter '*.json' -File|Sort-Object Name)){
            if($processed-ge$MaxItems){break}
            $transport=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50;if([string]$transport.status-ne'COMPLETED'){continue}
            try{
                if([string]::IsNullOrWhiteSpace([string]$transport.result_ref)){throw 'Completed actor transport has no result_ref.'}
                $resultPath=Join-Path ([string]$project.local_root) ([string]$transport.result_ref);if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Completed actor result file is missing.'}
                $actorResult=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
                $assignment=Read-AidosRuntimeActorAssignment -ProjectRoot ([string]$project.local_root) -AssignmentId ([string]$transport.assignment_id)
                $action=[string]$assignment.assignment.action
                $outcome=switch($action){
                    'RESOLVE_PROJECT_APPLICABILITY' {Invoke-AidosProjectApplicabilityResultConsumer -Project $project -ActorResult $actorResult -AidosRoot $AidosRoot -Push:$Push}
                    'START_DEFINITION' {
                        if([string]::IsNullOrWhiteSpace($ContractsRoot)){throw 'Definition result consumption requires ContractsRoot.'}
                        $definition=Invoke-AidosDefinitionThinkerResultConsumer -Project $project -ActorResult $actorResult -ContractsRoot $ContractsRoot -AidosRoot $AidosRoot -Push:$Push
                        $persist=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage ("AIDOS consume actor result $($actorResult.assignment_id)") -Push:$Push
                        [pscustomobject][ordered]@{status=[string]$definition.status;definition=$definition;persistence=$persist}
                    }
                    'RESUME_DEFINITION' {
                        if([string]::IsNullOrWhiteSpace($ContractsRoot)){throw 'Definition result consumption requires ContractsRoot.'}
                        $definition=Invoke-AidosDefinitionThinkerResultConsumer -Project $project -ActorResult $actorResult -ContractsRoot $ContractsRoot -AidosRoot $AidosRoot -Push:$Push
                        $persist=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage ("AIDOS consume actor result $($actorResult.assignment_id)") -Push:$Push
                        [pscustomobject][ordered]@{status=[string]$definition.status;definition=$definition;persistence=$persist}
                    }
                    default {throw "No Core consumer exists yet for runtime actor action '$action'."}
                }
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;assignment_id=[string]$transport.assignment_id;status=[string]$outcome.status;outcome=$outcome})
            }catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;assignment_id=[string]$transport.assignment_id;status='CONSUME_ERROR';error=$_.Exception.Message})}
            $processed++
        }
    }
    [pscustomobject][ordered]@{schema_version='0.2';observed_at=[DateTimeOffset]::UtcNow.ToString('o');processed=$processed;results=@($results);status=if(@($results|Where-Object {$_.status-eq'CONSUME_ERROR'}).Count){'ERROR'}elseif($processed-gt0){'PROCESSED'}else{'IDLE'}}
}

Export-ModuleMember -Function Get-AidosConsumerRuntimeProjects,Get-AidosProjectApplicabilityProposal,Assert-AidosActorSourceRefs,Test-AidosApplicabilityProfileMatchesProposal,Invoke-AidosProjectApplicabilityResultConsumer,Invoke-AidosRuntimeActorResultConsumerTick
