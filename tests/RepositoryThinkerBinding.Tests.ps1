[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryThinkerBinding.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Binding([bool]$Condition,[string]$Message){if(-not$Condition){throw "ASSERTION FAILED: $Message"};$script:passed++}
function Assert-BindingThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){$thrown=$false;try{& $Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected error: $($_.Exception.Message)"}};if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception"};$script:passed++}

$bindingSource=Get-Content -LiteralPath (Join-Path $root 'bridge/AidosRepositoryThinkerBinding.psm1') -Raw -Encoding UTF8
Assert-Binding ($bindingSource.Contains('[DllImport("user32.dll", SetLastError=true)]') -and $bindingSource.Contains('private static extern uint SendInput')) 'Repository Thinker uses native Win32 SendInput for keyboard injection'
Assert-Binding ($bindingSource.Contains('private static extern void keybd_event') -and $bindingSource.Contains('KEYBD_EVENT_ZERO_FALLBACK')) 'Repository Thinker has a bounded legacy fallback for the live zero-result SendInput failure'
Assert-Binding ($bindingSource.Contains('Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x41') -and $bindingSource.Contains('Invoke-AidosRepositoryThinkerNativeChord -Modifier 0x11 -Key 0x56')) 'Repository Thinker hydrates the composer with native Ctrl+A and Ctrl+V keyboard events'
Assert-Binding (-not$bindingSource.Contains('System.Windows.Forms.SendKeys') -and -not$bindingSource.Contains('SendWait(')) 'Repository Thinker no longer depends on unstable Windows Forms SendKeys'
Assert-Binding ($bindingSource.Contains("@('composer-submit-button')") -and $bindingSource.Contains("@('send-button','composer-send-button')")) 'Repository Thinker supports bounded current and alternate send automation identifiers'
Assert-Binding ($bindingSource.Contains("@('Send prompt','Send message','Send')")) 'Repository Thinker has a bounded accessible-name send fallback'
Assert-Binding ($bindingSource.Contains('Invoke-AidosRepositoryThinkerNativeKey -Key 0x0D') -and $bindingSource.Contains('$sendMethod="NATIVE_ENTER::$enterTransport"')) 'Repository Thinker has a native Enter fallback after exact composer proof'
Assert-Binding ($bindingSource.Contains('if(sent != 0)') -and $bindingSource.Contains('fallback is forbidden') -and $bindingSource.Contains('ReleaseChord(modifier, key)')) 'Repository Thinker cleans up and fails closed after partial SendInput acceptance'
Assert-Binding ($bindingSource.Contains('$inputSentinel="AIDOS_INPUT_PROBE::') -and $bindingSource.Contains("sentinel_proof='PROVEN'")) 'Repository Thinker proves a unique composer mutation before trusting unacknowledged legacy input fallback'
Assert-Binding ($bindingSource.Contains('payload hydration was not attempted')) 'Repository Thinker never hydrates or sends the payload without sentinel input proof'
Assert-Binding ($bindingSource.Contains('function Set-AidosRepositoryThinkerComposerValue') -and $bindingSource.Contains("'UIA_VALUE_PATTERN_ZERO_FALLBACK'")) 'Repository Thinker has an exact UI Automation ValuePattern compatibility surface for the live zero-input host'
Assert-Binding ($bindingSource.Contains("`$sentinelSelectTransport.StartsWith('KEYBD_EVENT_ZERO_FALLBACK('") -and $bindingSource.Contains("`$sentinelPasteTransport.StartsWith('KEYBD_EVENT_ZERO_FALLBACK('")) 'UI Automation hydration is reachable only after both sentinel keyboard chords report the exact zero-event fallback'
Assert-Binding ($bindingSource.Contains('$payloadSelectTransport=Set-AidosRepositoryThinkerComposerValue -Composer $composer -Value $PromptText') -and $bindingSource.Contains('$uiaValueFallback=$true')) 'Repository Thinker uses UI Automation for the real payload only after exact sentinel readback proved that route'
Assert-Binding ($bindingSource.Contains('win32_error=') -and $bindingSource.Contains('input_size=') -and $bindingSource.Contains('pointer_size=')) 'Repository Thinker reports native input diagnostics for live transport failures and fallbacks'
Assert-Binding ($bindingSource.Contains('send_proof=$null') -and $bindingSource.Contains('$state.send_proof=$send')) 'Repository Thinker durably records the committed native input and submit proof'
Assert-Binding ($bindingSource.Contains('Test-AidosRepositoryThinkerVisibleHandoffMarker') -and $bindingSource.Contains('visible_handoff_marker_proof_state')) 'Repository Thinker requires the exact visible handoff marker before durable COMMITTED state'
$bindingModule=Get-Module AidosRepositoryThinkerBinding | Select-Object -First 1
& $bindingModule { Initialize-AidosRepositoryThinkerNativeInput }
Assert-Binding ([bool]('AidosRepositoryThinkerNativeInputV2' -as [type])) 'Repository Thinker native input helper compiles successfully'
$payloadProof=& $bindingModule {
    $expected="AIDOS_HANDOFF_READY`nproject_id=P1`nhandoff_id=H1`nhandoff_sha256=$('a'*64)`nrepository=https://github.com/example/project.git`n`nProcess the handoff."
    $projection="AIDOS_HANDOFF_READY`nproject_id=P1`nhandoff_id=H1`nhandoff_sha256=$('a'*64)`nrepository=`n`nexample/project.git`nProcess the handoff."
    [pscustomobject]@{
        exact=Get-AidosRepositoryThinkerComposerPayloadProof -Expected $expected -Observed $expected
        projection=Get-AidosRepositoryThinkerComposerPayloadProof -Expected $expected -Observed $projection
        altered=Get-AidosRepositoryThinkerComposerPayloadProof -Expected $expected -Observed ($projection.Replace('Process','Altered'))
        wrong_host=Get-AidosRepositoryThinkerComposerPayloadProof -Expected ($expected.Replace('github.com','example.com')) -Observed $projection
    }
}
Assert-Binding ([bool]$payloadProof.exact.proven -and [string]$payloadProof.exact.mode-eq'EXACT') 'exact composer payload proof remains accepted'
Assert-Binding ([bool]$payloadProof.projection.proven -and [string]$payloadProof.projection.mode-eq'CHATGPT_UIA_GITHUB_AUTOLINK_PROJECTION') 'exact Chromium GitHub autolink UIA projection is accepted explicitly'
Assert-Binding (-not[bool]$payloadProof.altered.proven) 'autolink projection rejects any change outside the projected repository URI'
Assert-Binding (-not[bool]$payloadProof.wrong_host.proven) 'autolink projection is limited to the exact GitHub HTTPS authority'
Assert-Binding ($bindingSource.Contains('function Test-AidosRepositoryThinkerComposerFocusProof') -and $bindingSource.Contains('[System.Windows.Automation.AutomationElement]::FocusedElement')) 'Repository Thinker inspects the actual focused UIA element for composer focus proof'
Assert-Binding ($bindingSource.Contains('[System.Windows.Automation.TreeWalker]::RawViewWalker') -and $bindingSource.Contains("AutomationId -eq 'prompt-textarea'")) 'Repository Thinker accepts only focus within the unique prompt-textarea ancestry'
Assert-Binding ($bindingSource.Contains('Test-AidosRepositoryThinkerComposerFocusProof -Composer $composer') -and $bindingSource.Contains("throw 'ChatGPT composer keyboard focus proof is required before send.'")) 'Repository Thinker requires focused composer ancestry before clipboard input'
Assert-Binding ($bindingSource.Contains("throw 'ChatGPT composer keyboard focus proof is required before Enter fallback.'")) 'Repository Thinker re-proves focused composer ancestry before Enter fallback'
Assert-Binding ($bindingSource.Contains('committed-send proof is absent')) 'Repository Thinker remains fail-closed unless the outbound payload leaves the composer'
Assert-Binding ($bindingSource.Contains('function ConvertTo-AidosRepositoryThinkerComposerComparableText') -and $bindingSource.Contains('.Replace("`r`n","`n").Replace("`r","`n")')) 'Repository Thinker normalizes only transport line endings for composer hydration proof'
Assert-Binding ($bindingSource.Contains('$currentComposer=Get-AidosRepositoryThinkerComposerElement -RootElement $root') -and $bindingSource.Contains('Get-AidosRepositoryThinkerComposerPayloadProof -Expected $PromptText -Observed $current')) 'Repository Thinker rebinds the live composer before proving hydrated payload text'
Assert-Binding (-not$bindingSource.Contains('SendPrompt=$desktop.SendPrompt')) 'Repository Thinker no longer delegates trigger sending to the legacy Desktop sender'
Assert-Binding ($bindingSource.Contains('New-Object -ComObject WScript.Shell') -and $bindingSource.Contains('AppActivate([int]$Context.process_id)')) 'Repository Thinker explicitly activates the bound ChatGPT process before legacy focus proof'
Assert-Binding ($bindingSource.Contains('$desktopFocus=$desktop.FocusConversation') -and -not$bindingSource.Contains('FocusConversation=$desktop.FocusConversation')) 'Repository Thinker wraps the proven Desktop focus routine instead of delegating it directly'
Assert-Binding ($bindingSource.Contains('function Wait-AidosRepositoryThinkerComposerElement') -and $bindingSource.Contains('$composer=Wait-AidosRepositoryThinkerComposerElement -RootElement $root')) 'Repository Thinker waits for bounded unique composer readiness before keyboard transport'
Assert-Binding ($bindingSource.Contains('Treat that as transient readiness failure') -and $bindingSource.Contains('try{$current=Get-AidosRepositoryThinkerCurrentConversationFromRoot -RootElement $root}catch{}')) 'Repository Thinker tolerates transient WebView document URL absence during bounded conversation activation'

