Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopChatGPT.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosDesktopSessionGate.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousIntegration.psm1') -DisableNameChecking

function Get-AidosAutonomousExecutionPathFromState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$state=Get-AidosState $root
    if([string]::IsNullOrWhiteSpace([string]$state.execution_id)-or$null-eq$state.revision){throw 'Review requires exact execution/revision state binding.'}
    Join-Path $root ('.aidos/executions/{0}/revision-{1}/EXECUTION.json' -f [string]$state.execution_id,[int]$state.revision)
}
function Publish-AidosAutonomousReview {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$state=Get-AidosState $root
    if([string]$state.state-ne'REVIEW_READY'){throw "Autonomous review publication requires REVIEW_READY, found '$($state.state)'."}
    $executionPath=Get-AidosAutonomousExecutionPathFromState -ProjectRoot $root
    if(-not(Test-Path -LiteralPath $executionPath -PathType Leaf)){throw 'Bound execution artifact is missing for review publication.'}
    $published=Publish-AidosReviewPackage -ProjectRoot $root -ExecutionPath $executionPath
    [pscustomobject][ordered]@{status='PUBLISHED';review=$published;persistence=[pscustomobject][ordered]@{status='LOCAL_DURABLE';reason='Review evidence remains local while Worker source mutations are intentionally uncommitted.'}}
}
function Get-AidosPortfolioRuntimeProjectsForReview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryRoot)
    $projectsRoot=Join-Path ([IO.Path]::GetFullPath($RegistryRoot)) 'projects'
    if(-not(Test-Path -LiteralPath $projectsRoot -PathType Container)){return @()}
    @(Get-ChildItem -LiteralPath $projectsRoot -Filter '*.json' -File -ErrorAction SilentlyContinue|Sort-Object Name|ForEach-Object {$project=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json -Depth 50;if([string]$project.stage-eq'RUNTIME' -and [string]$project.status-eq'PROMOTED'){$project}})
}
function Get-AidosAutonomousReviewAssignmentPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Record)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    if(-not[string]::IsNullOrWhiteSpace([string]$Record.assignment_path)){return (Resolve-AidosRecordBoundPath $root ([string]$Record.assignment_path))}
    Join-Path (Resolve-AidosRecordBoundPath $root ([string]$Record.package_path)) 'REVIEW_ASSIGNMENT.json'
}
function Invoke-AidosBoundReviewConsumer {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][string]$ReviewId,[Parameter(Mandatory)][string]$ResponsePath,[scriptblock]$ReviewConsumer)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root)
    $response=Get-Content -LiteralPath $ResponsePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
    if([string]$response.review_id-ne$ReviewId){throw 'Review response identity differs from active review.'}
    if([string]$response.outcome-eq'PASS'){
        # Persist an integration intent before the review consumer changes state to
        # IDLE. If the process dies after acceptance, the project manager can still
        # reconcile and integrate the exact PASS review on the next tick.
        New-AidosPassIntegrationIntent -ProjectRoot $root -ReviewId $ReviewId -ExecutionId ([string]$response.execution_id) -Revision ([int]$response.revision)|Out-Null
    }
    if($ReviewConsumer){& $ReviewConsumer $root $ResponsePath}else{Invoke-AidosReviewConsumer -ProjectRoot $root -ResponsePath $ResponsePath -Actor BRIDGE}
}
function Invoke-AidosAutonomousReviewTransportDispatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryRoot,[string]$ProcessName='ChatGPT Classic',[int]$ResponseTimeoutSeconds=5,[int]$MaxItems=1,
        [scriptblock]$ReviewInvoker,[scriptblock]$ReviewConsumer
    )
    if($MaxItems-lt1){throw 'MaxItems must be at least 1.'}
    $results=[Collections.Generic.List[object]]::new();$processed=0
    foreach($project in @(Get-AidosPortfolioRuntimeProjectsForReview -RegistryRoot $RegistryRoot)){
        if($processed-ge$MaxItems){break}
        $root=Resolve-AidosFileSystemPath ([string]$project.local_root);$state=Get-AidosState $root
        if([string]$state.state -notin @('GPT_REVIEWING','WAITING_INTERACTIVE_SESSION')){continue}
        try{
            $reconciled=Invoke-AidosReviewReconciliation -ProjectRoot $root
            if([string]$reconciled.status-ne'PUBLISHED'){$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status=[string]$reconciled.status;review=$reconciled});$processed++;continue}
            $reviewId=[string]$reconciled.review_id;$record=Read-AidosReviewRecord -ProjectRoot $root -ReviewId $reviewId
            if($null-eq$record){throw 'Published portfolio review record is missing.'}
            $responsePath=Get-AidosDesktopChatGPTResponsePath -ProjectRoot $root -ReviewId $reviewId
            $adapterState=Read-AidosDesktopChatGPTState -ProjectRoot $root -ReviewId $reviewId
            if($adapterState -and [string]$adapterState.status-eq'HANDOFF_COMPLETE' -and (Test-Path -LiteralPath $responsePath -PathType Leaf)){
                $consumed=Invoke-AidosBoundReviewConsumer -Project $project -ReviewId $reviewId -ResponsePath $responsePath -ReviewConsumer $ReviewConsumer
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='CONSUMED';review_id=$reviewId;outcome=$consumed});$processed++;continue
            }
            $assignmentPath=Get-AidosAutonomousReviewAssignmentPath -ProjectRoot $root -Record $record
            $desktop=if($ReviewInvoker){& $ReviewInvoker $root $assignmentPath $ProcessName $ResponseTimeoutSeconds}else{AidosDesktopSessionGate\Invoke-AidosDesktopChatGPTReview -ProjectRoot $root -AssignmentPath $assignmentPath -ProcessName $ProcessName -ResponseTimeoutSeconds $ResponseTimeoutSeconds -WaitForInteractiveSession:$false}
            if([string]$desktop.status-eq'HANDOFF_COMPLETE'){
                $responsePath=Get-AidosDesktopChatGPTResponsePath -ProjectRoot $root -ReviewId $reviewId
                $consumed=Invoke-AidosBoundReviewConsumer -Project $project -ReviewId $reviewId -ResponsePath $responsePath -ReviewConsumer $ReviewConsumer
                $results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='CONSUMED';review_id=$reviewId;transport=$desktop;outcome=$consumed})
            }else{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status=[string]$desktop.status;review_id=$reviewId;transport=$desktop})}
        }catch{$results.Add([pscustomobject][ordered]@{project_id=[string]$project.project_id;status='REVIEW_TRANSPORT_ERROR';error=$_.Exception.Message})}
        $processed++
    }
    [pscustomobject][ordered]@{status=if(@($results|Where-Object {$_.status-eq'REVIEW_TRANSPORT_ERROR'}).Count){'ERROR'}elseif($processed-gt0){'PROCESSED'}else{'IDLE'};processed=$processed;results=@($results)}
}

Export-ModuleMember -Function Get-AidosAutonomousExecutionPathFromState,Publish-AidosAutonomousReview,Get-AidosPortfolioRuntimeProjectsForReview,Get-AidosAutonomousReviewAssignmentPath,Invoke-AidosBoundReviewConsumer,Invoke-AidosAutonomousReviewTransportDispatch
