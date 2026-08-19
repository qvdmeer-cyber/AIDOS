[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDefinitionResultConsumer.psm1') -Force -DisableNameChecking

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-definition-source-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp '.aidos'),(Join-Path $temp '.aidos/definitions/DEF-TEST/v1') -Force|Out-Null
try {
    '{"project_id":"P1","project_mode":"NEW_PROJECT"}'|Set-Content -LiteralPath (Join-Path $temp '.aidos/PROJECT.json') -Encoding utf8NoBOM
    '{"state":"WAITING_DEFINITION"}'|Set-Content -LiteralPath (Join-Path $temp '.aidos/STATE.json') -Encoding utf8NoBOM

    $resolved=Resolve-AidosDefinitionActorSourceRef -ProjectRoot $temp -AidosRoot $root -SourceRef '.aidos/PROJECT.json' -DefinitionId 'DEF-TEST' -DefinitionVersion 1
    if([string]$resolved.ref-ne'.aidos/PROJECT.json' -or [string]$resolved.scope-ne'PROJECT'){throw 'ASSERTION FAILED: canonical project identity must be accepted as a Definition source ref.'}

    $rejected=$false
    try { Resolve-AidosDefinitionActorSourceRef -ProjectRoot $temp -AidosRoot $root -SourceRef '.aidos/STATE.json' -DefinitionId 'DEF-TEST' -DefinitionVersion 1|Out-Null } catch { $rejected=$_.Exception.Message -like 'Definition source_ref is outside authorized project source set:*' }
    if(-not$rejected){throw 'ASSERTION FAILED: arbitrary .aidos runtime state must remain outside the Definition source allowlist.'}

    Write-Output 'PASS: Definition project identity source allowlist'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
