[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Replace-Exact {
    param([string]$Path,[string]$Old,[string]$New)
    $text=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $count=([regex]::Matches($text,[regex]::Escape($Old))).Count
    if($count-ne1){throw "$Path expected exactly one source match; found $count"}
    Set-Content -LiteralPath $Path -Value ($text.Replace($Old,$New)) -Encoding utf8NoBOM -NoNewline
}

$hostPath='bridge/Invoke-AidosRepositoryHandoffHost.ps1'
$old=@'
    'Stop' {
        $config=Read-AidosRepositoryHostConfiguration
        $stopPath=Get-AidosRepositoryHandoffHostPath -StateRoot $StateRoot -Kind stop
        if(-not(Test-Path -LiteralPath $StateRoot -PathType Container)){New-Item -ItemType Directory -Path $StateRoot -Force|Out-Null}
        Set-Content -LiteralPath $stopPath -Value ([DateTimeOffset]::UtcNow.ToString('o')) -Encoding utf8NoBOM
        Stop-AidosRepositoryHandoffBridge -StateRoot ([string]$config.bridge_state_root)|Out-Null
        Stop-AidosRepositoryHandoffGateway -StateRoot ([string]$config.gateway_state_root)|Out-Null
        [pscustomobject][ordered]@{status='STOP_REQUESTED';task=(Get-AidosRepositoryHostTaskStatus);state_root=$StateRoot}|ConvertTo-Json -Depth 50
    }
'@
$new=@'
    'Stop' {
        $stop=Stop-AidosRepositoryHostTask
        [pscustomobject][ordered]@{status=if($stop -and $stop.PSObject.Properties['status']){[string]$stop.status}else{'STOPPED'};stop=$stop;task=(Get-AidosRepositoryHostTaskStatus);state_root=$StateRoot}|ConvertTo-Json -Depth 50
    }
'@
Replace-Exact -Path $hostPath -Old $old.TrimEnd() -New $new.TrimEnd()

$testPath='tests/RepositoryHandoffBootstrap.Tests.ps1'
$test=Get-Content -LiteralPath $testPath -Raw -Encoding UTF8
$anchor="Assert-Bootstrap (`$runtimeHost.Contains(`$runtimeGatewayName)) 'runtime host imports restart-safe runtime gateway'"
$addition=@"
$anchor
Assert-Bootstrap (`$hostText.Contains('`$stop=Stop-AidosRepositoryHostTask')) 'Stop command delegates to the bounded canonical host-stop lifecycle'
Assert-Bootstrap (-not`$hostText.Contains("status='STOP_REQUESTED'")) 'Stop command no longer returns before host shutdown completes'
"@.TrimEnd()
if(-not$test.Contains($anchor)){throw 'Bootstrap regression anchor not found.'}
$test=$test.Replace($anchor,$addition)
Set-Content -LiteralPath $testPath -Value $test -Encoding utf8NoBOM -NoNewline

foreach($path in @($hostPath,$testPath)){
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "${path}: $($errors.Message -join '; ')"}
}

./tests/RepositoryHandoffBootstrap.Tests.ps1
./tests/HostAgentReload.Tests.ps1
