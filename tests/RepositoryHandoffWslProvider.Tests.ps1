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

Write-Output 'PASS: WSL provider link metadata compatibility assertions'
