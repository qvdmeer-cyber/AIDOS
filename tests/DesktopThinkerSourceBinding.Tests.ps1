[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Source([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$base=Join-Path ([IO.Path]::GetTempPath()) ('aidos-thinker-source-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $base '.aidos/documentation') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base '.aidos/evidence') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base '.aidos/profile') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base '.aidos/definitions/DEF-A/v1/decisions') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base '.aidos/definitions/DEF-B/v1') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base '.aidos/human-input') -Force|Out-Null
    New-Item -ItemType Directory -Path (Join-Path $base 'docs') -Force|Out-Null
    Set-Content -LiteralPath (Join-Path $base '.aidos/PROJECT.json') -Value '{"project_id":"SOURCE-TEST"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/documentation/PROJECT_BASELINE.json') -Value '{"project_id":"SOURCE-TEST"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/documentation/PROJECT_ACCESS.json') -Value '{"project_id":"SOURCE-TEST"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/evidence/EVIDENCE_INVENTORY.json') -Value '{"project_id":"SOURCE-TEST"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/profile/PROJECT_APPLICABILITY.json') -Value '{"project_id":"SOURCE-TEST"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base 'docs/PRODUCT.md') -Value '# Product' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/definitions/DEF-A/v1/APPLICABILITY.json') -Value '{"definition_id":"DEF-A","definition_version":1}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/definitions/DEF-A/v1/PROGRESS.json') -Value '{"definition_id":"DEF-A","definition_version":1}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/definitions/DEF-A/v1/decisions/decision-a.json') -Value '{"decision_id":"decision-a"}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/definitions/DEF-B/v1/APPLICABILITY.json') -Value '{"definition_id":"DEF-B","definition_version":1}' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $base '.aidos/definitions/DEF-B/v1/PROGRESS.json') -Value '{"definition_id":"DEF-B","definition_version":1}' -Encoding utf8NoBOM
    [ordered]@{request_id='hir-a';binding=[ordered]@{definition_id='DEF-A';definition_version=1}}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $base '.aidos/human-input/hir-a.json') -Encoding utf8NoBOM
    [ordered]@{request_id='hir-b';binding=[ordered]@{definition_id='DEF-B';definition_version=1}}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $base '.aidos/human-input/hir-b.json') -Encoding utf8NoBOM

    $bound=[pscustomobject]@{sha256=('a'*64);assignment=[pscustomobject][ordered]@{assignment_id='assignment-a';action='RESUME_DEFINITION';binding=[pscustomobject][ordered]@{definition_id='DEF-A';definition_version=1}}}
    $documents=@(Get-AidosDesktopThinkerAuthorizedDocuments -ProjectRoot $base -BoundAssignment $bound)
    $paths=@($documents|ForEach-Object {[string]$_.path})
    Assert-Source ($paths -contains '.aidos/profile/PROJECT_APPLICABILITY.json') 'bound Definition source pack includes Project Applicability'
    Assert-Source ($paths -contains '.aidos/definitions/DEF-A/v1/APPLICABILITY.json') 'bound Definition Applicability is included'
    Assert-Source ($paths -contains '.aidos/definitions/DEF-A/v1/PROGRESS.json') 'bound Definition Progress is included'
    Assert-Source ($paths -contains '.aidos/definitions/DEF-A/v1/decisions/decision-a.json') 'bound Definition decisions are included'
    Assert-Source ($paths -contains '.aidos/human-input/hir-a.json') 'Human Input from exact Definition binding is included'
    Assert-Source ($paths -notcontains '.aidos/definitions/DEF-B/v1/APPLICABILITY.json') 'foreign Definition lineage is excluded'
    Assert-Source ($paths -notcontains '.aidos/definitions/DEF-B/v1/PROGRESS.json') 'foreign Definition progress is excluded'
    Assert-Source ($paths -notcontains '.aidos/human-input/hir-b.json') 'foreign Definition Human Input is excluded'

    $prompt=New-AidosDesktopThinkerPrompt -BoundAssignment $bound -Documents $documents
    Assert-Source ($prompt -match 'applicability_resolutions' -and $prompt -match 'surface_resolutions') 'Definition prompt uses the current Definition Thinker output contract'
} finally {
    if(Test-Path -LiteralPath $base){Remove-Item -LiteralPath $base -Recurse -Force}
}
Write-Output "PASS: $passed Desktop Thinker source-binding assertions"
