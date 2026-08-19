[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffGateway.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-GatewaySecurity([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-GatewaySecurityThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-gateway-security-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp 'projects') -Force|Out-Null
try{
    foreach($safe in @('AIDOS','AIDOS-INTERFACE','PROJECT_1','project.v2')){
        Assert-GatewaySecurity ((Test-AidosRepositoryHandoffGatewayProjectId -ProjectId $safe)-eq$safe) "safe project_id is accepted: $safe"
    }
    foreach($unsafe in @('',' ','..','../outside','..\outside','/absolute','C:/outside','project/name','project\name','.hidden','-leading','project:name',('A'*129))){
        Assert-GatewaySecurityThrows {Test-AidosRepositoryHandoffGatewayProjectId -ProjectId $unsafe} 'project_id is invalid' "unsafe project_id is rejected: $unsafe"
    }

    $routed=Invoke-AidosRepositoryHandoffGatewayRequest -Method GET -Path '/v1/projects/..%2Foutside/handoff' -PresentedKey 'test-key' -ExpectedKey 'test-key' -RegistryRoot $temp -AidosRoot $root
    Assert-GatewaySecurity ([int]$routed.status_code-eq409) 'URL-decoded project path traversal is rejected before registry access'
    Assert-GatewaySecurity ([string]$routed.body.detail-match'project_id is invalid') 'project traversal rejection is explicit and fail-closed'

    Write-Output "PASS: $passed repository handoff gateway security assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
