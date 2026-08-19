Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryActorHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking

function Get-AidosRepositoryHandoffGatewayDefaultStateRoot {
    if([OperatingSystem]::IsWindows()){return (Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-gateway')}
    Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-repository-handoff-gateway'
}

function Get-AidosRepositoryHandoffGatewayPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[ValidateSet('config','key','status','stop')][string]$Kind)
    $names=@{config='CONFIG.json';key='API_KEY.txt';status='STATUS.json';stop='STOP'}
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) $names[$Kind]
}

function Write-AidosRepositoryHandoffGatewayJsonAtomic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $dir=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function New-AidosRepositoryHandoffGatewayKey {
    [CmdletBinding()]
    param()
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
        [int]$Port=47831,
        [switch]$RotateKey
    )
    if($Port-lt1024 -or $Port-gt65535){throw 'Repository handoff gateway port must be between 1024 and 65535.'}
    $state=[IO.Path]::GetFullPath($StateRoot)
    if(-not(Test-Path -LiteralPath $state -PathType Container)){New-Item -ItemType Directory -Path $state -Force|Out-Null}
    $keyPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $state -Kind key
    if($RotateKey -or -not(Test-Path -LiteralPath $keyPath -PathType Leaf)){
        New-AidosRepositoryHandoffGatewayKey|Set-Content -LiteralPath $keyPath -Encoding ascii -NoNewline
    }
    $config=[ordered]@{
        schema_version='0.1'
        registry_root=[IO.Path]::GetFullPath($RegistryRoot)
        aidos_root=[IO.Path]::GetFullPath($AidosRoot)
        state_root=$state
        listen_prefix="http://127.0.0.1:$Port/"
        port=$Port
        maximum_request_bytes=1048576
        maximum_source_bytes=262144
        configured_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-AidosRepositoryHandoffGatewayJsonAtomic -Path (Get-AidosRepositoryHandoffGatewayPath -StateRoot $state -Kind config) -Value $config
    [pscustomobject][ordered]@{status='CONFIGURED';config=[pscustomobject]$config;api_key=(Get-Content -LiteralPath $keyPath -Raw -Encoding ASCII)}
}

function Read-AidosRepositoryHandoffGatewayConfiguration {
    [CmdletBinding()]
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
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Expected,[AllowNull()][AllowEmptyString()][string]$Presented)
    if([string]::IsNullOrWhiteSpace($Expected)-or[string]::IsNullOrWhiteSpace($Presented)){return $false}
    $a=[Text.Encoding]::UTF8.GetBytes($Expected)
    $b=[Text.Encoding]::UTF8.GetBytes($Presented)
    if($a.Length-ne$b.Length){return $false}
    [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a,$b)
}

function Get-AidosRepositoryHandoffGatewayPresentedKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Headers)
    $custom=[string]$Headers['X-AIDOS-Key']
    if(-not[string]::IsNullOrWhiteSpace($custom)){return $custom.Trim()}
    $authorization=[string]$Headers['Authorization']
    if($authorization.StartsWith('Bearer ',[StringComparison]::OrdinalIgnoreCase)){return $authorization.Substring(7).Trim()}
    $null
}

function Get-AidosRepositoryHandoffGatewayProject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    $project=Get-AidosRegisteredProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    if([string]$project.stage-ne'RUNTIME' -or [string]$project.status-ne'PROMOTED'){throw "Project '$ProjectId' is not an active AIDOS runtime project."}
    Test-AidosRegistryProjectBinding -Project $project|Out-Null
    $project
}

function Get-AidosRepositoryHandoffGatewayPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$Handoff)
    $path=Resolve-AidosRepositoryHandoffPayloadPath -ProjectRoot ([string]$Project.local_root) -RelativePath ([string]$Handoff.metadata.payload_ref)
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Repository handoff payload is missing.'}
    $bytes=[IO.File]::ReadAllBytes($path)
    if($bytes.Length-gt1048576){throw 'Repository handoff payload exceeds the gateway limit.'}
    $sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if(-not[string]::IsNullOrWhiteSpace([string]$Handoff.metadata.payload_sha256) -and [string]$Handoff.metadata.payload_sha256-ne$sha){throw 'Repository handoff payload hash mismatch.'}
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    if($text.IndexOf([char]0)-ge0){throw 'Repository handoff payload is not UTF-8 text.'}
    try{$value=$text|ConvertFrom-Json -Depth 100}catch{$value=$text}
    [pscustomobject][ordered]@{path=[string]$Handoff.metadata.payload_ref;sha256=$sha;content=$value}
}

