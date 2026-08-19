Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosRepositoryThinkerBinding.psm1') -Global -DisableNameChecking

function Get-AidosRepositoryHumanInputTriggerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RequestId
    )
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("human-input-triggers/$ProjectId/$RequestId.json")
}

function Get-AidosRepositoryHumanInputTriggerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RequestId
    )
    $path=Get-AidosRepositoryHumanInputTriggerPath -StateRoot $StateRoot -ProjectId $ProjectId -RequestId $RequestId
    if(Test-Path -LiteralPath $path -PathType Leaf){Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50}else{$null}
}

function Assert-AidosRepositoryHumanInputBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Request
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    if($null-eq$Request.binding){throw 'Human Input Request binding is missing.'}
    $state=Get-AidosState $root
    foreach($name in @('definition_id','definition_version','execution_id','revision','review_id')){
        $expected=$Request.binding.PSObject.Properties[$name]
        if($null-eq$expected -or $null-eq$expected.Value){continue}
        $actual=$state.PSObject.Properties[$name]
        if($null-eq$actual -or [string]$actual.Value-ne[string]$expected.Value){throw "Human Input Request binding mismatch for '$name'."}
    }
    if($Request.binding.PSObject.Properties['baseline_version'] -and $null-ne$Request.binding.baseline_version){
        $baselinePath=Join-Path $root '.aidos/documentation/PROJECT_BASELINE.json'
        if(-not(Test-Path -LiteralPath $baselinePath -PathType Leaf)){throw 'Bound Project Baseline is unavailable.'}
        $baseline=Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
        if([int]$baseline.baseline_version-ne[int]$Request.binding.baseline_version){throw 'Human Input Request baseline binding mismatch.'}
    }
    $true
}

function Get-AidosRepositoryWaitingHumanInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $state=Get-AidosState $root
    if([string]$state.state-ne'WAITING_USER'){return $null}
    $requestRoot=Join-Path $root '.aidos/human-input'
    if(-not(Test-Path -LiteralPath $requestRoot -PathType Container)){throw 'Project is WAITING_USER but has no Human Input request directory.'}
    $waiting=@(
        Get-ChildItem -LiteralPath $requestRoot -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $request=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
            if([string]$request.status-eq'WAITING'){
                [pscustomobject][ordered]@{path=$_.FullName;request=$request}
            }
        }
    )
    if($waiting.Count-eq0){throw 'Project is WAITING_USER but no WAITING Human Input Request exists.'}
    if($waiting.Count-ne1){throw "Project has $($waiting.Count) WAITING Human Input Requests; expected exactly one."}
    $candidate=$waiting[0]
    $request=$candidate.request
    if(-not[string]::Equals([string]$request.project_id,[string]$Project.project_id,[StringComparison]::Ordinal)){throw 'Human Input Request project binding mismatch.'}
    if([string]::IsNullOrWhiteSpace([string]$request.request_id)){throw 'Human Input Request request_id is missing.'}
    Assert-AidosRepositoryHumanInputBinding -ProjectRoot $root -Request $request|Out-Null
    $sha=(Get-FileHash -LiteralPath $candidate.path -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject][ordered]@{
        project_id=[string]$Project.project_id
        request_id=[string]$request.request_id
        request_sha256=$sha
        request=$request
        path=$candidate.path
    }
}

function New-AidosRepositoryHumanInputTriggerText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Binding,
        [Parameter(Mandatory)]$HumanInput
    )
    @"
AIDOS_HUMAN_INPUT_REQUIRED
project_id=$([string]$HumanInput.project_id)
request_id=$([string]$HumanInput.request_id)
request_sha256=$([string]$HumanInput.request_sha256)
repository=$([string]$Binding.repository)

Fetch the exact current Human Input through your configured AIDOS Human Input action. Verify the exact project_id, request_id and request_sha256 above. Present only that current request to the user and wait for the user's decision. Do not answer on the user's behalf and do not start another actor.
"@.Trim()
}

