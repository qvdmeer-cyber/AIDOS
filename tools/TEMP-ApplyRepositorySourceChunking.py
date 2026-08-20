from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        count = text.count(old)
        if count != 1:
            raise RuntimeError(f"{label} is ambiguous: {count} matches")
        return text.replace(old, new)
    if new not in text:
        raise RuntimeError(f"{label} anchor is missing")
    return text


gateway_path = Path('bridge/AidosRepositoryHandoffGateway.psm1')
gateway = gateway_path.read_text(encoding='utf-8')
old_config = "schema_version='0.2';registry_root=[IO.Path]::GetFullPath($RegistryRoot);aidos_root=[IO.Path]::GetFullPath($AidosRoot);state_root=$state;bridge_state_root=[IO.Path]::GetFullPath($BridgeStateRoot);listen_prefix=\"http://127.0.0.1:$Port/\";port=$Port;maximum_request_bytes=1048576;maximum_source_bytes=262144;configured_at=[DateTimeOffset]::UtcNow.ToString('o')"
new_config = "schema_version='0.2';registry_root=[IO.Path]::GetFullPath($RegistryRoot);aidos_root=[IO.Path]::GetFullPath($AidosRoot);state_root=$state;bridge_state_root=[IO.Path]::GetFullPath($BridgeStateRoot);listen_prefix=\"http://127.0.0.1:$Port/\";port=$Port;maximum_request_bytes=1048576;maximum_source_bytes=524288;maximum_source_chunk_characters=65536;configured_at=[DateTimeOffset]::UtcNow.ToString('o')"
gateway = replace_once(gateway, old_config, new_config, 'gateway config')

start = gateway.index('function Get-AidosRepositoryHandoffGatewaySource {')
end = gateway.index('\n\nfunction Assert-AidosRepositoryHandoffGatewayHumanInputBinding', start)
new_function = r'''function Get-AidosRepositoryHandoffGatewaySource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,
        [Parameter(Mandatory)][string]$AidosRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$SourceRef,
        [int]$MaximumBytes=524288,
        [int]$StartCharacter=0,
        [int]$MaximumCharacters=65536
    )
    if($MaximumBytes-lt1){throw 'Authorized source byte limit must be positive.'}
    if($StartCharacter-lt0){throw 'Authorized source startCharacter must be non-negative.'}
    if($MaximumCharacters-lt1-or$MaximumCharacters-gt65536){throw 'Authorized source maxCharacters must be between 1 and 65536.'}
    $project=Get-AidosRepositoryHandoffGatewayProject -RegistryRoot $RegistryRoot -ProjectId $ProjectId
    $handoff=Read-AidosRepositoryHandoff -ProjectRoot ([string]$project.local_root) -ExpectedProjectId ([string]$project.project_id)
    if($null-eq$handoff-or[string]$handoff.metadata.kind-ne'ASSIGNMENT'){throw 'No active assignment handoff authorizes source access.'}
    $authorized=@($handoff.metadata.source_refs|ForEach-Object {[string]$_})
    $exact=@($authorized|Where-Object {[string]::Equals($_,$SourceRef,[StringComparison]::Ordinal)})
    if($exact.Count-ne1){throw "Source ref '$SourceRef' is not authorized exactly by the current handoff."}
    $resolved=Resolve-AidosRepositoryHandoffGatewaySourcePath -Project $project -AidosRoot $AidosRoot -SourceRef $SourceRef
    $bytes=[IO.File]::ReadAllBytes($resolved.path)
    if($bytes.Length-gt$MaximumBytes){throw "Authorized source exceeds the $MaximumBytes byte limit: $SourceRef"}
    $decoder=[Text.UTF8Encoding]::new($false,$true)
    try{$text=$decoder.GetString($bytes)}catch{throw "Authorized source is not valid UTF-8 text: $SourceRef"}
    if($text.IndexOf([char]0)-ge0){throw "Authorized source is not UTF-8 text: $SourceRef"}
    if($text-match'(?im)-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|(?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[:=]\s*\S+'){throw "Authorized source is not secret-free: $SourceRef"}
    if($StartCharacter-gt$text.Length){throw "Authorized source startCharacter exceeds source length: $SourceRef"}
    if($StartCharacter-gt0-and$StartCharacter-lt$text.Length-and[char]::IsLowSurrogate($text[$StartCharacter])-and[char]::IsHighSurrogate($text[$StartCharacter-1])){throw 'Authorized source startCharacter splits a UTF-16 surrogate pair.'}
    $end=[Math]::Min($text.Length,$StartCharacter+$MaximumCharacters)
    if($end-lt$text.Length-and$end-gt$StartCharacter-and[char]::IsHighSurrogate($text[$end-1])-and[char]::IsLowSurrogate($text[$end])){$end--}
    $length=$end-$StartCharacter
    $content=if($length-gt0){$text.Substring($StartCharacter,$length)}else{''}
    $complete=$end-eq$text.Length
    $next=if($complete){$null}else{$end}
    [pscustomobject][ordered]@{
        project_id=[string]$project.project_id
        source_ref=$SourceRef
        sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        byte_length=$bytes.Length
        character_length=$text.Length
        chunk_start=$StartCharacter
        chunk_length=$length
        next_start=$next
        complete=$complete
        content=$content
    }
}'''
gateway = gateway[:start] + new_function + gateway[end:]

