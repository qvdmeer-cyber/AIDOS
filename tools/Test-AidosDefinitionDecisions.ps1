[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ContractsRoot,
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][int]$DefinitionVersion,
    [switch]$Json,
    [switch]$NoExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$definitionRoot = Join-Path $root ('.aidos\definitions\{0}\v{1}' -f $DefinitionId,$DefinitionVersion)
$progressPath = Join-Path $definitionRoot 'PROGRESS.json'
$decisionsRoot = Join-Path $definitionRoot 'decisions'
$autoValidator = Join-Path $PSScriptRoot 'Test-AidosAutoDecision.ps1'

foreach ($path in @($progressPath,$autoValidator)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

$progress = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json -Depth 100
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
if ($progress.project_id -ne $ProjectId -or $progress.definition_id -ne $DefinitionId -or $progress.definition_version -ne $DefinitionVersion) { $errors.Add('Definition progress binding mismatch.') }

$decisionById = @{}
$decisionByRef = @{}
$autoTotal = 0
$autoCurrent = 0
$autoSuperseded = 0

if (Test-Path -LiteralPath $decisionsRoot -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $decisionsRoot -Filter *.json -File) {
        try { $decision = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 100 }
        catch { $errors.Add("Invalid decision JSON '$($file.Name)': $($_.Exception.Message)"); continue }
        if ([string]::IsNullOrWhiteSpace([string]$decision.decision_id)) { $errors.Add("Decision '$($file.Name)' has no decision_id."); continue }
        if ($decisionById.ContainsKey($decision.decision_id)) { $errors.Add("Duplicate decision_id '$($decision.decision_id)'."); continue }
        $relative = ".aidos/definitions/$DefinitionId/v$DefinitionVersion/decisions/$($file.Name)"
        $decisionById[$decision.decision_id] = $decision
        $decisionByRef[$relative] = $decision

        if ($decision.decision_type -eq 'AUTO_DECISION') {
            $autoTotal++
            if ($decision.project_id -ne $ProjectId -or $decision.binding.definition_id -ne $DefinitionId -or $decision.binding.definition_version -ne $DefinitionVersion) {
                $errors.Add("Auto Decision '$($decision.decision_id)' binding mismatch.")
            }
            if ($null -eq $decision.superseded_by) {
                $autoCurrent++
                $validation = & $autoValidator -DecisionPath $file.FullName -ContractsRoot $ContractsRoot -NoExit
                if (-not $validation.pass) { foreach ($e in @($validation.errors)) { $errors.Add("Auto Decision '$($decision.decision_id)': $e") } }
            } else { $autoSuperseded++ }
        }
    }
}

# Validate supersession graph in both directions and prevent broken/cyclic lineage.
foreach ($id in @($decisionById.Keys)) {
    $d = $decisionById[$id]
    if ($d.decision_type -ne 'AUTO_DECISION') { continue }
    if ($null -ne $d.superseded_by) {
        if (-not $decisionById.ContainsKey([string]$d.superseded_by)) { $errors.Add("Auto Decision '$id' points to missing superseded_by '$($d.superseded_by)'.") }
        else {
            $next = $decisionById[[string]$d.superseded_by]
            if ($next.supersedes_decision_id -ne $id) { $errors.Add("Auto Decision '$id' supersession is not bidirectionally linked.") }
        }
    }
    if ($null -ne $d.supersedes_decision_id) {
        if (-not $decisionById.ContainsKey([string]$d.supersedes_decision_id)) { $errors.Add("Auto Decision '$id' points to missing predecessor '$($d.supersedes_decision_id)'.") }
        elseif ($decisionById[[string]$d.supersedes_decision_id].superseded_by -ne $id) { $errors.Add("Auto Decision '$id' predecessor is not bidirectionally linked.") }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $cursor = $d
    while ($null -ne $cursor.superseded_by) {
        if (-not $seen.Add([string]$cursor.decision_id)) { $errors.Add("Auto Decision lineage cycle detected from '$id'."); break }
        if (-not $decisionById.ContainsKey([string]$cursor.superseded_by)) { break }
        $cursor = $decisionById[[string]$cursor.superseded_by]
    }
}

# Every progress decision reference must resolve if it points into this Definition's decision directory.
foreach ($surface in @($progress.surfaces)) {
    foreach ($ref in @($surface.decision_refs)) {
        if ([string]::IsNullOrWhiteSpace([string]$ref)) { continue }
        if ($ref -like ".aidos/definitions/$DefinitionId/v$DefinitionVersion/decisions/*") {
            if (-not $decisionByRef.ContainsKey([string]$ref)) { $errors.Add("Surface '$($surface.surface_id)' references missing decision '$ref'."); continue }
            $d = $decisionByRef[[string]$ref]
            if ($d.decision_type -eq 'AUTO_DECISION' -and $null -ne $d.superseded_by) {
                $successorRef = ".aidos/definitions/$DefinitionId/v$DefinitionVersion/decisions/$($d.superseded_by).json"
                if (@($surface.decision_refs) -notcontains $successorRef) {
                    $errors.Add("Surface '$($surface.surface_id)' still relies on superseded Auto Decision '$($d.decision_id)' without successor ref '$successorRef'.")
                }
            }
        }
    }
}

$result = [pscustomobject][ordered]@{
    pass = ($errors.Count -eq 0)
    project_id = $ProjectId
    definition_id = $DefinitionId
    definition_version = $DefinitionVersion
    auto_decisions_total = $autoTotal
    auto_decisions_current = $autoCurrent
    auto_decisions_superseded = $autoSuperseded
    errors = @($errors)
    warnings = @($warnings)
}

if ($Json) { $result | ConvertTo-Json -Depth 100 }
elseif ($NoExit) { $result }
else {
    Write-Host "AIDOS Definition decisions: $(if ($result.pass) {'PASS'} else {'FAIL'})"
    Write-Host "Auto Decisions: $autoCurrent current; $autoSuperseded superseded; $autoTotal total"
    foreach ($error in $errors) { Write-Host "ERROR: $error" }
    foreach ($warning in $warnings) { Write-Host "WARN: $warning" }
}
if (-not $NoExit -and -not $result.pass) { exit 1 }
