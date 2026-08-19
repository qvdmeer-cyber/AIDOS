[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'bridge/AidosRepositoryThinkerBinding.psm1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8

if($text.Contains('[System.Windows.Automation.LegacyIAccessiblePattern]')){throw 'ASSERTION FAILED: LegacyIAccessiblePattern remains a hard type dependency.'}
if(-not$text.Contains("'System.Windows.Automation.LegacyIAccessiblePattern' -as [type]")){throw 'ASSERTION FAILED: optional legacy UIA type lookup is missing.'}
if(-not$text.Contains('Get-AidosRepositoryThinkerLegacyAccessiblePattern')){throw 'ASSERTION FAILED: optional legacy UIA resolver is missing.'}
if(-not$text.Contains('if($null-ne$legacyPattern)')){throw 'ASSERTION FAILED: legacy UIA fallback is not guarded.'}

$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw ('ASSERTION FAILED: Thinker binding module parses: '+(@($errors|ForEach-Object Message)-join'; '))}

Write-Output 'PASS: legacy UIA pattern is optional in Thinker binding'