old_router = r'''        if($Method-eq'GET'-and$Path-match'^/v1/projects/([^/]+)/sources$'){
            $sourceRef=[string]$Query['path'];if([string]::IsNullOrWhiteSpace($sourceRef)){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_PATH_REQUIRED'})}
            return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $RegistryRoot -AidosRoot $AidosRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -SourceRef $sourceRef)
        }'''
new_router = r'''        if($Method-eq'GET'-and$Path-match'^/v1/projects/([^/]+)/sources$'){
            $sourceRef=[string]$Query['path'];if([string]::IsNullOrWhiteSpace($sourceRef)){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_PATH_REQUIRED'})}
            $startCharacter=0
            if($Query.ContainsKey('startCharacter')-and-not[string]::IsNullOrWhiteSpace([string]$Query['startCharacter'])){
                if(-not[int]::TryParse([string]$Query['startCharacter'],[ref]$startCharacter)-or$startCharacter-lt0){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_CHUNK_RANGE_INVALID';detail='startCharacter must be a non-negative integer.'})}
            }
            $maxCharacters=65536
            if($Query.ContainsKey('maxCharacters')-and-not[string]::IsNullOrWhiteSpace([string]$Query['maxCharacters'])){
                if(-not[int]::TryParse([string]$Query['maxCharacters'],[ref]$maxCharacters)-or$maxCharacters-lt1-or$maxCharacters-gt65536){return New-AidosRepositoryHandoffGatewayResponse 400 ([ordered]@{error='SOURCE_CHUNK_RANGE_INVALID';detail='maxCharacters must be an integer between 1 and 65536.'})}
            }
            return New-AidosRepositoryHandoffGatewayResponse 200 (Get-AidosRepositoryHandoffGatewaySource -RegistryRoot $RegistryRoot -AidosRoot $AidosRoot -ProjectId ([Uri]::UnescapeDataString($Matches[1])) -SourceRef $sourceRef -StartCharacter $startCharacter -MaximumCharacters $maxCharacters)
        }'''
gateway = replace_once(gateway, old_router, new_router, 'gateway source router')
gateway_path.write_text(gateway, encoding='utf-8')

openapi_path = Path('bridge/AidosRepositoryHandoffOpenApi.psm1')
openapi = openapi_path.read_text(encoding='utf-8')
old_description = "description='Call only for exact source_refs returned by getAidosProjectHandoff. Do not construct or broaden paths.'"
new_description = "description='Call only for exact source_refs returned by getAidosProjectHandoff. Read from startCharacter 0 and follow exact next_start values until complete is true. Do not construct or broaden paths.'"
openapi = replace_once(openapi, old_description, new_description, 'OpenAPI source description')
old_parameters = r'''                    parameters=@(
                        [ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id from the trigger.';schema=[ordered]@{type='string';minLength=1}},
                        [ordered]@{name='path';in='query';required=$true;description='Exact project-relative source_ref returned by the current handoff.';schema=[ordered]@{type='string';minLength=1}}
                    )'''
