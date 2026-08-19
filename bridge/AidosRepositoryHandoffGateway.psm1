Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryActorHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffSignal.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking

function Get-AidosRepositoryHandoffGatewayDefaultStateRoot {
    if([OperatingSystem]::IsWindows()){return (Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-gateway')}
    Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-repository-handoff-gateway'
}
function Get-AidosRepositoryHandoffGatewayPath {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][ValidateSet('config','key','status','stop')][string]$Kind)
    $names=@{config='CONFIG.json';key='API_KEY.txt';status='STATUS.json';stop='STOP'}
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) $names[$Kind]
}
function Move-AidosRepositoryHandoffGatewayAtomicFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [ValidateRange(1,100)][int]$MaxAttempts=20,
        [ValidateRange(0,1000)][int]$DelayMilliseconds=25,
        [scriptblock]$MoveAction,
        [scriptblock]$SleepAction
    )
    if($null-eq$MoveAction){$MoveAction={param($source,$destination);[IO.File]::Move($source,$destination,$true)}}
    if($null-eq$SleepAction){$SleepAction={param($milliseconds);Start-Sleep -Milliseconds $milliseconds}}
    for($attempt=1;$attempt-le$MaxAttempts;$attempt++){
        try{
            & $MoveAction $SourcePath $DestinationPath
            return
        }catch [UnauthorizedAccessException]{
            if($attempt-ge$MaxAttempts){throw}
        }catch [IO.IOException]{
            if($attempt-ge$MaxAttempts){throw}
        }
        & $SleepAction $DelayMilliseconds
    }
}
function Write-AidosRepositoryHandoffGatewayJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $dir=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
        Move-AidosRepositoryHandoffGatewayAtomicFile -SourcePath $tmp -DestinationPath $Path
    }finally{
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}
    }
}
function New-AidosRepositoryHandoffGatewayKey {
    $bytes=[byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}
function Initialize-AidosRepositoryHandoffGateway {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [string]$AidosRoot=(Split-Path $PSScriptRoot -Parent),
        [string]$StateRoot=(Get-AidosRepositoryHandoffGatewayDefaultStateRoot),
        [string]$BridgeStateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),
        [int]$Port=47831,
        [switch]$RotateKey
    )
    if($Port-lt1024-or$Port-gt65535){throw 'Repository handoff gateway port must be between 1024 and 65535.'}
    $state=[IO.Path]::GetFullPath($StateRoot)
    if(-not(Test-Path -LiteralPath $state -PathType Container)){New-Item -ItemType Directory -Path $state -Force|Out-Null}
    $keyPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $state -Kind key
    if($RotateKey-or-not(Test-Path -LiteralPath $keyPath -PathType Leaf)){New-AidosRepositoryHandoffGatewayKey|Set-Content -LiteralPath $keyPath -Encoding ascii -NoNewline}
    $config=[pscustomobject][ordered]@{
        schema_version='0.2';registry_root=[IO.Path]::GetFullPath($RegistryRoot);aidos_root=[IO.Path]::GetFullPath($AidosRoot);state_root=$state;bridge_state_root=[IO.Path]::GetFullPath($BridgeStateRoot);listen_prefix="http://127.0.0.1:$Port/";port=$Port;maximum_request_bytes=1048576;maximum_source_bytes=262144;configured_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-AidosRepositoryHandoffGatewayJsonAtomic -Path (Get-AidosRepositoryHandoffGatewayPath -StateRoot $state -Kind config) -Value $config
    [pscustomobject][ordered]@{status='CONFIGURED';config=$config;api_key=(Get-Content -LiteralPath $keyPath -Raw -Encoding ASCII)}
}
function Read-AidosRepositoryHandoffGatewayConfiguration {
    param([string]$StateRoot=(Get-AidosRepositoryHandoffGatewayDefaultStateRoot))
    $configPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind config
    $keyPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind key
    if(-not(Test-Path -LiteralPath $configPath -PathType Leaf)){throw 'Repository handoff gateway is not configured.'}
    if(-not(Test-Path -LiteralPath $keyPath -PathType Leaf)){throw 'Repository handoff gateway API key is missing.'}
    $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    $key=(Get-Content -LiteralPath $keyPath -Raw -Encoding ASCII).Trim()
    if([string]::IsNullOrWhiteSpace($key)){throw 'Repository handoff gateway API key is empty.'}
    [pscustomobject][ordered]@{config=$config;api_key=$key}
}
function Test-AidosRepositoryHandoffGatewayKey {
    param([AllowNull()][AllowEmptyString()][string]$Expected,[AllowNull()][AllowEmptyString()][string]$Presented)
    if([string]::IsNullOrWhiteSpace($Expected)-or[string]::IsNullOrWhiteSpace($Presented)){return $false}
    $a=[Text.Encoding]::UTF8.GetBytes($Expected);$b=[Text.Encoding]::UTF8.GetBytes($Presented)
    if($a.Length-ne$b.Length){return $false}
    [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a,$b)
}
function Get-AidosRepositoryHandoffGatewayPresentedKey {
    param([Parameter(Mandatory)]$Headers)
    $custom=[string]$Headers['X-AIDOS-Key']
    if(-not[string]::IsNullOrWhiteSpace($custom)){return $custom.Trim()}
    $authorization=[string]$Headers['Authorization']
    if($authorization.StartsWith('Bearer ',[StringComparison]::OrdinalIgnoreCase)){return $authorization.Substring(7).Trim()}
    $null
}
function Test-AidosRepositoryHandoffGatewayProjectId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectId)
    $value=$ProjectId.Trim()
    if([string]::IsNullOrWhiteSpace($value) -or $value.Length-gt128 -or $value-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]*$'){
        throw 'Repository handoff gateway project_id is invalid.'
    }
    $value
}
function Get-AidosRepositoryHandoffGatewayProject {
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    $safeProjectId=Test-AidosRepositoryHandoffGatewayProjectId -ProjectId $ProjectId
    $project=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId $safeProjectId
    if([string]$project.stage-ne'RUNTIME'-or[string]$project.status-ne'PROMOTED'){throw "Project '$safeProjectId' is not an active AIDOS runtime project."}
    if(-not[string]::Equals([string]$project.project_id,$safeProjectId,[StringComparison]::Ordinal)){throw 'Registered project identity does not match the requested gateway project_id.'}
    Test-AidosRegistryProjectBinding -Project $project|Out-Null
    $project
}
function Get-AidosRepositoryHandoffGatewayPayload {
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$Handoff)
    $path=Resolve-AidosRepositoryHandoffPayloadPath -ProjectRoot ([string]$Project.local_root) -RelativePath ([string]$Handoff.metadata.payload_ref)
    $bytes=[IO.File]::ReadAllBytes($path)
    if($bytes.Length-gt1048576){throw 'Repository handoff payload exceeds the gateway limit.'}
    $sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if(-not[string]::IsNullOrWhiteSpace([string]$Handoff.metadata.payload_sha256)-and[string]$Handoff.metadata.payload_sha256-ne$sha){throw 'Repository handoff payload hash mismatch.'}
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    if($text.IndexOf([char]0)-ge0){throw 'Repository handoff payload is not UTF-8 text.'}
    try{$content=$text|ConvertFrom-Json -Depth 100}catch{$content=$text}
    [pscustomobject][ordered]@{path=[string]$Handoff.metadata.payload_ref;sha256=$sha;content=$content}
}
function Get-AidosRepositoryHandoffGatewayCurrentHandoff {
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId ([string]$project.project_id)
    if($null-eq$handoff){return [pscustomobject][ordered]@{status='NO_HANDOFF';project_id=[string]$project.project_id}}
    [pscustomobject][ordered]@{status='READY';project_id=[string]$project.project_id;handoff_sha256=[string]$handoff.text_sha256;metadata=$handoff.metadata;body=[string]$handoff.body;payload=(Get-AidosRepositoryHandoffGatewayPayload -Project $project -Handoff $handoff)}
}
function Resolve-AidosRepositoryHandoffGatewaySourcePath {
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$AidosRoot,[Parameter(Mandatory)][string]$SourceRef)
    $ref=$SourceRef.Replace('\','/').Trim()
    if($ref.StartsWith('AIDOS/',[StringComparison]::Ordinal)){
        $base=Resolve-AidosFileSystemPath $AidosRoot
        $relative=$ref.Substring(6)
    }else{
        $base=Resolve-AidosFileSystemPath ([string]$Project.local_root)
        $relative=$ref
    }
    $path=Resolve-AidosRepositoryContainedPath -BaseRoot $base -RelativePath $relative -FieldName 'source_ref' -RequireLeaf
    [pscustomobject][ordered]@{path=$path;source_ref=$ref}
}
function Get-AidosRepositoryHandoffGatewaySource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$AidosRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)][string]$SourceRef,[int]$MaximumBytes=262144)
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId ([string]$project.project_id)
    if($null-eq$handoff-or[string]$handoff.metadata.kind-ne'ASSIGNMENT'){throw 'No active assignment handoff authorizes source access.'}
    $authorized=@($handoff.metadata.source_refs|ForEach-Object {[string]$_})
    $exact=@($authorized|Where-Object {[string]::Equals($_,$SourceRef,[StringComparison]::Ordinal)})
    if($exact.Count-ne1){throw "Source ref '$SourceRef' is not authorized exactly by the current handoff."}
    $resolved=Resolve-AidosRepositoryHandoffGatewaySourcePath -Project $project -AidosRoot $AidosRoot -SourceRef $SourceRef
    $bytes=[IO.File]::ReadAllBytes($resolved.path)
    if($bytes.Length-gt$MaximumBytes){throw "Authorized source exceeds the $MaximumBytes byte limit: $SourceRef"}
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    if($text.IndexOf([char]0)-ge0){throw "Authorized source is not UTF-8 text: $SourceRef"}
    if($text-match'(?im)-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|(?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[:=]\s*\S+'){throw "Authorized source is not secret-free: $SourceRef"}
    [pscustomobject][ordered]@{project_id=[string]$project.project_id;source_ref=$SourceRef;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant();byte_length=$bytes.Length;content=$text}
}
function Ensure-AidosRepositoryRuntimeActorActivated {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$AssignmentId)
    $state=Read-AidosRuntimeActorTransportState -ProjectRoot $ProjectRoot -AssignmentId $AssignmentId
    if($null-eq$state){$state=Initialize-AidosRuntimeActorTransportState -ProjectRoot $ProjectRoot -AssignmentId $AssignmentId}
    if([string]$state.status-eq'PENDING'){return Set-AidosRuntimeActorTransportState -ProjectRoot $ProjectRoot -AssignmentId $AssignmentId -Status ACTIVATED -TransportType REPOSITORY_HANDOFF -LastError $null}
    if([string]$state.status-notin@('ACTIVATED','COMPLETED')){throw "Repository result cannot use runtime actor transport state '$($state.status)'."}
    $state
}
function Submit-AidosRepositoryRuntimeActorResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$Request,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId ([string]$Project.project_id)
    if($null-eq$handoff){throw 'No repository assignment handoff is available.'}
    if([string]$handoff.metadata.kind-eq'RESULT'){
        if([string]::Equals([string]$handoff.metadata.parent_handoff_id,[string]$Request.expected_parent_handoff_id,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject][ordered]@{status='ALREADY_ACCEPTED';handoff=$handoff}}
        throw 'Repository handoff already contains a different result.'
    }
    if([string]$handoff.metadata.kind-ne'ASSIGNMENT'-or[string]$handoff.metadata.to_actor-ne'THINKER'){throw 'Current repository handoff is not a Thinker assignment.'
    }
    if(-not[string]::Equals([string]$handoff.metadata.handoff_id,[string]$Request.expected_parent_handoff_id,[StringComparison]::OrdinalIgnoreCase)){throw 'Result submission parent handoff is stale.'}
    $result=$Request.result
    $binding=Test-AidosRuntimeActorResultBinding -ProjectRoot $root -Result $result
    if([string]$result.actor_role-ne'THINKER'){throw 'Gateway result payload is not a Thinker result.'}
    $assignment=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId ([string]$result.assignment_id)
    $assignmentRef=[IO.Path]::GetRelativePath($root,$assignment.path).Replace('\','/')
    if([string]$handoff.metadata.payload_ref-ne$assignmentRef-or[string]$handoff.metadata.payload_sha256-ne[string]$assignment.sha256){throw 'Current handoff does not bind the submitted runtime assignment.'}
    Ensure-AidosRepositoryRuntimeActorActivated -ProjectRoot $root -AssignmentId ([string]$result.assignment_id)|Out-Null
    $saved=Save-AidosRuntimeActorResult -ProjectRoot $root -Result $result
    $resultPath=Get-AidosRuntimeActorResultPath -ProjectRoot $root -AssignmentId ([string]$result.assignment_id)
    $resultRef=[IO.Path]::GetRelativePath($root,$resultPath).Replace('\','/')
    $resultSha=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata=[pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=[guid]::NewGuid().ToString();project_id=[string]$Project.project_id;kind='RESULT';from_actor='THINKER';to_actor='CORE';status='READY';parent_handoff_id=[string]$handoff.metadata.handoff_id;created_at=[DateTimeOffset]::UtcNow.ToString('o');action=([string]$assignment.assignment.action+'_RESULT');payload_ref=$resultRef;payload_sha256=$resultSha;binding=$assignment.assignment.binding;source_refs=@()}
    Test-AidosRepositoryHandoffTransition -Previous $handoff -Next $metadata|Out-Null
    $body=if($Request.PSObject.Properties['summary']-and-not[string]::IsNullOrWhiteSpace([string]$Request.summary)){"# Thinker result`n`n$([string]$Request.summary)"}else{"# Thinker result`n`nRuntime actor result submitted to AIDOS Core."}
    $written=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId ([string]$handoff.metadata.handoff_id)
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_HANDOFF_RESULT_PUBLISHED' -Actor DEFINITION_AGENT -Payload @{handoff_id=[string]$metadata.handoff_id;parent_handoff_id=[string]$metadata.parent_handoff_id;assignment_id=[string]$result.assignment_id;payload_ref=$resultRef}|Out-Null
    $persistence=Invoke-AidosPreparationGitPersistence -Project $Project -CommitMessage ("AIDOS Thinker result $($result.assignment_id)") -Push:$Push
    [pscustomobject][ordered]@{status='ACCEPTED';handoff=$written;saved=$saved;binding=$binding;persistence=$persistence}
}
function Submit-AidosRepositoryHandoffGatewayResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)]$Request,[string]$BridgeStateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),[switch]$Push)
    foreach($name in @('expected_parent_handoff_id','result')){if(-not$Request.PSObject.Properties[$name]){throw "Result submission is missing '$name'."}}
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $accepted=switch([string]$Request.result.envelope_type){
        'RUNTIME_ACTOR_RESULT' {Submit-AidosRepositoryRuntimeActorResult -Project $project -Request $Request -Push:$Push}
        'REVIEW_RESPONSE' {Submit-AidosRepositoryReviewResult -Project $project -Request $Request -Push:$Push}
        default {throw "Unsupported repository handoff result envelope '$([string]$Request.result.envelope_type)'."}
    }
    if([string]$accepted.status-in@('ACCEPTED','ALREADY_ACCEPTED')){
        $handoffId=if($accepted.PSObject.Properties['handoff']){[string]$accepted.handoff.metadata.handoff_id}else{$null}
        Signal-AidosRepositoryHandoffBridge -StateRoot $BridgeStateRoot -Reason 'ACTOR_RESULT_ACCEPTED' -ProjectId ([string]$project.project_id) -HandoffId $handoffId|Out-Null
    }
    $accepted
}
function New-AidosRepositoryHandoffGatewayResponse {
    param([int]$StatusCode,[Parameter(Mandatory)]$Body)
    [pscustomobject][ordered]@{status_code=$StatusCode;body=$Body}
}
function Invoke-AidosRepositoryHandoffGatewayRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][string]$Path,[hashtable]$Query=@{},[AllowNull()]$Body,[Parameter(Mandatory)][string]$PresentedKey,[Parameter(Mandatory)][string]$ExpectedKey,[Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$AidosRoot,[string]$BridgeStateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),[switch]$Push)
    if(-not(Test-AidosRepositoryHandoffGatewayKey -Expected $ExpectedKey -Presented $PresentedKey)){return New-AidosRepositoryHandoffGatewayResponse 401 ([ordered]@{error='UNAUTHORIZED'})}
    try{
        if($Method-eq'GET'-and$Path-eq'/health'){return New-AidosRepositoryHandoffGatewayResponse 200 ([ordered]@{status='OK';service='AIDOS_REPOSITORY_HANDOFF_GATEWAY'})}
        if($Method-eq'GET'-and$Path-match'^/v1/projects/([^/]+)/handoff$'){return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryHandoffGatewayCurrentHandoff -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])))}
        if($Method-eq'GET'-and$Path-match'^/v1/projects/([^/]+)/sources$'){
            $sourceRef=[string]$Query['path'];if([string]::IsNullOrWhiteSpace($sourceRef)){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_PATH_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $RegistryRoot -AidosRoot $AidosRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -SourceRef $sourceRef)
        }
        if($Method-eq'POST'-and$Path-match'^/v1/projects/([^/]+)/results$'){
            if($null-eq$Body){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='BODY_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse 200 (Submit-AidosRepositoryHandoffGatewayResult -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -Request $Body -BridgeStateRoot $BridgeStateRoot -Push:$Push)
        }
        New-AidosRepositoryHandoffGatewayResponse 404 ([ordered]@{error='NOT_FOUND'})
    }catch{New-AidosRepositoryHandoffGatewayResponse 409 ([ordered]@{error='REQUEST_REJECTED';detail=$_.Exception.Message})}
}
function ConvertFrom-AidosRepositoryHandoffGatewayQuery {
    param([Parameter(Mandatory)][Uri]$Uri)
    $query=@{};$text=$Uri.Query.TrimStart('?')
    if([string]::IsNullOrWhiteSpace($text)){return $query}
    foreach($part in $text.Split('&',[StringSplitOptions]::RemoveEmptyEntries)){$items=$part.Split('=',2);$query[[Uri]::UnescapeDataString($items[0])]=if($items.Count-gt1){[Uri]::UnescapeDataString($items[1].Replace('+',' '))}else{''}}
    $query
}
function Write-AidosRepositoryHandoffGatewayHttpResponse {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Response)
    $json=$Response.body|ConvertTo-Json -Depth 100 -Compress;$bytes=[Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode=[int]$Response.status_code;$Context.Response.ContentType='application/json; charset=utf-8';$Context.Response.ContentEncoding=[Text.Encoding]::UTF8;$Context.Response.ContentLength64=$bytes.Length;$Context.Response.Headers['Cache-Control']='no-store';$Context.Response.OutputStream.Write($bytes,0,$bytes.Length);$Context.Response.OutputStream.Close()
}
function Start-AidosRepositoryHandoffGateway {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffGatewayDefaultStateRoot),[switch]$Push)
    $loaded=Read-AidosRepositoryHandoffGatewayConfiguration -StateRoot $StateRoot;$config=$loaded.config
    $bridgeStateRoot=if($config.PSObject.Properties['bridge_state_root']){[string]$config.bridge_state_root}else{Get-AidosRepositoryHandoffBridgeDefaultStateRoot}
    $listener=[Net.HttpListener]::new();$listener.Prefixes.Add([string]$config.listen_prefix)
    $statusPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind status;$stopPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind stop;Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    try{
        $listener.Start();Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.2';status='RUNNING';pid=$PID;listen_prefix=[string]$config.listen_prefix;started_at=[DateTimeOffset]::UtcNow.ToString('o');heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o')})
        while(-not(Test-Path -LiteralPath $stopPath -PathType Leaf)){
            $async=$listener.BeginGetContext($null,$null)
            while(-not$async.AsyncWaitHandle.WaitOne(1000)){if(Test-Path -LiteralPath $stopPath -PathType Leaf){break};$status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20;$status.heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value $status}
            if(Test-Path -LiteralPath $stopPath -PathType Leaf){break}
            $context=$listener.EndGetContext($async)
            try{
                $presented=Get-AidosRepositoryHandoffGatewayPresentedKey -Headers $context.Request.Headers;$body=$null
                if($context.Request.HasEntityBody){if($context.Request.ContentLength64-gt[int]$config.maximum_request_bytes){throw 'Gateway request body exceeds configured limit.'};$reader=[IO.StreamReader]::new($context.Request.InputStream,$context.Request.ContentEncoding,$true,4096,$false);try{$bodyText=$reader.ReadToEnd()}finally{$reader.Dispose()};if(-not[string]::IsNullOrWhiteSpace($bodyText)){$body=$bodyText|ConvertFrom-Json -Depth 100}}
                $response=Invoke-AidosRepositoryHandoffGatewayRequest -Method ([string]$context.Request.HttpMethod) -Path ([string]$context.Request.Url.AbsolutePath) -Query (ConvertFrom-AidosRepositoryHandoffGatewayQuery -Uri $context.Request.Url) -Body $body -PresentedKey $presented -ExpectedKey ([string]$loaded.api_key) -RegistryRoot ([string]$config.registry_root) -AidosRoot ([string]$config.aidos_root) -BridgeStateRoot $bridgeStateRoot -Push:$Push
            }catch{$response=New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='BAD_REQUEST';detail=$_.Exception.Message})}
            Write-AidosRepositoryHandoffGatewayHttpResponse -Context $context -Response $response
        }
        Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.2';status='STOPPED';pid=$PID;stopped_at=[DateTimeOffset]::UtcNow.ToString('o')})
    }catch{Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.2';status='ERROR';pid=$PID;observed_at=[DateTimeOffset]::UtcNow.ToString('o');error=$_.Exception.Message});throw}finally{if($listener.IsListening){$listener.Stop()};$listener.Close()}
}
function Stop-AidosRepositoryHandoffGateway {
    [CmdletBinding()]param([string]$StateRoot=(Get-AidosRepositoryHandoffGatewayDefaultStateRoot))
    $path=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind stop;$dir=Split-Path -Parent $path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Set-Content -LiteralPath $path -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
    [pscustomobject][ordered]@{status='STOP_REQUESTED';state_root=[IO.Path]::GetFullPath($StateRoot)}
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffGatewayDefaultStateRoot,Get-AidosRepositoryHandoffGatewayPath,Move-AidosRepositoryHandoffGatewayAtomicFile,Write-AidosRepositoryHandoffGatewayJsonAtomic,New-AidosRepositoryHandoffGatewayKey,Initialize-AidosRepositoryHandoffGateway,Read-AidosRepositoryHandoffGatewayConfiguration,Test-AidosRepositoryHandoffGatewayKey,Get-AidosRepositoryHandoffGatewayPresentedKey,Test-AidosRepositoryHandoffGatewayProjectId,Get-AidosRepositoryHandoffGatewayProject,Get-AidosRepositoryHandoffGatewayPayload,Get-AidosRepositoryHandoffGatewayCurrentHandoff,Resolve-AidosRepositoryHandoffGatewaySourcePath,Get-AidosRepositoryHandoffGatewaySource,Ensure-AidosRepositoryRuntimeActorActivated,Submit-AidosRepositoryRuntimeActorResult,Submit-AidosRepositoryHandoffGatewayResult,New-AidosRepositoryHandoffGatewayResponse,Invoke-AidosRepositoryHandoffGatewayRequest,ConvertFrom-AidosRepositoryHandoffGatewayQuery,Write-AidosRepositoryHandoffGatewayHttpResponse,Start-AidosRepositoryHandoffGateway,Stop-AidosRepositoryHandoffGateway
