[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffInstallation.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Install([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-InstallThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-handoff-install-'+[guid]::NewGuid().ToString('N'))
try{
    Assert-Install ((Get-AidosRepositoryHandoffHostTaskName)-eq'AIDOS Repository Handoff Host') 'new scheduled task has a stable name'
    Assert-Install ((Get-AidosRepositoryHandoffLegacyTaskName)-eq'AIDOS Persistent Local Desktop Agent') 'installer recognizes the legacy transport task'

    $status=ConvertFrom-AidosTailscaleStatusJson -Json '{"BackendState":"Running","Self":{"DNSName":"aidos.tail1234.ts.net.","TailscaleIPs":["100.1.2.3"]}}'
    Assert-Install ([string]$status.dns_name-eq'aidos.tail1234.ts.net') 'Tailscale DNS name is normalized'
    Assert-Install ([string]$status.public_url-eq'https://aidos.tail1234.ts.net') 'Tailscale public URL is derived deterministically'
    Assert-InstallThrows {ConvertFrom-AidosTailscaleStatusJson -Json '{}'} 'no Self record' 'missing Tailscale Self record is rejected'
    Assert-InstallThrows {ConvertFrom-AidosTailscaleStatusJson -Json '{"Self":{"DNSName":"example.com"}}'} 'not a valid ts.net' 'non-tailnet DNS name is rejected'

    $enable=@(Get-AidosRepositoryHandoffFunnelArguments -LocalPort 47831 -PublicPort 443)
    Assert-Install (($enable-join' ')-eq'funnel --bg --yes --https=443 http://127.0.0.1:47831') 'Funnel enable command is exact and backgrounded'
    $disable=@(Get-AidosRepositoryHandoffFunnelArguments -LocalPort 47831 -PublicPort 443 -Disable)
    Assert-Install (($disable-join' ')-eq'funnel --yes --https=443 http://127.0.0.1:47831 off') 'Funnel disable command removes only the exact endpoint'
    Assert-InstallThrows {Get-AidosRepositoryHandoffFunnelArguments -LocalPort 80} 'between 1024 and 65535' 'privileged local gateway port is rejected'

    Assert-Install ((Get-AidosRepositoryHandoffUrlPrefix -Port 47831)-eq'http://127.0.0.1:47831/') 'HttpListener prefix is loopback-only'
    $acl=@(Get-AidosRepositoryHandoffUrlAclArguments -AuthorizedUser 'AIDOS\qvdm' -Port 47831)
    Assert-Install (($acl-join' ')-eq'http add urlacl url=http://127.0.0.1:47831/ user=AIDOS\qvdm listen=yes delegate=no') 'URL ACL grants only the configured Windows identity'

    foreach($dir in @('aidos','registry','builder','contracts','host','bridge','gateway')){New-Item -ItemType Directory -Path (Join-Path $temp $dir) -Force|Out-Null}
    $entryPoint=Join-Path $temp 'entry.ps1';Set-Content -LiteralPath $entryPoint -Value '# entry' -Encoding utf8NoBOM
    $tailscale=Join-Path $temp 'tailscale.exe';Set-Content -LiteralPath $tailscale -Value 'fixture' -Encoding ascii
    $config=New-AidosRepositoryHandoffHostConfiguration -EntryPoint $entryPoint -AidosRoot (Join-Path $temp 'aidos') -RegistryRoot (Join-Path $temp 'registry') -BuilderRoot (Join-Path $temp 'builder') -ContractsRoot (Join-Path $temp 'contracts') -HostStateRoot (Join-Path $temp 'host') -BridgeStateRoot (Join-Path $temp 'bridge') -GatewayStateRoot (Join-Path $temp 'gateway') -AuthorizedUser 'AIDOS\qvdm' -ProcessName 'ChatGPT Classic' -PublicUrl 'https://aidos.tail1234.ts.net/' -TailscalePath $tailscale
    Assert-Install ([string]$config.public_url-eq'https://aidos.tail1234.ts.net') 'host configuration normalizes public URL'
    Assert-Install ([string]$config.schema_version-eq'0.1') 'host configuration schema is explicit'
    Assert-Install (-not($config.PSObject.Properties.Name-contains'api_key')) 'host configuration never embeds the gateway secret'
    Assert-Install ([string]$config.openapi_path-eq(Get-AidosRepositoryHandoffHostPath -StateRoot (Join-Path $temp 'host') -Kind openapi)) 'host configuration binds generated OpenAPI path'

    $launcher=New-AidosRepositoryHandoffLauncherText
    Assert-Install ($launcher.Contains('-Command Start -StateRoot $root')) 'stable launcher starts the host from local configuration'
    Assert-Install (-not$launcher.Contains('api_key')) 'stable launcher contains no API key'
    $vbs=New-AidosRepositoryHandoffVbsText
    Assert-Install ($vbs.Contains('LAUNCHER.ps1') -and $vbs.Contains('shell.Run(command, 0, True)')) 'VBS bootstrap starts PowerShell hidden and waits'

    $instructions=New-AidosRepositoryThinkerGptInstructions
    Assert-Install ($instructions.Contains('AIDOS_HANDOFF_READY')) 'custom GPT instructions require the bridge marker'
    Assert-Install ($instructions.Contains('getAidosProjectHandoff') -and $instructions.Contains('submitAidosBoundResult')) 'custom GPT instructions bind read and submit actions'
    Assert-Install ($instructions.Contains('Never put the work product or result JSON in the chat')) 'custom GPT instructions keep content transport out of chat'
    Assert-Install ($instructions.Contains('AIDOS Core validates the result and selects the next actor')) 'custom GPT instructions preserve Core scheduling authority'

    $engine=if([OperatingSystem]::IsWindows()){Join-Path $PSHOME 'pwsh.exe'}else{Join-Path $PSHOME 'pwsh'}
    $written=Write-AidosRepositoryHandoffHostFiles -Configuration $config -PowerShellPath $engine
    Assert-Install ([string]$written.status-eq'WRITTEN') 'host-owned installation files are written'
    foreach($path in @($written.config_path,$written.launcher_path,$written.vbs_path,$written.engine_path,$written.instructions_path)){Assert-Install (Test-Path -LiteralPath $path -PathType Leaf) "host file exists: $path"}
    $persisted=Get-Content -LiteralPath $written.config_path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50
    Assert-Install (-not($persisted.PSObject.Properties.Name-contains'api_key')) 'persisted host configuration contains no gateway secret'

    Write-Output "PASS: $passed repository handoff installation assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
