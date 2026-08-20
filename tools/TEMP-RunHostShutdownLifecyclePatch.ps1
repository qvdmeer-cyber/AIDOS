[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$source=Get-Content -LiteralPath 'tools/TEMP-ApplyHostShutdownLifecyclePatch.ps1' -Raw -Encoding UTF8
$reloadAnchorReplacement='$reloadTestAnchor=''Assert-Reload ($text.IndexOf("Invoke-AidosRepositoryHandoffHostBootstrap.ps1",[StringComparison]::Ordinal) -ge 0 -and $text.IndexOf("-Command Stop -StateRoot $repositoryHostStateRoot",[StringComparison]::Ordinal) -ge 0) ''''Repository Handoff reload stops the running host through its canonical bootstrap'''''''
$updated=[regex]::Replace($source,'(?m)^\$reloadTestAnchor=.*$',$reloadAnchorReplacement,1)
$updated=$updated.Replace("`$host='bridge/Invoke-AidosRepositoryHandoffHost.ps1'","`$hostPath='bridge/Invoke-AidosRepositoryHandoffHost.ps1'")
$updated=$updated.Replace('Replace-Exact -Path $host -Old $oldStop.Trim() -New $newStop.Trim()','Replace-Exact -Path $hostPath -Old $oldStop.Trim() -New $newStop.Trim()')
$updated=$updated.Replace('@($installer,$host,$reload,$installTest,$reloadTest)','@($installer,$hostPath,$reload,$installTest,$reloadTest)')
if($updated-eq$source){throw 'Temporary lifecycle patch corrections did not modify the source.'}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-host-shutdown-patch-'+[guid]::NewGuid().ToString('N')+'.ps1')
try{
    Set-Content -LiteralPath $tmp -Value $updated -Encoding utf8NoBOM -NoNewline
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($tmp,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('Corrected temporary lifecycle patch still has parse errors: '+($errors.Message -join '; '))}
    & $tmp
}finally{
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
