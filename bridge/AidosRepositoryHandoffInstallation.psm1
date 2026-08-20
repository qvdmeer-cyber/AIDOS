Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-AidosRepositoryHandoffHostDefaultStateRoot {
    [CmdletBinding()]
    param()
    if([OperatingSystem]::IsWindows()){return (Join-Path $env:LOCALAPPDATA 'AIDOS\repository-handoff-host')}
    Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-repository-handoff-host'
}

function Get-AidosRepositoryHandoffHostTaskName {
    'AIDOS Repository Handoff Host'
}

function Get-AidosRepositoryHandoffLegacyTaskName {
    'AIDOS Persistent Local Desktop Agent'
}

function Get-AidosRepositoryHandoffHostPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [Parameter(Mandatory)][ValidateSet('config','status','stop','lease','launcher','vbs','engine','openapi','instructions','stdout','stderr')][string]$Kind
    )
    $names=@{
        config='CONFIG.json'
        status='STATUS.json'
        stop='STOP'
        lease='LEASE.json'
        launcher='LAUNCHER.ps1'
        vbs='LAUNCHER.vbs'
        engine='ENGINE.txt'
        openapi='OPENAPI.json'
        instructions='GPT_INSTRUCTIONS.md'
        stdout='HOST_STDOUT.log'
        stderr='HOST_STDERR.log'
    }
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) $names[$Kind]
}

function Write-AidosRepositoryHandoffInstallationJsonAtomic {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $full=[IO.Path]::GetFullPath($Path)
    $dir=Split-Path -Parent $full
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $tmp="$full.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
        Move-Item -LiteralPath $tmp -Destination $full -Force
    }finally{
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}
    }
}

function ConvertFrom-AidosTailscaleStatusJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    if([string]::IsNullOrWhiteSpace($Json)){throw 'Tailscale status JSON is empty.'}
    try{$status=$Json|ConvertFrom-Json -Depth 100}catch{throw "Tailscale status JSON is invalid: $($_.Exception.Message)"}
    if(-not$status.PSObject.Properties['Self'] -or $null-eq$status.Self){throw 'Tailscale status JSON has no Self record.'}
    if(-not$status.Self.PSObject.Properties['DNSName']){throw 'Tailscale status JSON has no Self.DNSName.'}
    $dnsName=[string]$status.Self.DNSName
    if([string]::IsNullOrWhiteSpace($dnsName)){throw 'Tailscale status JSON has no Self.DNSName.'}
    $dnsName=$dnsName.Trim().TrimEnd('.')
    if($dnsName-notmatch'^[A-Za-z0-9][A-Za-z0-9.-]*\.ts\.net$'){throw "Tailscale DNS name '$dnsName' is not a valid ts.net host."}
    [pscustomobject][ordered]@{
        dns_name=$dnsName.ToLowerInvariant()
        public_url=('https://'+$dnsName.ToLowerInvariant())
        backend_state=if($status.PSObject.Properties['BackendState']){[string]$status.BackendState}else{$null}
        tailscale_ips=if($status.Self.PSObject.Properties['TailscaleIPs']){@($status.Self.TailscaleIPs)}else{@()}
    }
}

function Get-AidosRepositoryHandoffFunnelArguments {
    [CmdletBinding()]
    param(
        [int]$LocalPort=47831,
        [ValidateSet(443,8443,10000)][int]$PublicPort=443,
        [switch]$Disable
    )
    if($LocalPort-lt1024-or$LocalPort-gt65535){throw 'Repository handoff gateway port must be between 1024 and 65535.'}
    $arguments=@('funnel','--yes',"--https=$PublicPort","http://127.0.0.1:$LocalPort")
    if($Disable){return @($arguments+@('off'))}
    @($arguments[0],'--bg')+$arguments[1..($arguments.Count-1)]
}

function Get-AidosRepositoryHandoffUrlPrefix {
    [CmdletBinding()]
    param([int]$Port=47831)
    if($Port-lt1024-or$Port-gt65535){throw 'Repository handoff gateway port must be between 1024 and 65535.'}
    "http://127.0.0.1:$Port/"
}

function Get-AidosRepositoryHandoffUrlAclArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AuthorizedUser,[int]$Port=47831,[switch]$Delete)
    $prefix=Get-AidosRepositoryHandoffUrlPrefix -Port $Port
    if($Delete){return @('http','delete','urlacl',"url=$prefix")}
    if([string]::IsNullOrWhiteSpace($AuthorizedUser)){throw 'URL ACL configuration requires AuthorizedUser.'}
    @('http','add','urlacl',"url=$prefix","user=$AuthorizedUser",'listen=yes','delegate=no')
}

