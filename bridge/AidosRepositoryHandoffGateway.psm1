Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryActorHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryReviewHandoff.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryHandoffSignal.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosHumanInput.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosOperator.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectGoal.psm1') -DisableNameChecking

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
        schema_version='0.2';registry_root=[IO.Path]::GetFullPath($RegistryRoot);aidos_root=[IO.Path]::GetFullPath($AidosRoot);state_root=$state;bridge_state_root=[IO.Path]::GetFullPath($BridgeStateRoot);listen_prefix="http://127.0.0.1:$Port/";port=$Port;maximum_request_bytes=1048576;maximum_source_bytes=524288;maximum_source_chunk_characters=65536;configured_at=[DateTimeOffset]::UtcNow.ToString('o')
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
    if(-not$project.PSObject.Properties['official_root'] -or [string]::IsNullOrWhiteSpace([string]$project.official_root)){
        $project|Add-Member -NotePropertyName official_root -NotePropertyValue ([string]$project.local_root) -Force
    }
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
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$AidosRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$SourceRef,
        [int]$MaximumBytes=524288,
        [int]$StartCharacter=0,
        [int]$MaximumCharacters=65536
    )
    if($MaximumBytes-lt1){throw 'Authorized source byte limit must be positive.'}
    if($StartCharacter-lt0){throw 'Authorized source startCharacter must be non-negative.'}
    if($MaximumCharacters-lt1-or$MaximumCharacters-gt65536){throw 'Authorized source maxCharacters must be between 1 and 65536.'}
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId ([string]$project.project_id)
    if($null-eq$handoff-or[string]$handoff.metadata.kind-ne'ASSIGNMENT'){throw 'No active assignment handoff authorizes source access.'}
    $authorized=@($handoff.metadata.source_refs|ForEach-Object {[string]$_})
    $exact=@($authorized|Where-Object {[string]::Equals($_,$SourceRef,[StringComparison]::Ordinal)})
    if($exact.Count-ne1){throw "Source ref '$SourceRef' is not authorized exactly by the current handoff."}
    $resolved=Resolve-AidosRepositoryHandoffGatewaySourcePath -Project $project -AidosRoot $AidosRoot -SourceRef $SourceRef
    $bytes=[IO.File]::ReadAllBytes($resolved.path)
    if($bytes.Length-gt$MaximumBytes){throw "Authorized source exceeds the $MaximumBytes byte limit: $SourceRef"}
    $decoder=[Text.UTF8Encoding]::new($false,$true)
    try{$text=$decoder.GetString($bytes)}catch{throw "Authorized source is not valid UTF-8 text: $SourceRef"}
    if($text.IndexOf([char]0)-ge0){throw "Authorized source is not UTF-8 text: $SourceRef"}
    if($text-match'(?im)-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|(?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[:=]\s*\S+'){throw "Authorized source is not secret-free: $SourceRef"}
    if($StartCharacter-gt$text.Length){throw "Authorized source startCharacter exceeds source length: $SourceRef"}
    if($StartCharacter-gt0-and$StartCharacter-lt$text.Length-and[char]::IsLowSurrogate($text[$StartCharacter])-and[char]::IsHighSurrogate($text[$StartCharacter-1])){throw 'Authorized source startCharacter splits a UTF-16 surrogate pair.'}
    $end=[Math]::Min($text.Length,$StartCharacter+$MaximumCharacters)
    if($end-lt$text.Length-and$end-gt$StartCharacter-and[char]::IsHighSurrogate($text[$end-1])-and[char]::IsLowSurrogate($text[$end])){$end--}
    $length=$end-$StartCharacter
    $content=if($length-gt0){$text.Substring($StartCharacter,$length)}else{''}
    $complete=$end-eq$text.Length
    $next=if($complete){$null}else{$end}
    [pscustomobject][ordered]@{
        project_id=[string]$project.project_id
        source_ref=$SourceRef
        sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        byte_length=$bytes.Length
        character_length=$text.Length
        chunk_start=$StartCharacter
        chunk_length=$length
        next_start=$next
        complete=$complete
        content=$content
    }
}

