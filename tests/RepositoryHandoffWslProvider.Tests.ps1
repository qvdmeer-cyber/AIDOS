[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$bootstrapPath=Join-Path $root 'bridge/Invoke-AidosRepositoryHandoffHostBootstrap.ps1'
$text=Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8

$pattern='(?s)\$handoffReplacement=@''\r?\n(?<body>function Test-AidosRepositoryPathItemIsLink .*?)\r?\n''@'
$match=[regex]::Match($text,$pattern)
if(-not$match.Success){throw 'Unable to extract runtime WSL link validator from bootstrap.'}
Invoke-Expression $match.Groups['body'].Value

function Assert-Result([bool]$Actual,[bool]$Expected,[string]$Case){
    if($Actual-ne$Expected){throw "ASSERTION FAILED: $Case expected $Expected, got $Actual"}
}
function Assert-Throws([scriptblock]$Action,[string]$Pattern,[string]$Case){
    $thrown=$false
    try{&$Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Case unexpected error: $($_.Exception.Message)"}}
    if(-not$thrown){throw "ASSERTION FAILED: $Case expected exception"}
}

$wslDirectory=[pscustomobject]@{
    Attributes=[IO.FileAttributes]::Directory
    LinkType='HardLink'
    LinkTarget=''
    Target=''
    FullName='\\wsl.localhost\Ubuntu\home\aidos\repos\AIDOS-interface\.aidos'
}
Assert-Result (Test-AidosRepositoryPathItemIsLink -Item $wslDirectory) $false 'WSL provider HardLink metadata without target is ordinary directory metadata'

$wslHardLinkWithTarget=[pscustomobject]@{
    Attributes=[IO.FileAttributes]::Directory
    LinkType='HardLink'
    LinkTarget='../other'
    Target='../other'
    FullName='\\wsl.localhost\Ubuntu\home\aidos\repos\AIDOS-interface\.aidos'
}
Assert-Result (Test-AidosRepositoryPathItemIsLink -Item $wslHardLinkWithTarget) $true 'WSL HardLink metadata with an actual target remains blocked'

$wslSymlink=[pscustomobject]@{
    Attributes=[IO.FileAttributes]::Directory
    LinkType='SymbolicLink'
    LinkTarget=''
    Target=''
    FullName='\\wsl.localhost\Ubuntu\home\aidos\repos\AIDOS-interface\.aidos'
}
Assert-Result (Test-AidosRepositoryPathItemIsLink -Item $wslSymlink) $true 'WSL explicit symbolic link type remains blocked even if provider omits target'

$windowsReparse=[pscustomobject]@{
    Attributes=([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)
    LinkType=''
    LinkTarget=''
    Target=''
    FullName='C:\repos\project\.aidos'
}
Assert-Result (Test-AidosRepositoryPathItemIsLink -Item $windowsReparse) $true 'normal Windows reparse point remains blocked'

$workerModulePath=Join-Path $root 'bridge/AidosRepositoryWorkerHandoff.psm1'
Import-Module $workerModulePath -Force -DisableNameChecking
$moduleRoot=Split-Path $workerModulePath -Parent
$canonicalPath=Join-Path $moduleRoot 'AidosRepositoryHandoff.psm1'
$fallback=Resolve-AidosRepositoryWorkerHandoffModulePath -ModuleRoot $moduleRoot -LoadedModules @()
if(-not[string]::Equals([IO.Path]::GetFullPath($fallback),[IO.Path]::GetFullPath($canonicalPath),[StringComparison]::Ordinal)){throw 'ASSERTION FAILED: Worker handoff falls back to canonical module when no runtime module is loaded'}

$runtimeOne=Join-Path $moduleRoot 'AidosRepositoryHandoff.runtime.0123456789abcdef0123456789abcdef.psm1'
$runtimeTwo=Join-Path $moduleRoot 'AidosRepositoryHandoff.runtime.fedcba9876543210fedcba9876543210.psm1'
try{
    Set-Content -LiteralPath $runtimeOne -Value '# test runtime handoff' -Encoding utf8NoBOM
    $resolved=Resolve-AidosRepositoryWorkerHandoffModulePath -ModuleRoot $moduleRoot -LoadedModules @([pscustomobject]@{Path=$runtimeOne})
    if(-not[string]::Equals([IO.Path]::GetFullPath($resolved),[IO.Path]::GetFullPath($runtimeOne),[StringComparison]::Ordinal)){throw 'ASSERTION FAILED: Worker handoff does not select the single loaded runtime handoff module'}

    Set-Content -LiteralPath $runtimeTwo -Value '# second test runtime handoff' -Encoding utf8NoBOM
    Assert-Throws {Resolve-AidosRepositoryWorkerHandoffModulePath -ModuleRoot $moduleRoot -LoadedModules @([pscustomobject]@{Path=$runtimeOne},[pscustomobject]@{Path=$runtimeTwo})|Out-Null} 'has 2 loaded repository handoff modules' 'Worker handoff fails closed on ambiguous runtime handoff modules'
}finally{
    Remove-Item -LiteralPath $runtimeOne,$runtimeTwo -Force -ErrorAction SilentlyContinue
}

Write-Output 'PASS: WSL provider link metadata and Worker runtime routing compatibility assertions'
