[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bootstrapPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'
$bootstrap=Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8

$passed=0
function Assert-Routing([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

Assert-Routing ($bootstrap.Contains("`$runtimeReviewHandoffName='AidosRepositoryReviewHandoff.runtime.'")) 'bootstrap materializes runtime review handoff'
Assert-Routing ($bootstrap.Contains("if(Test-Path -LiteralPath `$runtimeReviewHandoff){Remove-Item -LiteralPath `$runtimeReviewHandoff -Force}")) 'runtime review module is cleaned up'

$gatewayMatch=[regex]::Match($bootstrap,'(?s)\$gatewayReplacements=\[ordered\]@\{(?<body>.*?)\r?\n\}')
Assert-Routing $gatewayMatch.Success 'gateway replacement map is present'
$gatewayBody=$gatewayMatch.Groups['body'].Value
Assert-Routing ($gatewayBody.Contains("'AidosRepositoryHandoff.psm1'" ) -and $gatewayBody.Contains('$runtimeHandoffName')) 'gateway routes direct handoff dependency through runtime handoff'
Assert-Routing ($gatewayBody.Contains("'AidosRepositoryActorHandoff.psm1'") -and $gatewayBody.Contains('$runtimeActorHandoffName')) 'gateway routes actor dependency through runtime actor handoff'
Assert-Routing ($gatewayBody.Contains("'AidosRepositoryReviewHandoff.psm1'") -and $gatewayBody.Contains('$runtimeReviewHandoffName')) 'gateway routes review dependency through runtime review handoff'

$bridgeMatch=[regex]::Match($bootstrap,'(?s)\$bridgeReplacements=\[ordered\]@\{(?<body>.*?)\r?\n\}')
Assert-Routing $bridgeMatch.Success 'bridge replacement map is present'
$bridgeBody=$bridgeMatch.Groups['body'].Value
Assert-Routing ($bridgeBody.Contains("'AidosRepositoryReviewHandoff.psm1'") -and $bridgeBody.Contains('$runtimeReviewHandoffName')) 'bridge routes review dependency through runtime review handoff'

$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($bootstrapPath,[ref]$tokens,[ref]$errors)
Assert-Routing (@($errors).Count-eq0) ('bootstrap parses: '+(@($errors|ForEach-Object Message)-join'; '))

Write-Output "PASS: $passed nested repository handoff runtime routing assertions"
