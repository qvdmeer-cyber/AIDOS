[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryThinkerBinding.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Retry([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-RetryThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$iso='2026-08-19T19:56:48.0000000+00:00'
$parsed=ConvertTo-AidosRepositoryThinkerRetryAfter -Value $iso
Assert-Retry ($parsed -is [DateTimeOffset]) 'ISO retry timestamp returns DateTimeOffset'
Assert-Retry ($parsed.ToUniversalTime().ToString('o') -eq '2026-08-19T19:56:48.0000000+00:00') 'ISO retry timestamp preserves instant'

$dto=[DateTimeOffset]::Parse($iso,[Globalization.CultureInfo]::InvariantCulture)
$parsedDto=ConvertTo-AidosRepositoryThinkerRetryAfter -Value $dto
Assert-Retry ($parsedDto -eq $dto) 'DateTimeOffset input is accepted without string round-trip'

$dt=[DateTime]::SpecifyKind([DateTime]::ParseExact('2026-08-19 21:56:48','yyyy-MM-dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture),[DateTimeKind]::Local)
$parsedDt=ConvertTo-AidosRepositoryThinkerRetryAfter -Value $dt
Assert-Retry ($parsedDt -is [DateTimeOffset]) 'DateTime input is accepted without culture-dependent string conversion'

$legacy='08/19/2026 21:56:48'
$parsedLegacy=ConvertTo-AidosRepositoryThinkerRetryAfter -Value $legacy
Assert-Retry ($parsedLegacy.Year-eq2026 -and $parsedLegacy.Month-eq8 -and $parsedLegacy.Day-eq19) 'invariant legacy timestamp remains readable'

Assert-RetryThrows {ConvertTo-AidosRepositoryThinkerRetryAfter -Value 'not-a-time'} 'not a valid timestamp' 'invalid retry timestamp fails closed'
Write-Output "PASS: $passed Thinker retry timestamp assertions"
