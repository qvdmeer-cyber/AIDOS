param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\\')
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "ProjectRoot does not exist: $root"
}

$excludedSegments = @(
    '\\.git\\','\\node_modules\\','\\bin\\','\\obj\\','\\dist\\','\\build\\',
    '\\.vs\\','\\coverage\\','\\packages\\','\\.aidos\\reviews\\'
)

$files = Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
    $p = $_.FullName
    -not ($excludedSegments | Where-Object { $p -match $_ })
}

function Relative([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    return $full.Substring($root.Length).TrimStart('\\').Replace('\\','/')
}

function MatchesAny([string]$Text, [string[]]$Patterns) {
    foreach ($pattern in $Patterns) {
        if ($Text -match $pattern) { return $true }
    }
    return $false
}

$rules = [ordered]@{
    identity = @('(^|/)(readme|project[_-]?snapshot|project[_-]?context)(\.|$)','(^|/)agents\.md$')
    product = @('product','requirements?','scope','roadmap','readme','project[_-]?(snapshot|context)')
    architecture = @('architect','design','(^|/)adr','decision[_-]?record','topology','system[_-]?overview')
    runtime = @('runtime','routing','hosting','reverse[_-]?proxy','iis','nginx','apache','docker','compose','web\.config','appsettings')
    data = @('database','schema','migration','storage','persistence','repository','\.sql$','db[_-]')
    interfaces = @('openapi','swagger','api','contract','integration','webhook','endpoint')
    development = @('development','getting[_-]?started','setup','toolchain','commands?','package\.json$','\.sln$','\.csproj$','makefile','build\.ps1$')
    validation = @('test','acceptance','validator','harness','smoke','spec')
    deployment = @('deploy','release','rollback','staging','production','workflow','pipeline','dockerfile')
    security_privacy = @('security','privacy','auth','credential','secret','permission','threat')
    operations = @('runbook','operations?','monitor','observab','logging','health','recovery','incident')
    decisions = @('(^|/)adr','decision','architecture[_-]?decision')
    constraints = @('constraint','limitation','legacy','technical[_-]?debt','known[_-]?(issue|problem)','compatib')
}

$relativeFiles = @($files | ForEach-Object { Relative $_.FullName })
$concerns = @()

foreach ($entry in $rules.GetEnumerator()) {
    $matches = @($relativeFiles | Where-Object { MatchesAny $_ $entry.Value } | Sort-Object -Unique)
    $concerns += [ordered]@{
        id = $entry.Key
        candidate_sources = $matches
        candidate_count = $matches.Count
    }
}

$head = $null
try {
    $head = (& git -C $root rev-parse HEAD 2>$null | Select-Object -First 1)
}
catch { $head = $null }

$result = [ordered]@{
    schema_version = '0.1'
    generated_at = [DateTimeOffset]::UtcNow.ToString('o')
    project_root = $root
    git_head = $head
    file_count_scanned = $relativeFiles.Count
    concerns = $concerns
    note = 'Candidate discovery only. AIDOS Project Documentation Agent must determine canonical sources, provenance, applicability, conflicts and gaps.'
}

$json = $result | ConvertTo-Json -Depth 10

if ($OutputPath) {
    $outputFull = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        [System.IO.Path]::GetFullPath($OutputPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
    }
    if (-not $outputFull.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputPath escapes ProjectRoot: $outputFull"
    }
    $parent = Split-Path -Parent $outputFull
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $outputFull -Value $json -Encoding UTF8
}

Write-Output $json
