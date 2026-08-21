[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDefinitionResultConsumer.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Compat([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-CompatThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-definition-applicability-compat-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp '.aidos') -Force|Out-Null
try{
    [ordered]@{schema_version='0.1';project_id='PROJECT-1';project_mode='NEW_PROJECT'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $temp '.aidos/PROJECT.json') -Encoding utf8NoBOM

    Assert-Compat ((Resolve-AidosDefinitionThinkerApplicabilityState -ProjectRoot $temp -AssignmentAction START_DEFINITION -DefinitionState AFFECTED)-eq'AFFECTED') 'canonical AFFECTED remains unchanged'
    Assert-Compat ((Resolve-AidosDefinitionThinkerApplicabilityState -ProjectRoot $temp -AssignmentAction START_DEFINITION -DefinitionState NOT_AFFECTED)-eq'NOT_AFFECTED') 'canonical NOT_AFFECTED remains unchanged'
    Assert-Compat ((Resolve-AidosDefinitionThinkerApplicabilityState -ProjectRoot $temp -AssignmentAction START_DEFINITION -DefinitionState APPLICABLE)-eq'AFFECTED') 'legacy NEW_PROJECT APPLICABLE maps to AFFECTED'
    Assert-Compat ((Resolve-AidosDefinitionThinkerApplicabilityState -ProjectRoot $temp -AssignmentAction START_DEFINITION -DefinitionState NOT_APPLICABLE)-eq'NOT_AFFECTED') 'legacy NEW_PROJECT NOT_APPLICABLE maps to NOT_AFFECTED'

    Assert-Compat ((Resolve-AidosDefinitionThinkerApplicabilityState -ProjectRoot $temp -AssignmentAction RESUME_DEFINITION -DefinitionState APPLICABLE)-eq'AFFECTED') 'legacy NEW_PROJECT APPLICABLE maps to AFFECTED on Definition resume'
    [ordered]@{schema_version='0.1';project_id='PROJECT-1';project_mode='EXISTING_PROJECT'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $temp '.aidos/PROJECT.json') -Encoding utf8NoBOM
    Assert-CompatThrows {Resolve-AidosDefinitionThinkerApplicabilityState -ProjectRoot $temp -AssignmentAction RESUME_DEFINITION -DefinitionState APPLICABLE} 'only compatible with NEW_PROJECT Definition assignments' 'legacy state is rejected for existing projects'
    Assert-CompatThrows {Resolve-AidosDefinitionThinkerApplicabilityState -ProjectRoot $temp -AssignmentAction START_DEFINITION -DefinitionState UNKNOWN} 'Unsupported Definition applicability state' 'unknown state remains fail closed'

    Write-Output "PASS: $passed Definition applicability compatibility assertions"
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