function Get-AidosRepositoryHumanInputComposerText {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    if(-not('System.Windows.Automation.AutomationElement' -as [type])){Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes}
    if([string]::IsNullOrWhiteSpace([string]$Context.window_handle)){throw 'ChatGPT window is not present for Human Input send proof.'}
    $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]([int64]$Context.window_handle))
    if(-not$root){throw 'ChatGPT window is unavailable through UI Automation for Human Input send proof.'}
    $matches=@($root.FindAll([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.Condition]::TrueCondition)|Where-Object {
        [string]$_.Current.AutomationId-eq'prompt-textarea' -and
        $_.Current.ControlType-eq[System.Windows.Automation.ControlType]::Edit -and
        [bool]$_.Current.IsKeyboardFocusable
    })
    if($matches.Count-ne1){throw "Expected exactly one ChatGPT composer control during Human Input send proof, found $($matches.Count)."}
    $composer=$matches[0]
    try{$value=$composer.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern);if($value){return [string]$value.Current.Value}}catch{}
    try{$text=$composer.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern);if($text){return [string]$text.DocumentRange.GetText(-1)}}catch{}
    [string]$composer.Current.Name
}

function Wait-AidosRepositoryHumanInputSendCommitProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$PromptText,
        [ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,
        [ValidateRange(25,1000)][int]$PollMilliseconds=100,
        [scriptblock]$ReadComposerText,
        [scriptblock]$SleepAction
    )
    if($null-eq$ReadComposerText){$ReadComposerText={param($CurrentContext);Get-AidosRepositoryHumanInputComposerText -Context $CurrentContext}}
    if($null-eq$SleepAction){$SleepAction={param($Milliseconds);Start-Sleep -Milliseconds $Milliseconds}}
    $attempts=[Math]::Max(1,[int][Math]::Ceiling($TimeoutMilliseconds/[double]$PollMilliseconds))
    for($attempt=1;$attempt-le$attempts;$attempt++){
        $remaining=[string](& $ReadComposerText $Context)
        if([string]::IsNullOrWhiteSpace($remaining) -or $remaining.IndexOf($PromptText,[StringComparison]::Ordinal)-lt0){
            return [pscustomobject][ordered]@{
                schema_version='0.1'
                send_invocation_state='INVOKED'
                composer_result='RELEASED_AFTER_SETTLE'
                committed_message_proof_state='PROVEN_AFTER_SETTLE'
                settle_attempt=$attempt
                settle_timeout_milliseconds=$TimeoutMilliseconds
                committed=$true
            }
        }
        if($attempt-lt$attempts){& $SleepAction $PollMilliseconds}
    }
    throw "ChatGPT composer still contains the exact outbound payload after submit and $TimeoutMilliseconds ms settle window; committed-send proof is absent."
}

