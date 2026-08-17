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
    [int]$ResponseTimeoutSeconds=180,
    [ValidateSet('SUPERVISED','UNATTENDED_ALLOWED')][string]$SessionPolicy='SUPERVISED',
    [bool]$WaitForInteractiveSession=$true,
    [int]$InteractiveSessionPollSeconds=2,
    [int]$InteractiveSessionWaitTimeoutSeconds=0
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopSessionGate.psm1') -Force -DisableNameChecking
# Import the session module last. The gate imports it as a nested dependency with
# -Force; importing it again here makes its public commands available in this
# launcher scope for retry/recovery paths as well.
Import-Module (Join-Path $PSScriptRoot 'AidosWindowsSession.psm1') -Force -DisableNameChecking

$backend=if($BackendMode -eq 'Stub'){
    AidosDesktopChatGPT\New-AidosDesktopChatGPTStubBackend -InteractiveSession:$StubInteractiveSession -ConversationMatches:$StubConversationMatches -NoResponse:$StubNoResponse -ResponseText $StubResponseText -ProcessName $ProcessName
} else {
    $null
}

switch ($Mode) {
    'Enroll' {
        if([string]::IsNullOrWhiteSpace($ConversationProofText)){ throw 'Enroll mode requires ConversationProofText.' }
        $result=Invoke-AidosDesktopChatGPTEnroll -ProjectRoot $ProjectRoot -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -Backend $backend -SessionPolicy $SessionPolicy
        $result | ConvertTo-Json -Depth 100
    }
    'Review' {
        if([string]::IsNullOrWhiteSpace($AssignmentPath)){ throw 'Review mode requires AssignmentPath.' }
        $retryStarted=[DateTimeOffset]::UtcNow
        while($true){
            try {
                $result=Invoke-AidosDesktopChatGPTReview -ProjectRoot $ProjectRoot -AssignmentPath $AssignmentPath -ConversationProofText $ConversationProofText -AccountProofText $AccountProofText -ProcessName $ProcessName -ResponseTimeoutSeconds $ResponseTimeoutSeconds -Backend $backend -SessionPolicy $SessionPolicy -WaitForInteractiveSession:$WaitForInteractiveSession -InteractiveSessionPollSeconds $InteractiveSessionPollSeconds -InteractiveSessionWaitTimeoutSeconds $InteractiveSessionWaitTimeoutSeconds
                break
            } catch {
                if($_.Exception.Message -ne 'Interactive wait was requested without a blocking or transient session reason.' -or -not $WaitForInteractiveSession){ throw }
                $snapshot=Get-AidosInteractiveSessionSnapshot
                $decision=Test-AidosInteractiveSessionPolicy -Snapshot $snapshot -Policy $SessionPolicy
                if(-not $decision.allowed){ throw }
                if($InteractiveSessionWaitTimeoutSeconds -gt 0 -and ([DateTimeOffset]::UtcNow-$retryStarted).TotalSeconds -ge $InteractiveSessionWaitTimeoutSeconds){ throw }
                Start-Sleep -Seconds ([Math]::Max(1,$InteractiveSessionPollSeconds))
            }
        }
        if($result.status -eq 'HANDOFF_COMPLETE' -and $result.response){
            $result.response | ConvertTo-Json -Depth 100
        } else {
            $result | ConvertTo-Json -Depth 100
        }
    }
}
