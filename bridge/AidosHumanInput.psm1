Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -Force -DisableNameChecking

function Invoke-AidosHumanInputExclusive {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][scriptblock]$ScriptBlock,[int]$TimeoutSeconds=15)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $dir=Join-Path $root '.aidos/runtime'
    if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $lock=$null
    while($null -eq $lock){
        try{$lock=[IO.FileStream]::new((Join-Path $dir 'human-input.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException]{if([DateTimeOffset]::UtcNow -ge $deadline){throw 'Timed out acquiring AIDOS Human Input lock.'};Start-Sleep -Milliseconds 50}
    }
    try{&$ScriptBlock}finally{$lock.Dispose()}
}

function Get-AidosHumanInputRequestPath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RequestId)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/human-input/{0}.json' -f $RequestId)
}

function Get-AidosHumanInputProjectId {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $profilePath=Join-Path $root '.aidos/PROJECT.json'
    if(Test-Path -LiteralPath $profilePath -PathType Leaf){return [string](Read-AidosJson $profilePath).project_id}
    $baselinePath=Join-Path $root '.aidos/documentation/PROJECT_BASELINE.json'
    if(Test-Path -LiteralPath $baselinePath -PathType Leaf){return [string](Read-AidosJson $baselinePath).project_id}
    throw 'Unable to determine AIDOS project identity from runtime profile or Project Baseline.'
}

function Assert-AidosHumanInputBinding {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Request)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $binding=$Request.binding
    if($null -eq $binding){throw 'Human Input Request binding is missing.'}
    if($null -ne $binding.baseline_version){
        $baselinePath=Join-Path $root '.aidos/documentation/PROJECT_BASELINE.json'
        if(-not(Test-Path -LiteralPath $baselinePath -PathType Leaf)){throw 'Bound Project Baseline is unavailable.'}
        $baseline=Read-AidosJson $baselinePath
        if([int]$baseline.baseline_version -ne [int]$binding.baseline_version){throw 'Human Input Request baseline binding mismatch.'}
    }
    $runtimeFields=@('definition_id','definition_version','execution_id','revision','review_id')
    $requiresRuntime=$false
    foreach($name in $runtimeFields){if($null -ne $binding.$name){$requiresRuntime=$true;break}}
    if(-not$requiresRuntime){return}
    $statePath=Join-Path $root '.aidos/STATE.json'
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'Bound runtime state is unavailable.'}
    $state=Read-AidosJson $statePath
    foreach($name in $runtimeFields){
        $expected=$binding.$name
        if($null -eq $expected){continue}
        $property=$state.PSObject.Properties[$name]
        if($null -eq $property -or [string]$property.Value -ne [string]$expected){throw "Human Input Request binding mismatch for '$name'."}
    }
}

function Get-AidosHumanInputResumePath {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RequestId)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) ('.aidos/runtime/resume/{0}.json' -f $RequestId)
}