function Get-AidosRepositoryHandoffGatewayCurrentHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId $ProjectId
    if($null-eq$handoff){return [pscustomobject][ordered]@{status='NO_HANDOFF';project_id=$ProjectId}}
    $payload=Get-AidosRepositoryHandoffGatewayPayload -Project $project -Handoff $handoff
    [pscustomobject][ordered]@{
        status='READY'
        project_id=$ProjectId
        handoff_sha256=[string]$handoff.text_sha256
        metadata=$handoff.metadata
        body=[string]$handoff.body
        payload=$payload
    }
}

function Resolve-AidosRepositoryHandoffGatewaySourcePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$AidosRoot,[Parameter(Mandatory)][string]$SourceRef)
    $ref=$SourceRef.Replace('\','/').Trim()
    if($ref.StartsWith('AIDOS/',[StringComparison]::Ordinal)){
        $base=[IO.Path]::GetFullPath($AidosRoot)
        $relative=$ref.Substring(6)
    }else{
        $base=Resolve-AidosFileSystemPath ([string]$Project.local_root)
        $relative=$ref
    }
    $relative=Test-AidosRepositoryRelativePath -Path $relative -FieldName 'source_ref'
    $path=[IO.Path]::GetFullPath((Join-Path $base $relative))
    $comparison=if([OperatingSystem]::IsWindows()){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    $prefix=$base.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not$path.StartsWith($prefix,$comparison)){throw 'Repository handoff source_ref escapes its authority root.'}
    [pscustomobject][ordered]@{path=$path;source_ref=$ref}
}

function Get-AidosRepositoryHandoffGatewaySource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$AidosRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$SourceRef,
        [int]$MaximumBytes=262144
    )
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId $ProjectId
    if($null-eq$handoff -or [string]$handoff.metadata.kind-ne'ASSIGNMENT'){throw 'No active assignment handoff authorizes source access.'}
    $authorized=@($handoff.metadata.source_refs|ForEach-Object {[string]$_})
    if($SourceRef-notin$authorized){throw "Source ref '$SourceRef' is not authorized by the current handoff."}
    $resolved=Resolve-AidosRepositoryHandoffGatewaySourcePath -Project $project -AidosRoot $AidosRoot -SourceRef $SourceRef
    if(-not(Test-Path -LiteralPath $resolved.path -PathType Leaf)){throw "Authorized source is missing: $SourceRef"}
    $bytes=[IO.File]::ReadAllBytes($resolved.path)
    if($bytes.Length-gt$MaximumBytes){throw "Authorized source exceeds the $MaximumBytes byte limit: $SourceRef"}
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    if($text.IndexOf([char]0)-ge0){throw "Authorized source is not UTF-8 text: $SourceRef"}
    if($text-match'(?im)-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|(?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[:=]\s*\S+'){throw "Authorized source is not secret-free: $SourceRef"}
    [pscustomobject][ordered]@{
        project_id=$ProjectId
        source_ref=$SourceRef
        sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        byte_length=$bytes.Length
        content=$text
    }
}

