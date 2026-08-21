[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffOpenApi.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-OpenApi([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-OpenApiThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-handoff-openapi-'+[guid]::NewGuid().ToString('N'))
try{
    $normalized=Normalize-AidosRepositoryHandoffPublicUrl -ServerUrl ' https://aidos-machine.example.ts.net/ '
    Assert-OpenApi ($normalized-eq'https://aidos-machine.example.ts.net') 'public URL is normalized without trailing slash'
    Assert-OpenApiThrows {Normalize-AidosRepositoryHandoffPublicUrl -ServerUrl 'http://127.0.0.1:47831'} 'must use HTTPS' 'public GPT Action URL rejects plaintext HTTP'
    Assert-OpenApiThrows {Normalize-AidosRepositoryHandoffPublicUrl -ServerUrl 'https://example.test/path?key=value'} 'query or fragment' 'public GPT Action URL rejects query data'
    Assert-OpenApiThrows {Normalize-AidosRepositoryHandoffPublicUrl -ServerUrl 'relative/path'} 'absolute HTTPS' 'public GPT Action URL rejects relative paths'

    $document=New-AidosRepositoryHandoffOpenApiDocument -ServerUrl 'https://aidos-machine.example.ts.net/'
    Assert-OpenApi ([string]$document.openapi-eq'3.1.0') 'OpenAPI version matches the proven custom GPT Action schema generation'
    Assert-OpenApi ([string]$document.servers[0].url-eq'https://aidos-machine.example.ts.net') 'OpenAPI server uses normalized Funnel URL'
    foreach($pathKey in $document.paths.Keys){foreach($methodKey in $document.paths[$pathKey].Keys){Assert-OpenApi (([string]$document.paths[$pathKey][$methodKey].description).Length-le300) "OpenAPI operation description fits the 300-character GPT Action limit: $methodKey $pathKey"}}
    foreach($pathKey in $document.paths.Keys){foreach($methodKey in $document.paths[$pathKey].Keys){Assert-OpenApi (@($document.paths[$pathKey][$methodKey].security).Count-eq1 -and @($document.paths[$pathKey][$methodKey].security[0].Keys)-contains'BearerAuth') "every GPT Action operation declares Bearer authentication: $methodKey $pathKey"}}
    Assert-OpenApi (@($document.paths.Keys).Count-eq7) 'OpenAPI exposes operator control, project goal, handoff, Human Input read/submit, authorized source and result endpoints'
    $control=$document.paths.'/v1/projects/{projectId}/control'.post
    Assert-OpenApi ([string]$control.operationId-eq'submitAidosChatControl') 'chat control operation ID is stable'
    Assert-OpenApi ($control.'x-openai-isConsequential'-eq$false) 'an explicit whole-message operator command needs no duplicate platform confirmation'
    Assert-OpenApi (@($document.components.schemas.ChatControlRequest.properties.command.enum)-join','-eq'START,STOP') 'chat control Action schema exposes only canonical START and STOP'
    Assert-OpenApi (@($document.components.schemas.ChatControlResponse.properties.acknowledgement.enum)-contains'AIDOS_CONTROL_ALREADY_PAUSED') 'chat control schema publishes durable idempotent acknowledgements'
    Assert-OpenApi ([string]$document.paths.'/v1/projects/{projectId}/goals'.post.operationId-eq'submitAidosProjectGoal') 'project goal operation ID is stable'
    Assert-OpenApi ([int]$document.components.schemas.ProjectGoalRequest.properties.goal.maxLength-eq12000) 'project goal Action input is explicitly bounded'
    Assert-OpenApi ([string]$document.paths.'/v1/projects/{projectId}/handoff'.get.operationId-eq'getAidosProjectHandoff') 'handoff operation ID is stable'
    Assert-OpenApi ([string]$document.paths.'/v1/projects/{projectId}/human-input'.get.operationId-eq'getAidosHumanInput') 'Human Input read operation ID is stable'
    $humanSubmit=$document.paths.'/v1/projects/{projectId}/human-input/{requestId}/response'.post
    Assert-OpenApi ([string]$humanSubmit.operationId-eq'submitAidosHumanInputResponse') 'Human Input submit operation ID is stable'
    Assert-OpenApi ($humanSubmit.'x-openai-isConsequential'-eq$false) 'explicit user answer can be submitted without a second platform confirmation'
    Assert-OpenApi ([string]$document.paths.'/v1/projects/{projectId}/sources'.get.operationId-eq'getAidosAuthorizedSource') 'source operation ID is stable'
    $submit=$document.paths.'/v1/projects/{projectId}/results'.post
    Assert-OpenApi ([string]$submit.operationId-eq'submitAidosBoundResult') 'result operation ID is stable'
    Assert-OpenApi ($submit.'x-openai-isConsequential'-eq$false) 'bound result submission remains marked non-consequential at the Action UI layer'
    Assert-OpenApi ([string]$document.components.securitySchemes.BearerAuth.scheme-eq'bearer') 'OpenAPI requires bearer API-key authentication'
    Assert-OpenApi ([string]$document.components.schemas.HumanInputSubmitRequest.properties.request_sha256.pattern-eq'^[0-9a-f]{64}$') 'Human Input submission binds the exact request hash'
    $resultToolSchema=$document.components.schemas.SubmitResultRequest.properties.result
    Assert-OpenApi ([string]$resultToolSchema.type-eq'object' -and -not[bool]$resultToolSchema.additionalProperties -and @($resultToolSchema.properties.Keys)-contains'envelope_type') 'GPT Action result argument exposes bounded envelope properties instead of an unsupported free-form object'
    Assert-OpenApi (@($resultToolSchema.required)-contains'assignment_sha256' -and @($resultToolSchema.required)-contains'outcome') 'GPT Action result argument retains common bound-result requirements'
    Assert-OpenApi ([string]$resultToolSchema.properties.binding.'$ref'-eq'#/components/schemas/Binding') 'GPT Action result binding uses an explicit supported schema'
    Assert-OpenApi (@($resultToolSchema.properties.evidence_refs.items.required)-contains'sha256') 'GPT Action REVIEW_RESPONSE evidence refs expose exact hash-bearing objects'
    Assert-OpenApi ([string]$document.components.schemas.Payload.properties.content.type-eq'object') 'handoff payload schema avoids unnecessary union constructs'

    $json=ConvertTo-AidosRepositoryHandoffOpenApiJson -ServerUrl 'https://aidos-machine.example.ts.net'
    Assert-OpenApi (-not($json.Contains('"nullable"'))) 'OpenAPI 3.1 output contains no 3.0 nullable keyword'
    $roundTrip=$json|ConvertFrom-Json -Depth 100
    Assert-OpenApi ([string]$roundTrip.paths.'/v1/projects/{projectId}/human-input'.get.operationId-eq'getAidosHumanInput') 'Human Input OpenAPI JSON round-trips without losing operation identity'
    Assert-OpenApi ([string]$roundTrip.paths.'/v1/projects/{projectId}/results'.post.operationId-eq'submitAidosBoundResult') 'OpenAPI JSON round-trips without losing Thinker operation identity'
    Assert-OpenApi ([string]$roundTrip.paths.'/v1/projects/{projectId}/control'.post.operationId-eq'submitAidosChatControl') 'OpenAPI JSON round-trips without losing chat control identity'
    Assert-OpenApi ([string]$roundTrip.paths.'/v1/projects/{projectId}/goals'.post.operationId-eq'submitAidosProjectGoal') 'OpenAPI JSON round-trips without losing project goal identity'
    Assert-OpenApi (@($roundTrip.components.schemas.Binding.properties.definition_id.type)-contains'null') 'OpenAPI 3.1 nullable binding values use JSON Schema null types'

    $path=Join-Path $temp 'openapi.json'
    $written=Write-AidosRepositoryHandoffOpenApiDocument -ServerUrl 'https://aidos-machine.example.ts.net' -Path $path
    Assert-OpenApi ([string]$written.status-eq'WRITTEN' -and (Test-Path -LiteralPath $path -PathType Leaf)) 'OpenAPI document writes atomically'
    $file=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    Assert-OpenApi ([string]$file.servers[0].url-eq'https://aidos-machine.example.ts.net') 'written OpenAPI document preserves public server URL'

    Write-Output "PASS: $passed repository handoff OpenAPI assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
