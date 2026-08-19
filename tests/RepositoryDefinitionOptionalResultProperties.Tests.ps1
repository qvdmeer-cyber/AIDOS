[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$consumer=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosDefinitionResultConsumer.psm1') -Raw -Encoding UTF8

$script:passed=0
function Assert-Optional([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

Assert-Optional ($consumer.Contains("`$resolution.PSObject.Properties['auto_decision']")) 'auto_decision is read through property metadata so absence is safe under StrictMode'
Assert-Optional ($consumer.Contains("if(`$null-eq`$autoDecisionProperty){`$null}else{`$autoDecisionProperty.Value}")) 'missing auto_decision resolves to null'
Assert-Optional ($consumer.Contains("`$resolution.PSObject.Properties['open_question_count']")) 'open_question_count is read through property metadata so absence is safe under StrictMode'
Assert-Optional ($consumer.Contains("if(`$null-eq`$openQuestionProperty){0}else{[int]`$openQuestionProperty.Value}")) 'missing open_question_count defaults deterministically to zero'
Assert-Optional (-not $consumer.Contains('$null-ne$resolution.auto_decision')) 'non-auto authorities no longer dereference missing auto_decision directly'
Assert-Optional (-not $consumer.Contains('$null-eq$resolution.auto_decision')) 'AUTO_DECIDABLE validation no longer dereferences missing auto_decision directly'
Assert-Optional (-not $consumer.Contains('[int]$resolution.open_question_count')) 'surface persistence no longer dereferences missing open_question_count directly'

Write-Output "PASS: $passed optional Definition result property assertions"
