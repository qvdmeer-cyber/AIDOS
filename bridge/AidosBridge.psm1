Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AllowedTransitions = @{
    'IDLE'                        = @('WAITING_DEFINITION','TASK_READY')
    'WAITING_DEFINITION'          = @('TASK_READY','WAITING_USER')
    'TASK_READY'                  = @('QUEUED','CODEX_RUNNING','RECOVERY_REQUIRED')
    'QUEUED'                      = @('CODEX_RUNNING','RECOVERY_REQUIRED')
    'CODEX_RUNNING'               = @('TERMINAL_PENDING','CONTEXT_ROTATION_REQUIRED','RECOVERY_REQUIRED')
    'TERMINAL_PENDING'            = @('REVIEW_READY','WAITING_USER','WAITING_DEFINITION','RECOVERY_REQUIRED')
    'REVIEW_READY'                = @('GPT_REVIEWING','WAITING_INTERACTIVE_SESSION','RECOVERY_REQUIRED')
    'WAITING_INTERACTIVE_SESSION' = @('GPT_REVIEWING','RECOVERY_REQUIRED')
    'GPT_REVIEWING'               = @('IDLE','TASK_READY','WAITING_DEFINITION','WAITING_USER','CONTEXT_ROTATION_REQUIRED','RECOVERY_REQUIRED')
    'WAITING_USER'                = @('WAITING_DEFINITION','TASK_READY','IDLE','RECOVERY_REQUIRED')
    'CONTEXT_ROTATION_REQUIRED'   = @('TASK_READY','REVIEW_READY','RECOVERY_REQUIRED')
    'RECOVERY_REQUIRED'           = @('IDLE','WAITING_DEFINITION','TASK_READY','QUEUED','CODEX_RUNNING','REVIEW_READY','WAITING_USER')
}

function Get-AidosProjectRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StartPath)

    $item = Get-Item -LiteralPath $StartPath
    if (-not $item.PSIsContainer) { $item = $item.Directory }

    while ($null -ne $item) {
        $manifest = Join-Path $item.FullName '.aidos\PROJECT.json'
        if (Test-Path -LiteralPath $manifest) { return $item.FullName }
        $item = $item.Parent
    }
    throw "No .aidos/PROJECT.json found above '$StartPath'."
}

function Read-AidosJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Required AIDOS file not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-AidosProjectProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    return Read-AidosJson (Join-Path $ProjectRoot '.aidos\PROJECT.json')
}

function Test-AidosProjectBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $resolved = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\\')
    $profile = Get-AidosProjectProfile -ProjectRoot $resolved
    $expected = [System.IO.Path]::GetFullPath([string]$profile.official_root).TrimEnd('\\')

    if (-not [string]::Equals($resolved, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "AIDOS project-root mismatch. Expected '$expected'; actual '$resolved'."
    }

    $gitRoot = (& git -C $resolved rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { throw "'$resolved' is not a readable Git worktree." }
    $gitRoot = [System.IO.Path]::GetFullPath(($gitRoot | Select-Object -First 1)).TrimEnd('\\')
    if (-not [string]::Equals($gitRoot, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Git root '$gitRoot' does not equal AIDOS official_root '$expected'."
    }

    $origin = (& git -C $resolved remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $origin) { throw "Git origin is unavailable for '$resolved'." }
    $originText = ($origin | Select-Object -First 1).Trim()
    $repo = [string]$profile.repository
    if ($originText -notmatch [regex]::Escape($repo)) {
        throw "Git origin '$originText' does not contain expected repository '$repo'."
    }

    [pscustomobject]@{
        ProjectId = [string]$profile.project_id
        Repository = $repo
        Root = $expected
        Origin = $originText
        Valid = $true
    }
}

function Get-AidosState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    return Read-AidosJson (Join-Path $ProjectRoot '.aidos\STATE.json')
}

function Add-AidosEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$EventType,
        [Parameter(Mandatory)][ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    $profile = Get-AidosProjectProfile -ProjectRoot $ProjectRoot
    $event = [ordered]@{
        schema_version = '0.1'
        event_id = [guid]::NewGuid().ToString()
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        project_id = [string]$profile.project_id
        definition_id = $null
        definition_version = $null
        execution_id = $null
        revision = $null
        review_id = $null
        event_type = $EventType
        actor = $Actor
        payload = $Payload
    }

    $statePath = Join-Path $ProjectRoot '.aidos\STATE.json'
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-AidosState -ProjectRoot $ProjectRoot
        foreach ($name in @('definition_id','definition_version','execution_id','revision','review_id')) {
            if ($null -ne $state.$name) { $event[$name] = $state.$name }
        }
    }

    $eventDir = Join-Path $ProjectRoot '.aidos\events'
    New-Item -ItemType Directory -Force -Path $eventDir | Out-Null
    $eventPath = Join-Path $eventDir ((Get-Date).ToUniversalTime().ToString('yyyy-MM') + '.jsonl')
    ($event | ConvertTo-Json -Depth 20 -Compress) | Add-Content -LiteralPath $eventPath -Encoding UTF8
    return [pscustomobject]$event
}

function Set-AidosState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$NewState,
        [Parameter(Mandatory)][ValidateSet('HUMAN','DEFINITION_AGENT','WORKER_AGENT','EXECUTION_AGENT','BRIDGE','SYSTEM')][string]$Actor,
        [hashtable]$Patch = @{}
    )

    Test-AidosProjectBinding -ProjectRoot $ProjectRoot | Out-Null
    $statePath = Join-Path $ProjectRoot '.aidos\STATE.json'
    $state = Get-AidosState -ProjectRoot $ProjectRoot
    $oldState = [string]$state.state

    if (-not $script:AllowedTransitions.ContainsKey($oldState)) { throw "Unknown current AIDOS state '$oldState'." }
    if ($NewState -notin $script:AllowedTransitions[$oldState]) {
        throw "Illegal AIDOS state transition: $oldState -> $NewState"
    }

    $object = [ordered]@{}
    foreach ($p in $state.PSObject.Properties) { $object[$p.Name] = $p.Value }
    foreach ($key in $Patch.Keys) { $object[$key] = $Patch[$key] }
    $object['state'] = $NewState
    $object['updated_at'] = [DateTimeOffset]::UtcNow.ToString('o')

    if ($PSCmdlet.ShouldProcess($statePath, "$oldState -> $NewState")) {
        ($object | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $statePath -Encoding UTF8
        Add-AidosEvent -ProjectRoot $ProjectRoot -EventType 'STATE_TRANSITION' -Actor $Actor -Payload @{ from = $oldState; to = $NewState } | Out-Null
    }
    return [pscustomobject]$object
}

Export-ModuleMember -Function Get-AidosProjectRoot,Read-AidosJson,Get-AidosProjectProfile,Test-AidosProjectBinding,Get-AidosState,Add-AidosEvent,Set-AidosState
