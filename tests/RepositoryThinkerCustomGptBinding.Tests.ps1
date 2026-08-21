[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryThinkerBinding.psm1') -Force -DisableNameChecking

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-custom-gpt-binding-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try{
    if(-not(Test-AidosRepositoryThinkerConversationTitleMatch -ObservedTitle 'AIDOS :: AIDOS-INTERFACE :: THINKER, vastgezet gesprek' -ExpectedTitle 'AIDOS :: AIDOS-INTERFACE :: THINKER')){throw 'ASSERTION FAILED: localized pinned-chat accessibility suffix must match the bound title.'}
    if(Test-AidosRepositoryThinkerConversationTitleMatch -ObservedTitle 'AIDOS :: OTHER :: THINKER, vastgezet gesprek' -ExpectedTitle 'AIDOS :: AIDOS-INTERFACE :: THINKER'){throw 'ASSERTION FAILED: a different pinned-chat title must not match.'}
    if(-not(Test-AidosRepositoryThinkerConversationUrlMatch -ObservedUrl 'https://chatgpt.com/g/g-example/a/c/6a8850c0-63a4-83ed-acf0-542922b30cde' -ExpectedUrl 'https://chatgpt.com/c/6a8850c0-63a4-83ed-acf0-542922b30cde')){throw 'ASSERTION FAILED: custom GPT URL prefix must not change conversation identity.'}
    $runtime=[pscustomobject]@{
        document_title='ChatGPT - AIDOS Repository Thinker'
        conversation_title='AIDOS :: AIDOS-INTERFACE :: THINKER'
        conversation_url='https://chatgpt.com/c/custom-gpt-project-chat'
        resolve_count=0
    }
    $backend=[pscustomobject]@{
        GetProcessContext={param($ProcessName);[pscustomobject]@{process_name=$ProcessName;window_handle='1'}}
        GetCurrentConversation=({param($Context);[pscustomobject]@{title=$runtime.document_title;url=$runtime.conversation_url}}).GetNewClosure()
        ResolveConversationByTitle=({
            param($Context,$ConversationTitle)
            $runtime.resolve_count++
            if(-not[string]::Equals([string]$ConversationTitle,[string]$runtime.conversation_title,[StringComparison]::Ordinal)){throw "Pinned ChatGPT conversation '$ConversationTitle' was not found as an actionable sidebar item."}
            [pscustomobject][ordered]@{
                status='RESOLVED'
                method='TEST'
                conversation=[pscustomobject][ordered]@{
                    title=[string]$runtime.conversation_title
                    document_title=[string]$runtime.document_title
                    url=[string]$runtime.conversation_url
                }
                context=$Context
            }
        }).GetNewClosure()
    }

    $binding=Bind-AidosRepositoryThinkerConversation -StateRoot $temp -ProjectId 'AIDOS-INTERFACE' -Repository 'https://github.com/qvdmeer-cyber/AIDOS-interface.git' -ExpectedConversationTitle 'AIDOS :: AIDOS-INTERFACE :: THINKER' -Backend $backend
    if([int]$runtime.resolve_count-ne1){throw 'ASSERTION FAILED: binding must resolve the exact sidebar conversation once.'}
    if([string]$binding.conversation_title-ne'AIDOS :: AIDOS-INTERFACE :: THINKER'){throw 'ASSERTION FAILED: binding must persist the sidebar conversation title, not the custom GPT document title.'}
    if([string]$binding.conversation_url-ne'https://chatgpt.com/c/custom-gpt-project-chat'){throw 'ASSERTION FAILED: binding must persist the resolved custom GPT conversation URL.'}

    $failed=$false
    try{Bind-AidosRepositoryThinkerConversation -StateRoot $temp -ProjectId 'OTHER' -Repository 'example/other' -ExpectedConversationTitle 'AIDOS :: OTHER :: THINKER' -Backend $backend|Out-Null}catch{$failed=$_.Exception.Message-match'not found as an actionable sidebar item'}
    if(-not$failed){throw 'ASSERTION FAILED: binding must fail closed when the exact sidebar title cannot be resolved.'}

    Write-Output 'PASS: custom GPT Thinker binding uses exact sidebar identity'
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
