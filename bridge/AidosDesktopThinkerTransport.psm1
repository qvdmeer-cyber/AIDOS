Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -DisableNameChecking
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
    param([string]$ResponseText,[bool]$InteractiveSession=$true)
    $state=[pscustomobject]@{send_count=0;last_prompt=$null;proof_text=$null}
    [pscustomobject]@{
        State=$state
        AssertInteractiveSession=({param();if(-not$InteractiveSession){throw 'Windows session unavailable.'};$true}).GetNewClosure()
        GetProcessContext=({param([string]$ProcessName);[pscustomobject]@{present=$true;process_id=42;process_name=$ProcessName;session_id=1;main_window_handle='99';window_handle='99';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$true;window_is_visible=$true;window_source='stub'}}).GetNewClosure()
        FocusConversation=({param($Context,$Enrollment);$Context.window_is_foreground=$true;$Context}).GetNewClosure()
        SendPrompt=({param($Context,$Enrollment,[string]$PromptText);$state.send_count++;$state.last_prompt=$PromptText;if($PromptText -match 'AIDOS_THINKER_TRANSPORT_ENROLLMENT::(?<id>[0-9a-f-]+)'){$state.proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::'+$Matches.id}}).GetNewClosure()
        LocateConversation=({param($Context,[string]$ProofText,$Enrollment);[pscustomobject]@{conversation_fingerprint=[ordered]@{window_title=$Context.window_title;window_class_name=$Context.window_class_name;conversation_proof_text=$ProofText;path=@([ordered]@{name='stub';control_type='Window'})};conversation_fingerprint_sha256=(Get-AidosDesktopChatGPTFingerprintHash ([ordered]@{window_title=$Context.window_title;window_class_name=$Context.window_class_name;conversation_proof_text=$ProofText;path=@([ordered]@{name='stub';control_type='Window'})}))}}).GetNewClosure()
        ReadActorResponseText=({param($Context,$Enrollment,[int]$Attempt,$Assignment);if($state.send_count-lt1){return $null};$ResponseText}).GetNewClosure()
    }
}
function Initialize-AidosDesktopThinkerEnrollment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[string]$ProcessName='ChatGPT Classic',[object]$Backend)
    $existing=Read-AidosDesktopThinkerEnrollment -StateRoot $StateRoot
    if(-not$Backend){$Backend=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName}
    & $Backend.AssertInteractiveSession|Out-Null
    $context=& $Backend.GetProcessContext $ProcessName
    if(-not$context -or -not$context.present){throw 'ChatGPT process/window is unavailable for Thinker enrollment.'}
    if($existing){
        if([string]$existing.process_name -ne [string]$context.process_name -or [string]$existing.session_id -ne [string]$context.session_id -or [string]$existing.window_title -ne [string]$context.window_title -or [string]$existing.window_class_name -ne [string]$context.window_class_name){throw 'Desktop Thinker shell binding changed; enrollment is stale.'}
        $loc=& $Backend.LocateConversation $context ([string]$existing.conversation_proof_text) $existing
        if([string]$loc.conversation_fingerprint_sha256 -ne [string]$existing.conversation_fingerprint_sha256){throw 'Desktop Thinker conversation fingerprint changed; enrollment is stale.'}
        return [pscustomobject][ordered]@{status='ENROLLED';idempotent=$true;enrollment=$existing;context=$context}
    }
    if($context.window_is_minimized -or -not[bool]$context.window_is_foreground){$context=& $Backend.FocusConversation $context ([pscustomobject]@{})}
    $marker='AIDOS_THINKER_TRANSPORT_ENROLLMENT::'+[guid]::NewGuid().ToString()
    $prompt=$marker+"`nThis is a transport enrollment marker for the AIDOS dedicated Thinker shell. Reply with exactly: AIDOS_THINKER_ENROLLMENT_ACK"
    & $Backend.SendPrompt $context ([pscustomobject]@{}) $prompt
    $loc=$null
    for($attempt=0;$attempt-lt20;$attempt++){
        try{$loc=& $Backend.LocateConversation $context $marker ([pscustomobject]@{})}catch{$loc=$null}
        if($loc){break};Start-Sleep -Milliseconds 250
    }
    if(-not$loc){throw 'Unable to prove the Thinker conversation after enrollment marker send.'}
    $now=[DateTimeOffset]::UtcNow.ToString('o')
    $enrollment=[ordered]@{schema_version='0.1';transport_type='DESKTOP_CHATGPT_THINKER';process_name=[string]$context.process_name;session_id=[string]$context.session_id;window_title=[string]$context.window_title;window_class_name=[string]$context.window_class_name;conversation_proof_text=$marker;conversation_fingerprint_sha256=[string]$loc.conversation_fingerprint_sha256;conversation_fingerprint=$loc.conversation_fingerprint;enrolled_at=$now;updated_at=$now}
    Write-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -Enrollment $enrollment|Out-Null
    [pscustomobject][ordered]@{status='ENROLLED';idempotent=$false;enrollment=[pscustomobject]$enrollment;context=$context}
}
function Get-AidosDesktopThinkerAuthorizedDocuments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[int]$MaximumDocumentBytes=131072,[int]$MaximumTotalBytes=786432)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $paths=[System.Collections.Generic.List[string]]::new()
    foreach($relative in @('.aidos/PROJECT.json','.aidos/documentation/PROJECT_BASELINE.json','.aidos/documentation/PROJECT_ACCESS.json','.aidos/evidence/EVIDENCE_INVENTORY.json','AGENTS.md')){
        if(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf){$paths.Add($relative)}
    }
    $docsRoot=Join-Path $root 'docs'
    if(Test-Path -LiteralPath $docsRoot -PathType Container){foreach($file in @(Get-ChildItem -LiteralPath $docsRoot -Filter '*.md' -File|Sort-Object Name)){$paths.Add([IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/'))}}
    $agentPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'agents/DEFINITION_AGENT.md'
    $documents=[System.Collections.Generic.List[object]]::new();$total=0
    foreach($relative in $paths){
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
    $template=[ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$assignment.assignment_id;assignment_sha256=[string]$BoundAssignment.sha256;project_id=[string]$assignment.project_id;actor_role=[string]$assignment.actor_role;actor_identity=[string]$assignment.actor_identity;action=[string]$assignment.action;binding=$assignment.binding;outcome='COMPLETED';result=[ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='';proposed_artifacts=@();human_input_request=$null};responded_at=[DateTimeOffset]::UtcNow.ToString('o')}
    @"
You are the AIDOS Definition Thinker operating under the attached DEFINITION_AGENT instructions.
Use only the immutable runtime actor assignment and authorized source documents below. Do not rely on chat history, hidden filesystem access, or unbound sources.
Do not claim to have written project files. Propose durable artifacts or a Human Input Request inside result; AIDOS Core will validate and persist them.
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
    if([string]$transport.status -eq 'COMPLETED'){
        return [pscustomobject][ordered]@{status='HANDOFF_COMPLETE';idempotent=$true;assignment_id=$AssignmentId;result_ref=[string]$transport.result_ref}
    }
    if(-not$Backend){$Backend=New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName}
    $interactive=$true
    try{& $Backend.AssertInteractiveSession|Out-Null}catch{$interactive=$false}
    if(-not$interactive){$state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError 'WINDOWS_LOCKED_OR_SESSION_UNAVAILABLE';return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;transport=$state}}
    $enrolled=Initialize-AidosDesktopThinkerEnrollment -StateRoot $StateRoot -ProcessName $ProcessName -Backend $Backend
    $context=$enrolled.context;$enrollment=$enrolled.enrollment
    if($context.window_is_minimized -or -not[bool]$context.window_is_foreground){$context=& $Backend.FocusConversation $context $enrollment}
    $loc=& $Backend.LocateConversation $context ([string]$enrollment.conversation_proof_text) $enrollment
    if([string]$loc.conversation_fingerprint_sha256 -ne [string]$enrollment.conversation_fingerprint_sha256){throw 'Desktop Thinker conversation binding mismatch before send.'}
    if([string]$transport.status -notin @('ACTIVATED')){
        $documents=Get-AidosDesktopThinkerAuthorizedDocuments -ProjectRoot $root
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

Export-ModuleMember -Function Get-AidosDesktopThinkerRoot,Get-AidosDesktopThinkerEnrollmentPath,Read-AidosDesktopThinkerEnrollment,Write-AidosDesktopThinkerEnrollment,Get-AidosDesktopThinkerResponseText,New-AidosDesktopThinkerStubBackend,Initialize-AidosDesktopThinkerEnrollment,Get-AidosDesktopThinkerAuthorizedDocuments,New-AidosDesktopThinkerPrompt,Invoke-AidosDesktopThinkerAssignment