new_parameters = r'''                    parameters=@(
                        [ordered]@{name='projectId';in='path';required=$true;description='Exact AIDOS project_id from the trigger.';schema=[ordered]@{type='string';minLength=1}},
                        [ordered]@{name='path';in='query';required=$true;description='Exact project-relative source_ref returned by the current handoff.';schema=[ordered]@{type='string';minLength=1}},
                        [ordered]@{name='startCharacter';in='query';required=$false;description='Exact zero-based UTF-16 continuation offset. Start with 0; thereafter copy next_start exactly.';schema=[ordered]@{type='integer';minimum=0;default=0}},
                        [ordered]@{name='maxCharacters';in='query';required=$false;description='Maximum UTF-16 characters returned in one bounded response.';schema=[ordered]@{type='integer';minimum=1;maximum=65536;default=65536}}
                    )'''
openapi = replace_once(openapi, old_parameters, new_parameters, 'OpenAPI source parameters')
old_schema = r'''                SourceResponse=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('project_id','source_ref','sha256','byte_length','content')
                    properties=[ordered]@{
                        project_id=[ordered]@{type='string';minLength=1}
                        source_ref=[ordered]@{type='string';minLength=1}
                        sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        byte_length=[ordered]@{type='integer';minimum=0}
                        content=[ordered]@{type='string'}
                    }
                }'''
new_schema = r'''                SourceResponse=[ordered]@{
                    type='object'
                    additionalProperties=$false
                    required=@('project_id','source_ref','sha256','byte_length','character_length','chunk_start','chunk_length','next_start','complete','content')
                    properties=[ordered]@{
                        project_id=[ordered]@{type='string';minLength=1}
                        source_ref=[ordered]@{type='string';minLength=1}
                        sha256=[ordered]@{type='string';pattern='^[0-9a-f]{64}$'}
                        byte_length=[ordered]@{type='integer';minimum=0;description='Full source byte length.'}
                        character_length=[ordered]@{type='integer';minimum=0;description='Full source UTF-16 character length.'}
                        chunk_start=[ordered]@{type='integer';minimum=0}
                        chunk_length=[ordered]@{type='integer';minimum=0;maximum=65536}
                        next_start=[ordered]@{type=@('integer','null');minimum=0}
                        complete=[ordered]@{type='boolean'}
                        content=[ordered]@{type='string'}
                    }
                }'''
openapi = replace_once(openapi, old_schema, new_schema, 'OpenAPI SourceResponse')
openapi_path.write_text(openapi, encoding='utf-8')

install_path = Path('bridge/AidosRepositoryHandoffInstallation.psm1')
install = install_path.read_text(encoding='utf-8')
old_step = '5. Call `getAidosAuthorizedSource` only for exact source_refs listed by that handoff. Never construct or broaden paths. Do not use web search, chat memory, unbound files, or unstated project facts.'
new_step = '5. Call `getAidosAuthorizedSource` only for exact source_refs listed by that handoff, first with startCharacter 0 and maxCharacters 65536. If complete is false, repeat the same exact source_ref with startCharacter equal to the exact next_start until complete is true. Require project_id, source_ref, full SHA-256, byte_length and character_length to remain identical; require chunk_start to equal the requested continuation; concatenate content in order. Stop on a missing, repeated or non-advancing continuation. Never construct or broaden paths. Do not use web search, chat memory, unbound files, or unstated project facts.'
install = replace_once(install, old_step, new_step, 'Thinker source instructions')
install_path.write_text(install, encoding='utf-8')

workflow_path = Path('.github/workflows/validate-repository-handoff.yml')
workflow = workflow_path.read_text(encoding='utf-8')
parse_anchor = "            'tests/RepositoryHandoffGateway.Tests.ps1',\n"
parse_add = parse_anchor + "            'tests/RepositorySourceChunking.Tests.ps1',\n"
if "'tests/RepositorySourceChunking.Tests.ps1'" not in workflow:
    if workflow.count(parse_anchor) != 1:
        raise RuntimeError('Repository workflow parse anchor missing')
    workflow = workflow.replace(parse_anchor, parse_add)
step_anchor = "      - name: Repository handoff gateway\n        shell: pwsh\n        run: ./tests/RepositoryHandoffGateway.Tests.ps1\n"
step_add = step_anchor + "      - name: Chunked authorized source transport\n        shell: pwsh\n        run: ./tests/RepositorySourceChunking.Tests.ps1\n"
if 'Chunked authorized source transport' not in workflow:
    if workflow.count(step_anchor) != 1:
        raise RuntimeError('Repository workflow step anchor missing')
    workflow = workflow.replace(step_anchor, step_add)
workflow_path.write_text(workflow, encoding='utf-8')