function Resolve-AidosRepositoryHandoffPublicUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PublicUrl,
        [ValidateSet(443,8443,10000)][int]$PublicPort=443
    )
    $uri=$null
    if(-not[Uri]::TryCreate($PublicUrl.Trim(),[UriKind]::Absolute,[ref]$uri) -or -not[string]::Equals($uri.Scheme,'https',[StringComparison]::OrdinalIgnoreCase)){throw 'Repository handoff host PublicUrl must be an absolute HTTPS URL.'}
    if(-not[string]::IsNullOrWhiteSpace($uri.UserInfo) -or -not[string]::IsNullOrWhiteSpace($uri.Query) -or -not[string]::IsNullOrWhiteSpace($uri.Fragment)){throw 'Repository handoff host PublicUrl may not contain user information, a query, or a fragment.'}
    if($uri.AbsolutePath -notin @('','/')){throw 'Repository handoff host PublicUrl must point to the HTTPS origin root.'}
    $builder=[UriBuilder]::new($uri)
    $builder.Path=''
    $builder.Query=''
    $builder.Fragment=''
    $builder.Port=if($PublicPort-eq443){-1}else{$PublicPort}
    $builder.Uri.AbsoluteUri.TrimEnd('/')
}

function New-AidosRepositoryHandoffHostConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntryPoint,
        [Parameter(Mandatory)][string]$AidosRoot,
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$BuilderRoot,
        [Parameter(Mandatory)][string]$ContractsRoot,
        [Parameter(Mandatory)][string]$HostStateRoot,
        [Parameter(Mandatory)][string]$BridgeStateRoot,
        [Parameter(Mandatory)][string]$GatewayStateRoot,
        [Parameter(Mandatory)][string]$AuthorizedUser,
        [Parameter(Mandatory)][string]$ProcessName,
        [Parameter(Mandatory)][string]$PublicUrl,
        [Parameter(Mandatory)][AllowEmptyString()][string]$TailscalePath,
        [int]$GatewayPort=47831,
        [ValidateSet(443,8443,10000)][int]$PublicPort=443,
        [int]$RecoveryIntervalSeconds=30,
        [int]$MaxProjectsPerTick=6,
        [bool]$Push=$true
    )
    if([string]::IsNullOrWhiteSpace($AuthorizedUser)){throw 'Repository handoff host requires AuthorizedUser.'}
    if([string]::IsNullOrWhiteSpace($ProcessName)){throw 'Repository handoff host requires ProcessName.'}
    [pscustomobject][ordered]@{
        schema_version='0.2'
        entry_point=[IO.Path]::GetFullPath($EntryPoint)
        aidos_root=[IO.Path]::GetFullPath($AidosRoot)
        registry_root=[IO.Path]::GetFullPath($RegistryRoot)
        builder_root=[IO.Path]::GetFullPath($BuilderRoot)
        contracts_root=[IO.Path]::GetFullPath($ContractsRoot)
        host_state_root=[IO.Path]::GetFullPath($HostStateRoot)
        bridge_state_root=[IO.Path]::GetFullPath($BridgeStateRoot)
        gateway_state_root=[IO.Path]::GetFullPath($GatewayStateRoot)
        authorized_user=$AuthorizedUser
        process_name=$ProcessName
        public_url=Resolve-AidosRepositoryHandoffPublicUrl -PublicUrl $PublicUrl -PublicPort $PublicPort
        tailscale_path=if([string]::IsNullOrWhiteSpace($TailscalePath)){$null}else{[IO.Path]::GetFullPath($TailscalePath)}
        gateway_port=$GatewayPort
        public_port=$PublicPort
        recovery_interval_seconds=$RecoveryIntervalSeconds
        max_projects_per_tick=$MaxProjectsPerTick
        push=$Push
        openapi_path=(Get-AidosRepositoryHandoffHostPath -StateRoot $HostStateRoot -Kind openapi)
        instructions_path=(Get-AidosRepositoryHandoffHostPath -StateRoot $HostStateRoot -Kind instructions)
        configured_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
}

function New-AidosRepositoryHandoffLauncherText {
    [CmdletBinding()]
    param()
    @'
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSCommandPath
$configPath=Join-Path $root 'CONFIG.json'
$statusPath=Join-Path $root 'STATUS.json'
$errorPath=Join-Path $root 'STARTUP_ERROR.log'
try {
    Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
    $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    if(-not(Test-Path -LiteralPath ([string]$config.entry_point) -PathType Leaf)){throw "Repository handoff host entrypoint is unavailable: $($config.entry_point)"}
    & ([string]$config.entry_point) -Command Start -StateRoot $root
    exit 0
} catch {
    $detail=$_.Exception.ToString()
    $detail|Set-Content -LiteralPath $errorPath -Encoding utf8NoBOM
    [ordered]@{schema_version='0.1';status='STARTUP_ERROR';observed_at=[DateTimeOffset]::UtcNow.ToString('o');reason=$_.Exception.Message;detail=$detail}|ConvertTo-Json -Depth 50|Set-Content -LiteralPath $statusPath -Encoding utf8NoBOM
    exit 1
}
'@
}