function Assert-AidosRepositoryHandoffGatewayHumanInputBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Request)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    if($null-eq$Request.binding){throw 'Human Input Request binding is missing.'}
    $state=Get-AidosState $root
    foreach($name in @('definition_id','definition_version','execution_id','revision','review_id')){
        $expected=$Request.binding.PSObject.Properties[$name]
        if($null-eq$expected -or $null-eq$expected.Value){continue}
        $actual=$state.PSObject.Properties[$name]
        if($null-eq$actual -or [string]$actual.Value-ne[string]$expected.Value){throw "Human Input Request binding mismatch for '$name'."}
    }
    if($Request.binding.PSObject.Properties['baseline_version'] -and $null-ne$Request.binding.baseline_version){
        $baselinePath=Join-Path $root '.aidos/documentation/PROJECT_BASELINE.json'
        if(-not(Test-Path -LiteralPath $baselinePath -PathType Leaf)){throw 'Bound Project Baseline is unavailable.'}
        $baseline=Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
        if([int]$baseline.baseline_version-ne[int]$Request.binding.baseline_version){throw 'Human Input Request baseline binding mismatch.'}
    }
    $true
}

function Get-AidosRepositoryHandoffGatewayHumanInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
    $state=Get-AidosState $root
    if([string]$state.state-ne'WAITING_USER'){return [pscustomobject][ordered]@{status='NO_HUMAN_INPUT';project_id=[string]$project.project_id}}
    $requestRoot=Join-Path $root '.aidos/human-input'
    if(-not(Test-Path -LiteralPath $requestRoot -PathType Container)){throw 'Project is WAITING_USER but Human Input request storage is missing.'}
    $waiting=@(
        Get-ChildItem -LiteralPath $requestRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $request=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
            if([string]$request.status-eq'WAITING'){[pscustomobject][ordered]@{path=$_.FullName;request=$request}}
        }
    )
    if($waiting.Count-eq0){return [pscustomobject][ordered]@{status='NO_HUMAN_INPUT';project_id=[string]$project.project_id}}
    if($waiting.Count-ne1){throw "Project has $($waiting.Count) WAITING Human Input Requests; expected exactly one."}
    $candidate=$waiting[0];$request=$candidate.request
    if(-not[string]::Equals([string]$request.project_id,[string]$project.project_id,[StringComparison]::Ordinal)){throw 'Human Input Request project binding mismatch.'}
    Assert-AidosRepositoryHandoffGatewayHumanInputBinding -ProjectRoot $root -Request $request|Out-Null
    $sha=(Get-FileHash -LiteralPath $candidate.path -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject][ordered]@{
        status='READY'
        project_id=[string]$project.project_id
        request_id=[string]$request.request_id
        request_sha256=$sha
        phase=[string]$request.phase
        request_type=[string]$request.request_type
        context_summary=[string]$request.context_summary
        question=[string]$request.question
        options=@($request.options|ForEach-Object {[pscustomobject][ordered]@{option_id=[string]$_.option_id;label=[string]$_.label;description=if($null-eq$_.description){$null}else{[string]$_.description}}})
        authority_classification=[string]$request.authority_classification
        auto_define_stop_reason=if($request.PSObject.Properties['auto_define_stop_reason'] -and $null-ne$request.auto_define_stop_reason){[string]$request.auto_define_stop_reason}else{$null}
        binding=$request.binding
    }
}

