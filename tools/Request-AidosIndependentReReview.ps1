[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ReviewId
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'bridge/AidosReviewAuthorityRecovery.psm1') -Force -DisableNameChecking

Request-AidosIndependentReReview -ProjectRoot $ProjectRoot -ReviewId $ReviewId |
    ConvertTo-Json -Depth 100
