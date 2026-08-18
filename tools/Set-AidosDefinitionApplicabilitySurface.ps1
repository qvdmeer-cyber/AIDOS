[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [Parameter(Mandatory)][string]$SurfaceId,
    [Parameter(Mandatory)][ValidateSet('AFFECTED','NOT_AFFECTED')][string]$DefinitionState,
    [Parameter(Mandatory)][string]$Reason,
    [Parameter(Mandatory)][string[]]$SourceRefs
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=[IO.Path]::GetFullPath($ProjectRoot)
$projectPath=Join-Path $root '.aidos/profile/PROJECT_APPLICABILITY.json'
$definitionPath=Join-Path $root ('.aidos/definitions/{0}/v{1}/APPLICABILITY.json' -f $DefinitionId,$DefinitionVersion)
foreach($path in @($projectPath,$definitionPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Applicability artifact missing: $path"}}
if([string]::IsNullOrWhiteSpace($Reason)){throw 'Definition applicability resolution requires a reason.'}
if(@($SourceRefs|Where-Object {-not[string]::IsNullOrWhiteSpace([string]$_)}).Count -eq 0){throw 'Definition applicability resolution requires source refs.'}

$project=Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
$definition=Get-Content -LiteralPath $definitionPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
if([string]$definition.project_id -ne [string]$project.project_id){throw 'Definition/project applicability project binding mismatch.'}
if([string]$definition.definition_id -ne $DefinitionId -or [int]$definition.definition_version -ne $DefinitionVersion){throw 'Definition applicability identity mismatch.'}
$projectSurface=@($project.resolved_surfaces|Where-Object {[string]$_.surface_id -eq $SurfaceId})
$definitionSurface=@($definition.development_surfaces|Where-Object {[string]$_.surface_id -eq $SurfaceId})
if($projectSurface.Count -ne 1 -or $definitionSurface.Count -ne 1){throw "Definition applicability surface '$SurfaceId' is not uniquely bound."}
if([string]$projectSurface[0].state -eq 'NOT_APPLICABLE'){throw "Project-NOT_APPLICABLE surface '$SurfaceId' cannot be reclassified by Definition."}
if([string]$projectSurface[0].state -eq 'UNRESOLVED'){throw "Project-unresolved surface '$SurfaceId' cannot be classified at Definition scope."}
if([string]$definitionSurface[0].project_state -ne [string]$projectSurface[0].state){throw "Definition applicability project_state mismatch for '$SurfaceId'."}

$definitionSurface[0].definition_state=$DefinitionState
$definitionSurface[0].reason=$Reason
$definitionSurface[0].source_refs=@($SourceRefs|ForEach-Object {[string]$_}|Where-Object {-not[string]::IsNullOrWhiteSpace($_)}|Select-Object -Unique)
$definition.unresolved_count=@($definition.development_surfaces|Where-Object {[string]$_.definition_state -eq 'DECISION_REQUIRED'}).Count
$definition.updated_at=[DateTimeOffset]::UtcNow.ToString('o')

if($PSCmdlet.ShouldProcess($definitionPath,"Set Definition applicability surface '$SurfaceId' to '$DefinitionState'")){
    [IO.File]::WriteAllText($definitionPath,($definition|ConvertTo-Json -Depth 100)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
[pscustomobject][ordered]@{project_id=[string]$definition.project_id;definition_id=$DefinitionId;definition_version=$DefinitionVersion;surface_id=$SurfaceId;definition_state=$DefinitionState;unresolved_count=[int]$definition.unresolved_count}