function Submit-AidosRepositoryHandoffGatewayHumanInputResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)]$Request,
        [string]$BridgeStateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),
        [switch]$Push
    )
    if(-not$Request.PSObject.Properties['request_sha256'] -or [string]::IsNullOrWhiteSpace([string]$Request.request_sha256)){throw 'Human Input response requires request_sha256.'}
    $selectedOptionId=if($Request.PSObject.Properties['selected_option_id']){[string]$Request.selected_option_id}else{$null}
    $text=if($Request.PSObject.Properties['text']){[string]$Request.text}else{$null}
    if([string]::IsNullOrWhiteSpace($selectedOptionId)-and[string]::IsNullOrWhiteSpace($text)){throw 'Human Input response requires selected_option_id and/or text.'}
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
    $requestPath=Get-AidosHumanInputRequestPath -ProjectRoot $root -RequestId $RequestId
    if(-not(Test-Path -LiteralPath $requestPath -PathType Leaf)){throw "Human Input Request not found: $RequestId"}
    $current=Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    if(-not[string]::Equals([string]$current.project_id,[string]$project.project_id,[StringComparison]::Ordinal)){throw 'Human Input response project binding mismatch.'}
    if(-not[string]::Equals([string]$current.request_id,$RequestId,[StringComparison]::OrdinalIgnoreCase)){throw 'Human Input response request_id mismatch.'}
    if([string]$current.status-eq'WAITING'){
        $sha=(Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if(-not[string]::Equals($sha,[string]$Request.request_sha256,[StringComparison]::Ordinal)){throw 'Human Input Request hash is stale.'}
    }elseif([string]$current.status-ne'RESOLVED'){
        throw "Human Input Request status '$($current.status)' cannot accept a response."
    }
    $response=Submit-AidosHumanInputResponse -ProjectRoot $root -RequestId $RequestId -RespondedBy 'CHATGPT_CLASSIC_OPERATOR' -SelectedOptionId $selectedOptionId -Text $text
    $persistence=$null
    if([string]$response.status-eq'RESOLVED'){$persistence=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage ("AIDOS Human Input $RequestId") -Push:$Push}
    $accepted=if([string]$response.status-eq'ALREADY_RESOLVED'){'ALREADY_ACCEPTED'}else{'ACCEPTED'}
    Signal-AidosRepositoryHandoffBridge -StateRoot $BridgeStateRoot -Reason 'HUMAN_INPUT_ACCEPTED' -ProjectId ([string]$project.project_id) -HandoffId $RequestId|Out-Null
    [pscustomobject][ordered]@{status=$accepted;project_id=[string]$project.project_id;request_id=$RequestId;resume_ref=[string]$response.resume_ref;persistence=$persistence}
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
function Submit-AidosRepositoryHandoffGatewayControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)]$Request,
        [string]$BridgeStateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),
        [switch]$Push
    )
    $properties=@($Request.PSObject.Properties.Name)
    if($properties.Count-ne1-or$properties[0]-ne'command'){throw 'Chat control request must contain exactly one command field.'}
    $command=[string]$Request.command
    if($command-notin@('START','STOP')){throw "Unsupported chat control command '$command'."}
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
    $before=Get-AidosOperatorControlState -ProjectRoot $root
    $coreCommand=if($command-eq'START'){'RESUME'}else{'PAUSE'}
    $submitted=Submit-AidosControlIntent -ProjectRoot $root -Command $coreCommand -RequestedBy 'CHATGPT_OPERATOR' -Payload @{channel='CHATGPT';chat_command=$command}
    $intent=$submitted.intent
    if([string]$intent.status-ne'APPLIED'){
        return [pscustomobject][ordered]@{
            status='REJECTED';project_id=[string]$project.project_id;command=$command
            acknowledgement='AIDOS_CONTROL_REJECTED';control_id=[string]$intent.control_id
            control_mode=[string](Get-AidosOperatorControlState -ProjectRoot $root).mode
            reason=[string]$intent.result.reason;intent_ref=[string]$submitted.path
        }
    }
    $already=($command-eq'START'-and[string]$before.mode-eq'RUNNING')-or($command-eq'STOP'-and[string]$before.mode-in@('PAUSED','SAFE_STOPPED'))
    $acknowledgement=if($already){if($command-eq'START'){'AIDOS_CONTROL_ALREADY_RUNNING'}else{'AIDOS_CONTROL_ALREADY_PAUSED'}}else{"AIDOS_CONTROL_ACCEPTED::$command"}
    $null=Invoke-AidosPreparationGitPersistence -Project $project -CommitMessage ("AIDOS apply chat control $($intent.control_id)") -Push:$Push
    Signal-AidosRepositoryHandoffBridge -StateRoot $BridgeStateRoot -Reason 'CHAT_CONTROL_APPLIED' -ProjectId ([string]$project.project_id)|Out-Null
    [pscustomobject][ordered]@{
        status=if($already){'ALREADY_APPLIED'}else{'ACCEPTED'}
        project_id=[string]$project.project_id
        command=$command
        acknowledgement=$acknowledgement
        control_id=[string]$intent.control_id
        control_mode=[string]$intent.result.control.mode
        reason=$null
        intent_ref=[string]$submitted.path
    }
}
function Submit-AidosRepositoryHandoffGatewayGoal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId,[Parameter(Mandatory)]$Request,[string]$BridgeStateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),[switch]$Push)
    $properties=@($Request.PSObject.Properties.Name)
    if($properties.Count-ne1-or$properties[0]-ne'goal'){throw 'Chat goal request must contain exactly one goal property.'}
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $root=Resolve-AidosFileSystemPath ([string]$project.local_root)
    $activeHandoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId ([string]$project.project_id)
    if($null-ne$activeHandoff){
        $allowGoal=($activeHandoff.metadata -and [string]$activeHandoff.metadata.kind-eq'RESULT')
        if($allowGoal){
            $state=Get-AidosState -ProjectRoot $root
            $reviewId=[string]$activeHandoff.metadata.binding.review_id
            $stateOnlyAllowGoal=$false
            if([string]::IsNullOrWhiteSpace($reviewId)){
                if([string]$state.state -eq 'WAITING_DEFINITION'){
                    $stateOnlyAllowGoal=$true
                }else{
                    $reviewId=[string]$state.review_id
                    if([string]::IsNullOrWhiteSpace($reviewId)){
                    $reviewRoot=Join-Path ([string]$project.local_root) '.aidos/reviews'
                    if(Test-Path -LiteralPath $reviewRoot -PathType Container){
                        $matches=@(
                            Get-ChildItem -LiteralPath $reviewRoot -Directory -ErrorAction SilentlyContinue |
                            ForEach-Object {
                                $reviewPath=Join-Path $_.FullName 'REVIEW.json'
                                if(-not(Test-Path -LiteralPath $reviewPath -PathType Leaf)){return}
                                $review=Read-AidosJson -Path $reviewPath
                                if([string]$review.transport_state -notin @('CONSUMED','CLEANED')){return}
                                if([string]$review.decision.outcome -ne 'PASS'){return}
                                if([string]$review.project_id -ne [string]$project.project_id){return}
                                if([string]$review.definition_id -ne [string]$state.definition_id){return}
                                if([int]$review.definition_version -ne [int]$state.definition_version){return}
                                if([string]$review.execution_id -ne [string]$state.execution_id){return}
                                if([int]$review.revision -ne [int]$state.revision){return}
                                $review
                            }
                        )
                        if($matches.Count -eq 1){$reviewId=[string]$matches[0].review_id}
                    }
                    }
                }
            }
            if($stateOnlyAllowGoal){
                $allowGoal=$true
            }elseif([string]::IsNullOrWhiteSpace($reviewId)){$allowGoal=$false}else{
                $reviewPath=Join-Path ([string]$project.local_root) ('.aidos/reviews/{0}/REVIEW.json' -f $reviewId)
                if(-not(Test-Path -LiteralPath $reviewPath -PathType Leaf)){$allowGoal=$false}else{
                    $review=Read-AidosJson -Path $reviewPath
                    $allowGoal=([string]$review.transport_state -in @('CONSUMED','CLEANED') -and [string]$review.decision.outcome -eq 'PASS')
                }
            }
        }
        if($allowGoal){
            $state=Get-AidosState -ProjectRoot $root
            if(-not$stateOnlyAllowGoal -and [string]$state.state-ne'IDLE'){
                Set-AidosState -ProjectRoot $root -NewState IDLE -Actor SYSTEM -Patch @{review_id=$null}|Out-Null
            }
        }
        if(-not$allowGoal){throw 'A new project goal is blocked by an active repository handoff.'}
    }
    $accepted=Submit-AidosProjectGoal -Project $project -Goal ([string]$Request.goal) -SubmittedBy CHATGPT_OPERATOR -AllowNonIdleState:$stateOnlyAllowGoal -SkipDefinitionWorkspace:$stateOnlyAllowGoal -Push:$Push
    Signal-AidosRepositoryHandoffBridge -StateRoot $BridgeStateRoot -Reason 'PROJECT_GOAL_ACCEPTED' -ProjectId ([string]$project.project_id)|Out-Null
    $accepted
}
function New-AidosRepositoryHandoffGatewayResponse {
    param([int]$StatusCode,[Parameter(Mandatory)]$Body)
    [pscustomobject][ordered]@{status_code=$StatusCode;body=$Body}
}
function Get-AidosRepositoryInterfaceSnapshot {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$RegistryRoot)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects'
    $projects=[Collections.Generic.List[object]]::new();$humanInputs=[Collections.Generic.List[object]]::new();$timeline=[Collections.Generic.List[object]]::new()
    foreach($file in @(Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File -ErrorAction SilentlyContinue|Sort-Object Name)){
        $project=Read-AidosJson $file.FullName;$root=Resolve-AidosFileSystemPath ([string]$project.local_root);$status=Get-AidosRuntimeStatusProjection $root;$runtime=@($status.projects)[0];$state=[string]$runtime.state
        $mapped=if($state-in @('CODEX_RUNNING','TASK_READY','GPT_REVIEWING','DEFINITION_RUNNING')){'RUNNING'}elseif($state-in @('WAITING_USER','RECOVERY_REQUIRED')){'BLOCKED'}elseif($state-in @('PAUSED','SAFE_STOPPED')){'PAUSED'}elseif($state-eq'IDLE'){'COMPLETE'}else{'UNKNOWN'}
        $workstreams=@($runtime.workstreams|ForEach-Object {[pscustomobject][ordered]@{id=[string]$_.workstream_id;name=[string]$_.workstream_id;status=if([string]$_.status-eq'ACTIVE'){'RUNNING'}else{'UNKNOWN'};progress=0;activeActor=[string]$_.current_actor_role;blocker=if([int]$_.blocker_count-gt0){'Open blocker'}else{$null}}})
        $projects.Add([pscustomobject][ordered]@{id=[string]$project.project_id;name=[string]$project.project_id;status=$mapped;progress=0;eta=[ordered]@{confidence='NOT_RELIABLY_ESTIMABLE'};workstreams=@($workstreams);controls=@('START','PAUSE','RESUME','SAFE_STOP');latestActivity=$null})
        foreach($request in @(Get-AidosRepositoryInterfaceOpenHumanInputs $root)){$humanInputs.Add([pscustomobject][ordered]@{id=[string]$request.request_id;projectId=[string]$project.project_id;title=[string]$request.title;context=[string]$request.question;options=@($request.options|ForEach-Object {[string]$_.id})})}
        foreach($event in @(Get-AidosRepositoryInterfaceRecentEvents -ProjectRoot $root -Limit 25)){$timeline.Add([pscustomobject][ordered]@{id=[string]$event.event_id;projectId=[string]$project.project_id;at=[string]$event.timestamp;kind=[string]$event.event_type;message=([string]$event.event_type)})}
    }
    [pscustomobject][ordered]@{contractVersion='0.1';generatedAt=[DateTimeOffset]::UtcNow.ToString('o');projects=@($projects);humanInputs=@($humanInputs);insights=@();timeline=@($timeline)}
}
function Get-AidosRepositoryInterfaceOpenHumanInputs { param([Parameter(Mandatory)][string]$ProjectRoot) $dir=Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/human-input';if(-not(Test-Path -LiteralPath $dir -PathType Container)){return @()};@(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue|ForEach-Object {$x=Read-AidosJson $_.FullName;if([string]$x.status-in@('WAITING','OPEN','PENDING')){$x}}) }
function Get-AidosRepositoryInterfaceRecentEvents { param([Parameter(Mandatory)][string]$ProjectRoot,[int]$Limit=25) $dir=Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/events';if(-not(Test-Path -LiteralPath $dir -PathType Container)){return @()};$items=@();foreach($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File|Sort-Object Name -Descending)){foreach($line in @(Get-Content -LiteralPath $f.FullName)){if($items.Count-ge$Limit){break};try{$items+=($line|ConvertFrom-Json -Depth 50)}catch{}};if($items.Count-ge$Limit){break}};@($items)
}
function Get-AidosRepositoryInterfaceDefinition {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$ProjectId)
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId;$root=Resolve-AidosFileSystemPath ([string]$project.local_root);$state=Get-AidosState $root
    $definitionId=[string]$state.definition_id;$version=[int]$state.definition_version;$path=Join-Path $root ('.aidos/definitions/{0}/v{1}/DEFINITION.json' -f $definitionId,$version);$definition=if(Test-Path -LiteralPath $path -PathType Leaf){Read-AidosJson $path}else{$null}
    [pscustomobject][ordered]@{projectId=$ProjectId;definitionId=$definitionId;version=$version;status=if($definition){[string]$definition.status}else{[string]$state.state};goal=if($definition){[string]$definition.goal}else{''};requirements=@($definition.requirements|ForEach-Object {[pscustomobject][ordered]@{id=[string]$_.surface_id;summary=[string]$_.summary;status=[string]$_.status}})}
}
function Invoke-AidosRepositoryHandoffGatewayRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][string]$Path,[hashtable]$Query=@{},[AllowNull()]$Body,[Parameter(Mandatory)][string]$PresentedKey,[Parameter(Mandatory)][string]$ExpectedKey,[Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$AidosRoot,[string]$BridgeStateRoot=(Get-AidosRepositoryHandoffBridgeDefaultStateRoot),[switch]$Push)
    if(-not(Test-AidosRepositoryHandoffGatewayKey -Expected $ExpectedKey -Presented $PresentedKey)){return New-AidosRepositoryHandoffGatewayResponse 401 ([ordered]@{error='UNAUTHORIZED'})}
    try{
        if($Method-eq'GET'-and$Path-eq'/health'){return New-AidosRepositoryHandoffGatewayResponse 200 ([ordered]@{status='OK';service='AIDOS_REPOSITORY_HANDOFF_GATEWAY'})}
        if($Method-eq'GET'-and$Path-eq'/v1/interface/snapshot'){return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryInterfaceSnapshot -RegistryRoot $RegistryRoot)}
        if($Method-eq'GET'-and$Path-match'^/v1/interface/projects/([^/]+)/definition$'){return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryInterfaceDefinition -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])))}
        if($Method-eq'POST'-and$Path-eq'/v1/interface/intents'){
            if($null-eq$Body -or -not$Body.projectId -or -not$Body.kind){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='BODY_REQUIRED'})}
            $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId ([string]$Body.projectId);$root=Resolve-AidosFileSystemPath ([string]$project.local_root);$command=switch([string]$Body.kind){'START' {'RESUME'}'RESUME' {'RESUME'}'PAUSE' {'PAUSE'}'SAFE_STOP' {'SAFE_STOP'}default {throw 'Unsupported interface control.'}}
            $submitted=Submit-AidosControlIntent -ProjectRoot $root -Command $command -RequestedBy 'AIDOS_INTERFACE';if([string]$submitted.intent.status-ne'APPLIED'){throw [string]$submitted.intent.result.reason};$workflowState=[string](Get-AidosState $root).state
            if([string]$Body.kind-eq'START' -and $workflowState-eq'IDLE'){
                $state=Get-AidosState $root;if([string]::IsNullOrWhiteSpace([string]$state.definition_id)){throw 'START requires an accepted Definition or a new project goal.'}
                $definitionPath=Join-Path $root ('.aidos/definitions/{0}/v{1}/DEFINITION.json' -f [string]$state.definition_id,[int]$state.definition_version);if(-not(Test-Path -LiteralPath $definitionPath -PathType Leaf)){throw 'START requires the active Definition artifact.'};$definition=Read-AidosJson $definitionPath;if([string]$definition.status-ne'ACCEPTED'){throw "START requires an ACCEPTED Definition; current status is '$([string]$definition.status)'."}
                Set-AidosState -ProjectRoot $root -NewState TASK_READY -Actor AIDOS_INTERFACE -Patch @{}|Out-Null;$workflowState='TASK_READY';Signal-AidosRepositoryHandoffBridge -StateRoot $BridgeStateRoot -Reason 'INTERFACE_START_TASK_READY' -ProjectId ([string]$project.project_id)|Out-Null
            }
            return New-AidosRepositoryHandoffGatewayResponse 202 ([ordered]@{accepted=$true;control_id=[string]$submitted.intent.control_id;workflow_state=$workflowState})
        }
        if($Method-eq'POST'-and$Path-match'^/v1/interface/human-input/([^/]+)/resolve$'){
            if($null-eq$Body -or -not$Body.option){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='BODY_REQUIRED'})}
            $projectId=if($Body.projectId){[string]$Body.projectId}else{(Get-ChildItem -LiteralPath (Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects') -Filter '*.json' -File|Select-Object -First 1|ForEach-Object {$_.BaseName})};$result=Submit-AidosRepositoryHandoffGatewayHumanInputResponse -RegistryRoot $RegistryRoot -ProjectId $projectId -RequestId ([Uri]::UnescapeDataString($Matches[1])) -Request ([pscustomobject]@{option=[string]$Body.option});return New-AidosRepositoryHandoffGatewayResponse 202 ([ordered]@{accepted=$true;result=$result})
        }
        if($Method-eq'GET'-and$Path-match'^/v1/projects/([^/]+)/handoff$'){return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryHandoffGatewayCurrentHandoff -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])))}
        if($Method-eq'GET'-and$Path-match'^/v1/projects/([^/]+)/human-input$'){return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryHandoffGatewayHumanInput -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])))}
        if($Method-eq'POST'-and$Path-match'^/v1/projects/([^/]+)/control$'){
            if($null-eq$Body){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='BODY_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse 200 (Submit-AidosRepositoryHandoffGatewayControl -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -Request $Body -BridgeStateRoot $BridgeStateRoot -Push:$Push)
        }
        if($Method-eq'POST'-and$Path-match'^/v1/projects/([^/]+)/goals$'){
            if($null-eq$Body){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='BODY_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse 200 (Submit-AidosRepositoryHandoffGatewayGoal -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -Request $Body -BridgeStateRoot $BridgeStateRoot -Push:$Push)
        }
        if($Method-eq'POST'-and$Path-match'^/v1/projects/([^/]+)/human-input/([^/]+)/response$'){
            if($null-eq$Body){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='BODY_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse 200 (Submit-AidosRepositoryHandoffGatewayHumanInputResponse -RegistryRoot $RegistryRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -RequestId ([Uri]::UnescapeDataString($Matches[2])) -Request $Body -BridgeStateRoot $BridgeStateRoot -Push:$Push)
        }
        if($Method-eq'GET'-and$Path-match'^/v1/projects/([^/]+)/sources$'){
            $sourceRef=[string]$Query['path'];if([string]::IsNullOrWhiteSpace($sourceRef)){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_PATH_REQUIRED'})}
            $startCharacter=0
            if($Query.ContainsKey('startCharacter')-and-not[string]::IsNullOrWhiteSpace([string]$Query['startCharacter'])){
                if(-not[int]::TryParse([string]$Query['startCharacter'],[ref]$startCharacter)-or$startCharacter-lt0){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_CHUNK_RANGE_INVALID';detail='startCharacter must be a non-negative integer.'})}
            }
            $maxCharacters=65536
            if($Query.ContainsKey('maxCharacters')-and-not[string]::IsNullOrWhiteSpace([string]$Query['maxCharacters'])){
                if(-not[int]::TryParse([string]$Query['maxCharacters'],[ref]$maxCharacters)-or$maxCharacters-lt1-or$maxCharacters-gt65536){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_CHUNK_RANGE_INVALID';detail='maxCharacters must be an integer between 1 and 65536.'})}
            }
            return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $RegistryRoot -AidosRoot $AidosRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -SourceRef $sourceRef -StartCharacter $startCharacter -MaximumCharacters $maxCharacters)
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

Export-ModuleMember -Function Get-AidosRepositoryHandoffGatewayDefaultStateRoot,Get-AidosRepositoryHandoffGatewayPath,Move-AidosRepositoryHandoffGatewayAtomicFile,Write-AidosRepositoryHandoffGatewayJsonAtomic,New-AidosRepositoryHandoffGatewayKey,Initialize-AidosRepositoryHandoffGateway,Read-AidosRepositoryHandoffGatewayConfiguration,Test-AidosRepositoryHandoffGatewayKey,Get-AidosRepositoryHandoffGatewayPresentedKey,Test-AidosRepositoryHandoffGatewayProjectId,Get-AidosRepositoryHandoffGatewayProject,Get-AidosRepositoryHandoffGatewayPayload,Get-AidosRepositoryHandoffGatewayCurrentHandoff,Resolve-AidosRepositoryHandoffGatewaySourcePath,Get-AidosRepositoryHandoffGatewaySource,Assert-AidosRepositoryHandoffGatewayHumanInputBinding,Get-AidosRepositoryHandoffGatewayHumanInput,Submit-AidosRepositoryHandoffGatewayHumanInputResponse,Ensure-AidosRepositoryRuntimeActorActivated,Submit-AidosRepositoryRuntimeActorResult,Submit-AidosRepositoryHandoffGatewayResult,Submit-AidosRepositoryHandoffGatewayControl,Submit-AidosRepositoryHandoffGatewayGoal,New-AidosRepositoryHandoffGatewayResponse,Invoke-AidosRepositoryHandoffGatewayRequest,ConvertFrom-AidosRepositoryHandoffGatewayQuery,Write-AidosRepositoryHandoffGatewayHttpResponse,Start-AidosRepositoryHandoffGateway,Stop-AidosRepositoryHandoffGateway
