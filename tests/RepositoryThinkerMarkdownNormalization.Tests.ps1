[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoffInstallation.psm1') -Force -DisableNameChecking

$instructions=New-AidosRepositoryThinkerGptInstructions
if(-not$instructions.Contains("normalize only ChatGPT's Markdown escaping of underscores")){throw 'ASSERTION FAILED: Thinker instructions must normalize only ChatGPT underscore escaping.'}
if(-not$instructions.Contains('replacing every literal `\_` sequence with `_`')){throw 'ASSERTION FAILED: Thinker instructions must define exact underscore normalization.'}
if(-not$instructions.Contains('Do not perform any other normalization, decoding, trimming, case folding, or reconstruction.')){throw 'ASSERTION FAILED: Thinker normalization must remain narrowly bounded.'}
if(-not$instructions.Contains('exact marker `AIDOS_HANDOFF_READY`')){throw 'ASSERTION FAILED: normalized Thinker marker must still require the exact AIDOS literal.'}
if(-not$instructions.Contains('Extract those marker fields from that normalized newest user message only.')){throw 'ASSERTION FAILED: Thinker marker fields must remain bound to the newest normalized message.'}
if(-not$instructions.Contains('exact marker `AIDOS_HUMAN_INPUT_REQUIRED`')){throw 'ASSERTION FAILED: Human Input marker uses the same narrowly bounded normalization boundary.'}

Write-Output 'PASS: Thinker and Human Input markdown marker normalization instructions'
