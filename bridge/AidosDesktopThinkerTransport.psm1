Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -DisableNameChecking
$script:DesktopChatGPTWindowDiscoveryModule=Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPTWindowDiscovery.psm1') -DisableNameChecking -PassThru
$script:ResilientProcessContextCommand=$script:DesktopChatGPTWindowDiscoveryModule.ExportedCommands['Get-AidosDesktopChatGPTResilientProcessContext']
if($null-eq$script:ResilientProcessContextCommand){throw 'Resilient Desktop ChatGPT process-context command is unavailable.'}
Import-Module (Join-Path $PSScriptRoot 'AidosRuntimeActorTransport.psm1') -DisableNameChecking

function Get-AidosDesktopThinkerRoot {
    param([Parameter(Mandatory)][string]$StateRoot)
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) 'thinker-transport'
}
function Get-AidosDesktopThinkerEnrollmentPath {
    param([Parameter(Mandatory)][string]$StateRoot)
    Join-Path (Get-AidosDesktopThinkerRoot -StateRoot $StateRoot) 'ENROLLMENT.json'
}
function Read-AidosDesktopThinkerEnrollment {
    param([Parameter(Mandatory)][string]$StateRoot)
    $path=Get-AidosDesktopThinkerEnrollmentPath -StateRoot $StateRoot
    if(Test-Path -LiteralPath $path -PathType Leaf){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}else{$null}
}
function Write-AidosDesktopThinkerEnrollment {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$Enrollment)
    $path=Get-AidosDesktopThinkerEnrollmentPath -StateRoot $StateRoot
    $dir=Split-Path -Parent $path
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Write-AidosJsonAtomic $path $Enrollment
    $path
}
function Get-AidosDesktopThinkerResponseText {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$AssignmentId)
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){return $null}
    if(-not ('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not$root){return $null}
    $candidates=[System.Collections.Generic.List[string]]::new()
    foreach($element in @($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))){
        $text=Get-AidosDesktopChatGPTElementText $element
        if([string]::IsNullOrWhiteSpace([string]$text)){continue}
        if(([string]$text).IndexOf('RUNTIME_ACTOR_RESULT',[StringComparison]::OrdinalIgnoreCase) -ge 0 -and ([string]$text).IndexOf($AssignmentId,[StringComparison]::OrdinalIgnoreCase) -ge 0){$candidates.Add([string]$text)}
    }
    if($candidates.Count-eq0){return $null}
    $candidates[$candidates.Count-1]
}
function New-AidosDesktopThinkerStubBackend {
    param([string]$ResponseText,[bool]$InteractiveSession=$true,[bool]$ConversationProofAvailable=$true)
    $state=[pscustomobject]@{send_count=0;last_prompt=$null;proof_text=$null}
    [pscustomobject]@{
        State=$state
        AssertInteractiveSession=({param();if(-not$InteractiveSession){throw 'Windows session unavailable.'};$true}).GetNewClosure()
        GetProcessContext=({param([string]$ProcessName);[pscustomobject]@{present=$true;process_id=42;process_name=$ProcessName;session_id=1;main_window_handle='99';window_handle='99';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$true;window_is_visible=$true;window_source='stub'}}).GetNewClosure()
        FocusConversation=({param($Context,$Enrollment);$Context.window_is_foreground=$true;$Context}).GetNewClosure()
        SendPrompt=({param($Context,$Enrollment,[string]$PromptText);$state.send_count++;$state.last_prompt=$PromptText;if($PromptText -match 'AIDOS_THINKER_TRANSPORT_ENROLLMENT::(?<id>[0-9a-f-]+)'){$state.proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::'+$Matches.id}}).GetNewClosure()
        LocateConversation=({
            param($Context,[string]$ProofText,$Enrollment)
            if(-not$ConversationProofAvailable){throw 'Stub Thinker conversation proof is unavailable.'}
            if([string]::IsNullOrWhiteSpace([string]$state.proof_text) -or [string]$state.proof_text -ne $ProofText){throw 'Stub Thinker conversation proof is not present.'}
            $fingerprint=[ordered]@{window_title=$Context.window_title;window_class_name=$Context.window_class_name;conversation_proof_text=$ProofText;path=@([ordered]@{name='stub';control_type='Window'})}
            $json=$fingerprint|ConvertTo-Json -Depth 100 -Compress
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
            [pscustomobject]@{conversation_fingerprint=$fingerprint;conversation_fingerprint_sha256=$hash}
        }).GetNewClosure()
        ReadActorResponseText=({param($Context,$Enrollment,[int]$Attempt,$Assignment);if($state.send_count-lt1){return $null};$ResponseText}).GetNewClosure()
    }
}
function New-AidosDesktopThinkerWindowsBackend {
    param([string]$ProcessName='ChatGPT Classic')
    $backend=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName
    $primaryResolver=$backend.GetProcessContext
    $resilientProcessContext=$script:ResilientProcessContextCommand
    $backend.GetProcessContext=({param([string]$RequestedProcessName);& $resilientProcessContext -ProcessName $RequestedProcessName -PrimaryResolver $primaryResolver}).GetNewClosure()
    $backend
}
function Complete-AidosDesktopThinkerEnrollment {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$Enrollment,[Parameter(Mandatory)]$Location)
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $Enrollment.status='ENROLLED'
    $Enrollment.conversation_fingerprint_sha256=[string]$Location.conversation_fingerprint_sha256
    $Enrollment.conversation_fingerprint=$Location.conversation_fingerprint
    if(-not $Enrollment.PSObject.Properties['enrolled_at'] -or [string]::IsNullOrWhiteSpace([string]$Enrollment.enrolled_at)){$Enrollment|Add-Member -NotePropertyName enrolled_at -NotePropertyValue $now -Force}
    $Enrollment.updated_at=$now
    Write-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -Enrollment $Enrollment|Out-Null
    $Enrollment
}
function Initialize-AidosDesktopThinkerEnrollment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[string]$ProcessName='ChatGPT Classic',[object]$Backend)
    $existing=Read-AidosDesktopThinkerEnrollment -StateRoot $StateRoot
    if(-not$Backend){$Backend=New-AidosDesktopThinkerWindowsBackend -ProcessName $ProcessName}
    & $Backend.AssertInteractiveSession|Out-Null
    $context=& $Backend.GetProcessContext $ProcessName
    if(-not$context -or -not$context.present){throw 'ChatGPT process/window is unavailable for Thinker enrollment.'}
    if($existing){
        if([string]$existing.process_name -ne [string]$context.process_name -or [string]$existing.session_id -ne [string]$context.session_id -or [string]$existing.window_title -ne [string]$context.window_title -or [string]$existing.window_class_name -ne [string]$context.window_class_name){throw 'Desktop Thinker shell binding changed; enrollment is stale.'}
        $existingStatus=if($existing.PSObject.Properties['status']){[string]$existing.status}else{'ENROLLED'}
        if($existingStatus -eq 'PENDING_ENROLLMENT'){
            $loc=$null
            try{$loc=& $Backend.LocateConversation $context ([string]$existing.conversation_proof_text) $existing}catch{$loc=$null}
            if(-not $loc){return [pscustomobject][ordered]@{status='PENDING_ENROLLMENT';idempotent=$true;enrollment=$existing;context=$context}}
            $completed=Complete-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -Enrollment $existing -Location $loc
            return [pscustomobject][ordered]@{status='ENROLLED';idempotent=$true;enrollment=$completed;context=$context}
        }
        if($existingStatus -ne 'ENROLLED'){throw "Unsupported Desktop Thinker enrollment status '$existingStatus'."}
        $loc=& $Backend.LocateConversation $context ([string]$existing.conversation_proof_text) $existing
        if([string]$loc.conversation_fingerprint_sha256 -ne [string]$existing.conversation_fingerprint_sha256){throw 'Desktop Thinker conversation fingerprint changed; enrollment is stale.'}
        return [pscustomobject][ordered]@{status='ENROLLED';idempotent=$true;enrollment=$existing;context=$context}
    }
    if($context.window_is_minimized -or -not[bool]$context.window_is_foreground){$context=& $Backend.FocusConversation $context ([pscustomobject]@{})}
    $marker='AIDOS_THINKER_TRANSPORT_ENROLLMENT::'+[guid]::NewGuid().ToString()
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $pending=[pscustomobject][ordered]@{schema_version='0.2';transport_type='DESKTOP_CHATGPT_THINKER';status='PENDING_ENROLLMENT';process_name=[string]$context.process_name;session_id=[string]$context.session_id;window_title=[string]$context.window_title;window_class_name=[string]$context.window_class_name;conversation_proof_text=$marker;conversation_fingerprint_sha256=$null;conversation_fingerprint=$null;created_at=$now;enrolled_at=$null;updated_at=$now}
    Write-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -Enrollment $pending|Out-Null
    $prompt=$marker+"`nThis is a transport enrollment marker for the AIDOS dedicated Thinker shell. Reply with exactly: AIDOS_THINKER_ENROLLMENT_ACK"
    & $Backend.SendPrompt $context $pending $prompt
    $loc=$null
    for($attempt=0;$attempt-lt20;$attempt++){
        try{$loc=& $Backend.LocateConversation $context $marker $pending}catch{$loc=$null}
        if($loc){break};Start-Sleep -Milliseconds 250
    }
    if(-not $loc){return [pscustomobject][ordered]@{status='PENDING_ENROLLMENT';idempotent=$false;enrollment=$pending;context=$context}}
    $completed=Complete-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -Enrollment $pending -Location $loc
    [pscustomobject][ordered]@{status='ENROLLED';idempotent=$false;enrollment=$completed;context=$context}
}

