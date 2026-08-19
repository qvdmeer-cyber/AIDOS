[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHumanInputTransport.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Human([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-HumanThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-human-input-transport-'+[guid]::NewGuid().ToString('N'))
$projectRoot=Join-Path $temp 'project';$stateRoot=Join-Path $temp 'state';$requestId=[guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path (Join-Path $projectRoot '.aidos/human-input'),(Join-Path $stateRoot 'bindings') -Force|Out-Null
try{
    [ordered]@{schema_version='0.1';project_id='P1'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/PROJECT.json') -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';project_id='P1';state='WAITING_USER';definition_id='DEF-1';definition_version=1;execution_id=$null;revision=$null;review_id=$null}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    $request=[ordered]@{contract_version='0.1.0';request_id=$requestId;project_id='P1';workstream_id=$null;phase='DEFINITION';request_type='AUTHORITY';status='WAITING';context_summary='Definition is ready.';question='Accept Definition?';options=@([ordered]@{option_id='ACCEPT';label='Accept';description='Proceed'},[ordered]@{option_id='REOPEN';label='Reopen';description='Return to Definition'});authority_classification='HUMAN_REQUIRED';binding=[ordered]@{baseline_version=$null;definition_id='DEF-1';definition_version=1;execution_id=$null;revision=$null;review_id=$null};response=$null;created_at=[DateTimeOffset]::UtcNow.ToString('o');updated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $requestPath=Join-Path $projectRoot ".aidos/human-input/$requestId.json";$request|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $requestPath -Encoding utf8NoBOM
    $project=[pscustomobject]@{project_id='P1';local_root=$projectRoot;repository='https://github.com/example/P1.git'}
    $current=Get-AidosRepositoryWaitingHumanInput -Project $project
    Assert-Human ([string]$current.request_id-eq$requestId) 'WAITING_USER resolves exactly one current Human Input Request'
    Assert-Human ([string]$current.request_sha256-match'^[0-9a-f]{64}$') 'Human Input trigger binds exact request hash'

    $binding=[ordered]@{schema_version='0.1';binding_type='MANUAL_PROJECT_CHATGPT_CONVERSATION';project_id='P1';repository='https://github.com/example/P1.git';process_name='ChatGPT Classic Test';conversation_title='AIDOS :: P1 :: THINKER';conversation_url='https://chatgpt.com/g/test/c/test';status='BOUND';bound_at=[DateTimeOffset]::UtcNow.ToString('o');updated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    $binding|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $stateRoot 'bindings/P1.json') -Encoding utf8NoBOM
    $calls=[pscustomobject]@{send=0;prompt=$null}
    $backend=[pscustomobject]@{
        GetProcessContext={param($ProcessName)[pscustomobject]@{window_handle=1}}
        ActivateConversation={param($Context,$Binding)[pscustomobject]@{status='ALREADY_ACTIVE';context=$Context}}
        FocusConversation={param($Context,$Binding)$Context}
        SendPrompt=({param($Context,$Binding,$Prompt,$Metadata);$calls.send++;$calls.prompt=$Prompt;[pscustomobject]@{committed=$true}}).GetNewClosure()
    }
    $trigger=Invoke-AidosRepositoryHumanInputTrigger -StateRoot $stateRoot -HumanInput $current -ProcessName 'ChatGPT Classic Test' -Backend $backend
    Assert-Human ([string]$trigger.status-eq'TRIGGERED') 'first WAITING Human Input is sent to bound ChatGPT conversation'
    Assert-Human ($calls.send-eq1) 'Human Input prompt is sent exactly once'
    Assert-Human ($calls.prompt.StartsWith('AIDOS_HUMAN_INPUT_REQUIRED')) 'Human Input prompt starts with exact transport marker'
    Assert-Human ($calls.prompt.Contains("request_id=$requestId") -and $calls.prompt.Contains("request_sha256=$($current.request_sha256)")) 'trigger carries exact request identity and hash'
    $again=Invoke-AidosRepositoryHumanInputTrigger -StateRoot $stateRoot -HumanInput $current -ProcessName 'ChatGPT Classic Test' -Backend $backend
    Assert-Human ([string]$again.status-eq'ALREADY_TRIGGERED' -and $calls.send-eq1) 'committed Human Input trigger is idempotent'

    $request.context_summary='Changed after committed trigger.';$request.updated_at=[DateTimeOffset]::UtcNow.ToString('o');$request|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $requestPath -Encoding utf8NoBOM
    $changed=Get-AidosRepositoryWaitingHumanInput -Project $project
    Assert-HumanThrows {Invoke-AidosRepositoryHumanInputTrigger -StateRoot $stateRoot -HumanInput $changed -ProcessName 'ChatGPT Classic Test' -Backend $backend} 'hash differs' 'same request_id with changed durable content cannot reuse a committed prompt'

    $state=Get-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Raw|ConvertFrom-Json;$state.state='TASK_READY';$state|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $projectRoot '.aidos/STATE.json') -Encoding utf8NoBOM
    Assert-Human ($null-eq(Get-AidosRepositoryWaitingHumanInput -Project $project)) 'Human Input transport does not surface requests outside WAITING_USER'

    Write-Output "PASS: $passed repository Human Input transport assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
