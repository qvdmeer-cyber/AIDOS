[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$Repository,
    [ValidateSet('NEW_PROJECT','EXISTING_PROJECT')][string]$ProjectMode = 'EXISTING_PROJECT',
    [string]$DefaultBranch = 'main',
    [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$RunnerPolicy = 'SUPERVISED'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\\')
if (-not (Test-Path -LiteralPath $root)) { throw "Project root does not exist: $root" }

$aidos = Join-Path $root '.aidos'
$baselinePath = Join-Path $aidos 'documentation\PROJECT_BASELINE.json'
$accessPath = Join-Path $aidos 'documentation\PROJECT_ACCESS.json'
$evidencePath = Join-Path $aidos 'evidence\EVIDENCE_INVENTORY.json'
$cpsPath = Join-Path $aidos 'discovery\CURRENT_PRODUCT_STATE.json'

foreach ($path in @($baselinePath,$accessPath,$evidencePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required AIDOS-Builder preparation artifact is missing: '$path'. Prepare the project first with qvdmeer-cyber/AIDOS-Builder and AIDOS-Contracts."
    }
}

$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json -Depth 100
if ([string]::IsNullOrWhiteSpace([string]$baseline.accepted_at) -or [string]::IsNullOrWhiteSpace([string]$baseline.accepted_by) -or [string]::IsNullOrWhiteSpace([string]$baseline.accepted_commit)) {
    throw 'Project Baseline exists but is not accepted.'
}

if ($ProjectMode -eq 'EXISTING_PROJECT') {
    if (-not (Test-Path -LiteralPath $cpsPath -PathType Leaf)) {
        throw "Existing project requires accepted Current Product State at '$cpsPath'. Run AIDOS-Builder Existing Project Discovery first."
    }
    $cps = Get-Content -LiteralPath $cpsPath -Raw | ConvertFrom-Json -Depth 100
    if ([string]::IsNullOrWhiteSpace([string]$cps.accepted_at) -or [string]::IsNullOrWhiteSpace([string]$cps.accepted_by) -or [string]::IsNullOrWhiteSpace([string]$cps.accepted_commit)) {
        throw 'Current Product State exists but is not accepted.'
    }
    if ($cps.project_id -ne $ProjectId) { throw 'Current Product State project_id does not match requested project.' }
}

$projectPath = Join-Path $aidos 'PROJECT.json'
if (Test-Path -LiteralPath $projectPath) { throw "AIDOS project is already initialized: $projectPath" }

if ($PSCmdlet.ShouldProcess($aidos, 'Initialize private AIDOS runtime state against accepted project preparation')) {
    foreach ($dir in @('definitions','executions','events','reviews')) {
        $path = Join-Path $aidos $dir
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }

    $canonicalSources = [System.Collections.Generic.List[string]]::new()
    foreach ($source in @('AGENTS.md','docs/','.aidos/documentation/PROJECT_BASELINE.json','.aidos/evidence/EVIDENCE_INVENTORY.json')) { $canonicalSources.Add($source) }
    if ($ProjectMode -eq 'EXISTING_PROJECT') { $canonicalSources.Add('.aidos/discovery/CURRENT_PRODUCT_STATE.json') }

    $project = [ordered]@{
        schema_version = '0.1'
        project_id = $ProjectId
        project_mode = $ProjectMode
        repository = $Repository
        official_root = $root
        default_branch = $DefaultBranch
        canonical_sources = @($canonicalSources)
        agent_profile = '.aidos/AGENT_PROFILE.json'
        project_baseline = '.aidos/documentation/PROJECT_BASELINE.json'
        project_access = '.aidos/documentation/PROJECT_ACCESS.json'
        evidence_inventory = '.aidos/evidence/EVIDENCE_INVENTORY.json'
        current_product_state = if ($ProjectMode -eq 'EXISTING_PROJECT') { '.aidos/discovery/CURRENT_PRODUCT_STATE.json' } else { $null }
        contracts_repository = 'qvdmeer-cyber/AIDOS-Contracts'
        capabilities = @()
        project_validators = @()
        runner_policy = $RunnerPolicy
    }

    $agentProfile = [ordered]@{
        schema_version = '0.1'
        project_id = $ProjectId
        aidos_agents = [ordered]@{
            definition = 'agents/DEFINITION_AGENT.md'
            worker = 'agents/WORKER_AGENT.md'
            execution = 'agents/EXECUTION_AGENT.md'
        }
        project_specific_sources = @()
        project_constraints = @()
        executor = [ordered]@{ model = 'gpt-5.4-mini'; reasoning_effort = 'medium' }
    }

    $state = [ordered]@{
        schema_version = '0.1'
        project_id = $ProjectId
        state = 'IDLE'
        definition_id = $null
        definition_version = $null
        execution_id = $null
        revision = $null
        codex_session_id = $null
        review_id = $null
        lease_id = $null
        updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    }

    ($project | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $projectPath -Encoding UTF8
    ($agentProfile | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $aidos 'AGENT_PROFILE.json') -Encoding UTF8
    ($state | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $aidos 'STATE.json') -Encoding UTF8

    $initialEvent = [ordered]@{
        schema_version = '0.1'
        event_id = [guid]::NewGuid().ToString()
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        project_id = $ProjectId
        definition_id = $null
        definition_version = $null
        execution_id = $null
        revision = $null
        review_id = $null
        event_type = 'PROJECT_INITIALIZED'
        actor = 'SYSTEM'
        payload = @{
            runner_policy = $RunnerPolicy
            project_mode = $ProjectMode
            baseline = '.aidos/documentation/PROJECT_BASELINE.json'
            current_product_state = if ($ProjectMode -eq 'EXISTING_PROJECT') { '.aidos/discovery/CURRENT_PRODUCT_STATE.json' } else { $null }
        }
    }
    ($initialEvent | ConvertTo-Json -Depth 20 -Compress) | Set-Content -LiteralPath (Join-Path $aidos 'events\initial.jsonl') -Encoding UTF8

    Write-Host "Initialized private AIDOS runtime for '$ProjectId' ($ProjectMode) at '$root'."
}
