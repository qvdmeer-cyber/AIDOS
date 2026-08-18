[CmdletBinding()]
param([string]$RepoRoot=(Split-Path $PSScriptRoot -Parent))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($RepoRoot)

$parseErrors=[Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1')} | ForEach-Object {
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
    foreach($error in @($errors)){$parseErrors.Add("$($_.FullName): $($error.Message)")}
}
if($parseErrors.Count){throw "PowerShell parse validation failed:`n$($parseErrors -join [Environment]::NewLine)"}

Get-ChildItem -LiteralPath $root -Recurse -Filter '*.json' -File | ForEach-Object {
    try{Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100|Out-Null}
    catch{throw "JSON parse validation failed for '$($_.FullName)': $($_.Exception.Message)"}
}

$tests=@(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter '*.Tests.ps1' -File|Sort-Object Name)
if($tests.Count-eq0){throw 'No AIDOS Core regression tests were found.'}

# Some cross-platform execution fixtures mark generated shell stubs executable
# with chmod. Windows has no executable permission bit, so when validation runs
# under the host PowerShell engine provide a temporary no-op compatibility shim.
# This preserves the fixture semantics without requiring Unix tooling on Windows.
$createdChmodShim=$false
if($IsWindows -and -not(Get-Command chmod -ErrorAction SilentlyContinue)){
    Set-Item -Path Function:\global:chmod -Value {
        param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments)
    }
    $createdChmodShim=$true
}

$executed=[Collections.Generic.List[string]]::new()
try {
    foreach($test in $tests){
        # Tests are invoked in-process with ErrorActionPreference=Stop. A stale
        # LASTEXITCODE from a native command inside an otherwise successful test is
        # not the test result; only a thrown assertion/command failure fails here.
        & $test.FullName
        $executed.Add($test.Name)
    }
} finally {
    if($createdChmodShim){Remove-Item -Path Function:\global:chmod -ErrorAction SilentlyContinue}
}
[pscustomobject][ordered]@{status='PASS';repo_root=$root;tests=@($executed);test_count=$executed.Count;validated_at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 20
