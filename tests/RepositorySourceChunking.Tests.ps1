[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffGateway.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffOpenApi.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffInstallation.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Chunk([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Invoke-Git([string]$Repo,[string[]]$Arguments){$output=@(&git -C $Repo @Arguments 2>&1);if($LASTEXITCODE-ne0){throw "git $($Arguments -join ' ') failed: $($output -join '; ')"};@($output)}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-source-chunking-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $temp 'project'
$registryRoot=Join-Path $temp 'registry'
$gatewayRoot=Join-Path $temp 'gateway'
try {
    New-Item -ItemType Directory -Path $projectRoot,$registryRoot -Force|Out-Null
    &git init $projectRoot|Out-Null
    Invoke-Git $projectRoot @('config','user.email','aidos-tests@example.invalid')|Out-Null
    Invoke-Git $projectRoot @('config','user.name','AIDOS Tests')|Out-Null
    Invoke-Git $projectRoot @('remote','add','origin','https://github.com/example/chunked-source.git')|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime/actor-assignments'),(Join-Path $projectRoot 'docs') -Force|Out-Null
    [ordered]@{schema_version='0.1';project_id='CHUNKED-SOURCE'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='CHUNKED-SOURCE';state='WAITING_DEFINITION';definition_id='DEF-CHUNK';definition_version=1;execution_id=$null;revision=$null;review_id=$null}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM

    $emoji=[char]::ConvertFromUtf32(0x1F642)
    $largeText=([string]::new('A',65535))+$emoji+([string]::new('B',240000))
    $largePath=Join-Path $projectRoot 'docs/LARGE.txt'
    [IO.File]::WriteAllText($largePath,$largeText,[Text.UTF8Encoding]::new($false))
    $largeBytes=[IO.File]::ReadAllBytes($largePath)
    Assert-Chunk ($largeBytes.Length-gt262144 -and $largeBytes.Length-lt524288) 'fixture exceeds the legacy source limit but stays inside the review evidence ceiling'

    $assignmentId=[guid]::NewGuid().ToString()
    $binding=[pscustomobject][ordered]@{project_state='WAITING_DEFINITION';definition_id='DEF-CHUNK';definition_version=1;execution_id=$null;revision=$null;review_id=$null}
    $assignment=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_ASSIGNMENT';assignment_id=$assignmentId;project_id='CHUNKED-SOURCE';actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='START_DEFINITION';binding=$binding;requested_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $assignmentPath=Join-Path $projectRoot ".aidos/runtime/actor-assignments/$assignmentId.json"
    $assignment|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $assignmentPath -Encoding utf8NoBOM
    $assignmentSha=(Get-FileHash -LiteralPath $assignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id='CHUNKED-SOURCE';kind='ASSIGNMENT';from_actor='CORE';to_actor='THINKER';status='READY';parent_handoff_id=$null;created_at=[DateTimeOffset]::UtcNow.ToString('o');action='START_DEFINITION';payload_ref=".aidos/runtime/actor-assignments/$assignmentId.json";payload_sha256=$assignmentSha;binding=$binding;source_refs=@('docs/LARGE.txt')}
    Write-AidosRepositoryHandoff -ProjectRoot $projectRoot -Metadata $metadata -Body '# Chunked source assignment'|Out-Null
    Invoke-Git $projectRoot @('add','.')|Out-Null
    Invoke-Git $projectRoot @('commit','-m','fixture')|Out-Null
    Register-AidosPreparationProject -RegistryRoot $registryRoot -ProjectId 'CHUNKED-SOURCE' -Repository 'https://github.com/example/chunked-source.git' -LocalRoot $projectRoot -ProjectMode NEW_PROJECT -AllowedPersistencePaths @('.aidos')|Out-Null
    Set-AidosPreparationProjectPhase -RegistryRoot $registryRoot -ProjectId 'CHUNKED-SOURCE' -Phase RUNTIME -Status PROMOTED|Out-Null

    $first=Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $registryRoot -AidosRoot $root -ProjectId 'CHUNKED-SOURCE' -SourceRef 'docs/LARGE.txt' -StartCharacter 0 -MaximumCharacters 65536
    Assert-Chunk (-not[bool]$first.complete -and [int]$first.chunk_start-eq0) 'first large-source response is an incomplete first chunk'
    Assert-Chunk ([int]$first.chunk_length-eq65535 -and [int]$first.next_start-eq65535) 'chunk boundary backs off before a UTF-16 surrogate pair'
    Assert-Chunk ([string]$first.content-eq[string]::new('A',65535)) 'first chunk contains no split replacement character'
    Assert-Chunk ([int]$first.byte_length-eq$largeBytes.Length -and [int]$first.character_length-eq$largeText.Length) 'every chunk reports immutable full-source lengths'

    $parts=[Collections.Generic.List[string]]::new()
    $start=0
    $sha=$null
    $calls=0
    do {
        $chunk=Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $registryRoot -AidosRoot $root -ProjectId 'CHUNKED-SOURCE' -SourceRef 'docs/LARGE.txt' -StartCharacter $start -MaximumCharacters 65536
        if($null-eq$sha){$sha=[string]$chunk.sha256}else{Assert-Chunk ([string]$chunk.sha256-eq$sha) 'full-source SHA remains constant across chunks'}
        Assert-Chunk ([int]$chunk.chunk_start-eq$start) 'chunk begins at the exact requested continuation offset'
        Assert-Chunk ([int]$chunk.chunk_length-le65536) 'chunk never exceeds the declared character limit'
        $parts.Add([string]$chunk.content)|Out-Null
        $calls++
        if([bool]$chunk.complete){break}
        Assert-Chunk ($null-ne$chunk.next_start -and [int]$chunk.next_start-gt$start) 'incomplete chunk exposes a strictly advancing continuation offset'
        $start=[int]$chunk.next_start
    } while($calls-lt20)
    Assert-Chunk ($calls-gt1 -and [bool]$chunk.complete -and $null-eq$chunk.next_start) 'large source completes after multiple bounded calls'
    Assert-Chunk (($parts.ToArray()-join'')-ceq$largeText) 'ordered chunk concatenation reproduces the exact UTF-16 source text'
    Assert-Chunk ($sha-eq[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($largeBytes)).ToLowerInvariant()) 'chunk responses bind the exact full-file SHA-256'

    $splitRejected=$false
    try{Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $registryRoot -AidosRoot $root -ProjectId 'CHUNKED-SOURCE' -SourceRef 'docs/LARGE.txt' -StartCharacter 65536 -MaximumCharacters 10|Out-Null}catch{$splitRejected=$_.Exception.Message-match'surrogate pair'}
    Assert-Chunk $splitRejected 'caller cannot begin a chunk inside a surrogate pair'

    $configured=Initialize-AidosRepositoryHandoffGateway -RegistryRoot $registryRoot -AidosRoot $root -StateRoot $gatewayRoot -Port 47841
    Assert-Chunk ([int]$configured.config.maximum_source_bytes-eq524288 -and [int]$configured.config.maximum_source_chunk_characters-eq65536) 'gateway configuration publishes total-source and per-call chunk ceilings'
    $routed=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/CHUNKED-SOURCE/sources' -Query @{path='docs/LARGE.txt';startCharacter='65535';maxCharacters='2'} -PresentedKey $configured.api_key -ExpectedKey $configured.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Chunk ([int]$routed.status_code-eq200 -and [int]$routed.body.chunk_start-eq65535 -and [int]$routed.body.chunk_length-eq2 -and [string]$routed.body.content-eq$emoji) 'HTTP router passes exact safe chunk controls to the authorized source reader'
    $badRange=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/CHUNKED-SOURCE/sources' -Query @{path='docs/LARGE.txt';startCharacter='-1'} -PresentedKey $configured.api_key -ExpectedKey $configured.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Chunk ([int]$badRange.status_code-eq400) 'HTTP router rejects invalid chunk controls as a client error'

    $openapi=New-AidosRepositoryHandoffOpenApiDocument -ServerUrl 'https://aidos.example.ts.net'
    $sourceOperation=$openapi.paths.'/v1/projects/{projectId}/sources'.get
    $parameterNames=@($sourceOperation.parameters|ForEach-Object {[string]$_.name})
    Assert-Chunk ($parameterNames-contains'startCharacter' -and $parameterNames-contains'maxCharacters') 'OpenAPI exposes bounded source continuation controls'
    $sourceSchema=$openapi.components.schemas.SourceResponse
    foreach($required in @('character_length','chunk_start','chunk_length','next_start','complete')){Assert-Chunk (@($sourceSchema.required)-contains$required) "OpenAPI SourceResponse requires $required"}

    $instructions=New-AidosRepositoryThinkerGptInstructions
    Assert-Chunk ($instructions.Contains('next_start') -and $instructions.Contains('complete is false')) 'Thinker instructions require continuation until the source is complete'
    Assert-Chunk ($instructions.Contains('full SHA-256') -and $instructions.Contains('concatenate')) 'Thinker instructions preserve full-source hash identity and ordered reconstruction'

    Write-Output "PASS: $passed repository source chunking assertions"
} finally {
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
