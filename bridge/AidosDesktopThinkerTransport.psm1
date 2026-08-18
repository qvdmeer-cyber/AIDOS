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
function Get-AidosDesktopThinkerComposerStatePath {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$AssignmentId)
    Join-Path (Join-Path (Get-AidosDesktopThinkerRoot -StateRoot $StateRoot) 'composer') ($AssignmentId+'.json')
}
function Get-AidosDesktopThinkerPromptHash { param([Parameter(Mandatory)][string]$Prompt) [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Prompt))).ToLowerInvariant() }
function Read-AidosDesktopThinkerComposerState {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$AssignmentId)
    $path=Get-AidosDesktopThinkerComposerStatePath -StateRoot $StateRoot -AssignmentId $AssignmentId
    if(Test-Path -LiteralPath $path -PathType Leaf){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50}else{$null}
}
function Write-AidosDesktopThinkerComposerState {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$State)
    $path=Get-AidosDesktopThinkerComposerStatePath -StateRoot $StateRoot -AssignmentId ([string]$State.assignment_id)
    $dir=Split-Path -Parent $path;if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Write-AidosJsonAtomic $path $State;$State
}
function Get-AidosDesktopThinkerComposerObservation {
    param(
        [Parameter(Mandatory)]$Backend,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Enrollment,
        [Parameter(Mandatory)][string]$ExpectedPrompt
    )
    if($Backend.PSObject.Properties['InspectComposer']){
        $inspection=& $Backend.InspectComposer $Context $Enrollment
    } else {
        if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){ throw 'ChatGPT window is not present.' }
        $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
        if(-not $root){ throw 'ChatGPT window is not accessible through UI Automation.' }
        $composer=Get-AidosDesktopChatGPTComposerElement $root
        $text=Get-AidosDesktopChatGPTElementText $composer
        $inspection=[pscustomobject]@{present=$true;composer_text=$text;composer_text_sha256=if([string]::IsNullOrWhiteSpace([string]$text)){$null}else{Get-AidosDesktopChatGPTTextSha256 $text};composer_text_length=if([string]::IsNullOrWhiteSpace([string]$text)){0}else{([string]$text).Length}}
    }
    $text=[string]$inspection.composer_text
    $textSha=if([string]::IsNullOrWhiteSpace($text)){$null}else{if($inspection.PSObject.Properties['composer_text_sha256']){[string]$inspection.composer_text_sha256}else{Get-AidosDesktopThinkerPromptHash -Prompt $text}}
    $textLength=if($inspection.PSObject.Properties['composer_text_length']){[int]$inspection.composer_text_length}else{if([string]::IsNullOrWhiteSpace($text)){0}else{$text.Length}}
    $promptMatches=if([string]::IsNullOrWhiteSpace($ExpectedPrompt)){0}else{[regex]::Matches($text,[regex]::Escape($ExpectedPrompt)).Count}
    $result=if([string]::IsNullOrWhiteSpace($text)){'EMPTY'}elseif($text -eq $ExpectedPrompt){'MATCHING_EXACT'}elseif($promptMatches -gt 1){'DUPLICATE'}else{'MISMATCH'}
    [pscustomobject]@{
        schema_version='0.1'
        present=[bool]$inspection.present
        composer_text_sha256=$textSha
        composer_text_length=$textLength
        composer_result=$result
        exact_bound_composer=($result -eq 'MATCHING_EXACT')
        duplicate_payload=($result -eq 'DUPLICATE')
        mutation_occurred=$false
        send_invocation_state='NOT_INVOKED'
        committed_message_proof_state='NOT_PROVEN'
        failure_reason=$null
    }
}
function Test-AidosDesktopThinkerSendResultContract {
    param([Parameter(Mandatory)]$Result)
    foreach($name in @('schema_version','assignment_id','assignment_sha256','conversation_fingerprint_sha256','composer_state','composer_result','mutation_occurred','send_invocation_state','committed_message_proof_state','failure_reason','committed')){
        if(-not $Result.PSObject.Properties[$name]){throw "Thinker send result contract is missing '$name'."}
    }
    if([string]$Result.schema_version -ne '0.1'){throw 'Thinker send result contract schema_version mismatch.'}
    if([string]::IsNullOrWhiteSpace([string]$Result.send_invocation_state)){throw 'Thinker send result contract requires a send_invocation_state.'}
    if([string]::IsNullOrWhiteSpace([string]$Result.committed_message_proof_state)){throw 'Thinker send result contract requires a committed_message_proof_state.'}
    if([string]::IsNullOrWhiteSpace([string]$Result.composer_state)){throw 'Thinker send result contract requires a composer_state.'}
    if([string]::IsNullOrWhiteSpace([string]$Result.composer_result)){throw 'Thinker send result contract requires a composer_result.'}
    if([string]::IsNullOrWhiteSpace([string]$Result.assignment_id)){throw 'Thinker send result contract requires assignment_id.'}
    if([string]::IsNullOrWhiteSpace([string]$Result.assignment_sha256)){throw 'Thinker send result contract requires assignment_sha256.'}
    if([string]::IsNullOrWhiteSpace([string]$Result.conversation_fingerprint_sha256)){throw 'Thinker send result contract requires conversation_fingerprint_sha256.'}
    if($Result.committed -isnot [bool]){throw 'Thinker send result contract requires a boolean committed flag.'}
    [pscustomobject]@{
        schema_version=[string]$Result.schema_version
        assignment_id=[string]$Result.assignment_id
        assignment_sha256=[string]$Result.assignment_sha256
        conversation_fingerprint_sha256=[string]$Result.conversation_fingerprint_sha256
        composer_state=[string]$Result.composer_state
        composer_result=[string]$Result.composer_result
        mutation_occurred=[bool]$Result.mutation_occurred
        send_invocation_state=[string]$Result.send_invocation_state
        committed_message_proof_state=[string]$Result.committed_message_proof_state
        failure_reason=if($null -eq $Result.failure_reason){$null}else{[string]$Result.failure_reason}
        committed=[bool]$Result.committed
    }
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
function ConvertTo-AidosDesktopThinkerPromptProofText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if($null-eq$Text){return ''}
    ([string]$Text).Replace("`r`n","`n").Replace("`r","`n").Trim()
}
function Get-AidosDesktopThinkerCommittedPromptProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Enrollment,
        [Parameter(Mandatory)]$BoundAssignment,
        [Parameter(Mandatory)][string]$ExpectedPrompt
    )
    $assignment=$BoundAssignment.assignment
    if($null-eq$assignment){throw 'Committed Thinker prompt proof requires a bound runtime actor assignment.'}
    $assignmentId=[string]$assignment.assignment_id
    $assignmentSha=[string]$BoundAssignment.sha256
    if([string]::IsNullOrWhiteSpace($assignmentId)-or[string]::IsNullOrWhiteSpace($assignmentSha)){throw 'Committed Thinker prompt proof requires assignment identity and hash.'}
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw 'ChatGPT window is not present for committed prompt proof.'}
    if(-not ('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not$root){throw 'ChatGPT window is not accessible through UI Automation for committed prompt proof.'}
    $normalizedPrompt=ConvertTo-AidosDesktopThinkerPromptProofText -Text $ExpectedPrompt
    $requiredFragments=[ordered]@{
        runtime_assignment_heading='RUNTIME_ACTOR_ASSIGNMENT:'
        authorized_documents_heading='AUTHORIZED_SOURCE_DOCUMENTS:'
        result_template_heading='RUNTIME_ACTOR_RESULT_TEMPLATE:'
        assignment_id=$assignmentId
        assignment_sha256=$assignmentSha
    }
    $texts=[System.Collections.Generic.List[string]]::new()
    $proofState='NOT_PROVEN'
    $proofSource='BOUND_PROMPT_NOT_VISIBLE_IN_ENROLLED_CONVERSATION'
    foreach($element in @($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition))){
        try {
            if([string]$element.Current.AutomationId -eq 'prompt-textarea'){continue}
            $text=Get-AidosDesktopChatGPTElementText $element
        } catch {continue}
        if([string]::IsNullOrWhiteSpace([string]$text)){continue}
        $normalized=ConvertTo-AidosDesktopThinkerPromptProofText -Text ([string]$text)
        if([string]::IsNullOrWhiteSpace($normalized)){continue}
        $texts.Add($normalized)
        if(-not[string]::IsNullOrWhiteSpace($normalizedPrompt) -and $normalized.IndexOf($normalizedPrompt,[StringComparison]::Ordinal)-ge0){
            $proofState='PROVEN'
            $proofSource='EXACT_BOUND_PROMPT_VISIBLE_IN_ENROLLED_CONVERSATION'
            break
        }
        $resolvedResponseVisible=(
            $normalized.IndexOf('RUNTIME_ACTOR_RESULT',[StringComparison]::OrdinalIgnoreCase)-ge0 -and
            $normalized.IndexOf($assignmentId,[StringComparison]::OrdinalIgnoreCase)-ge0 -and
            $normalized.IndexOf($assignmentSha,[StringComparison]::OrdinalIgnoreCase)-ge0 -and
            $normalized.IndexOf('REQUIRED:',[StringComparison]::OrdinalIgnoreCase)-lt0 -and
            $normalized.IndexOf('REQUIRED_NONEMPTY:',[StringComparison]::OrdinalIgnoreCase)-lt0
        )
        if($resolvedResponseVisible){
            $proofState='PROVEN'
            $proofSource='BOUND_ACTOR_RESPONSE_VISIBLE_IN_ENROLLED_CONVERSATION'
            break
        }
    }
    $missing=[System.Collections.Generic.List[string]]::new()
    if($proofState-ne'PROVEN'){
        $aggregate=[string]::Join("`n",@($texts))
        foreach($name in @($requiredFragments.Keys)){
            $fragment=[string]$requiredFragments[$name]
            if($aggregate.IndexOf($fragment,[StringComparison]::OrdinalIgnoreCase)-lt0){$missing.Add([string]$name)}
        }
        if($missing.Count-eq0){
            $proofState='PROVEN'
            $proofSource='BOUND_PROMPT_FRAGMENTS_VISIBLE_IN_ENROLLED_CONVERSATION'
        }
    }
    [pscustomobject][ordered]@{
        schema_version='0.1'
        assignment_id=$assignmentId
        assignment_sha256=$assignmentSha
        conversation_fingerprint_sha256=[string]$Enrollment.conversation_fingerprint_sha256
        prompt_sha256=Get-AidosDesktopThinkerPromptHash -Prompt $ExpectedPrompt
        proof_state=$proofState
        proof_source=$proofSource
        missing_fragments=@($missing)
    }
}
function Test-AidosDesktopThinkerCommittedPromptProofContract {
    param([Parameter(Mandatory)]$Result)
    foreach($name in @('schema_version','assignment_id','assignment_sha256','conversation_fingerprint_sha256','prompt_sha256','proof_state','proof_source','missing_fragments')){
        if(-not $Result.PSObject.Properties[$name]){throw "Committed Thinker prompt proof contract is missing '$name'."}
    }
    if([string]$Result.schema_version-ne'0.1'){throw 'Committed Thinker prompt proof schema_version mismatch.'}
    if([string]$Result.proof_state-notin@('PROVEN','NOT_PROVEN')){throw 'Committed Thinker prompt proof state is invalid.'}
    foreach($name in @('assignment_id','assignment_sha256','conversation_fingerprint_sha256','prompt_sha256','proof_source')){
        if([string]::IsNullOrWhiteSpace([string]$Result.$name)){throw "Committed Thinker prompt proof requires '$name'."}
    }
    [pscustomobject][ordered]@{
        schema_version=[string]$Result.schema_version
        assignment_id=[string]$Result.assignment_id
        assignment_sha256=[string]$Result.assignment_sha256
        conversation_fingerprint_sha256=[string]$Result.conversation_fingerprint_sha256
        prompt_sha256=[string]$Result.prompt_sha256
        proof_state=[string]$Result.proof_state
        proof_source=[string]$Result.proof_source
        missing_fragments=@($Result.missing_fragments)
    }
}
function New-AidosDesktopThinkerStubBackend {
    param([string]$ResponseText,[bool]$InteractiveSession=$true,[bool]$ConversationProofAvailable=$true)
    $state=[pscustomobject]@{send_count=0;last_prompt=$null;proof_text=$null;composer_text=$null;successful_commit_count=0}
    [pscustomobject]@{
        State=$state
        AssertInteractiveSession=({param();if(-not$InteractiveSession){throw 'Windows session unavailable.'};$true}).GetNewClosure()
        GetProcessContext=({param([string]$ProcessName);[pscustomobject]@{present=$true;process_id=42;process_name=$ProcessName;session_id=1;main_window_handle='99';window_handle='99';window_title='ChatGPT Classic';window_class_name='Chrome_WidgetWin_1';window_is_minimized=$false;window_is_foreground=$true;window_is_visible=$true;window_source='stub'}}).GetNewClosure()
        FocusConversation=({param($Context,$Enrollment);$Context.window_is_foreground=$true;$Context}).GetNewClosure()
        InspectComposer=({param($Context,$Enrollment);[pscustomobject]@{present=$true;composer_text=$state.composer_text;composer_text_sha256=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){$null}else{[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$state.composer_text))).ToLowerInvariant()};composer_text_length=if([string]::IsNullOrWhiteSpace([string]$state.composer_text)){0}else{([string]$state.composer_text).Length}}}).GetNewClosure()
        SendPrompt=({param($Context,$Enrollment,[string]$PromptText,$Assignment);$state.send_count++;$isEnrollmentMarker=([string]$PromptText).IndexOf('AIDOS_THINKER_TRANSPORT_ENROLLMENT::',[StringComparison]::OrdinalIgnoreCase) -ge 0;$before=[string]$state.composer_text;$mutationOccurred=(-not $isEnrollmentMarker -and ([string]::IsNullOrWhiteSpace($before) -or $before -ne [string]$PromptText));if($mutationOccurred){$state.composer_text=$PromptText};$state.last_prompt=$PromptText;if($isEnrollmentMarker -and $PromptText -match 'AIDOS_THINKER_TRANSPORT_ENROLLMENT::(?<id>[0-9a-f-]+)'){$state.proof_text='AIDOS_THINKER_TRANSPORT_ENROLLMENT::'+$Matches.id};$state.successful_commit_count++;[pscustomobject]@{schema_version='0.1';assignment_id=if($Assignment -and $Assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment_id}elseif($Assignment -and $Assignment.PSObject.Properties['assignment'] -and $Assignment.assignment.PSObject.Properties['assignment_id']){[string]$Assignment.assignment.assignment_id}else{$null};assignment_sha256=if($Assignment -and $Assignment.PSObject.Properties['assignment_sha256']){[string]$Assignment.assignment_sha256}elseif($Assignment -and $Assignment.PSObject.Properties['sha256']){[string]$Assignment.sha256}else{$null};conversation_fingerprint_sha256=if($Enrollment){[string]$Enrollment.conversation_fingerprint_sha256}else{$null};composer_state='COMMITTED';composer_result=if($isEnrollmentMarker){'EMPTY'}elseif([string]::IsNullOrWhiteSpace($before)){'EMPTY'}elseif($before -eq [string]$PromptText){'MATCHING_EXACT'}elseif(($before).IndexOf($PromptText,[StringComparison]::Ordinal) -ge 0){'DUPLICATE'}else{'MISMATCH'};mutation_occurred=$mutationOccurred;send_invocation_state='INVOKED';committed_message_proof_state='PROVEN';failure_reason=$null;committed=$true}}).GetNewClosure()
        LocateConversation=({
            param($Context,[string]$ProofText,$Enrollment)
            if(-not$ConversationProofAvailable){throw 'Stub Thinker conversation proof is unavailable.'}
            if([string]::IsNullOrWhiteSpace([string]$state.proof_text) -or [string]$state.proof_text -ne $ProofText){throw 'Stub Thinker conversation proof is not present.'}
            $fingerprint=[ordered]@{window_title=$Context.window_title;window_class_name=$Context.window_class_name;conversation_proof_text=$ProofText;path=@([ordered]@{name='stub';control_type='Window'})}
            $json=$fingerprint|ConvertTo-Json -Depth 100 -Compress
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
            [pscustomobject]@{conversation_fingerprint=$fingerprint;conversation_fingerprint_sha256=$hash}
        }).GetNewClosure()
        ReadActorResponseText=({param($Context,$Enrollment,[int]$Attempt,$Assignment);if($state.successful_commit_count-lt1){return $null};$ResponseText}).GetNewClosure()
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
    # Enrollment has its own completion proof below. Never leak the composer
    # send-result contract into this function's enrollment-result contract.
    $null=& $Backend.SendPrompt $context $pending $prompt
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
    # Accepted Project Baselines are authoritative Thinker inputs and can exceed
    # 128 KiB. Keep the bounded source pack while allowing one full baseline.
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$BoundAssignment,[int]$MaximumDocumentBytes=262144,[int]$MaximumTotalBytes=786432)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $assignment=$BoundAssignment.assignment
    if($null-eq$assignment){throw 'Thinker source pack requires a bound runtime actor assignment.'}
    $paths=[System.Collections.Generic.List[string]]::new()
    $isApplicability=[string]$assignment.action -eq 'RESOLVE_PROJECT_APPLICABILITY'
    # Applicability is derived from canonical product evidence. The accepted
    # baseline is an index of that evidence, not a desktop-chat payload.
    foreach($relative in @('.aidos/PROJECT.json','.aidos/documentation/PROJECT_ACCESS.json','.aidos/evidence/EVIDENCE_INVENTORY.json','AGENTS.md')){
        if(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf){$paths.Add($relative)}
    }
    $docsRoot=Join-Path $root 'docs'
    if(Test-Path -LiteralPath $docsRoot -PathType Container){foreach($file in @(Get-ChildItem -LiteralPath $docsRoot -Filter '*.md' -File|Sort-Object Name)){$paths.Add([IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/'))}}

    if($isApplicability){
        $catalogPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog/profile-presets.catalog.json'
        if(-not(Test-Path -LiteralPath $catalogPath -PathType Leaf)){throw 'Authoritative profile preset catalog is unavailable.'}
    }
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
    if($isApplicability){
        $catalogPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog/profile-presets.catalog.json'
        $bytes=[IO.File]::ReadAllBytes($catalogPath);if($bytes.Length-gt$MaximumDocumentBytes){throw 'Profile preset catalog exceeds per-document transport limit.'};$total+=$bytes.Length;if($total-gt$MaximumTotalBytes){throw 'Thinker source pack exceeds total transport limit.'}
        $documents.Add([ordered]@{path='AIDOS/catalog/profile-presets.catalog.json';sha256=(Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash.ToLowerInvariant();content=[Text.Encoding]::UTF8.GetString($bytes)})
    }
    if(Test-Path -LiteralPath $agentPath -PathType Leaf){$text=Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8;$documents.Insert(0,[ordered]@{path='AIDOS/agents/DEFINITION_AGENT.md';sha256=(Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash.ToLowerInvariant();content=$text})}
    @($documents)
}

function New-AidosDesktopThinkerPrompt {
    param([Parameter(Mandatory)]$BoundAssignment,[Parameter(Mandatory)][object[]]$Documents)
    $assignment=$BoundAssignment.assignment
    $allowedRefs=@()
    if([string]$assignment.action -eq 'RESOLVE_PROJECT_APPLICABILITY'){
        $allowedRefs=@($Documents|ForEach-Object {[string]$_.path}|Where-Object {$_ -notlike 'AIDOS/*' -and ($_ -eq '.aidos/documentation/PROJECT_ACCESS.json' -or $_ -eq '.aidos/evidence/EVIDENCE_INVENTORY.json' -or $_ -eq 'AGENTS.md' -or $_.StartsWith('docs/'))})
        $payload=[ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='REQUIRED: concise evidence-based applicability rationale';proposed_artifacts=@([ordered]@{artifact_type='PROJECT_APPLICABILITY_PROPOSAL';authority_classification='REPO_VERIFIABLE';preset_ids='REQUIRED_NONEMPTY: exact preset_id values from AIDOS/catalog/profile-presets.catalog.json';selection_source='BASELINE_DERIVED';overrides=@();source_refs='REQUIRED_NONEMPTY: only paths from ALLOWED_SOURCE_REFS'});human_input_request=$null}
    }else{
        $payload=[ordered]@{result_type='DEFINITION_THINKER_OUTPUT';summary='';applicability_resolutions=@();surface_resolutions=@();human_input_request=$null}
    }
    $template=[ordered]@{schema_version='0.1';envelope_type='RUNTIME_ACTOR_RESULT';assignment_id=[string]$assignment.assignment_id;assignment_sha256=[string]$BoundAssignment.sha256;project_id=[string]$assignment.project_id;actor_role=[string]$assignment.actor_role;actor_identity=[string]$assignment.actor_identity;action=[string]$assignment.action;binding=$assignment.binding;outcome='COMPLETED';result=$payload;responded_at='REQUIRED: ISO-8601 completion timestamp'}
    @"
You are the AIDOS Definition Thinker operating under the attached DEFINITION_AGENT instructions.
Use only the immutable runtime actor assignment and authorized source documents below. Do not rely on chat history, hidden filesystem access, or unbound sources.
Do not claim to have written project files. Propose only output permitted by the response template; AIDOS Core will validate authority, persist canonical artifacts, and create Human Input when required.
For START_DEFINITION or RESUME_DEFINITION, return applicability_resolutions and surface_resolutions using the Definition Thinker Output contract. For RESOLVE_PROJECT_APPLICABILITY, return exactly one PROJECT_APPLICABILITY_PROPOSAL inside proposed_artifacts. Replace every REQUIRED_* template value with a schema-correct resolved value; never return an empty preset_ids or source_refs array. Choose preset_ids only from the authoritative attached profile catalog and source_refs only from ALLOWED_SOURCE_REFS.
Return exactly one raw JSON RUNTIME_ACTOR_RESULT object with no markdown or commentary.
Copy assignment_id, assignment_sha256, project_id, actor_role, actor_identity, action, and binding exactly from the response template.

RUNTIME_ACTOR_ASSIGNMENT:
$($assignment|ConvertTo-Json -Depth 100 -Compress)

AUTHORIZED_SOURCE_DOCUMENTS:
$($Documents|ConvertTo-Json -Depth 100 -Compress)

ALLOWED_SOURCE_REFS:
$($allowedRefs|ConvertTo-Json -Compress)

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
        $promptHash=Get-AidosDesktopThinkerPromptHash -Prompt $prompt
        $composer=Read-AidosDesktopThinkerComposerState -StateRoot $StateRoot -AssignmentId $AssignmentId
        $observation=Get-AidosDesktopThinkerComposerObservation -Backend $Backend -Context $context -Enrollment $enrollment -ExpectedPrompt $prompt
        if($composer -and [string]$composer.assignment_sha256 -ne [string]$bound.sha256){throw 'Composer assignment binding mismatch.'}
        if($composer -and [string]$composer.conversation_fingerprint_sha256 -ne [string]$enrollment.conversation_fingerprint_sha256){throw 'Composer conversation binding mismatch.'}
        if($composer -and [string]$composer.prompt_sha256 -ne $promptHash){
            $composer.composer_state='FAILED'
            $composer.composer_result=$observation.composer_result
            $composer.observed_composer_text_sha256=$observation.composer_text_sha256
            $composer.observed_composer_text_length=$observation.composer_text_length
            $composer.failure_reason='Exact bound composer contains a different staged payload; refusing mutation.'
            $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
            $state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError $composer.failure_reason
            return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;composer=$composer;transport=$state}
        }
        if(-not $composer){
            $composer=[pscustomobject][ordered]@{
                schema_version='0.1'
                assignment_id=$AssignmentId
                assignment_sha256=[string]$bound.sha256
                conversation_fingerprint_sha256=[string]$enrollment.conversation_fingerprint_sha256
                binding_project_state=[string]$bound.assignment.binding.project_state
                binding_definition_id=if([string]::IsNullOrWhiteSpace([string]$bound.assignment.binding.definition_id)){$null}else{[string]$bound.assignment.binding.definition_id}
                binding_definition_version=if($null -eq $bound.assignment.binding.definition_version){$null}else{[int]$bound.assignment.binding.definition_version}
                prompt_sha256=$promptHash
                observed_composer_text_sha256=$observation.composer_text_sha256
                observed_composer_text_length=$observation.composer_text_length
                composer_result=$observation.composer_result
                composer_state=if($observation.composer_result -eq 'EMPTY'){'STAGED'}elseif($observation.composer_result -eq 'MATCHING_EXACT'){'STAGED'}else{'FAILED'}
                mutation_occurred=($observation.composer_result -eq 'EMPTY')
                send_invocation_state='NOT_INVOKED'
                committed_message_proof_state='NOT_PROVEN'
                failure_reason=$null
                updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            }
            Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
        } else {
            $composer.observed_composer_text_sha256=$observation.composer_text_sha256
            $composer.observed_composer_text_length=$observation.composer_text_length
            $composer.composer_result=$observation.composer_result
            $composer.mutation_occurred=([bool]$composer.mutation_occurred -or $observation.composer_result -eq 'EMPTY')
            $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
        }
        if($observation.composer_result -in @('MISMATCH','DUPLICATE')){
            $composer.composer_state='FAILED'
            $composer.committed_message_proof_state='NOT_PROVEN'
            $composer.failure_reason='Bound composer contents are stale, malformed, or duplicated; recovery requires an exact staged payload.'
            $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
            $state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError $composer.failure_reason
            return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;composer=$composer;transport=$state}
        }
        if([string]$composer.send_invocation_state -eq 'FAILED' -and $observation.composer_result -eq 'EMPTY'){
            $proof=$null;$proofError=$null
            try {
                $rawProof=if($Backend.PSObject.Properties['ProveCommittedPrompt']){& $Backend.ProveCommittedPrompt $context $enrollment $bound $prompt}else{Get-AidosDesktopThinkerCommittedPromptProof -Context $context -Enrollment $enrollment -BoundAssignment $bound -ExpectedPrompt $prompt}
                $proof=Test-AidosDesktopThinkerCommittedPromptProofContract -Result $rawProof
                if([string]$proof.assignment_id-ne$AssignmentId){throw 'Committed Thinker prompt proof assignment_id mismatch.'}
                if([string]$proof.assignment_sha256-ne[string]$bound.sha256){throw 'Committed Thinker prompt proof assignment_sha256 mismatch.'}
                if([string]$proof.conversation_fingerprint_sha256-ne[string]$enrollment.conversation_fingerprint_sha256){throw 'Committed Thinker prompt proof conversation binding mismatch.'}
                if([string]$proof.prompt_sha256-ne$promptHash){throw 'Committed Thinker prompt proof prompt_sha256 mismatch.'}
            } catch {$proofError=$_.Exception.Message;$proof=$null}
            if($proof -and [string]$proof.proof_state-eq'PROVEN'){
                $now=[DateTimeOffset]::UtcNow.ToString('o')
                $composer.composer_state='COMMITTED'
                $composer.composer_result='EMPTY'
                $composer.send_invocation_state='INVOKED'
                $composer.committed_message_proof_state='PROVEN'
                $composer.failure_reason=$null
                $composer.observed_composer_text_sha256=$observation.composer_text_sha256
                $composer.observed_composer_text_length=$observation.composer_text_length
                $composer.updated_at=$now
                $composer|Add-Member -NotePropertyName committed_message_proof_source -NotePropertyValue ([string]$proof.proof_source) -Force
                $composer|Add-Member -NotePropertyName committed_message_proven_at -NotePropertyValue $now -Force
                Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
                $transport=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status ACTIVATED -TransportType DESKTOP_CHATGPT_THINKER
                # Re-enter through durable ACTIVATED state so the normal response reader is reused without resending.
                return Invoke-AidosDesktopThinkerAssignment -ProjectRoot $root -AssignmentId $AssignmentId -StateRoot $StateRoot -ProcessName $ProcessName -ResponseTimeoutSeconds $ResponseTimeoutSeconds -Backend $Backend
            }
            $composer.composer_state='FAILED'
            $composer.committed_message_proof_state='NOT_PROVEN'
            $composer.failure_reason=if(-not[string]::IsNullOrWhiteSpace($proofError)){"Delayed committed-send proof failed: $proofError"}elseif($proof){'Bound outbound prompt is not visible in the enrolled Thinker conversation; delayed commit remains unproven.'}else{'Delayed committed-send proof is unavailable.'}
            $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
            $state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError $composer.failure_reason
            return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;composer=$composer;transport=$state;commit_proof=$proof}
        }
        $composer.send_invocation_state='INVOKED'
        $composer.committed_message_proof_state='NOT_PROVEN'
        $composer.failure_reason=$null
        $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
        try {
            $outbound=& $Backend.SendPrompt $context $enrollment $prompt $bound
        } catch {
            $composer.composer_state='FAILED'
            $composer.send_invocation_state='FAILED'
            $composer.committed_message_proof_state='NOT_PROVEN'
            $composer.failure_reason=$_.Exception.Message
            $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
            $state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError $composer.failure_reason
            return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;composer=$composer;transport=$state}
        }
        $sendResult=Test-AidosDesktopThinkerSendResultContract -Result $outbound
        $composer.assignment_id=[string]$sendResult.assignment_id
        $composer.assignment_sha256=[string]$sendResult.assignment_sha256
        $composer.conversation_fingerprint_sha256=[string]$sendResult.conversation_fingerprint_sha256
        $composer.composer_state=[string]$sendResult.composer_state
        $composer.composer_result=[string]$sendResult.composer_result
        $composer.mutation_occurred=([bool]$composer.mutation_occurred -or [bool]$sendResult.mutation_occurred)
        $composer.send_invocation_state=[string]$sendResult.send_invocation_state
        $composer.committed_message_proof_state=[string]$sendResult.committed_message_proof_state
        $composer.failure_reason=$sendResult.failure_reason
        $composer.observed_composer_text_sha256=$observation.composer_text_sha256
        $composer.observed_composer_text_length=$observation.composer_text_length
        $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
        if(-not [bool]$sendResult.committed -or [string]$sendResult.committed_message_proof_state -ne 'PROVEN'){
            $composer.composer_state='FAILED'
            $composer.send_invocation_state='FAILED'
            $composer.committed_message_proof_state='NOT_PROVEN'
            $composer.failure_reason=if([string]::IsNullOrWhiteSpace([string]$sendResult.failure_reason)){'Desktop Thinker outbound message has no committed-send proof.'}else{[string]$sendResult.failure_reason}
            $composer.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
            Write-AidosDesktopThinkerComposerState -StateRoot $StateRoot -State $composer|Out-Null
            $state=Set-AidosRuntimeActorTransportState -ProjectRoot $root -AssignmentId $AssignmentId -Status WAITING_TRANSPORT -TransportType DESKTOP_CHATGPT_THINKER -LastError $composer.failure_reason
            return [pscustomobject][ordered]@{status='WAITING_TRANSPORT';assignment_id=$AssignmentId;composer=$composer;transport=$state}
        }
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

Export-ModuleMember -Function Get-AidosDesktopThinkerRoot,Get-AidosDesktopThinkerEnrollmentPath,Get-AidosDesktopThinkerComposerStatePath,Get-AidosDesktopThinkerPromptHash,Read-AidosDesktopThinkerComposerState,Write-AidosDesktopThinkerComposerState,Read-AidosDesktopThinkerEnrollment,Write-AidosDesktopThinkerEnrollment,Get-AidosDesktopThinkerResponseText,Get-AidosDesktopThinkerCommittedPromptProof,Test-AidosDesktopThinkerCommittedPromptProofContract,New-AidosDesktopThinkerStubBackend,New-AidosDesktopThinkerWindowsBackend,Complete-AidosDesktopThinkerEnrollment,Initialize-AidosDesktopThinkerEnrollment,Get-AidosDesktopThinkerAuthorizedDocuments,New-AidosDesktopThinkerPrompt,Invoke-AidosDesktopThinkerAssignment
