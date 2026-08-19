[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root 'tools/Invoke-AidosHostSelfUpdate.ps1'
$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw "ASSERTION FAILED: self-update script has PowerShell parse errors: $(@($errors).Message -join '; ')"}

$passed=0
function Assert-LocalValidation([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

Assert-LocalValidation ($text.Contains("Join-Path ([IO.Path]::GetTempPath()) 'AIDOS-core-validation'")) 'candidate validation uses an AIDOS-owned local Windows temp root'
Assert-LocalValidation ($text.Contains('Get-ChildItem -LiteralPath $candidateUnc -Force|Copy-Item -Destination $validationRoot -Recurse -Force')) 'candidate contents are mirrored from the bound WSL worktree before execution'
Assert-LocalValidation ($text.Contains('$validator=Join-Path $validationRoot ''tools\Test-AidosCorePortable.ps1''')) 'portable validator is resolved from the local mirror'
Assert-LocalValidation ($text.Contains('-File $validator -RepoRoot $validationRoot')) 'PowerShell executes validation only against the local mirror'
Assert-LocalValidation (-not$text.Contains('-File $sourceValidator -RepoRoot $candidateUnc')) 'UNC candidate validator is never executed directly'
Assert-LocalValidation ($text.Contains('Remove-Item -LiteralPath $validationRoot -Recurse -Force')) 'ephemeral local validation mirror is removed in cleanup'

Write-Output "PASS: $passed host self-update local-validation assertions"
