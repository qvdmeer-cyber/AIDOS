[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosAutonomousExecution.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Recovery([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$runtime=[pscustomobject]@{project_root='/tmp/project'}
$execution=[pscustomobject]@{authority=[pscustomobject]@{network=$false}}
$session='01a024b2-6a07-7cb1-a583-193ac05dfe11'
$arguments=@(Get-AidosAutonomousCodexArguments -Runtime $runtime -Execution $execution -PromptText 'continue' -ResumeSessionId $session)
Assert-Recovery (($arguments -join ' ')-eq"exec resume --json $session continue") 'resume uses the exact durable Codex session id'

$source=Get-Content (Join-Path $root 'bridge/AidosAutonomousExecution.psm1') -Raw -Encoding UTF8
Assert-Recovery ($source.Contains("state.state-ne'RECOVERY_REQUIRED'")) 'resume requires RECOVERY_REQUIRED'
Assert-Recovery ($source.Contains("'.aidos/runtime/lease.json'")) 'resume rejects an unreconciled lease'
Assert-Recovery ($source.Contains("'RESULT.json'")) 'resume rejects an existing terminal result'
Assert-Recovery ($source.Contains("type-eq'thread.started'")) 'resume binds durable thread.started evidence'
Assert-Recovery ($source.Contains("type-in@('turn.completed','turn.failed','error')")) 'resume classifies terminal event evidence'
Assert-Recovery ($source.Contains("RECOVERY.json")) 'resume requires Core terminal-event recovery evidence'
Assert-Recovery ($source.Contains('StreamWriter]::new($eventsPath,$resuming')) 'resume appends to prior event evidence'
Assert-Recovery ($source.Contains('resumed=$resuming')) 'terminal result records resume provenance'
Write-Output "PASS: $passed autonomous execution recovery assertions"
