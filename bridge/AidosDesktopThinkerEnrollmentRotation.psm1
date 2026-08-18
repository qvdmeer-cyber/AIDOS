Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosDesktopThinkerTransport.psm1') -DisableNameChecking

function Get-AidosDesktopThinkerEnrollmentHistoryRoot {
    param([Parameter(Mandatory)][string]$StateRoot)
    Join-Path (Get-AidosDesktopThinkerRoot -StateRoot $StateRoot) 'enrollment-history'
}

function Rotate-AidosDesktopThinkerEnrollment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [string]$ProcessName='ChatGPT Classic',
        [object]$Backend
    )
    $path=Get-AidosDesktopThinkerEnrollmentPath -StateRoot $StateRoot
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Desktop Thinker enrollment does not exist; use normal enrollment instead of rotation.'}
    $existing=Read-AidosDesktopThinkerEnrollment -StateRoot $StateRoot
    if(-not$existing){throw 'Desktop Thinker enrollment is unreadable.'}

    $historyRoot=Get-AidosDesktopThinkerEnrollmentHistoryRoot -StateRoot $StateRoot
    if(-not(Test-Path -LiteralPath $historyRoot -PathType Container)){New-Item -ItemType Directory -Path $historyRoot -Force|Out-Null}
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $timestamp=[DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
    $archivePath=Join-Path $historyRoot ($timestamp+'-'+$hash+'.json')
    Copy-Item -LiteralPath $path -Destination $archivePath -ErrorAction Stop
    $archivedHash=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($archivedHash -ne $hash){throw 'Archived Desktop Thinker enrollment hash mismatch; refusing rotation.'}

    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    try {
        $rotated=Initialize-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -ProcessName $ProcessName -Backend $Backend
    } catch {
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
            Copy-Item -LiteralPath $archivePath -Destination $path -ErrorAction Stop
        }
        throw
    }

    [pscustomobject][ordered]@{
        status='ROTATED'
        previous_status=if($existing.PSObject.Properties['status']){[string]$existing.status}else{$null}
        previous_conversation_fingerprint_sha256=if($existing.PSObject.Properties['conversation_fingerprint_sha256']){[string]$existing.conversation_fingerprint_sha256}else{$null}
        archive_path=$archivePath
        archive_sha256=$hash
        enrollment_result=$rotated
    }
}

Export-ModuleMember -Function Get-AidosDesktopThinkerEnrollmentHistoryRoot,Rotate-AidosDesktopThinkerEnrollment
