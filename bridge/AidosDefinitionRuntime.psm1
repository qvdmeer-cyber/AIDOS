Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking

function Get-AidosDefinitionWorkspacePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$DefinitionId,
        [Parameter(Mandatory)][int]$DefinitionVersion
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $definitionRoot=Join-Path $root ('.aidos/definitions/{0}/v{1}' -f $DefinitionId,$DefinitionVersion)
    [pscustomobject][ordered]@{
        root=$definitionRoot
        applicability=(Join-Path $definitionRoot 'APPLICABILITY.json')
        progress=(Join-Path $definitionRoot 'PROGRESS.json')
    }
}

function Test-AidosDefinitionWorkspaceBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$DefinitionId,
        [Parameter(Mandatory)][int]$DefinitionVersion
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $binding=Test-AidosProjectBinding $root
    $state=Get-AidosState $root
    if([string]$state.state -ne 'WAITING_DEFINITION'){throw "Definition workspace requires WAITING_DEFINITION state, found '$($state.state)'."}
    if([string]$state.definition_id -ne $DefinitionId -or [int]$state.definition_version -ne $DefinitionVersion){throw 'Definition workspace state binding mismatch.'}
    if(-not(Test-Path -LiteralPath (Join-Path $root '.aidos/profile/PROJECT_APPLICABILITY.json') -PathType Leaf)){throw 'Definition workspace requires Project Applicability.'}
    [pscustomobject][ordered]@{valid=$true;project_id=[string]$binding.ProjectId;definition_id=$DefinitionId;definition_version=$DefinitionVersion}
}

function Assert-AidosExistingDefinitionWorkspaceArtifactBinding {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$DefinitionId,
        [Parameter(Mandatory)][int]$DefinitionVersion,
        [Parameter(Mandatory)][string]$ArtifactName
    )
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
    $artifact=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    if([string]$artifact.project_id -ne $ProjectId -or [string]$artifact.definition_id -ne $DefinitionId -or [int]$artifact.definition_version -ne $DefinitionVersion){throw "$ArtifactName binding mismatch."}
    $true
}

function Ensure-AidosDefinitionWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$AidosRoot=(Split-Path $PSScriptRoot -Parent)
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $state=Get-AidosState $root
    if([string]::IsNullOrWhiteSpace([string]$state.definition_id) -or $null -eq $state.definition_version){throw 'Definition workspace requires exact Definition identity in project state.'}
    $definitionId=[string]$state.definition_id
    $definitionVersion=[int]$state.definition_version
    $binding=Test-AidosDefinitionWorkspaceBinding -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion
    $paths=Get-AidosDefinitionWorkspacePaths -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion
    $aidos=[IO.Path]::GetFullPath($AidosRoot)

    $applicabilityInitializer=Join-Path $aidos 'tools/New-AidosDefinitionApplicability.ps1'
    $progressInitializer=Join-Path $aidos 'tools/New-AidosDefinitionProgress.ps1'
    $applicabilityValidator=Join-Path $aidos 'tools/Test-AidosDefinitionApplicability.ps1'
    $progressValidator=Join-Path $aidos 'tools/Test-AidosDefinitionProgress.ps1'
    foreach($tool in @($applicabilityInitializer,$progressInitializer,$applicabilityValidator,$progressValidator)){
        if(-not(Test-Path -LiteralPath $tool -PathType Leaf)){throw "Definition workspace tool unavailable: $tool"}
    }

    $created=[System.Collections.Generic.List[string]]::new()
    if(-not(Assert-AidosExistingDefinitionWorkspaceArtifactBinding -Path $paths.applicability -ProjectId ([string]$binding.project_id) -DefinitionId $definitionId -DefinitionVersion $definitionVersion -ArtifactName 'Definition Applicability')){
        & $applicabilityInitializer -ProjectRoot $root -ProjectId ([string]$binding.project_id) -DefinitionId $definitionId -DefinitionVersion $definitionVersion | Out-Null
        $created.Add('.aidos/definitions/'+$definitionId+'/v'+$definitionVersion+'/APPLICABILITY.json')
    }
    if(-not(Assert-AidosExistingDefinitionWorkspaceArtifactBinding -Path $paths.progress -ProjectId ([string]$binding.project_id) -DefinitionId $definitionId -DefinitionVersion $definitionVersion -ArtifactName 'Definition Progress')){
        & $progressInitializer -ProjectRoot $root -ProjectId ([string]$binding.project_id) -DefinitionId $definitionId -DefinitionVersion $definitionVersion | Out-Null
        $created.Add('.aidos/definitions/'+$definitionId+'/v'+$definitionVersion+'/PROGRESS.json')
    }

    $applicabilityCheck=& $applicabilityValidator -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -NoExit
    if(-not[bool]$applicabilityCheck.pass){throw "Definition Applicability validation failed: $(@($applicabilityCheck.errors) -join '; ')"}
    $progressCheck=& $progressValidator -ProjectRoot $root -DefinitionId $definitionId -DefinitionVersion $definitionVersion -NoExit
    if(-not[bool]$progressCheck.pass){throw "Definition Progress validation failed: $(@($progressCheck.errors) -join '; ')"}

    Add-AidosEvent -ProjectRoot $root -EventType 'DEFINITION_WORKSPACE_READY' -Actor SYSTEM -Payload @{definition_id=$definitionId;definition_version=$definitionVersion;created=@($created);applicability_unresolved=[int]$applicabilityCheck.unresolved_count;progress_incomplete=[int]$progressCheck.incomplete_count}|Out-Null
    [pscustomobject][ordered]@{
        status=if($created.Count -gt 0){'INITIALIZED'}else{'READY'}
        project_id=[string]$binding.project_id
        definition_id=$definitionId
        definition_version=$definitionVersion
        created=@($created)
        applicability=$applicabilityCheck
        progress=$progressCheck
    }
}

Export-ModuleMember -Function Get-AidosDefinitionWorkspacePaths,Test-AidosDefinitionWorkspaceBinding,Assert-AidosExistingDefinitionWorkspaceArtifactBinding,Ensure-AidosDefinitionWorkspace