$composerProbe=[pscustomobject]@{calls=0;ready=[pscustomobject]@{automation_id='prompt-textarea'}}
$transientResolver=({param($Root);$composerProbe.calls++;if($composerProbe.calls-lt3){throw 'Expected exactly one ChatGPT composer control, found 0.'};$composerProbe.ready}).GetNewClosure()
$waitedComposer=& $bindingModule {param($Resolver) Wait-AidosRepositoryThinkerComposerElement -RootElement ([pscustomobject]@{}) -MaxAttempts 3 -PollMilliseconds 0 -ComposerResolver $Resolver} $transientResolver
Assert-Binding ($composerProbe.calls-eq3 -and $waitedComposer.automation_id-eq'prompt-textarea') 'Repository Thinker tolerates bounded transient composer absence and returns only the unique ready control'

$ambiguousProbe=[pscustomobject]@{calls=0}
$ambiguousResolver=({param($Root);$ambiguousProbe.calls++;throw 'Expected exactly one ChatGPT composer control, found 2.'}).GetNewClosure()
Assert-BindingThrows {& $bindingModule {param($Resolver) Wait-AidosRepositoryThinkerComposerElement -RootElement ([pscustomobject]@{}) -MaxAttempts 3 -PollMilliseconds 0 -ComposerResolver $Resolver} $ambiguousResolver} 'found 2' 'Repository Thinker fails immediately on ambiguous composer discovery'
Assert-Binding ($ambiguousProbe.calls-eq1) 'ambiguous composer discovery is never retried'

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

    Assert-BindingThrows {Reset-AidosRepositoryThinkerTrigger -StateRoot $temp -ProjectId 'PROJECT-1' -HandoffId ([string]$handoff.metadata.handoff_id)} 'Only an uncommitted FAILED' 'operator cannot reset a committed Thinker trigger'

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
    Assert-Binding ([string]$backoff.status-eq'FAILED_REQUIRES_RESET') 'ticker never retries a failed ChatGPT trigger without explicit reset'
    Assert-Binding ($failureRuntime.send_count-eq0) 'failed conversation activation never sends into an unknown chat'
    Reset-AidosRepositoryThinkerTrigger -StateRoot $temp -ProjectId 'PROJECT-1' -HandoffId ([string]$failedHandoff.metadata.handoff_id)|Out-Null
    Assert-Binding ($null-eq(Get-AidosRepositoryThinkerTriggerState -StateRoot $temp -ProjectId 'PROJECT-1' -HandoffId ([string]$failedHandoff.metadata.handoff_id))) 'operator reset removes only an uncommitted FAILED trigger'

    $pendingHandoff=[pscustomobject][ordered]@{metadata=[pscustomobject][ordered]@{project_id='PROJECT-1';handoff_id=[guid]::NewGuid().ToString();kind='ASSIGNMENT';to_actor='THINKER'};text_sha256=('d'*64)}
    $pendingPath=Get-AidosRepositoryThinkerTriggerPath -StateRoot $temp -ProjectId 'PROJECT-1' -HandoffId ([string]$pendingHandoff.metadata.handoff_id)
    Write-AidosRepositoryThinkerJsonAtomic -Path $pendingPath -Value ([pscustomobject][ordered]@{schema_version='0.1';project_id='PROJECT-1';handoff_id=[string]$pendingHandoff.metadata.handoff_id;handoff_sha256=('d'*64);status='PENDING';attempt=1;triggered_at=$null;retry_after=$null;last_error=$null;send_proof=$null;updated_at=[DateTimeOffset]::UtcNow.ToString('o')})
    $pending=Invoke-AidosRepositoryThinkerTrigger -StateRoot $temp -Handoff $pendingHandoff -Backend $backend
    Assert-Binding ([string]$pending.status-eq'PENDING_REQUIRES_RECOVERY') 'ticker never re-enters an interrupted PENDING trigger'
    $recovered=Recover-AidosRepositoryThinkerInterruptedTrigger -StateRoot $temp -ProjectId 'PROJECT-1' -HandoffId ([string]$pendingHandoff.metadata.handoff_id)
    Assert-Binding ([string]$recovered.status-eq'RECOVERED_INTERRUPTED' -and [string]$recovered.state.status-eq'FAILED' -and $recovered.state.last_error-eq'INTERRUPTED_BEFORE_COMMIT: host stopped while trigger attempt was PENDING; explicit reset is required.') 'proofless PENDING trigger has explicit durable interrupted recovery'

    Remove-AidosRepositoryThinkerBinding -StateRoot $temp -ProjectId 'PROJECT-1'|Out-Null
    Assert-Binding ($null-eq(Read-AidosRepositoryThinkerBinding -StateRoot $temp -ProjectId 'PROJECT-1')) 'operator can replace a disposable project chat binding'

    Write-Output "PASS: $passed repository Thinker binding assertions"
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