function Invoke-AidosRepositoryHumanInputTrigger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [Parameter(Mandatory)]$HumanInput,
        [string]$ProcessName='ChatGPT Classic',
        [object]$Backend
    )
    $projectId=[string]$HumanInput.project_id
    $requestId=[string]$HumanInput.request_id
    if([string]::IsNullOrWhiteSpace($projectId)-or[string]::IsNullOrWhiteSpace($requestId)){throw 'Human Input trigger requires exact project_id and request_id.'}
    $binding=Read-AidosRepositoryThinkerBinding -StateRoot $StateRoot -ProjectId $projectId
    if($null-eq$binding -or [string]$binding.status-ne'BOUND'){return [pscustomobject][ordered]@{status='UNBOUND';project_id=$projectId;request_id=$requestId}}
    $existing=Get-AidosRepositoryHumanInputTriggerState -StateRoot $StateRoot -ProjectId $projectId -RequestId $requestId
    if($existing -and [string]$existing.status-eq'COMMITTED'){
        if(-not[string]::Equals([string]$existing.request_sha256,[string]$HumanInput.request_sha256,[StringComparison]::Ordinal)){throw 'Committed Human Input trigger hash differs from the current WAITING request.'}
        return [pscustomobject][ordered]@{status='ALREADY_TRIGGERED';state=$existing}
    }
    if($existing -and [string]$existing.status-eq'FAILED' -and $existing.retry_after){
        $retry=ConvertTo-AidosRepositoryThinkerRetryAfter -Value $existing.retry_after
        if([DateTimeOffset]::UtcNow-lt$retry){return [pscustomobject][ordered]@{status='BACKOFF';retry_after=$retry.ToString('o');state=$existing}}
    }
    if($null-eq$Backend){$Backend=New-AidosRepositoryThinkerWindowsBackend -ProcessName $ProcessName}
    $attempt=if($existing){[int]$existing.attempt+1}else{1}
    $path=Get-AidosRepositoryHumanInputTriggerPath -StateRoot $StateRoot -ProjectId $projectId -RequestId $requestId
    $state=[pscustomobject][ordered]@{
        schema_version='0.1'
        project_id=$projectId
        request_id=$requestId
        request_sha256=[string]$HumanInput.request_sha256
        status='PENDING'
        attempt=$attempt
        triggered_at=$null
        retry_after=$null
        last_error=$null
        updated_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
    try{
        $context=& $Backend.GetProcessContext ([string]$binding.process_name)
        $activation=& $Backend.ActivateConversation $context $binding
        $context=& $Backend.FocusConversation $activation.context $binding
        $prompt=New-AidosRepositoryHumanInputTriggerText -Binding $binding -HumanInput $HumanInput
        $metadata=[pscustomobject][ordered]@{kind='HUMAN_INPUT';project_id=$projectId;request_id=$requestId;request_sha256=[string]$HumanInput.request_sha256}
        try{
            $send=& $Backend.SendPrompt $context $binding $prompt $metadata
        }catch{
            $sendError=$_.Exception.Message
            if(-not$sendError.StartsWith('ChatGPT composer still contains the exact outbound payload after submit;',[StringComparison]::Ordinal)){throw}
            $send=Wait-AidosRepositoryHumanInputSendCommitProof -Context $context -PromptText $prompt
        }
        if($null-eq$send -or -not[bool]$send.committed){throw 'ChatGPT Human Input trigger has no committed-send proof.'}
        $state.status='COMMITTED';$state.triggered_at=[DateTimeOffset]::UtcNow.ToString('o');$state.updated_at=$state.triggered_at
        Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
        [pscustomobject][ordered]@{status='TRIGGERED';project_id=$projectId;request_id=$requestId;activation=$activation;send=$send;state=$state}
    }catch{
        $delays=@(60,300,900,1800);$delay=$delays[[Math]::Min(($attempt-1),($delays.Count-1))]
        $state.status='FAILED';$state.last_error=$_.Exception.Message;$state.retry_after=[DateTimeOffset]::UtcNow.AddSeconds($delay).ToString('o');$state.updated_at=[DateTimeOffset]::UtcNow.ToString('o')
        Write-AidosRepositoryThinkerJsonAtomic -Path $path -Value $state
        [pscustomobject][ordered]@{status='FAILED';project_id=$projectId;request_id=$requestId;error=$state.last_error;retry_after=$state.retry_after;state=$state}
    }
}

function Reset-AidosRepositoryHumanInputTrigger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RequestId
    )
    $path=Get-AidosRepositoryHumanInputTriggerPath -StateRoot $StateRoot -ProjectId $ProjectId -RequestId $RequestId
    if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
    [pscustomobject][ordered]@{status='RESET';project_id=$ProjectId;request_id=$RequestId}
}

Export-ModuleMember -Function Get-AidosRepositoryHumanInputTriggerPath,Get-AidosRepositoryHumanInputTriggerState,Assert-AidosRepositoryHumanInputBinding,Get-AidosRepositoryWaitingHumanInput,New-AidosRepositoryHumanInputTriggerText,Get-AidosRepositoryHumanInputComposerText,Wait-AidosRepositoryHumanInputSendCommitProof,Invoke-AidosRepositoryHumanInputTrigger,Reset-AidosRepositoryHumanInputTrigger
