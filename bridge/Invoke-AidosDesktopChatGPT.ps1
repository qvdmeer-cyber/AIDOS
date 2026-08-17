[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [ValidateSet('Enroll','Review')][string]$Mode='Review',
    [string]$ConversationProofText='',
    [string]$AccountProofText='',
    [string]$AssignmentPath,
    [string]$ProcessName='ChatGPT',
    [ValidateSet('Real','Stub')][string]$BackendMode='Real',
    [bool]$StubInteractiveSession=$true,
    [bool]$StubConversationMatches=$true,
    [bool]$StubNoResponse=$false,
    [string]$StubResponseText,
    [int]$ResponseTimeoutSeconds=180
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -Force -DisableNameChecking

$backend=if($BackendMode -eq 'Stub'){
    New-AidosDesktopChatGPTStubBackend -InteractiveSession:$StubInteractiveSession -ConversationMatches:$StubConversationMatches -NoResponse:$StubNoResponse -ResponseText $StubResponseText -ProcessName $ProcessName
} else {
    New-AidosDesktopChatGPTWindowsBackend -ProcessName $ProcessName
}

switch ($Mode) {
    'Enroll' {
        if([string]::IsNullOrWhiteSpace($ConversationProofText)){ throw 'Enroll mode requires ConversationProofText.' }
        $result=Invoke-AidosDesktopChatGPTEnroll -ProjectRoot $ProjectRoot -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -Backend $backend
        $result | ConvertTo-Json -Depth 100
    }
    'Review' {
        if([string]::IsNullOrWhiteSpace($AssignmentPath)){ throw 'Review mode requires AssignmentPath.' }
        $result=Invoke-AidosDesktopChatGPTReview -ProjectRoot $ProjectRoot -AssignmentPath $AssignmentPath -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -ResponseTimeoutSeconds $ResponseTimeoutSeconds -Backend $backend
        if($result.status -eq 'HANDOFF_COMPLETE' -and $result.response){
            $result.response | ConvertTo-Json -Depth 100
        } else {
            $result | ConvertTo-Json -Depth 100
        }
    }
}
