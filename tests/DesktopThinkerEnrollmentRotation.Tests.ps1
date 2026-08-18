[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosDesktopThinkerTransport.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'bridge/AidosDesktopThinkerEnrollmentRotation.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert-Rotation([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}

$stateRoot=Join-Path ([IO.Path]::GetTempPath()) ('aidos-thinker-rotation-'+[guid]::NewGuid().ToString('N'))
try {
    $backend=New-AidosDesktopThinkerStubBackend -ResponseText '{}'
    $first=Initialize-AidosDesktopThinkerEnrollment -StateRoot $stateRoot -Backend $backend
    Assert-Rotation ($first.status -eq 'ENROLLED') 'initial stub enrollment succeeds'
    $old=Read-AidosDesktopThinkerEnrollment -StateRoot $stateRoot
    $oldMarker=[string]$old.conversation_proof_text
    $oldHash=[string]$old.conversation_fingerprint_sha256

    $rotation=Rotate-AidosDesktopThinkerEnrollment -StateRoot $stateRoot -Backend $backend
    Assert-Rotation ($rotation.status -eq 'ROTATED') 'rotation completes through the normal enrollment lifecycle'
    Assert-Rotation ($rotation.previous_conversation_fingerprint_sha256 -eq $oldHash) 'rotation records the previous durable conversation fingerprint'
    Assert-Rotation (Test-Path -LiteralPath $rotation.archive_path -PathType Leaf) 'previous enrollment is archived before replacement'
    Assert-Rotation ((Get-FileHash -LiteralPath $rotation.archive_path -Algorithm SHA256).Hash.ToLowerInvariant() -eq [string]$rotation.archive_sha256) 'archived enrollment hash is preserved exactly'

    $archived=Get-Content -LiteralPath $rotation.archive_path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    Assert-Rotation ([string]$archived.conversation_proof_text -eq $oldMarker) 'archive preserves the previous enrollment marker'
    $current=Read-AidosDesktopThinkerEnrollment -StateRoot $stateRoot
    Assert-Rotation ($current.status -eq 'ENROLLED') 'new active enrollment is durable after rotation'
    Assert-Rotation ([string]$current.conversation_proof_text -ne $oldMarker) 'new enrollment uses a fresh marker instead of reusing prior conversation proof'
    Assert-Rotation (@(Get-ChildItem -LiteralPath (Get-AidosDesktopThinkerEnrollmentHistoryRoot -StateRoot $stateRoot) -Filter '*.json' -File).Count -eq 1) 'one rotation creates exactly one archived enrollment record'
} finally {
    if(Test-Path -LiteralPath $stateRoot){Remove-Item -LiteralPath $stateRoot -Recurse -Force}
}
Write-Output "PASS: $passed Desktop Thinker enrollment rotation assertions"
