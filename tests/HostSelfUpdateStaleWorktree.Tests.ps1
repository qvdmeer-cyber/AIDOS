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
function Assert-SelfUpdate([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}

Assert-SelfUpdate ($text -match 'function Clear-AidosValidationWorktree') 'stale validation worktree cleanup helper exists'
Assert-SelfUpdate ($text -match "\$Commit -notmatch '\^\[0-9a-f\]\{40\}\$'") 'cleanup requires an exact lowercase 40-hex commit id'
Assert-SelfUpdate ($text -match 'Refusing validation worktree cleanup outside the exact AIDOS-owned candidate path') 'cleanup rejects paths outside the exact AIDOS-owned candidate path'
Assert-SelfUpdate ($text -match "@\('git','-C',\$Repo,'worktree','prune'\)") 'cleanup prunes stale Git worktree metadata'
Assert-SelfUpdate ($text -match "@\('rm','-rf','--',\$Candidate\)") 'stale-directory removal uses the exact validated candidate path and option terminator'
Assert-SelfUpdate (([regex]::Matches($text,'Clear-AidosValidationWorktree -Repo \$repo -CandidateRoot \$candidateRoot -Candidate \$candidate -Commit \$remote')).Count -eq 2) 'cleanup runs both before validation worktree creation and in validation finally cleanup'
Assert-SelfUpdate ($text -match 'AIDOS validation worktree path remains after bounded cleanup') 'cleanup verifies the candidate path is actually absent'

Write-Output "PASS: $passed host self-update stale-worktree recovery assertions"