function Submit-AidosHumanInputResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$RespondedBy,
        [string]$SelectedOptionId,
        [string]$Text
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $projectId=Get-AidosHumanInputProjectId $root
    $requestPath=Get-AidosHumanInputRequestPath -ProjectRoot $root -RequestId $RequestId
    if(-not(Test-Path -LiteralPath $requestPath -PathType Leaf)){throw "Human Input Request not found: $RequestId"}
    if([string]::IsNullOrWhiteSpace($SelectedOptionId) -and [string]::IsNullOrWhiteSpace($Text)){throw 'Human input requires selected_option_id and/or text.'}

    Invoke-AidosHumanInputExclusive -ProjectRoot $root -ScriptBlock {
        $request=Read-AidosJson $requestPath
        if([string]$request.request_id -ne $RequestId){throw 'Human Input Request identity mismatch.'}
        if([string]$request.project_id -ne $projectId){throw 'Human Input Request project binding mismatch.'}
        Assert-AidosHumanInputBinding -ProjectRoot $root -Request $request
        if(-not[string]::IsNullOrWhiteSpace($SelectedOptionId)){
            $matches=@($request.options|Where-Object {[string]$_.option_id -eq $SelectedOptionId})
            if($matches.Count -ne 1){throw "Selected option '$SelectedOptionId' is not permitted by request '$RequestId'."}
        }
        if([string]$request.status -eq 'RESOLVED'){
            $sameOption=[string]$request.response.selected_option_id -eq [string]$SelectedOptionId
            $sameText=[string]$request.response.text -eq [string]$Text
            if(-not($sameOption -and $sameText)){throw 'Human Input Request is already resolved with a different response.'}
            $resumePath=Get-AidosHumanInputResumePath -ProjectRoot $root -RequestId $RequestId
            return [pscustomobject][ordered]@{status='ALREADY_RESOLVED';request=$request;resume_ref=if(Test-Path -LiteralPath $resumePath){[IO.Path]::GetRelativePath($root,$resumePath).Replace('\','/')}else{$null}}
        }
        if([string]$request.status -ne 'WAITING'){throw "Human Input Request status '$($request.status)' cannot accept a response."}
        $now=[DateTimeOffset]::UtcNow.ToString('o')
        $request.response=[pscustomobject][ordered]@{responded_by=$RespondedBy;responded_at=$now;selected_option_id=if([string]::IsNullOrWhiteSpace($SelectedOptionId)){$null}else{$SelectedOptionId};text=if([string]::IsNullOrWhiteSpace($Text)){$null}else{$Text}}
        $request.status='RESOLVED';$request.updated_at=$now
        Write-AidosJsonAtomic $requestPath $request
        $resume=[ordered]@{schema_version='0.1';resume_id=[guid]::NewGuid().ToString();request_id=$RequestId;project_id=$projectId;workstream_id=$request.workstream_id;phase=$request.phase;resume_actor_role=$request.resume_actor_role;binding=$request.binding;response_ref=[IO.Path]::GetRelativePath($root,$requestPath).Replace('\','/');status='PENDING';created_at=$now;updated_at=$now;applied_at=$null;result=$null}
        $resumePath=Get-AidosHumanInputResumePath -ProjectRoot $root -RequestId $RequestId
        if(Test-Path -LiteralPath $resumePath){throw "Resume intent already exists for request '$RequestId'."}
        Write-AidosJsonAtomic $resumePath $resume
        [pscustomobject][ordered]@{status='RESOLVED';request=$request;resume_ref=[IO.Path]::GetRelativePath($root,$resumePath).Replace('\','/');resume=[pscustomobject]$resume}
    }
}

function Submit-AidosHumanInputControlIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)][string]$RequestedBy,[Parameter(Mandatory)][hashtable]$Payload,[string]$WorkstreamId)
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $projectId=Get-AidosHumanInputProjectId $root
    $requestId=[string]$Payload.request_id
    if([string]::IsNullOrWhiteSpace($requestId)){throw 'SUBMIT_HUMAN_INPUT payload requires request_id.'}
    $selectedOptionId=[string]$Payload.selected_option_id;$text=[string]$Payload.text
    $controlId=[guid]::NewGuid().ToString();$now=[DateTimeOffset]::UtcNow.ToString('o')
    $intent=[ordered]@{schema_version='0.1';control_id=$controlId;command='SUBMIT_HUMAN_INPUT';project_id=$projectId;workstream_id=if([string]::IsNullOrWhiteSpace($WorkstreamId)){$null}else{$WorkstreamId};requested_by=$RequestedBy;status='RECEIVED';payload=$Payload;submitted_at=$now;applied_at=$null;result=$null}
    $intentRoot=Join-Path $root '.aidos/control/intents';if(-not(Test-Path -LiteralPath $intentRoot -PathType Container)){New-Item -ItemType Directory -Path $intentRoot -Force|Out-Null}
    $intentPath=Join-Path $intentRoot ($controlId+'.json');Write-AidosJsonAtomic $intentPath $intent
    try{$intent.status='ACCEPTED';Write-AidosJsonAtomic $intentPath $intent;$result=Submit-AidosHumanInputResponse -ProjectRoot $root -RequestId $requestId -RespondedBy $RequestedBy -SelectedOptionId $selectedOptionId -Text $text;$intent.result=[ordered]@{human_input=$result};$intent.status='APPLIED'}catch{$intent.status='REJECTED';$intent.result=[ordered]@{reason=$_.Exception.Message}}
    $intent.applied_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic $intentPath $intent
    [pscustomobject][ordered]@{intent=[pscustomobject]$intent;path=[IO.Path]::GetRelativePath($root,$intentPath).Replace('\','/')}
}

Export-ModuleMember -Function Get-AidosHumanInputProjectId,Get-AidosHumanInputRequestPath,Get-AidosHumanInputResumePath,Submit-AidosHumanInputResponse,Submit-AidosHumanInputControlIntent