function Submit-AidosRepositoryHandoffGatewayResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)]$Request,
        [switch]$Push
    )
    foreach($name in @('expected_parent_handoff_id','result')){if(-not$Request.PSObject.Properties[$name]){throw "Result submission is missing '$name'."}}
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot $root -ExpectedProjectId $ProjectId
    if($null-eq$handoff){throw 'No repository assignment handoff is available.'}
    if([string]$handoff.metadata.kind-eq'RESULT'){
        if([string]$handoff.metadata.parent_handoff_id-eq[string]$Request.expected_parent_handoff_id){
            return [pscustomobject][ordered]@{status='ALREADY_ACCEPTED';project_id=$ProjectId;handoff_id=[string]$handoff.metadata.handoff_id;parent_handoff_id=[string]$handoff.metadata.parent_handoff_id}
        }
        throw 'Repository handoff already contains a different result.'
    }
    if([string]$handoff.metadata.kind-ne'ASSIGNMENT'){throw 'Current repository handoff is not an assignment.'}
    if(-not[string]::Equals([string]$handoff.metadata.handoff_id,[string]$Request.expected_parent_handoff_id,[StringComparison]::OrdinalIgnoreCase)){throw 'Result submission parent handoff is stale.'}
    if([string]$handoff.metadata.to_actor-ne'THINKER'){throw 'Gateway result submission is currently restricted to THINKER assignments.'}
    $result=$Request.result
    $binding=Test-AidosRuntimeActorResultBinding -ProjectRoot $root -Result $result
    if([string]$result.actor_role-ne'THINKER'){throw 'Gateway result payload is not a Thinker result.'}
    $assignment=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId ([string]$result.assignment_id)
    $assignmentRef=[IO.Path]::GetRelativePath($root,$assignment.path).Replace('\','/')
    if([string]$handoff.metadata.payload_ref-ne$assignmentRef -or [string]$handoff.metadata.payload_sha256-ne[string]$assignment.sha256){throw 'Current handoff does not bind the submitted runtime assignment.'}
    $saved=Save-AidosRuntimeActorResult -ProjectRoot $root -Result $result
    $resultPath=Get-AidosRuntimeActorResultPath -ProjectRoot $root -AssignmentId ([string]$result.assignment_id)
    $resultRef=[IO.Path]::GetRelativePath($root,$resultPath).Replace('\','/')
    $resultSha=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata=[pscustomobject][ordered]@{
        schema_version='0.1'
        envelope_type='AIDOS_REPOSITORY_HANDOFF'
        handoff_id=[guid]::NewGuid().ToString()
        project_id=$ProjectId
        kind='RESULT'
        from_actor='THINKER'
        to_actor='CORE'
        status='READY'
        parent_handoff_id=[string]$handoff.metadata.handoff_id
        created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action=([string]$assignment.assignment.action+'_RESULT')
        payload_ref=$resultRef
        payload_sha256=$resultSha
        binding=$assignment.assignment.binding
        source_refs=@()
    }
    $null=Test-AidosRepositoryHandoffTransition -Previous $handoff -Next $metadata
    $body=if($Request.PSObject.Properties['summary'] -and -not[string]::IsNullOrWhiteSpace([string]$Request.summary)){"# Thinker result`n`n$([string]$Request.summary)"}else{"# Thinker result`n`nRuntime actor result submitted to AIDOS Core."}
    $written=Write-AidosRepositoryHandoff -ProjectRoot $root -Metadata $metadata -Body $body -ExpectedParentHandoffId ([string]$handoff.metadata.handoff_id)
    Add-AidosEvent -ProjectRoot $root -EventType 'REPOSITORY_HANDOFF_RESULT_PUBLISHED' -Actor THINKER -Payload @{handoff_id=[string]$metadata.handoff_id;parent_handoff_id=[string]$metadata.parent_handoff_id;assignment_id=[string]$result.assignment_id;payload_ref=$resultRef}|Out-Null
    $persist=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage ("AIDOS Thinker result $($result.assignment_id)") -Push:$Push
    [pscustomobject][ordered]@{status='ACCEPTED';project_id=$ProjectId;handoff=$written;saved=$saved;binding=$binding;persistence=$persist}
}

function New-AidosRepositoryHandoffGatewayResponse {
    param([int]$StatusCode,[Parameter(Mandatory)]$Body)
    [pscustomobject][ordered]@{status_code=$StatusCode;body=$Body}
}

function Invoke-AidosRepositoryHandoffGatewayRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Query=@{},
        [AllowNull()]$Body,
        [Parameter(Mandatory)][string]$PresentedKey,
        [Parameter(Mandatory)][string]$ExpectedKey,
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$AidosRoot,
        [switch]$Push
    )
    if(-not(Test-AidosRepositoryHandoffGatewayKey -Expected $ExpectedKey -Presented $PresentedKey)){return New-AidosRepositoryHandoffGatewayResponse -StatusCode 401 -Body ([ordered]@{error='UNAUTHORIZED'})}
    try{
        if($Method-eq'GET' -and $Path-eq'/health'){return New-AidosRepositoryHandoffGatewayResponse -StatusCode 200 -Body ([ordered]@{status='OK';service='AIDOS_REPOSITORY_HANDOFF_GATEWAY'})}
        if($Path-match'^/v1/projects/([^/]+)/handoff$' -and $Method-eq'GET'){
            $projectId=[Uri]::UnescapeDataString($Matches[1])
            return New-AidosRepositoryHandoffGatewayResponse -StatusCode 200 -Body (Get-AidosRepositoryHandoffGatewayCurrentHandoff -RegistryRoot $RegistryRoot -ProjectId $projectId)
        }
        if($Path-match'^/v1/projects/([^/]+)/sources$' -and $Method-eq'GET'){
            $projectId=[Uri]::UnescapeDataString($Matches[1])
            $sourceRef=[string]$Query['path']
            if([string]::IsNullOrWhiteSpace($sourceRef)){return New-AidosRepositoryHandoffGatewayResponse -StatusCode 400 -Body ([ordered]@{error='SOURCE_PATH_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse -StatusCode 200 -Body (Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $RegistryRoot -AidosRoot $AidosRoot -ProjectId $projectId -SourceRef $sourceRef)
        }
        if($Path-match'^/v1/projects/([^/]+)/results$' -and $Method-eq'POST'){
            $projectId=[Uri]::UnescapeDataString($Matches[1])
            if($null-eq$Body){return New-AidosRepositoryHandoffGatewayResponse -StatusCode 400 -Body ([ordered]@{error='BODY_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse -StatusCode 200 -Body (Submit-AidosRepositoryHandoffGatewayResult -RegistryRoot $RegistryRoot -ProjectId $projectId -Request $Body -Push:$Push)
        }
        New-AidosRepositoryHandoffGatewayResponse -StatusCode 404 -Body ([ordered]@{error='NOT_FOUND'})
    }catch{
        New-AidosRepositoryHandoffGatewayResponse -StatusCode 409 -Body ([ordered]@{error='REQUEST_REJECTED';detail=$_.Exception.Message})
    }
}

function ConvertFrom-AidosRepositoryHandoffGatewayQuery {
    param([Parameter(Mandatory)][Uri]$Uri)
    $query=@{}
    $text=$Uri.Query.TrimStart('?')
    if([string]::IsNullOrWhiteSpace($text)){return $query}
    foreach($part in $text.Split('&',[StringSplitOptions]::RemoveEmptyEntries)){
        $items=$part.Split('=',2)
        $name=[Uri]::UnescapeDataString($items[0])
        $value=if($items.Count-gt1){[Uri]::UnescapeDataString($items[1].Replace('+',' '))}else{''}
        $query[$name]=$value
    }
    $query
}

function Write-AidosRepositoryHandoffGatewayHttpResponse {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Response)
    $json=$Response.body|ConvertTo-Json -Depth 100 -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode=[int]$Response.status_code
    $Context.Response.ContentType='application/json; charset=utf-8'
    $Context.Response.ContentEncoding=[Text.Encoding]::UTF8
    $Context.Response.ContentLength64=$bytes.Length
    $Context.Response.Headers['Cache-Control']='no-store'
    $Context.Response.OutputStream.Write($bytes,0,$bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Start-AidosRepositoryHandoffGateway {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffGatewayDefaultStateRoot),[switch]$Push)
    $loaded=Read-AidosRepositoryHandoffGatewayConfiguration -StateRoot $StateRoot
    $config=$loaded.config
    $listener=[Net.HttpListener]::new()
    $listener.Prefixes.Add([string]$config.listen_prefix)
    $statusPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind status
    $stopPath=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind stop
    Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    try{
        $listener.Start()
        Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='RUNNING';pid=$PID;listen_prefix=[string]$config.listen_prefix;started_at=[DateTimeOffset]::UtcNow.ToString('o');heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o')})
        while(-not(Test-Path -LiteralPath $stopPath -PathType Leaf)){
            $async=$listener.BeginGetContext($null,$null)
            while(-not$async.AsyncWaitHandle.WaitOne(1000)){
                $status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
                $status.heartbeat_at=[DateTimeOffset]::UtcNow.ToString('o')
                Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value $status
                if(Test-Path -LiteralPath $stopPath -PathType Leaf){break}
            }
            if(Test-Path -LiteralPath $stopPath -PathType Leaf){break}
            $context=$listener.EndGetContext($async)
            try{
                $presented=Get-AidosRepositoryHandoffGatewayPresentedKey -Headers $context.Request.Headers
                $body=$null
                if($context.Request.HasEntityBody){
                    if($context.Request.ContentLength64-gt[int]$config.maximum_request_bytes){throw 'Gateway request body exceeds configured limit.'}
                    $reader=[IO.StreamReader]::new($context.Request.InputStream,$context.Request.ContentEncoding,$true,4096,$false)
                    try{$bodyText=$reader.ReadToEnd()}finally{$reader.Dispose()}
                    if(-not[string]::IsNullOrWhiteSpace($bodyText)){$body=$bodyText|ConvertFrom-Json -Depth 100}
                }
                $response=Invoke-AidosRepositoryHandoffGatewayRequest -Method ([string]$context.Request.HttpMethod) -Path ([string]$context.Request.Url.AbsolutePath) -Query (ConvertFrom-AidosRepositoryHandoffGatewayQuery -Uri $context.Request.Url) -Body $body -PresentedKey $presented -ExpectedKey ([string]$loaded.api_key) -RegistryRoot ([string]$config.registry_root) -AidosRoot ([string]$config.aidos_root) -Push:$Push
            }catch{$response=New-AidosRepositoryHandoffGatewayResponse -StatusCode 400 -Body ([ordered]@{error='BAD_REQUEST';detail=$_.Exception.Message})}
            Write-AidosRepositoryHandoffGatewayHttpResponse -Context $context -Response $response
        }
        Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='STOPPED';pid=$PID;stopped_at=[DateTimeOffset]::UtcNow.ToString('o')})
    }catch{
        Write-AidosRepositoryHandoffGatewayJsonAtomic -Path $statusPath -Value ([ordered]@{schema_version='0.1';status='ERROR';pid=$PID;observed_at=[DateTimeOffset]::UtcNow.ToString('o');error=$_.Exception.Message})
        throw
    }finally{
        if($listener.IsListening){$listener.Stop()}
        $listener.Close()
    }
}

function Stop-AidosRepositoryHandoffGateway {
    [CmdletBinding()]
    param([string]$StateRoot=(Get-AidosRepositoryHandoffGatewayDefaultStateRoot))
    $path=Get-AidosRepositoryHandoffGatewayPath -StateRoot $StateRoot -Kind stop
    $dir=Split-Path -Parent $path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Set-Content -LiteralPath $path -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
    [pscustomobject][ordered]@{status='STOP_REQUESTED';state_root=[IO.Path]::GetFullPath($StateRoot)}
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffGatewayDefaultStateRoot,Get-AidosRepositoryHandoffGatewayPath,Write-AidosRepositoryHandoffGatewayJsonAtomic,New-AidosRepositoryHandoffGatewayKey,Initialize-AidosRepositoryHandoffGateway,Read-AidosRepositoryHandoffGatewayConfiguration,Test-AidosRepositoryHandoffGatewayKey,Get-AidosRepositoryHandoffGatewayPresentedKey,Get-AidosRepositoryHandoffGatewayProject,Get-AidosRepositoryHandoffGatewayPayload,Get-AidosRepositoryHandoffGatewayCurrentHandoff,Resolve-AidosRepositoryHandoffGatewaySourcePath,Get-AidosRepositoryHandoffGatewaySource,Submit-AidosRepositoryHandoffGatewayResult,New-AidosRepositoryHandoffGatewayResponse,Invoke-AidosRepositoryHandoffGatewayRequest,ConvertFrom-AidosRepositoryHandoffGatewayQuery,Write-AidosRepositoryHandoffGatewayHttpResponse,Start-AidosRepositoryHandoffGateway,Stop-AidosRepositoryHandoffGateway
