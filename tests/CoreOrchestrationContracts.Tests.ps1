Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-CoreContract([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "CORE ORCHESTRATION CONTRACT TEST FAILED: $Message" }
}

function Read-Json([string]$RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    Assert-CoreContract (Test-Path -LiteralPath $path -PathType Leaf) "missing $RelativePath"
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
}

$workstream = Read-Json 'schemas/workstream.schema.json'
$humanInput = Read-Json 'schemas/human-input-request.schema.json'
$control = Read-Json 'schemas/control-intent.schema.json'
$progress = Read-Json 'schemas/progress-estimate.schema.json'
$insight = Read-Json 'schemas/system-insight.schema.json'
$statusProjection = Read-Json 'schemas/runtime-status.schema.json'
$event = Read-Json 'schemas/event.schema.json'

foreach ($required in @('workstream_id','scope_ownership','shared_contract_refs','dependencies','blockers','resource_claims','integration_gate_refs')) {
    Assert-CoreContract (@($workstream.required) -contains $required) "workstream contract missing required field $required"
}

foreach ($command in @('RUN','PAUSE','RESUME','SAFE_STOP','QUERY_STATUS','SUBMIT_HUMAN_INPUT','REQUEST_RECOVERY')) {
    Assert-CoreContract (@($control.properties.command.enum) -contains $command) "control intent missing $command"
}

foreach ($status in @('WAITING','RESOLVED')) {
    Assert-CoreContract (@($humanInput.properties.status.enum) -contains $status) "Human Input Request missing status $status"
}
Assert-CoreContract ($humanInput.properties.binding.properties.execution_id -ne $null) 'Human Input Request must support execution binding'
Assert-CoreContract ($humanInput.properties.workstream_id -ne $null) 'Human Input Request must support workstream binding'

foreach ($confidence in @('HIGH','MEDIUM','LOW','NOT_RELIABLY_ESTIMABLE')) {
    Assert-CoreContract (@($progress.properties.eta.properties.confidence.enum) -contains $confidence) "progress estimate missing confidence $confidence"
}
Assert-CoreContract ($progress.properties.outcome -ne $null) 'progress estimate must preserve actual outcome/calibration'

foreach ($kind in @('OBSERVATION','HYPOTHESIS','ADOPTED_IMPROVEMENT')) {
    Assert-CoreContract (@($insight.properties.kind.enum) -contains $kind) "system insight missing $kind"
}

Assert-CoreContract ($statusProjection.properties.projects -ne $null) 'runtime status projection must expose projects'
Assert-CoreContract ($statusProjection.'$defs'.projectStatus.properties.workstreams -ne $null) 'runtime status projection must expose workstreams'
Assert-CoreContract ($statusProjection.'$defs'.projectStatus.properties.open_human_input_request_ids -ne $null) 'runtime status projection must expose waiting human input'

Assert-CoreContract ($event.properties.workstream_id -ne $null) 'events must support workstream binding'
Assert-CoreContract ($event.properties.human_input_request_id -ne $null) 'events must support Human Input Request binding'
Assert-CoreContract ($event.properties.control_intent_id -ne $null) 'events must support control intent binding'
Assert-CoreContract ($event.properties.actor_role -ne $null) 'events must support abstract actor role'

Write-Host 'AIDOS core orchestration contract tests PASS.'
