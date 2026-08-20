[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $root 'bridge/AidosDesktopChatGPT.psm1') -Force -DisableNameChecking -PassThru
$script:passed=0
function Assert-Chunking([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Get-Sha256([byte[]]$Bytes){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()}
function Invoke-EvidenceDocuments {
    param([string]$ProjectRoot,$Assignment,$Manifest,[int]$MaximumDocumentBytes,[int]$MaximumTotalBytes)
    & $module {
        param($ProjectRoot,$Assignment,$Manifest,$MaximumDocumentBytes,$MaximumTotalBytes)
        Get-AidosDesktopChatGPTReviewEvidenceDocuments -ProjectRoot $ProjectRoot -Assignment $Assignment -Manifest $Manifest -MaximumDocumentBytes $MaximumDocumentBytes -MaximumTotalBytes $MaximumTotalBytes
    } $ProjectRoot $Assignment $Manifest $MaximumDocumentBytes $MaximumTotalBytes
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-review-evidence-chunking-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try{
    $utf8=[Text.UTF8Encoding]::new($false)
    $manifestPath=Join-Path $temp 'MANIFEST.json'
    $manifestText='{"schema_version":"0.1"}'
    [IO.File]::WriteAllText($manifestPath,$manifestText,$utf8)
    $manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
    $manifestSha=Get-Sha256 $manifestBytes

    $evidencePath=Join-Path $temp 'codex-events.jsonl'
    $evidenceText=("header`n"+((('é'*19)+"`n")*8)+"footer`n")
    [IO.File]::WriteAllText($evidencePath,$evidenceText,$utf8)
    $evidenceBytes=[IO.File]::ReadAllBytes($evidencePath)
    $evidenceSha=Get-Sha256 $evidenceBytes

    $assignment=[pscustomobject][ordered]@{
        package_manifest_path='MANIFEST.json'
        package_manifest_sha256=$manifestSha
        evidence_refs=@([pscustomobject][ordered]@{kind='EVENTS_JSONL';path='codex-events.jsonl';sha256=$evidenceSha})
    }
    $manifest=[pscustomobject]@{schema_version='0.1'}

    $documents=@(Invoke-EvidenceDocuments -ProjectRoot $temp -Assignment $assignment -Manifest $manifest -MaximumDocumentBytes 64 -MaximumTotalBytes 4096)
    $manifestDocuments=@($documents|Where-Object {$_.path -eq 'MANIFEST.json'})
    $chunks=@($documents|Where-Object {$_.path -eq 'codex-events.jsonl'})

    Assert-Chunking ($manifestDocuments.Count -eq 1 -and -not$manifestDocuments[0].PSObject.Properties['transport_chunk_index']) 'small evidence remains one legacy-shaped transport document'
    Assert-Chunking ($chunks.Count -gt 1) 'oversized evidence is split into multiple transport documents'
    Assert-Chunking (([string]::Concat(@($chunks|ForEach-Object {[string]$_.content}))) -ceq $evidenceText) 'ordered chunks reconstruct the exact original UTF-8 text'
    Assert-Chunking (@($chunks|Where-Object {[Text.Encoding]::UTF8.GetByteCount([string]$_.content) -gt 64}).Count -eq 0) 'every transport chunk stays within the per-document byte limit'
    Assert-Chunking (@($chunks|Where-Object {[string]$_.sha256 -ne $evidenceSha}).Count -eq 0) 'every chunk remains bound to the full original evidence SHA-256'
    Assert-Chunking (@($chunks|Where-Object {[int]$_.source_bytes -ne $evidenceBytes.Length}).Count -eq 0) 'every chunk records the original evidence byte length'
    Assert-Chunking ((@($chunks|ForEach-Object {[int]$_.transport_chunk_index}) -join ',') -eq (1..$chunks.Count -join ',')) 'chunk indexes are deterministic and contiguous'
    Assert-Chunking (@($chunks|Where-Object {[int]$_.transport_chunk_count -ne $chunks.Count}).Count -eq 0) 'every chunk records the stable total chunk count'
    $chunkHashesValid=$true
    foreach($chunk in $chunks){
        $actual=Get-Sha256 ([Text.Encoding]::UTF8.GetBytes([string]$chunk.content))
        if($actual -ne [string]$chunk.transport_chunk_sha256){$chunkHashesValid=$false;break}
    }
    Assert-Chunking $chunkHashesValid 'each chunk carries a SHA-256 for its transported UTF-8 bytes'

    $threw=$false
    try{Invoke-EvidenceDocuments -ProjectRoot $temp -Assignment $assignment -Manifest $manifest -MaximumDocumentBytes 64 -MaximumTotalBytes ($manifestBytes.Length+$evidenceBytes.Length-1)|Out-Null}catch{$threw=$_.Exception.Message -match 'total transport limit'}
    Assert-Chunking $threw 'the original aggregate 512-KiB-style total limit remains fail-closed before transport'

    $badAssignment=[pscustomobject][ordered]@{
        package_manifest_path='MANIFEST.json'
        package_manifest_sha256=$manifestSha
        evidence_refs=@([pscustomobject][ordered]@{kind='EVENTS_JSONL';path='codex-events.jsonl';sha256=('0'*64)})
    }
    $threw=$false
    try{Invoke-EvidenceDocuments -ProjectRoot $temp -Assignment $badAssignment -Manifest $manifest -MaximumDocumentBytes 64 -MaximumTotalBytes 4096|Out-Null}catch{$threw=$_.Exception.Message -match 'hash mismatch'}
    Assert-Chunking $threw 'full original evidence hash binding is still verified before chunking'

    $secretPath=Join-Path $temp 'secret.txt'
    $secretText=('x'*60)+'api_key=supersecretvalue'
    [IO.File]::WriteAllText($secretPath,$secretText,$utf8)
    $secretBytes=[IO.File]::ReadAllBytes($secretPath)
    $secretAssignment=[pscustomobject][ordered]@{
        package_manifest_path='MANIFEST.json'
        package_manifest_sha256=$manifestSha
        evidence_refs=@([pscustomobject][ordered]@{kind='STDERR_LOG';path='secret.txt';sha256=(Get-Sha256 $secretBytes)})
    }
    $threw=$false
    try{Invoke-EvidenceDocuments -ProjectRoot $temp -Assignment $secretAssignment -Manifest $manifest -MaximumDocumentBytes 64 -MaximumTotalBytes 4096|Out-Null}catch{$threw=$_.Exception.Message -match 'not secret-free'}
    Assert-Chunking $threw 'secret scanning remains whole-document and fail-closed before chunking'
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "PASS: $passed desktop review evidence chunking assertions"
