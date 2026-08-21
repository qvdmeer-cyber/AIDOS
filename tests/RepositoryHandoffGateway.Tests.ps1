[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRuntimeActorTransport.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffGateway.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Gateway([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Invoke-Git([string]$Repo,[string[]]$Arguments){$output=@(&git -C $Repo @Arguments 2>&1);if($LASTEXITCODE-ne0){throw "git $($Arguments -join ' ') failed: $($output -join '; ')"};@($output)}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-handoff-gateway-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $temp 'project';$registryRoot=Join-Path $temp 'registry';$stateRoot=Join-Path $temp 'gateway';$outsideRoot=Join-Path $temp 'outside'
New-Item -ItemType Directory -Path $projectRoot,$registryRoot,$outsideRoot -Force|Out-Null
try{
    &git init $projectRoot|Out-Null
    Invoke-Git $projectRoot @('config','user.email','aidos-tests@example.invalid')|Out-Null;Invoke-Git $projectRoot @('config','user.name','AIDOS Tests')|Out-Null;Invoke-Git $projectRoot @('remote','add','origin','https://github.com/example/project.git')|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/runtime/actor-assignments'),(Join-Path $projectRoot '.aidos/runtime/actor-transport'),(Join-Path $projectRoot 'docs') -Force|Out-Null
    [ordered]@{schema_version='0.1';project_id='PROJECT-1'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='PROJECT-1';state='WAITING_DEFINITION';definition_id='DEF-1';definition_version=1;execution_id=$null;revision=$null;review_id=$null}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $projectRoot 'docs/PRODUCT.md') -Value '# Product' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $outsideRoot 'SECRET.md') -Value 'outside secret' -Encoding utf8NoBOM
    $linkedSource='docs/LINKED.md'
    $linkCreated=$false
    try{New-Item -ItemType SymbolicLink -Path (Join-Path $projectRoot $linkedSource) -Target (Join-Path $outsideRoot 'SECRET.md') -Force|Out-Null;$linkCreated=$true}catch{}

    $assignmentId=[guid]::NewGuid().ToString()
    $assignment=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_ASSIGNMENT';assignment_id=$assignmentId;project_id='PROJECT-1';actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='START_DEFINITION';binding=[pscustomobject][ordered]@{project_state='WAITING_DEFINITION';definition_id='DEF-1';definition_version=1;execution_id=$null;revision=$null;review_id=$null};requested_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $assignmentPath=Join-Path $projectRoot ".aidos/runtime/actor-assignments/$assignmentId.json"
    $assignment|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $assignmentPath -Encoding utf8NoBOM
    $assignmentSha=(Get-FileHash -LiteralPath $assignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Initialize-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId $assignmentId|Out-Null
    $handoffId=[guid]::NewGuid().ToString()
    $sourceRefs=@('docs/PRODUCT.md')
    if($linkCreated){$sourceRefs+=$linkedSource}
    $metadata=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=$handoffId;project_id='PROJECT-1';kind='ASSIGNMENT';from_actor='CORE';to_actor='THINKER';status='READY';parent_handoff_id=$null;created_at=[DateTimeOffset]::UtcNow.ToString('o');action='START_DEFINITION';payload_ref=".aidos/runtime/actor-assignments/$assignmentId.json";payload_sha256=$assignmentSha;binding=$assignment.binding;source_refs=$sourceRefs}
    Write-AidosRepositoryHandoff -ProjectRoot $projectRoot -Metadata $metadata -Body '# Thinker assignment'|Out-Null
    Invoke-Git $projectRoot @('add','.')|Out-Null;Invoke-Git $projectRoot @('commit','-m','fixture')|Out-Null
    Register-AidosPreparationProject -RegistryRoot $registryRoot -ProjectId 'PROJECT-1' -Repository 'https://github.com/example/project.git' -LocalRoot $projectRoot -ProjectMode NEW_PROJECT -AllowedPersistencePaths @('.aidos')|Out-Null
    Set-AidosPreparationProjectPhase -RegistryRoot $registryRoot -ProjectId 'PROJECT-1' -Phase RUNTIME -Status PROMOTED|Out-Null

    $configured=Initialize-AidosRepositoryHandoffGateway -RegistryRoot $registryRoot -AidosRoot $root -StateRoot $stateRoot -Port 47839
    Assert-Gateway ([string]$configured.status-eq'CONFIGURED') 'gateway configuration is created'
    Assert-Gateway ([string]$configured.api_key -match'^[A-Za-z0-9_-]{40,}$') 'gateway API key is strong URL-safe text'
    $loaded=Read-AidosRepositoryHandoffGatewayConfiguration -StateRoot $stateRoot
    Assert-Gateway (Test-AidosRepositoryHandoffGatewayKey -Expected $loaded.api_key -Presented $configured.api_key) 'configured API key validates'
    Assert-Gateway (-not(Test-AidosRepositoryHandoffGatewayKey -Expected $loaded.api_key -Presented 'wrong')) 'wrong API key is rejected'
    $unauthorized=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/health' -PresentedKey 'wrong' -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Gateway ([int]$unauthorized.status_code-eq401) 'HTTP router rejects unauthorized requests before project access'
    $health=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/health' -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Gateway ([int]$health.status_code-eq200 -and [string]$health.body.status-eq'OK') 'authenticated health endpoint responds'
    $stopControl=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/control' -Body ([pscustomobject]@{command='STOP'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([int]$stopControl.status_code-eq200 -and [string]$stopControl.body.acknowledgement-eq'AIDOS_CONTROL_ACCEPTED::STOP' -and [string]$stopControl.body.control_mode-eq'PAUSED') 'exact STOP chat control durably pauses the project'
    Assert-Gateway (Test-Path -LiteralPath (Join-Path $projectRoot ([string]$stopControl.body.intent_ref)) -PathType Leaf) 'chat control persists its exact Core intent record'
    Assert-Gateway (Test-Path -LiteralPath (Join-Path $stateRoot 'WAKE.json') -PathType Leaf) 'accepted chat control signals the bridge for a safe tick'
    $stopAgain=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/control' -Body ([pscustomobject]@{command='STOP'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([string]$stopAgain.body.acknowledgement-eq'AIDOS_CONTROL_ALREADY_PAUSED') 'repeated STOP is idempotent at the orchestration boundary'
    $startControl=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/control' -Body ([pscustomobject]@{command='START'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([string]$startControl.body.acknowledgement-eq'AIDOS_CONTROL_ACCEPTED::START' -and [string]$startControl.body.control_mode-eq'RUNNING') 'exact START chat control durably resumes the project'
    $startAgain=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/control' -Body ([pscustomobject]@{command='START'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([string]$startAgain.body.acknowledgement-eq'AIDOS_CONTROL_ALREADY_RUNNING') 'repeated START is idempotent at the orchestration boundary'
    $badControl=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/control' -Body ([pscustomobject]@{command='START';requested_by='IMPOSTOR'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([int]$badControl.status_code-eq409 -and [string]$badControl.body.detail-match'exactly one command') 'chat control rejects caller-supplied authority fields'
    $busyGoal=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/goals' -Body ([pscustomobject]@{goal='Start a distinct new project Definition from this exact human goal.'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([int]$busyGoal.status_code-eq409 -and [string]$busyGoal.body.detail-match'active repository handoff') 'chat goal endpoint fails closed while a Definition handoff is active'
    $current=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/PROJECT-1/handoff' -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Gateway ([int]$current.status_code-eq200) 'current handoff endpoint responds'
    Assert-Gateway ([string]$current.body.metadata.handoff_id-eq$handoffId) 'current handoff endpoint preserves handoff identity'
    Assert-Gateway ([string]$current.body.payload.content.assignment_id-eq$assignmentId) 'current handoff endpoint returns exact assignment payload'
    $source=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/PROJECT-1/sources' -Query @{path='docs/PRODUCT.md'} -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Gateway ([int]$source.status_code-eq200 -and ([string]$source.body.content).Trim()-eq'# Product') 'authorized project source can be fetched'
    $wrongCase=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/PROJECT-1/sources' -Query @{path='docs/product.md'} -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Gateway ([int]$wrongCase.status_code-eq409) 'authorized source reference must match handoff casing and spelling exactly'
    $forbidden=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/PROJECT-1/sources' -Query @{path='.aidos/STATE.json'} -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root
    Assert-Gateway ([int]$forbidden.status_code-eq409) 'source not listed by handoff is rejected'
    if($linkCreated){
        $linked=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/PROJECT-1/sources' -Query @{path=$linkedSource} -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root
        Assert-Gateway ([int]$linked.status_code-eq409 -and [string]$linked.body.detail-match'symbolic link|reparse point') 'authorized source cannot escape through a symbolic link'
    }else{
        Assert-Gateway $true 'symbolic-link gateway assertion skipped where link creation is unavailable'
    }

    $result=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=$assignmentId;assignment_sha256=$assignmentSha;project_id='PROJECT-1';actor_role='THINKER';actor_identity='DEFINITION_AGENT';action='START_DEFINITION';binding=$assignment.binding;outcome='COMPLETED';result=[pscustomobject][ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='done';applicability_resolutions=@();surface_resolutions=@();human_input_request=$null};responded_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $request=[pscustomobject][ordered]@{expected_parent_handoff_id=$handoffId;summary='Thinker completed the assignment.';result=$result}
    $submitted=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/results' -Body $request -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([int]$submitted.status_code-eq200 -and [string]$submitted.body.status-eq'ACCEPTED') ("valid Thinker result is accepted: "+($submitted|ConvertTo-Json -Depth 100 -Compress))
    $resultPath=Join-Path $projectRoot ".aidos/runtime/actor-results/$assignmentId.json"
    Assert-Gateway (Test-Path -LiteralPath $resultPath -PathType Leaf) 'accepted result is persisted through existing actor binding validator'
    $resultHandoff=Read-AidosRepositoryHandoff -ProjectRoot $projectRoot -ExpectedProjectId 'PROJECT-1'
    Assert-Gateway ([string]$resultHandoff.metadata.kind-eq'RESULT' -and [string]$resultHandoff.metadata.from_actor-eq'THINKER' -and [string]$resultHandoff.metadata.to_actor-eq'CORE') 'accepted result replaces assignment with Core-bound RESULT handoff'
    Assert-Gateway ([string]$resultHandoff.metadata.parent_handoff_id-eq$handoffId) 'result handoff preserves exact assignment parent'
    $transport=Read-AidosRuntimeActorTransportState -ProjectRoot $projectRoot -AssignmentId $assignmentId
    Assert-Gateway ([string]$transport.status-eq'COMPLETED') 'accepted result advances existing transport state to COMPLETED'
    $retry=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/results' -Body $request -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([int]$retry.status_code-eq200 -and [string]$retry.body.status-eq'ALREADY_ACCEPTED') 'same parent retry is idempotent'
    $currentHandoff=Read-AidosRepositoryHandoff -ProjectRoot $projectRoot -ExpectedProjectId 'PROJECT-1'
    $projectState=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
    $goalAfterClean=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/goals' -Body ([pscustomobject]@{goal='Start a distinct new project Definition from this exact human goal.'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([int]$goalAfterClean.status_code-eq200 -and [string]$goalAfterClean.body.status-eq'ACCEPTED' -and [string]$goalAfterClean.body.acknowledgement -match '^AIDOS_GOAL_ACCEPTED::GOAL-') 'cleaned PASS review result no longer blocks a new project goal'
    $recoveryState=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json -Depth 20
    $recoveryState.state='RECOVERY_REQUIRED'
    $recoveryState|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    $rejectedStart=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path '/v1/projects/PROJECT-1/control' -Body ([pscustomobject]@{command='START'}) -PresentedKey $loaded.api_key -ExpectedKey $loaded.api_key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $stateRoot
    Assert-Gateway ([int]$rejectedStart.status_code-eq200 -and [string]$rejectedStart.body.acknowledgement-eq'AIDOS_CONTROL_REJECTED' -and [string]$rejectedStart.body.reason-match'RECOVERY_REQUIRED') 'chat START fails closed when Core requires explicit recovery'
    Write-Output "PASS: $passed repository handoff gateway assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