function Get-AidosDesktopThinkerAuthorizedDocuments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$BoundAssignment,[int]$MaximumDocumentBytes=131072,[int]$MaximumTotalBytes=786432)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $assignment=$BoundAssignment.assignment
    if($null-eq$assignment){throw 'Thinker source pack requires a bound runtime actor assignment.'}
    $paths=[System.Collections.Generic.List[string]]::new()
    foreach($relative in @('.aidos/PROJECT.json','.aidos/documentation/PROJECT_BASELINE.json','.aidos/documentation/PROJECT_ACCESS.json','.aidos/evidence/EVIDENCE_INVENTORY.json','AGENTS.md')){
        if(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf){$paths.Add($relative)}
    }
    $docsRoot=Join-Path $root 'docs'
    if(Test-Path -LiteralPath $docsRoot -PathType Container){foreach($file in @(Get-ChildItem -LiteralPath $docsRoot -Filter '*.md' -File|Sort-Object Name)){$paths.Add([IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/'))}}

    $definitionId=[string]$assignment.binding.definition_id
    $definitionVersion=if($null-eq$assignment.binding.definition_version){$null}else{[int]$assignment.binding.definition_version}
    if(-not[string]::IsNullOrWhiteSpace($definitionId) -and $null-ne$definitionVersion){
        $projectApplicability='.aidos/profile/PROJECT_APPLICABILITY.json'
        if(Test-Path -LiteralPath (Join-Path $root $projectApplicability) -PathType Leaf){$paths.Add($projectApplicability)}
        $definitionRelative=('.aidos/definitions/{0}/v{1}' -f $definitionId,$definitionVersion)
        foreach($name in @('APPLICABILITY.json','PROGRESS.json')){
            $relative="$definitionRelative/$name"
            if(-not(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)){throw "Bound Definition source is missing: $relative"}
            $paths.Add($relative)
        }
        $decisionsRoot=Join-Path $root "$definitionRelative/decisions"
        if(Test-Path -LiteralPath $decisionsRoot -PathType Container){foreach($file in @(Get-ChildItem -LiteralPath $decisionsRoot -Filter '*.json' -File|Sort-Object Name)){$paths.Add([IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/'))}}
        $humanRoot=Join-Path $root '.aidos/human-input'
        if(Test-Path -LiteralPath $humanRoot -PathType Container){
            foreach($file in @(Get-ChildItem -LiteralPath $humanRoot -Filter '*.json' -File|Sort-Object Name)){
                try{$request=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100}catch{continue}
                if([string]$request.binding.definition_id -eq $definitionId -and [int]$request.binding.definition_version -eq $definitionVersion){$paths.Add([IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/'))}
            }
        }
    }

    $agentPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'agents/DEFINITION_AGENT.md'
    $documents=[System.Collections.Generic.List[object]]::new();$total=0
    foreach($relative in @($paths|Select-Object -Unique)){
        $path=Join-Path $root $relative;$bytes=[IO.File]::ReadAllBytes($path)
        if($bytes.Length-gt$MaximumDocumentBytes){throw "Thinker source exceeds per-document transport limit: $relative"};$total+=$bytes.Length;if($total-gt$MaximumTotalBytes){throw 'Thinker source pack exceeds total transport limit.'}
        $text=[Text.Encoding]::UTF8.GetString($bytes);if($text.IndexOf([char]0)-ge0){throw "Thinker source is not UTF-8 text: $relative"}
        if($text-match'(?im)-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|(?:api[_-]?key|access[_-]?token|password|secret|authorization)\s*[:=]\s*\S+'){throw "Thinker source is not secret-free: $relative"}
        $documents.Add([ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();content=$text})
    }
    if(Test-Path -LiteralPath $agentPath -PathType Leaf){$text=Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8;$documents.Insert(0,[ordered]@{path='AIDOS/agents/DEFINITION_AGENT.md';sha256=(Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash.ToLowerInvariant();content=$text})}
    @($documents)
}

function New-AidosDesktopThinkerPrompt {
    param([Parameter(Mandatory)]$BoundAssignment,[Parameter(Mandatory)][object[]]$Documents)
    $assignment=$BoundAssignment.assignment
    if([string]$assignment.action -eq 'RESOLVE_PROJECT_APPLICABILITY'){
        $payload=[ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='';proposed_artifacts=@([ordered]@{artifact_type='PROJECT_APPLICABILITY_PROPOSAL';authority_classification='REPO_VERIFIABLE';preset_ids=@();selection_source='BASELINE_DERIVED';overrides=@();source_refs=@()});human_input_request=$null}
    }else{
        $payload=[ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='';applicability_resolutions=@();surface_resolutions=@();human_input_request=$null}
    }
    $template=[ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$assignment.assignment_id;assignment_sha256=[string]$BoundAssignment.sha256;project_id=[string]$assignment.project_id;actor_role=[string]$assignment.actor_role;actor_identity=[string]$assignment.actor_identity;action=[string]$assignment.action;binding=$assignment.binding;outcome='COMPLETED';result=$payload;responded_at=[DateTimeOffset]::UtcNow.ToString('o')}
    @"
You are the AIDOS Definition Thinker operating under the attached DEFINITION_AGENT instructions.
Use only the immutable runtime actor assignment and authorized source documents below. Do not rely on chat history, hidden filesystem access, or unbound sources.
Do not claim to have written project files. Propose only output permitted by the response template; AIDOS Core will validate authority, persist canonical artifacts, and create Human Input when required.
For START_DEFINITION or RESUME_DEFINITION, return applicability_resolutions and surface_resolutions using the Definition Thinker Output contract. For RESOLVE_PROJECT_APPLICABILITY, return exactly one PROJECT_APPLICABILITY_PROPOSAL inside proposed_artifacts.
Return exactly one raw JSON RUNTIME_ACTOR_RESULT object with no markdown or commentary.
Copy assignment_id, assignment_sha256, project_id, actor_role, actor_identity, action, and binding exactly from the response template.

RUNTIME_ACTOR_ASSIGNMENT:
$($assignment|ConvertTo-Json -Depth 100 -Compress)

AUTHORIZED_SOURCE_DOCUMENTS:
$($Documents|ConvertTo-Json -Depth 100 -Compress)

RUNTIME_ACTOR_RESULT_TEMPLATE:
$($template|ConvertTo-Json -Depth 100 -Compress)
"@
}
function Invoke-AidosDesktopThinkerAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$AssignmentId,
        [Parameter(Mandatory)][string]$StateRoot,
        [string]$ProcessName='ChatGPT Classic',
        [int]$ResponseTimeoutSeconds=5,
        [object]$Backend
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $bound=Read-AidosRuntimeActorAssignment -ProjectRoot $root -AssignmentId $AssignmentId
    $transport=Initialize-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId
    if([string]$transport.status -eq 'COMPLETED'){return [pscustomobject][ordered]@{status='HANDOFF_COMPLETE';idempotent=$true;assignment_id=$AssignmentId;result_ref=[string]$transport.result_ref}}
    if(-not$Backend){$Backend=New-AidosDesktopThinkerWindowsBackend -ProcessName $ProcessName}
    $interactive=$true
    try{& $Backend.AssertInteractiveSession|Out-Null}catch{$interactive=$false}
    if(-not$interactive){$state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError 'WINDOWS_LOCKED_OR_SESSION_UNAVAILABLE';return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;transport=$state}}
    $enrolled=Initialize-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -ProcessName $ProcessName -Backend $Backend
    if([string]$enrolled.status -eq 'PENDING_ENROLLMENT'){$state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError 'THINKER_ENROLLMENT_PROOF_PENDING';return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;enrollment=$enrolled;transport=$state}}
    $context=$enrolled.context;$enrollment=$enrolled.enrollment
    if($context.window_is_minimized -or -not[bool]$context.window_is_foreground){$context=& $Backend.FocusConversation $context $enrollment}
    $loc=& $Backend.LocateConversation $context ([string]$enrollment.conversation_proof_text) $enrollment
    if([string]$loc.conversation_fingerprint_sha256 -ne [string]$enrollment.conversation_fingerprint_sha256){throw 'Desktop Thinker conversation binding mismatch before send.'}
    if([string]$transport.status -notin @('ACTIVATED')){
        $documents=Get-AidosDesktopThinkerAuthorizedDocuments -ProjectRoot $root -BoundAssignment $bound
        $prompt=New-AidosDesktopThinkerPrompt -BoundAssignment $bound -Documents $documents
        & $Backend.SendPrompt $context $enrollment $prompt
        $transport=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status ACTIVATED -TransportType DESKTOP_CHATGPT_THINKER
    }
    $responseText=$null
    for($attempt=0;$attempt-lt$ResponseTimeoutSeconds;$attempt++){
        Start-Sleep -Seconds 1
        if($Backend.PSObject.Properties['ReadActorResponseText']){$responseText=& $Backend.ReadActorResponseText $context $enrollment ($attempt+1) $bound.assignment}else{$responseText=Get-AidosDesktopThinkerResponseText -Context $context -AssignmentId $AssignmentId}
        if(-not[string]::IsNullOrWhiteSpace([string]$responseText)){break}
    }
    if([string]::IsNullOrWhiteSpace([string]$responseText)){return [pscustomobject][ordered]@{status='ACTIVATED';waiting_for_response=$true;assignment_id=$AssignmentId;transport=$transport}}
    $result=ConvertFrom-AidosDesktopChatGPTStrictResponseText -Text $responseText
    $saved=Save-AidosRuntimeActorResult -ProjectRoot $root -Result $result
    [pscustomobject][ordered]@{status='HANDOFF_COMPLETE';idempotent=$false;assignment_id=$AssignmentId;saved=$saved;result=$result}
}

Export-ModuleMember -Function Get-AidosDesktopThinkerRoot,Get-AidosDesktopThinkerEnrollmentPath,Read-AidosDesktopThinkerEnrollment,Write-AidosDesktopThinkerEnrollment,Get-AidosDesktopThinkerResponseText,New-AidosDesktopThinkerStubBackend,New-AidosDesktopThinkerWindowsBackend,Complete-AidosDesktopThinkerEnrollment,Initialize-AidosDesktopThinkerEnrollment,Get-AidosDesktopThinkerAuthorizedDocuments,New-AidosDesktopThinkerPrompt,Invoke-AidosDesktopThinkerAssignment
