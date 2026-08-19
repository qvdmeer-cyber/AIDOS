[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffGateway.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-HumanGateway([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Invoke-Git([string]$Repo,[string[]]$Arguments){$output=@(&git -C $Repo @Arguments 2>&1);if($LASTEXITCODE-ne0){throw "git $($Arguments -join ' ') failed: $($output -join '; ')"};@($output)}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-human-input-gateway-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $temp 'project';$registryRoot=Join-Path $temp 'registry';$stateRoot=Join-Path $temp 'gateway';$bridgeState=Join-Path $temp 'bridge';$requestId=[guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/human-input'),$registryRoot,$stateRoot,$bridgeState -Force|Out-Null
try{
    &git init $projectRoot|Out-Null
    Invoke-Git $projectRoot @('config','user.email','aidos-tests@example.invalid')|Out-Null;Invoke-Git $projectRoot @('config','user.name','AIDOS Tests')|Out-Null;Invoke-Git $projectRoot @('remote','add','origin','https://github.com/example/project.git')|Out-Null
    [ordered]@{schema_version='0.1';project_id='PROJECT-1'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='PROJECT-1';state='WAITING_USER';definition_id='DEF-1';definition_version=1;execution_id=$null;revision=$null;review_id=$null}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    $request=[ordered]@{contract_version='0.1.0';request_id=$requestId;project_id='PROJECT-1';workstream_id=$null;phase='DEFINITION';request_type='AUTHORITY';status='WAITING';context_summary='Definition converged.';question='Accept Definition?';options=@([ordered]@{option_id='ACCEPT';label='Accept Definition';description='Proceed to execution'},[ordered]@{option_id='REOPEN';label='Reopen Definition';description='Return to Thinker'});authority_classification='HUMAN_REQUIRED';decision_assessment_ref=$null;auto_define_stop_reason='Final human gate';binding=[ordered]@{baseline_version=$null;definition_id='DEF-1';definition_version=1;execution_id=$null;revision=$null;review_id=$null};requested_by=[ordered]@{actor='AIDOS_CORE';model=$null;session_id=$null};resume_actor_role='THINKER';response=$null;evidence_refs=@();source_refs=@();created_at=[DateTimeOffset]::UtcNow.ToString('o');updated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $requestPath=Join-Path $projectRoot ".aidos/human-input/$requestId.json";$request|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $requestPath -Encoding utf8NoBOM
    Invoke-Git $projectRoot @('add','.')|Out-Null;Invoke-Git $projectRoot @('commit','-m','fixture')|Out-Null
    Register-AidosPreparationProject -RegistryRoot $registryRoot -ProjectId 'PROJECT-1' -Repository 'https://github.com/example/project.git' -LocalRoot $projectRoot -ProjectMode NEW_PROJECT -AllowedPersistencePaths @('.aidos')|Out-Null
    Set-AidosPreparationProjectPhase -RegistryRoot $registryRoot -ProjectId 'PROJECT-1' -Phase RUNTIME -Status PROMOTED|Out-Null

    $configured=Initialize-AidosRepositoryHandoffGateway -RegistryRoot $registryRoot -AidosRoot $root -StateRoot $stateRoot -BridgeStateRoot $bridgeState -Port 47840
    $key=[string]$configured.api_key
    $read=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/PROJECT-1/human-input' -PresentedKey $key -ExpectedKey $key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $bridgeState
    Assert-HumanGateway ([int]$read.status_code-eq200 -and [string]$read.body.status-eq'READY') 'current WAITING Human Input is exposed through authenticated gateway'
    Assert-HumanGateway ([string]$read.body.request_id-eq$requestId -and [string]$read.body.request_sha256-match'^[0-9a-f]{64}$') 'Human Input GET returns exact request identity and hash'
    Assert-HumanGateway (@($read.body.options).Count-eq2 -and [string]$read.body.options[0].option_id-eq'ACCEPT') 'Human Input GET returns only permitted option data'

    $stale=[pscustomobject]@{request_sha256=('0'*64);selected_option_id='ACCEPT';text=$null}
    $staleResult=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path "/v1/projects/PROJECT-1/human-input/$requestId/response" -Body $stale -PresentedKey $key -ExpectedKey $key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $bridgeState
    Assert-HumanGateway ([int]$staleResult.status_code-eq409 -and [string]$staleResult.body.detail-match'hash is stale') 'stale Human Input hash is rejected fail-closed'
    $stillWaiting=Get-Content -LiteralPath $requestPath -Raw|ConvertFrom-Json -Depth 40
    Assert-HumanGateway ([string]$stillWaiting.status-eq'WAITING') 'stale response cannot mutate request state'

    $body=[pscustomobject]@{request_sha256=[string]$read.body.request_sha256;selected_option_id='ACCEPT';text=$null}
    $accepted=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path "/v1/projects/PROJECT-1/human-input/$requestId/response" -Body $body -PresentedKey $key -ExpectedKey $key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $bridgeState
    Assert-HumanGateway ([int]$accepted.status_code-eq200 -and [string]$accepted.body.status-eq'ACCEPTED') 'valid Human Input response is accepted'
    $resolved=Get-Content -LiteralPath $requestPath -Raw|ConvertFrom-Json -Depth 40
    Assert-HumanGateway ([string]$resolved.status-eq'RESOLVED' -and [string]$resolved.response.selected_option_id-eq'ACCEPT') 'accepted response is durably written to Human Input Request'
    $resumePath=Join-Path $projectRoot ".aidos/runtime/resume/$requestId.json"
    Assert-HumanGateway (Test-Path -LiteralPath $resumePath -PathType Leaf) 'accepted response creates durable resume intent'
    $resume=Get-Content -LiteralPath $resumePath -Raw|ConvertFrom-Json -Depth 40
    Assert-HumanGateway ([string]$resume.status-eq'PENDING' -and [string]$resume.request_id-eq$requestId) 'resume intent is bound to exact Human Input Request'

    $none=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/PROJECT-1/human-input' -PresentedKey $key -ExpectedKey $key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $bridgeState
    Assert-HumanGateway ([int]$none.status_code-eq200 -and [string]$none.body.status-eq'NO_HUMAN_INPUT') 'resolved request is no longer exposed as WAITING'
    $retry=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path "/v1/projects/PROJECT-1/human-input/$requestId/response" -Body $body -PresentedKey $key -ExpectedKey $key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $bridgeState
    Assert-HumanGateway ([int]$retry.status_code-eq200 -and [string]$retry.body.status-eq'ALREADY_ACCEPTED') 'identical Human Input response retry is idempotent after request hash changes'
    $conflict=[pscustomobject]@{request_sha256=[string]$read.body.request_sha256;selected_option_id='REOPEN';text=$null}
    $different=Invoke-AidosRepositoryHandoffGatewayRequest -Method POST -Path "/v1/projects/PROJECT-1/human-input/$requestId/response" -Body $conflict -PresentedKey $key -ExpectedKey $key -RegistryRoot $registryRoot -AidosRoot $root -BridgeStateRoot $bridgeState
    Assert-HumanGateway ([int]$different.status_code-eq409) 'different response after resolution is rejected'

    Write-Output "PASS: $passed repository Human Input gateway assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
