[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ContractsRoot,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [switch]$Json,
    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$progressPath = Join-Path $root ('.aidos\definitions\{0}\v{1}\PROGRESS.json' -f $DefinitionId,$DefinitionVersion)
if (-not (Test-Path -LiteralPath $progressPath -PathType Leaf)) { throw "Definition progress not found: $progressPath" }
$progressObject = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json -Depth 100
$projectId = [string]$progressObject.project_id

$progressTool = Join-Path $PSScriptRoot 'Test-AidosDefinitionProgress.ps1'
$applicabilityTool = Join-Path $PSScriptRoot 'Test-AidosDefinitionApplicability.ps1'
$decisionsTool = Join-Path $PSScriptRoot 'Test-AidosDefinitionDecisions.ps1'
foreach ($path in @($progressTool,$decisionsTool)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required validator not found: $path" } }

$errors = [System.Collections.Generic.List[string]]::new()
$progress = & $progressTool -ProjectRoot $root -DefinitionId $DefinitionId -DefinitionVersion $DefinitionVersion -RequireReady -NoExit
if (-not $progress.pass) { foreach ($e in @($progress.errors)) { $errors.Add("Progress: $e") } }

$applicability = $null
$applicabilityPath = Join-Path $root ('.aidos\definitions\{0}\v{1}\APPLICABILITY.json' -f $DefinitionId,$DefinitionVersion)
if (Test-Path -LiteralPath $applicabilityPath -PathType Leaf) {
    if (-not (Test-Path -LiteralPath $applicabilityTool -PathType Leaf)) { $errors.Add('Applicability exists but validator is missing.') }
    else {
        $applicability = & $applicabilityTool -ProjectRoot $root -DefinitionId $DefinitionId -DefinitionVersion $DefinitionVersion -RequireResolved -NoExit
        if (-not $applicability.pass) { foreach ($e in @($applicability.errors)) { $errors.Add("Applicability: $e") } }
    }
}

$decisions = & $decisionsTool -ProjectRoot $root -ContractsRoot $ContractsRoot -ProjectId $projectId -DefinitionId $DefinitionId -DefinitionVersion $DefinitionVersion -NoExit
if (-not $decisions.pass) { foreach ($e in @($decisions.errors)) { $errors.Add("Decisions: $e") } }

$result = [pscustomobject][ordered]@{
    pass = ($errors.Count -eq 0)
    project_id = $projectId
    definition_id = $DefinitionId
    definition_version = $DefinitionVersion
    progress_complete = $progress.complete_count
    progress_total = $progress.total_count
    applicability_checked = ($null -ne $applicability)
    applicability_unresolved = if ($null -eq $applicability) {$null} else {$applicability.unresolved_count}
    auto_decisions_current = $decisions.auto_decisions_current
    auto_decisions_superseded = $decisions.auto_decisions_superseded
    errors = @($errors)
}

if ($Json) { $result | ConvertTo-Json -Depth 100 }
elseif ($NoExit) { $result }
else {
    Write-Host "AIDOS Definition Ready: $(if ($result.pass) {'PASS'} else {'FAIL'})"
    Write-Host "Progress: $($result.progress_complete)/$($result.progress_total); current Auto Decisions: $($result.auto_decisions_current)"
    foreach ($error in $errors) { Write-Host "ERROR: $error" }
}
if (-not $NoExit -and -not $result.pass) { exit 1 }