function New-AidosRepositoryHandoffVbsText {
    [CmdletBinding()]
    param()
    @'
Option Explicit
Dim shell, fso, root, engineFile, engine, launcher, command, rc
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
Set engineFile = fso.OpenTextFile(root & "\ENGINE.txt", 1, False)
engine = Trim(engineFile.ReadAll)
engineFile.Close
launcher = root & "\LAUNCHER.ps1"
command = Chr(34) & engine & Chr(34) & " -NoLogo -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & launcher & Chr(34)
rc = shell.Run(command, 0, True)
WScript.Quit rc
'@
}

function New-AidosRepositoryThinkerGptInstructions {
    [CmdletBinding()]
    param()
    @'
# AIDOS Repository Thinker

You are the reasoning/review actor and the Human Input presentation/return channel for AIDOS. AIDOS Core owns lifecycle authority. Repository/gateway state is authoritative. Chat history may only carry candidate routing identifiers; it is never project truth.

## Marker normalization

Before validating a bridge marker in the newest user message, normalize only ChatGPT's Markdown escaping of underscores by replacing every literal `\_` sequence with `_`. Do not perform any other normalization, decoding, trimming, case folding, or reconstruction.

## Thinker assignment protocol

When the normalized newest user message begins with the exact marker `AIDOS_HANDOFF_READY` and contains `project_id`, `handoff_id`, `handoff_sha256`, and `repository`:

1. Extract those marker fields from that normalized newest user message only.
2. Call `getAidosProjectHandoff` with the exact marker project_id.
3. Stop without improvising unless response status is `READY`, metadata kind is `ASSIGNMENT`, from_actor is `CORE`, to_actor is `THINKER`, project_id and handoff_id match exactly, and handoff_sha256 matches exactly.
4. Treat returned payload, handoff body, binding and source_refs as the complete assignment boundary.
5. Call `getAidosAuthorizedSource` only for exact source_refs listed by that handoff, first with startCharacter 0 and maxCharacters 65536. If complete is false, repeat the same exact source_ref with startCharacter equal to the exact next_start until complete is true. Require project_id, source_ref, full SHA-256, byte_length and character_length to remain identical; require chunk_start to equal the requested continuation; concatenate content in order. Stop on a missing, repeated or non-advancing continuation. Never construct or broaden paths. Do not use web search, chat memory, unbound files, or unstated project facts.
6. Perform the assigned reasoning/review and build exactly one required result envelope. Copy every identity, binding, hash and evidence reference exactly.
7. Call `submitAidosBoundResult` with exact project_id, expected_parent_handoff_id equal to the current assignment handoff_id, and the exact completed result envelope.
8. After `ACCEPTED` or `ALREADY_ACCEPTED`, reply only:
   `AIDOS_HANDOFF_RESULT_SUBMITTED::<project_id>::<handoff_id>`

## Human Input presentation protocol

When the normalized newest user message begins with the exact marker `AIDOS_HUMAN_INPUT_REQUIRED` and contains `project_id`, `request_id`, `request_sha256`, and `repository`:

1. Extract those marker fields from that normalized newest user message only.
2. Call `getAidosHumanInput` with the exact marker project_id.
3. Stop unless status is `READY`, project_id matches exactly, request_id matches exactly, and request_sha256 matches exactly.
4. Present the returned context_summary, question, and permitted options clearly to the user. Do not choose, infer, recommend, or submit an answer on the user's behalf.
5. End the presentation with exactly this transport sentinel on its own line:
   `AIDOS_HUMAN_INPUT_AWAITING::<project_id>::<request_id>::<request_sha256>`
6. Do not call `submitAidosHumanInputResponse` during the presentation turn.

## Human Input response protocol

A normal user message may be treated as a Human Input response only when the conversation contains exactly one most recent unresolved assistant sentinel `AIDOS_HUMAN_INPUT_AWAITING::<project_id>::<request_id>::<request_sha256>` and no later `AIDOS_HUMAN_INPUT_SUBMITTED` for that request.

For such a user message:

1. Treat the sentinel fields only as candidate routing identifiers. Call `getAidosHumanInput` again with that exact project_id before interpreting the response.
2. Stop unless the authoritative response is `READY` and its project_id, request_id and request_sha256 match the sentinel exactly.
3. Interpret only the newest user message as the candidate human answer.
4. If the request has options, submit only when the user's answer unambiguously identifies exactly one permitted option. Use that exact option_id. If ambiguous, ask one concise clarification question, do not submit, and repeat the same `AIDOS_HUMAN_INPUT_AWAITING` sentinel.
5. If free text is appropriate, copy only the user's intended response text. Never invent text.
6. Call `submitAidosHumanInputResponse` with exact project_id, exact request_id, exact request_sha256, and only the selected_option_id and/or text supplied or unambiguously selected by the user.
7. After `ACCEPTED` or `ALREADY_ACCEPTED`, reply only:
   `AIDOS_HUMAN_INPUT_SUBMITTED::<project_id>::<request_id>`

## No other action condition

If neither a current bridge marker nor an unresolved Human Input sentinel authorizes the newest user message, do not call an AIDOS action.

## Fail closed

On any mismatch, stale hash, missing request/source, action error, ambiguous human answer, unsupported result type, or authority problem, do not submit a guessed result/response and do not start another actor. For transport failures, reply only:
`AIDOS_HANDOFF_BLOCKED::<concise_reason>`

## Prohibitions

- Never put Thinker work product or result JSON in chat.
- Never answer a Human Input request on behalf of the user.
- Never directly instruct, activate, or schedule Codex, Worker, Human, or another Thinker.
- Never mutate project state except through the configured result/Human Input response actions.
- Never infer the next actor after submission. AIDOS Core validates durable state and selects the next lifecycle step.
- Never treat an earlier handoff, request body copied into chat, or prior conversation as current authority; re-fetch before every submission.
'@
}

function Sync-AidosRepositoryHandoffBridgeHostConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration)
    $path=Join-Path ([string]$Configuration.bridge_state_root) 'CONFIG.json'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject][ordered]@{status='BRIDGE_CONFIG_NOT_FOUND';path=$path}}
    $existing=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    $updated=[ordered]@{}
    foreach($property in $existing.PSObject.Properties){$updated[$property.Name]=$property.Value}
    $updated.schema_version='0.4'
    $updated.process_name=[string]$Configuration.process_name
    $updated.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    Write-AidosRepositoryHandoffInstallationJsonAtomic -Path $path -Value $updated
    [pscustomobject][ordered]@{status='SYNCHRONIZED';path=$path;process_name=[string]$Configuration.process_name}
}

function Write-AidosRepositoryHandoffHostFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$PowerShellPath
    )
    $root=[IO.Path]::GetFullPath([string]$Configuration.host_state_root)
    if(-not(Test-Path -LiteralPath $root -PathType Container)){New-Item -ItemType Directory -Path $root -Force|Out-Null}
    $configPath=Get-AidosRepositoryHandoffHostPath -StateRoot $root -Kind config
    $launcherPath=Get-AidosRepositoryHandoffHostPath -StateRoot $root -Kind launcher
    $vbsPath=Get-AidosRepositoryHandoffHostPath -StateRoot $root -Kind vbs
    $enginePath=Get-AidosRepositoryHandoffHostPath -StateRoot $root -Kind engine
    $instructionsPath=Get-AidosRepositoryHandoffHostPath -StateRoot $root -Kind instructions
    Write-AidosRepositoryHandoffInstallationJsonAtomic -Path $configPath -Value $Configuration
    New-AidosRepositoryHandoffLauncherText|Set-Content -LiteralPath $launcherPath -Encoding utf8NoBOM
    New-AidosRepositoryHandoffVbsText|Set-Content -LiteralPath $vbsPath -Encoding ascii
    Set-Content -LiteralPath $enginePath -Value ([IO.Path]::GetFullPath($PowerShellPath)) -Encoding utf8NoBOM -NoNewline
    New-AidosRepositoryThinkerGptInstructions|Set-Content -LiteralPath $instructionsPath -Encoding utf8NoBOM
    $bridgeConfiguration=Sync-AidosRepositoryHandoffBridgeHostConfiguration -Configuration $Configuration
    [pscustomobject][ordered]@{
        status='WRITTEN'
        config_path=$configPath
        launcher_path=$launcherPath
        vbs_path=$vbsPath
        engine_path=$enginePath
        instructions_path=$instructionsPath
        bridge_configuration=$bridgeConfiguration
    }
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffHostDefaultStateRoot,Get-AidosRepositoryHandoffHostTaskName,Get-AidosRepositoryHandoffLegacyTaskName,Get-AidosRepositoryHandoffHostPath,Write-AidosRepositoryHandoffInstallationJsonAtomic,ConvertFrom-AidosTailscaleStatusJson,Get-AidosRepositoryHandoffFunnelArguments,Get-AidosRepositoryHandoffUrlPrefix,Get-AidosRepositoryHandoffUrlAclArguments,Resolve-AidosRepositoryHandoffPublicUrl,New-AidosRepositoryHandoffHostConfiguration,New-AidosRepositoryHandoffLauncherText,New-AidosRepositoryHandoffVbsText,New-AidosRepositoryThinkerGptInstructions,Sync-AidosRepositoryHandoffBridgeHostConfiguration,Write-AidosRepositoryHandoffHostFiles
