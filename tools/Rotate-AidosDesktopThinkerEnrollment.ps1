[CmdletBinding()]
param(
    [string]$StateRoot,
    [string]$ProcessName='ChatGPT Classic'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not$IsWindows){throw 'Desktop Thinker enrollment rotation must run on the Windows AIDOS host.'}
if([string]::IsNullOrWhiteSpace($StateRoot)){$StateRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'}
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosDesktopThinkerEnrollmentRotation.psm1') -Force -DisableNameChecking
Rotate-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -ProcessName $ProcessName|ConvertTo-Json -Depth 100
