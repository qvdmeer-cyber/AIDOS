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

$windowsSkip=@{}
$portabilityPath=Join-Path $root 'tests/PORTABILITY.json'
if($IsWindows){
    if(-not(Test-Path -LiteralPath $portabilityPath -PathType Leaf)){throw 'Windows candidate validation requires tests/PORTABILITY.json.'}
    $portability=Get-Content -LiteralPath $portabilityPath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 20
    if([string]$portability.schema_version -ne '0.1'){throw 'Unsupported tests/PORTABILITY.json schema_version.'}
    foreach($property in @($portability.windows_candidate_validation_skip.PSObject.Properties)){
        $windowsSkip[[string]$property.Name]=[string]$property.Value
    }
}

$executed=[Collections.Generic.List[string]]::new()
$skipped=[Collections.Generic.List[object]]::new()
foreach($test in $tests){
    if($IsWindows -and $windowsSkip.ContainsKey($test.Name)){
        $skipped.Add([ordered]@{test=$test.Name;reason=$windowsSkip[$test.Name]})
        continue
    }
    # Tests are invoked in-process with ErrorActionPreference=Stop. A stale
    # LASTEXITCODE from a native command inside an otherwise successful test is
    # not the test result; only a thrown assertion/command failure fails here.
    & $test.FullName
    $executed.Add($test.Name)
}
[pscustomobject][ordered]@{
    status='PASS'
    repo_root=$root
    tests=@($executed)
    test_count=$executed.Count
    skipped_tests=@($skipped)
    skipped_test_count=$skipped.Count
    validated_at=[DateTimeOffset]::UtcNow.ToString('o')
}|ConvertTo-Json -Depth 20
