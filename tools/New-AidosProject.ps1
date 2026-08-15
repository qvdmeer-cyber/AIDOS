[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$Repository,
    [string]$DefaultBranch = 'main',
    [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$RunnerPolicy = 'SUPERVISED'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\\')
if (-not (Test-Path -LiteralPath $root)) { throw "Project root does not exist: $root" }

$aidos = Join-Path $root '.aidos'
if (Test-Path -LiteralPath $aidos) { throw "AIDOS project directory already exists: $aidos" }

if ($PSCmdlet.ShouldProcess($aidos, 'Initialize AIDOS project state')) {
    New-Item -ItemType Directory -Path $aidos | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $aidos 'documentation') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $aidos 'definitions') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $aidos 'executions') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $aidos 'events') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $aidos 'reviews') | Out-Null

    $project = [ordered]@{
        schema_version = '0.1'
        project_id = $ProjectId
        repository = $Repository
        official_root = $root
        default_branch = $DefaultBranch
        canonical_sources = @('AGENTS.md','docs/')
        agent_profile = '.aidos/AGENT_PROFILE.json'
        documentation_manifest = '.aidos/documentation/MANIFEST.json'
        capabilities = @()
        project_validators = @()
        runner_policy = $RunnerPolicy
    }

    $agentProfile = [ordered]@{
        schema_version = '0.1'
        project_id = $ProjectId
        aidos_agents = [ordered]@{
            documentation = 'agents/PROJECT_DOCUMENTATION_AGENT.md'
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

    $concernIds = @(
        'identity','product','architecture','runtime','data','interfaces','development',
        'validation','deployment','security_privacy','operations','decisions','constraints'
    )
    $concerns = foreach ($id in $concernIds) {
        [ordered]@{
            id = $id
            coverage = 'MISSING'
            canonical_source = $null
            supporting_sources = @()
            provenance = 'UNKNOWN'
            notes = ''
            last_verified_commit = $null
        }
    }

    $documentationManifest = [ordered]@{
        schema_version = '0.1'
        project_id = $ProjectId
        baseline_revision = 0
        status = 'UNINITIALIZED'
        accepted_at = $null
        accepted_commit = $null
        concerns = $concerns
        known_conflicts = @()
        open_material_gaps = @()
    }

    $documentationSession = [ordered]@{
        schema_version = '0.1'
        project_id = $ProjectId
        mode = 'EXISTING_PROJECT'
        state = 'INVENTORY'
        started_at = [DateTimeOffset]::UtcNow.ToString('o')
        last_updated_at = [DateTimeOffset]::UtcNow.ToString('o')
        questions = @()
        accepted_answers = @()
        pending_conflicts = @()
        notes = @()
    }

    ($project | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $aidos 'PROJECT.json') -Encoding UTF8
    ($agentProfile | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $aidos 'AGENT_PROFILE.json') -Encoding UTF8
    ($state | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $aidos 'STATE.json') -Encoding UTF8
    ($documentationManifest | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $aidos 'documentation\MANIFEST.json') -Encoding UTF8
    ($documentationSession | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $aidos 'documentation\SESSION.json') -Encoding UTF8

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
        payload = @{ runner_policy = $RunnerPolicy; documentation_status = 'UNINITIALIZED' }
    }
    ($initialEvent | ConvertTo-Json -Depth 20 -Compress) | Set-Content -LiteralPath (Join-Path $aidos 'events\initial.jsonl') -Encoding UTF8

    Write-Host "Initialized AIDOS project '$ProjectId' at '$root'."
}
