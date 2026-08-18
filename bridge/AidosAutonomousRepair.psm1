Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosProjectRegistry.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosAutonomousExecution.psm1') -DisableNameChecking

function ConvertTo-AidosRepairExecutionCopy {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Execution,[Parameter(Mandatory)][int]$Revision,[Parameter(Mandatory)][string]$RepairKind,[Parameter(Mandatory)][string[]]$Guidance,[Parameter(Mandatory)][string[]]$EvidenceRefs)
    $copy=($Execution|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -AsHashtable)
    $copy['revision']=$Revision
    $scope=if($copy.ContainsKey('scope') -and $copy['scope']){$copy['scope']}else{@{}}
    $scope['repair']=[ordered]@{kind=$RepairKind;guidance=@($Guidance);evidence_refs=@($EvidenceRefs)}
    $copy['scope']=$scope
    $copy['goal']=("Repair revision {0}: {1}" -f $Revision,(@($Guidance)-join ' | '))
    [pscustomobject]$copy
}

function Write-AidosRepairRevision {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)]$CurrentExecution,[Parameter(Mandatory)][string]$RepairKind,[Parameter(Mandatory)][string[]]$Guidance,[Parameter(Mandatory)][string[]]$EvidenceRefs)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$nextRevision=[int]$CurrentExecution.revision+1
    $nextPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$CurrentExecution.execution_id) -Revision $nextRevision
    if(Test-Path -LiteralPath $nextPath -PathType Leaf){
        $existing=Read-AidosJson $nextPath
        if([string]$existing.execution_id-ne[string]$CurrentExecution.execution_id -or [int]$existing.revision-ne$nextRevision){throw 'Existing repair revision binding mismatch.'}
        $state=Get-AidosState $root
        if([string]$state.state-ne'TASK_READY'){Set-AidosState -ProjectRoot $root -NewState TASK_READY -Actor SYSTEM -Patch @{}|Out-Null}
        Set-AidosExecutionDispatchBinding -ProjectRoot $root -ExecutionId ([string]$CurrentExecution.execution_id) -Revision $nextRevision|Out-Null
        return [pscustomobject][ordered]@{status='ALREADY_PLANNED';execution_path=$nextPath;execution=$existing}
    }
    $next=ConvertTo-AidosRepairExecutionCopy -Execution $CurrentExecution -Revision $nextRevision -RepairKind $RepairKind -Guidance $Guidance -EvidenceRefs $EvidenceRefs
    Write-AidosJsonAtomic $nextPath $next
    $state=Get-AidosState $root
    if([string]$state.state-ne'TASK_READY'){Set-AidosState -ProjectRoot $root -NewState TASK_READY -Actor SYSTEM -Patch @{}|Out-Null}
    Set-AidosExecutionDispatchBinding -ProjectRoot $root -ExecutionId ([string]$CurrentExecution.execution_id) -Revision $nextRevision|Out-Null
    Add-AidosEvent -ProjectRoot $root -EventType 'EXECUTION_REPAIR_PLANNED' -Actor SYSTEM -Payload @{execution_id=[string]$CurrentExecution.execution_id;from_revision=[int]$CurrentExecution.revision;revision=$nextRevision;repair_kind=$RepairKind;evidence_refs=@($EvidenceRefs)}|Out-Null
    [pscustomobject][ordered]@{status='PLANNED';execution_path=$nextPath;execution=$next;persistence=[pscustomobject][ordered]@{status='LOCAL_DURABLE';reason='Repair revision is preserved with the uncommitted Worker delta until review/integration.'}}
}

function Invoke-AidosAutonomousValidationRepairPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project,[switch]$Push)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$state=Get-AidosState $root
    if([string]$state.state-ne'EXECUTION_VALIDATION_FAILED'){throw "Validation repair planning requires EXECUTION_VALIDATION_FAILED, found '$($state.state)'."}
    $executionPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision)
    if(-not(Test-Path -LiteralPath $executionPath -PathType Leaf)){throw 'Validation repair source Execution is missing.'}
    $execution=Read-AidosJson $executionPath
    $validationPath=if([string]::IsNullOrWhiteSpace([string]$state.validation_result)){Join-Path (Split-Path -Parent $executionPath) 'VALIDATION.json'}else{Join-Path $root ([string]$state.validation_result)}
    if(-not(Test-Path -LiteralPath $validationPath -PathType Leaf)){throw 'Validation repair requires durable validation evidence.'}
    $validation=Read-AidosJson $validationPath
    $guidance=[Collections.Generic.List[string]]::new()
    if($validation.PSObject.Properties['error'] -and -not[string]::IsNullOrWhiteSpace([string]$validation.error)){$guidance.Add([string]$validation.error)}
    foreach($validator in @($validation.validators|Where-Object {-not[bool]$_.passed})){
        $tail=@($validator.output|Select-Object -Last 20)-join [Environment]::NewLine
        $guidance.Add(("Fix failing validator '{0}' (exit {1}). {2}" -f [string]$validator.validator,[string]$validator.exit_code,$tail))
    }
    foreach($requirement in @($validation.requirements|Where-Object {-not[bool]$_.passed})){$guidance.Add(("Satisfy execution evidence requirement: {0}" -f ($requirement|ConvertTo-Json -Compress -Depth 20)))}
    if($guidance.Count-eq0){$guidance.Add('Repair the deterministic execution validation failure without changing accepted Definition scope.')}
    $validationRef=[IO.Path]::GetRelativePath($root,$validationPath).Replace('\','/')
    Write-AidosRepairRevision -Project $Project -CurrentExecution $execution -RepairKind 'VALIDATION_FAILURE' -Guidance @($guidance) -EvidenceRefs @($validationRef)
}

function Get-AidosLatestRepairReview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][int]$Revision)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$reviewsRoot=Join-Path $root '.aidos/reviews'
    if(-not(Test-Path -LiteralPath $reviewsRoot -PathType Container)){return $null}
    $matches=@(Get-ChildItem -LiteralPath $reviewsRoot -Recurse -Filter 'REVIEW.json' -File -ErrorAction SilentlyContinue|ForEach-Object {try{$r=Read-AidosJson $_.FullName;if([string]$r.execution_id-eq$ExecutionId -and [int]$r.revision-eq$Revision -and $r.decision -and [string]$r.decision.outcome-eq'REPAIR'){$r|Add-Member -NotePropertyName _record_path -NotePropertyValue $_.FullName -Force;$r}}catch{}}|Sort-Object {[DateTimeOffset]$_.updated_at} -Descending)
    if($matches.Count){$matches[0]}else{$null}
}

function Ensure-AidosReviewRepairRevision {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Project)
    $root=Resolve-AidosFileSystemPath ([string]$Project.local_root);$state=Get-AidosState $root
    if([string]$state.state-ne'TASK_READY' -or [string]::IsNullOrWhiteSpace([string]$state.execution_id)-or$null-eq$state.revision){return [pscustomobject][ordered]@{status='NOT_APPLICABLE'}}
    $review=Get-AidosLatestRepairReview -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision)
    if($null-eq$review){return [pscustomobject][ordered]@{status='NO_REPAIR_REVIEW'}}
    $currentPath=Get-AidosExecutionArtifactPath -ProjectRoot $root -ExecutionId ([string]$state.execution_id) -Revision ([int]$state.revision)
    if(-not(Test-Path -LiteralPath $currentPath -PathType Leaf)){throw 'Review repair source Execution is missing.'}
    $current=Read-AidosJson $currentPath
    $guidance=@($review.response.repair_guidance|ForEach-Object {[string]$_}|Where-Object {-not[string]::IsNullOrWhiteSpace($_)})
    if($guidance.Count-eq0 -and -not[string]::IsNullOrWhiteSpace([string]$review.decision.reason)){$guidance=@([string]$review.decision.reason)}
    if($guidance.Count-eq0){$guidance=@('Repair the reviewed implementation inside the accepted Definition without scope expansion.')}
    $reviewRef=[IO.Path]::GetRelativePath($root,[string]$review._record_path).Replace('\','/')
    Write-AidosRepairRevision -Project $Project -CurrentExecution $current -RepairKind 'REVIEW_REPAIR' -Guidance $guidance -EvidenceRefs @($reviewRef)
}

Export-ModuleMember -Function ConvertTo-AidosRepairExecutionCopy,Write-AidosRepairRevision,Invoke-AidosAutonomousValidationRepairPlan,Get-AidosLatestRepairReview,Ensure-AidosReviewRepairRevision
