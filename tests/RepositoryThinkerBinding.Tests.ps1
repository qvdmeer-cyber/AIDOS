[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryThinkerBinding.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Binding([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-BindingThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{& $Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected error: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-thinker-binding-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    $runtime=[pscustomobject]@{active_title='AIDOS :: PROJECT-1 :: THINKER';active_url='https://chatgpt.com/c/project-1';send_count=0;activation_count=0;last_prompt=$null}
    $backend=[pscustomobject]@{
        GetProcessContext=({param($ProcessName);[pscustomobject]@{present=$true;process_name=$ProcessName;window_handle='1';window_is_foreground=$true;window_is_minimized=$false}}).GetNewClosure()
        GetCurrentConversation=({param($Context);[pscustomobject]@{title=$runtime.active_title;url=$runtime.active_url}}).GetNewClosure()
        ActivateConversation=({param($Context,$Binding);$runtime.activation_count++;$runtime.active_title=[string]$Binding.conversation_title;$runtime.active_url=[string]$Binding.conversation_url;[pscustomobject]@{status='ACTIVATED';context=$Context;conversation=[pscustomobject]@{title=$runtime.active_title;url=$runtime.active_url}}}).GetNewClosure()
        FocusConversation=({param($Context,$Binding);$Context}).GetNewClosure()
        SendPrompt=({param($Context,$Binding,$Prompt,$Assignment);$runtime.send_count++;$runtime.last_prompt=$Prompt;[pscustomobject]@{committed=$true;composer_state='COMMITTED'}}).GetNewClosure()
    }

    $binding=Bind-AidosRepositoryThinkerConversation -StateRoot $temp -ProjectId 'PROJECT-1' -Repository 'qvdmeer-cyber/project-1' -ExpectedConversationTitle 'AIDOS :: PROJECT-1 :: THINKER' -Backend $backend
    Assert-Binding ([string]$binding.project_id-eq'PROJECT-1') 'manual binding is project-specific'
    Assert-Binding ([string]$binding.conversation_url-eq'https://chatgpt.com/c/project-1') 'manual binding stores durable conversation URL rather than window handle'
    Assert-Binding ([string]$binding.conversation_title-eq'AIDOS :: PROJECT-1 :: THINKER') 'manual binding stores exact pinned title'
    $persisted=Read-AidosRepositoryThinkerBinding -StateRoot $temp -ProjectId 'PROJECT-1'
    Assert-Binding ([string]$persisted.status-eq'BOUND') 'manual binding is persisted locally'

    $handoff=[pscustomobject][ordered]@{metadata=[pscustomobject][ordered]@{project_id='PROJECT-1';handoff_id=[guid]::NewGuid().ToString();kind='ASSIGNMENT';to_actor='THINKER'};text_sha256=('a'*64)}
    $runtime.active_title='Another conversation';$runtime.active_url='https://chatgpt.com/c/other'
    $trigger=Invoke-AidosRepositoryThinkerTrigger -StateRoot $temp -Handoff $handoff -Backend $backend
    Assert-Binding ([string]$trigger.status-eq'TRIGGERED') ("READY Thinker handoff activates and triggers the bound conversation: "+($trigger|ConvertTo-Json -Depth 50 -Compress))
    Assert-Binding ($runtime.activation_count-eq1 -and $runtime.send_count-eq1) 'trigger performs one activation and one send'
    Assert-Binding ($runtime.last_prompt.Contains([string]$handoff.metadata.handoff_id)) 'trigger contains exact handoff identity'
    Assert-Binding ($runtime.last_prompt.Contains('Do not place the work product in this chat')) 'trigger explicitly keeps result transport in repository gateway'

    $again=Invoke-AidosRepositoryThinkerTrigger -StateRoot $temp -Handoff $handoff -Backend $backend
    Assert-Binding ([string]$again.status-eq'ALREADY_TRIGGERED') 'same handoff trigger is idempotent'
    Assert-Binding ($runtime.send_count-eq1) 'idempotent trigger does not resend to ChatGPT'

    Reset-AidosRepositoryThinkerTrigger -StateRoot $temp -ProjectId 'PROJECT-1' -HandoffId ([string]$handoff.metadata.handoff_id)|Out-Null
    $afterReset=Invoke-AidosRepositoryThinkerTrigger -StateRoot $temp -Handoff $handoff -Backend $backend
    Assert-Binding ([string]$afterReset.status-eq'TRIGGERED' -and $runtime.send_count-eq2) 'operator reset explicitly permits one retrigger'

    $unbound=[pscustomobject][ordered]@{metadata=[pscustomobject][ordered]@{project_id='PROJECT-2';handoff_id=[guid]::NewGuid().ToString();kind='ASSIGNMENT';to_actor='THINKER'};text_sha256=('b'*64)}
    $unboundResult=Invoke-AidosRepositoryThinkerTrigger -StateRoot $temp -Handoff $unbound -Backend $backend
    Assert-Binding ([string]$unboundResult.status-eq'UNBOUND') 'bridge fails closed when project has no manually bound conversation'

    $runtime.active_title='Wrong title';$runtime.active_url='https://chatgpt.com/c/wrong'
    Assert-BindingThrows {Bind-AidosRepositoryThinkerConversation -StateRoot $temp -ProjectId 'PROJECT-3' -Repository 'example/project-3' -ExpectedConversationTitle 'AIDOS :: PROJECT-3 :: THINKER' -Backend $backend} 'Rename and pin' 'binding requires exact unique pinned project title'

    $failureRuntime=[pscustomobject]@{send_count=0}
    $failing=[pscustomobject]@{
        GetProcessContext={param($ProcessName);[pscustomobject]@{process_name=$ProcessName;window_handle='1'}}
        ActivateConversation={param($Context,$Binding);throw 'conversation unavailable'}
        FocusConversation={param($Context,$Binding);$Context}
        SendPrompt=({param($Context,$Binding,$Prompt,$Assignment);$failureRuntime.send_count++;[pscustomobject]@{committed=$true}}).GetNewClosure()
    }
    $runtime.active_title='AIDOS :: PROJECT-1 :: THINKER';$runtime.active_url='https://chatgpt.com/c/project-1'
    $failedHandoff=[pscustomobject][ordered]@{metadata=[pscustomobject][ordered]@{project_id='PROJECT-1';handoff_id=[guid]::NewGuid().ToString();kind='ASSIGNMENT';to_actor='THINKER'};text_sha256=('c'*64)}
    $failed=Invoke-AidosRepositoryThinkerTrigger -StateRoot $temp -Handoff $failedHandoff -Backend $failing
    Assert-Binding ([string]$failed.status-eq'FAILED' -and $failed.retry_after) 'failed activation enters bounded backoff'
    $backoff=Invoke-AidosRepositoryThinkerTrigger -StateRoot $temp -Handoff $failedHandoff -Backend $failing
    Assert-Binding ([string]$backoff.status-eq'BACKOFF') 'ticker does not hammer ChatGPT during backoff'
    Assert-Binding ($failureRuntime.send_count-eq0) 'failed conversation activation never sends into an unknown chat'

    Remove-AidosRepositoryThinkerBinding -StateRoot $temp -ProjectId 'PROJECT-1'|Out-Null
    Assert-Binding ($null-eq(Read-AidosRepositoryThinkerBinding -StateRoot $temp -ProjectId 'PROJECT-1')) 'operator can replace a disposable project chat binding'

    Write-Output "PASS: $passed repository Thinker binding assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
