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
    Assert-OpenApi ([string]$document.openapi-eq'3.0.3') 'OpenAPI version is explicit and GPT Action compatible'
    Assert-OpenApi ([string]$document.servers[0].url-eq'https://aidos-machine.example.ts.net') 'OpenAPI server uses normalized Funnel URL'
    Assert-OpenApi (@($document.paths.Keys).Count-eq3) 'OpenAPI exposes only handoff, authorized source and result endpoints'
    Assert-OpenApi ([string]$document.paths.'/v1/projects/{projectId}/handoff'.get.operationId-eq'getAidosProjectHandoff') 'handoff operation ID is stable'
    Assert-OpenApi ([string]$document.paths.'/v1/projects/{projectId}/sources'.get.operationId-eq'getAidosAuthorizedSource') 'source operation ID is stable'
    $submit=$document.paths.'/v1/projects/{projectId}/results'.post
    Assert-OpenApi ([string]$submit.operationId-eq'submitAidosBoundResult') 'result operation ID is stable'
    Assert-OpenApi ($submit.'x-openai-isConsequential'-eq$false) 'bound result submission permits persistent operator approval'
    Assert-OpenApi ([string]$document.components.securitySchemes.BearerAuth.scheme-eq'bearer') 'OpenAPI requires bearer API-key authentication'
    Assert-OpenApi (@($document.components.schemas.SubmitResultRequest.properties.result.oneOf).Count-eq2) 'result submission accepts only runtime actor or review envelopes'

    $json=ConvertTo-AidosRepositoryHandoffOpenApiJson -ServerUrl 'https://aidos-machine.example.ts.net'
    $roundTrip=$json|ConvertFrom-Json -Depth 100
    Assert-OpenApi ([string]$roundTrip.paths.'/v1/projects/{projectId}/results'.post.operationId-eq'submitAidosBoundResult') 'OpenAPI JSON round-trips without losing operation identity'

    $path=Join-Path $temp 'openapi.json'
    $written=Write-AidosRepositoryHandoffOpenApiDocument -ServerUrl 'https://aidos-machine.example.ts.net' -Path $path
    Assert-OpenApi ([string]$written.status-eq'WRITTEN' -and (Test-Path -LiteralPath $path -PathType Leaf)) 'OpenAPI document writes atomically'
    $file=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    Assert-OpenApi ([string]$file.servers[0].url-eq'https://aidos-machine.example.ts.net') 'written OpenAPI document preserves public server URL'

    Write-Output "PASS: $passed repository handoff OpenAPI assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
