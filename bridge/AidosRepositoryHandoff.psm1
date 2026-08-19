Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking

$script:AidosRepositoryHandoffBegin='<!-- AIDOS_HANDOFF_V1_BEGIN -->'
$script:AidosRepositoryHandoffEnd='<!-- AIDOS_HANDOFF_V1_END -->'

function Get-AidosRepositoryHandoffRelativePath {
    '.aidos/HANDOFF.md'
}
function Get-AidosRepositoryHandoffPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) (Get-AidosRepositoryHandoffRelativePath)
}
function Get-AidosRepositoryHandoffTextSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}
function Test-AidosRepositoryRelativePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$FieldName)
    $value=$Path.Replace('\','/').Trim()
    if([string]::IsNullOrWhiteSpace($value)){throw "Repository handoff requires '$FieldName'."}
    if([IO.Path]::IsPathRooted($value) -or $value.StartsWith('../',[StringComparison]::Ordinal) -or $value.Contains('/../',[StringComparison]::Ordinal)){throw "Repository handoff '$FieldName' must be a project-relative path."}
    if($value.StartsWith('./',[StringComparison]::Ordinal)){$value=$value.Substring(2)}
    if([string]::IsNullOrWhiteSpace($value)){throw "Repository handoff requires '$FieldName'."}
    $value
}
function Test-AidosRepositoryHandoffBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Binding)
    if($null-eq$Binding){throw 'Repository handoff requires binding.'}
    foreach($name in @('project_state','definition_id','definition_version','execution_id','revision','review_id')){if(-not$Binding.PSObject.Properties[$name]){throw "Repository handoff binding is missing '$name'."}}
    [pscustomobject][ordered]@{
        project_state=if($null-eq$Binding.project_state){$null}else{[string]$Binding.project_state}
        definition_id=if($null-eq$Binding.definition_id){$null}else{[string]$Binding.definition_id}
        definition_version=if($null-eq$Binding.definition_version){$null}else{[int]$Binding.definition_version}
        execution_id=if($null-eq$Binding.execution_id){$null}else{[string]$Binding.execution_id}
        revision=if($null-eq$Binding.revision){$null}else{[int]$Binding.revision}
        review_id=if($null-eq$Binding.review_id){$null}else{[string]$Binding.review_id}
    }
}
function Test-AidosRepositoryHandoffMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Metadata,[string]$ExpectedProjectId)
    foreach($name in @('schema_version','envelope_type','handoff_id','project_id','kind','from_actor','to_actor','status','parent_handoff_id','created_at','action','payload_ref','payload_sha256','binding','source_refs')){if(-not$Metadata.PSObject.Properties[$name]){throw "Repository handoff metadata is missing '$name'."}}
    if([string]$Metadata.schema_version-ne'0.1'){throw "Unsupported repository handoff schema_version '$($Metadata.schema_version)'."}
    if([string]$Metadata.envelope_type-ne'AIDOS_REPOSITORY_HANDOFF'){throw 'Repository handoff envelope_type mismatch.'}
    $handoffId=[string]$Metadata.handoff_id;$parsedId=[guid]::Empty
    if(-not[guid]::TryParse($handoffId,[ref]$parsedId)){throw 'Repository handoff_id must be a UUID.'}
    $projectId=[string]$Metadata.project_id
    if([string]::IsNullOrWhiteSpace($projectId)){throw 'Repository handoff requires project_id.'}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedProjectId) -and -not[string]::Equals($projectId,$ExpectedProjectId,[StringComparison]::Ordinal)){throw "Repository handoff project_id '$projectId' does not match '$ExpectedProjectId'."}
    $kind=[string]$Metadata.kind
    if($kind-notin@('ASSIGNMENT','RESULT')){throw "Repository handoff kind '$kind' is invalid."}
    $fromActor=[string]$Metadata.from_actor;$toActor=[string]$Metadata.to_actor;$actors=@('CORE','THINKER','WORKER','HUMAN')
    if($fromActor-notin$actors){throw "Repository handoff from_actor '$fromActor' is invalid."}
    if($toActor-notin$actors){throw "Repository handoff to_actor '$toActor' is invalid."}
    if([string]$Metadata.status-ne'READY'){throw "Repository handoff status must be READY, found '$($Metadata.status)'."}
    if($kind-eq'ASSIGNMENT'){
        if($fromActor-ne'CORE'){throw 'Repository ASSIGNMENT handoffs must be published by CORE.'}
        if($toActor-notin@('THINKER','WORKER','HUMAN')){throw 'Repository ASSIGNMENT handoff has no executable target actor.'}
    }else{
        if($toActor-ne'CORE'){throw 'Repository RESULT handoffs must return to CORE.'}
        if($fromActor-notin@('THINKER','WORKER','HUMAN')){throw 'Repository RESULT handoff has no valid producing actor.'}
    }
    $parent=$null
    if($null-ne$Metadata.parent_handoff_id -and -not[string]::IsNullOrWhiteSpace([string]$Metadata.parent_handoff_id)){
        $parent=[string]$Metadata.parent_handoff_id;$parsedParent=[guid]::Empty
        if(-not[guid]::TryParse($parent,[ref]$parsedParent)){throw 'Repository parent_handoff_id must be null or a UUID.'}
        if([string]::Equals($parent,$handoffId,[StringComparison]::OrdinalIgnoreCase)){throw 'Repository handoff may not parent itself.'}
    }
    $created=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Metadata.created_at,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$created)){throw 'Repository handoff created_at must be ISO-8601.'}
    $action=[string]$Metadata.action
    if([string]::IsNullOrWhiteSpace($action)){throw 'Repository handoff requires action.'}
    $payloadRef=Test-AidosRepositoryRelativePath -Path ([string]$Metadata.payload_ref) -FieldName 'payload_ref'
    $payloadSha=$null
    if($null-ne$Metadata.payload_sha256 -and -not[string]::IsNullOrWhiteSpace([string]$Metadata.payload_sha256)){
        $payloadSha=[string]$Metadata.payload_sha256
        if($payloadSha-notmatch'^[0-9a-fA-F]{64}$'){throw 'Repository handoff payload_sha256 must be null or a SHA-256 hex value.'}
        $payloadSha=$payloadSha.ToLowerInvariant()
    }
    $binding=Test-AidosRepositoryHandoffBinding -Binding $Metadata.binding
    $sourceRefs=@();foreach($sourceRef in @($Metadata.source_refs)){$sourceRefs+=Test-AidosRepositoryRelativePath -Path ([string]$sourceRef) -FieldName 'source_refs'}
    [pscustomobject][ordered]@{schema_version='0.1';envelope_type='AIDOS_REPOSITORY_HANDOFF';handoff_id=$handoffId;project_id=$projectId;kind=$kind;from_actor=$fromActor;to_actor=$toActor;status='READY';parent_handoff_id=$parent;created_at=$created.ToUniversalTime().ToString('o');action=$action;payload_ref=$payloadRef;payload_sha256=$payloadSha;binding=$binding;source_refs=@($sourceRefs)}
}
function ConvertFrom-AidosRepositoryHandoffText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[string]$ExpectedProjectId,[int]$MaximumBytes=1048576)
    $bytes=[Text.Encoding]::UTF8.GetByteCount($Text)
    if($bytes-gt$MaximumBytes){throw "Repository HANDOFF.md exceeds the $MaximumBytes byte limit."}
    $begin=$Text.IndexOf($script:AidosRepositoryHandoffBegin,[StringComparison]::Ordinal)
    if($begin-lt0){throw 'Repository HANDOFF.md has no AIDOS_HANDOFF_V1_BEGIN marker.'}
    $metadataStart=$begin+$script:AidosRepositoryHandoffBegin.Length
    $end=$Text.IndexOf($script:AidosRepositoryHandoffEnd,$metadataStart,[StringComparison]::Ordinal)
    if($end-lt0){throw 'Repository HANDOFF.md has no AIDOS_HANDOFF_V1_END marker.'}
    if($Text.IndexOf($script:AidosRepositoryHandoffBegin,$metadataStart,[StringComparison]::Ordinal)-ge0){throw 'Repository HANDOFF.md contains multiple begin markers.'}
    if($Text.IndexOf($script:AidosRepositoryHandoffEnd,$end+$script:AidosRepositoryHandoffEnd.Length,[StringComparison]::Ordinal)-ge0){throw 'Repository HANDOFF.md contains multiple end markers.'}
    $json=$Text.Substring($metadataStart,$end-$metadataStart).Trim()
    if([string]::IsNullOrWhiteSpace($json)){throw 'Repository HANDOFF.md metadata block is empty.'}
    try{$raw=$json|ConvertFrom-Json -Depth 100}catch{throw "Repository HANDOFF.md metadata JSON is invalid: $($_.Exception.Message)"}
    $metadata=Test-AidosRepositoryHandoffMetadata -Metadata $raw -ExpectedProjectId $ExpectedProjectId
    $bodyStart=$end+$script:AidosRepositoryHandoffEnd.Length
    $body=if($bodyStart-lt$Text.Length){$Text.Substring($bodyStart).TrimStart("`r","`n")}else{''}
    [pscustomobject][ordered]@{metadata=$metadata;body=$body;text=$Text;text_sha256=Get-AidosRepositoryHandoffTextSha256 -Text $Text;byte_length=$bytes}
}
function Read-AidosRepositoryHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$ExpectedProjectId)
    $path=Get-AidosRepositoryHandoffPath -ProjectRoot $ProjectRoot
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    $text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $parsed=ConvertFrom-AidosRepositoryHandoffText -Text $text -ExpectedProjectId $ExpectedProjectId
    $parsed|Add-Member -NotePropertyName path -NotePropertyValue $path -Force
    $parsed
}
function New-AidosRepositoryHandoffText {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Metadata,[Parameter(Mandatory)][AllowEmptyString()][string]$Body)
    $validated=Test-AidosRepositoryHandoffMetadata -Metadata $Metadata
    $json=$validated|ConvertTo-Json -Depth 30
    @($script:AidosRepositoryHandoffBegin,$json,$script:AidosRepositoryHandoffEnd,'',$Body.TrimEnd(),'') -join "`n"
}
function Write-AidosRepositoryHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Metadata,[Parameter(Mandatory)][AllowEmptyString()][string]$Body,[string]$ExpectedParentHandoffId)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $path=Get-AidosRepositoryHandoffPath -ProjectRoot $root
    $existing=Read-AidosRepositoryHandoff -ProjectRoot $root
    if($existing -and -not[string]::IsNullOrWhiteSpace($ExpectedParentHandoffId) -and -not[string]::Equals([string]$existing.metadata.handoff_id,$ExpectedParentHandoffId,[StringComparison]::OrdinalIgnoreCase)){throw 'Repository handoff parent changed before write.'}
    if($existing -and [string]::IsNullOrWhiteSpace([string]$Metadata.parent_handoff_id)){$Metadata.parent_handoff_id=[string]$existing.metadata.handoff_id}
    $text=New-AidosRepositoryHandoffText -Metadata $Metadata -Body $Body
    $dir=Split-Path -Parent $path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Set-Content -LiteralPath $path -Value $text -Encoding utf8NoBOM -NoNewline
    ConvertFrom-AidosRepositoryHandoffText -Text $text -ExpectedProjectId ([string]$Metadata.project_id)
}
function Test-AidosRepositoryHandoffTransition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Previous,[Parameter(Mandatory)]$Next)
    $previousMetadata=if($Previous.PSObject.Properties['metadata']){$Previous.metadata}else{$Previous}
    $nextMetadata=if($Next.PSObject.Properties['metadata']){$Next.metadata}else{$Next}
    if(-not[string]::Equals([string]$previousMetadata.project_id,[string]$nextMetadata.project_id,[StringComparison]::Ordinal)){throw 'Repository handoff transition project_id mismatch.'}
    if(-not[string]::Equals([string]$nextMetadata.parent_handoff_id,[string]$previousMetadata.handoff_id,[StringComparison]::OrdinalIgnoreCase)){throw 'Repository handoff transition parent_handoff_id mismatch.'}
    if([string]$previousMetadata.kind-eq'ASSIGNMENT'){
        if([string]$nextMetadata.kind-ne'RESULT'){throw 'Repository ASSIGNMENT must be followed by a RESULT.'}
        if([string]$nextMetadata.from_actor-ne[string]$previousMetadata.to_actor -or [string]$nextMetadata.to_actor-ne'CORE'){throw 'Repository actor result transition mismatch.'}
    }else{
        if([string]$nextMetadata.kind-ne'ASSIGNMENT' -or [string]$nextMetadata.from_actor-ne'CORE'){throw 'Repository RESULT must be followed by a Core ASSIGNMENT.'}
    }
    [pscustomobject][ordered]@{valid=$true;previous_handoff_id=[string]$previousMetadata.handoff_id;next_handoff_id=[string]$nextMetadata.handoff_id}
}

Export-ModuleMember -Function Get-AidosRepositoryHandoffRelativePath,Get-AidosRepositoryHandoffPath,Get-AidosRepositoryHandoffTextSha256,Test-AidosRepositoryRelativePath,Test-AidosRepositoryHandoffBinding,Test-AidosRepositoryHandoffMetadata,ConvertFrom-AidosRepositoryHandoffText,Read-AidosRepositoryHandoff,New-AidosRepositoryHandoffText,Write-AidosRepositoryHandoff,Test-AidosRepositoryHandoffTransition
