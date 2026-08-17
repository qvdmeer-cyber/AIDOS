Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking

$script:OperatorCommands=@('RUN','PAUSE','RESUME','SAFE_STOP','QUERY_STATUS','SUBMIT_HUMAN_INPUT','REQUEST_RECOVERY')

function Get-AidosOptionalProperty {
    param($Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if($null -eq $Object){return $Default}
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){return $Default}
    $property.Value
}

function Get-AidosOperatorRoot { param([string]$ProjectRoot)
    Join-Path (Resolve-AidosFileSystemPath $ProjectRoot) '.aidos/operator'
}
function Get-AidosOperatorControlsRoot { param([string]$ProjectRoot) Join-Path (Get-AidosOperatorRoot $ProjectRoot) 'controls' }
function Get-AidosOperatorControlIntentPath { param([string]$ProjectRoot,[string]$ControlId) Join-Path (Get-AidosOperatorControlsRoot $ProjectRoot) ($ControlId+'.json') }
function Get-AidosOperatorControlStatePath { param([string]$ProjectRoot) Join-Path (Get-AidosOperatorRoot $ProjectRoot) 'CONTROL_STATE.json' }

function Get-AidosOperatorControlState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path=Get-AidosOperatorControlStatePath $ProjectRoot
    if(Test-Path -LiteralPath $path -PathType Leaf){return Read-AidosJson $path}
    [pscustomobject][ordered]@{schema_version='0.1';mode='RUNNING';updated_at=$null;updated_by=$null;last_control_id=$null}
}
function Set-AidosOperatorControlState {
    param([string]$ProjectRoot,[string]$Mode,[string]$RequestedBy,[string]$ControlId)
    $state=[ordered]@{schema_version='0.1';mode=$Mode;updated_at=[DateTimeOffset]::UtcNow.ToString('o');updated_by=$RequestedBy;last_control_id=$ControlId}
    Write-AidosJsonAtomic (Get-AidosOperatorControlStatePath $ProjectRoot) $state
    [pscustomobject]$state
}
function Submit-AidosControlIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][ValidateSet('RUN','PAUSE','RESUME','SAFE_STOP','QUERY_STATUS','SUBMIT_HUMAN_INPUT','REQUEST_RECOVERY')][string]$Command,
        [Parameter(Mandatory)][string]$RequestedBy,
        $Payload,
        [string]$WorkstreamId
    )
    $root=Resolve-AidosFileSystemPath $ProjectRoot
    $profile=Get-AidosProjectProfile $root
    $controlId=[guid]::NewGuid().ToString();$now=[DateTimeOffset]::UtcNow.ToString('o')
    $record=[ordered]@{schema_version='0.1';control_id=$controlId;command=$Command;project_id=[string]$profile.project_id;workstream_id=if([string]::IsNullOrWhiteSpace($WorkstreamId)){$null}else{$WorkstreamId};requested_by=$RequestedBy;status='RECEIVED';payload=$Payload;submitted_at=$now;applied_at=$null;result=$null}
    $path=Get-AidosOperatorControlIntentPath $root $controlId
    Write-AidosJsonAtomic $path $record
    try{
        switch($Command){
            'PAUSE' {$record.result=Set-AidosOperatorControlState $root 'PAUSED' $RequestedBy $controlId;$record.status='APPLIED'}
            'SAFE_STOP' {$record.result=Set-AidosOperatorControlState $root 'SAFE_STOPPED' $RequestedBy $controlId;$record.status='APPLIED'}
            'RUN' {$record.result=Set-AidosOperatorControlState $root 'RUNNING' $RequestedBy $controlId;$record.status='APPLIED'}
            'RESUME' {$record.result=Set-AidosOperatorControlState $root 'RUNNING' $RequestedBy $controlId;$record.status='APPLIED'}
            'QUERY_STATUS' {$record.result=Get-AidosOperatorSnapshot -ProjectRoot $root;$record.status='APPLIED'}
            'SUBMIT_HUMAN_INPUT' {throw 'SUBMIT_HUMAN_INPUT is routed through the dedicated Human Input processor.'}
            'REQUEST_RECOVERY' {throw 'REQUEST_RECOVERY processor is not implemented.'}
        }
    }catch{$record.status='REJECTED';$record.result=[ordered]@{reason=$_.Exception.Message}}
    $record.applied_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic $path $record
    [pscustomobject][ordered]@{intent=[pscustomobject]$record;path=[IO.Path]::GetRelativePath($root,$path).Replace('\','/')}
}
function Get-AidosOperatorSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$HostAgentStateRoot)
    $root=Resolve-AidosFileSystemPath $ProjectRoot;$profile=Get-AidosProjectProfile $root;$state=Get-AidosState $root;$control=Get-AidosOperatorControlState $root
    $humanInputRoot=Join-Path $root '.aidos/human-input';$human=@()
    if(Test-Path -LiteralPath $humanInputRoot -PathType Container){$human=@(Get-ChildItem -LiteralPath $humanInputRoot -Filter '*.json' -File -ErrorAction SilentlyContinue|ForEach-Object {try{Read-AidosJson $_.FullName}catch{$null}}|Where-Object {$null-ne$_})}
    $eventsRoot=Join-Path $root '.aidos/events';$events=@()
    if(Test-Path -LiteralPath $eventsRoot -PathType Container){$events=@(Get-ChildItem -LiteralPath $eventsRoot -Filter '*.jsonl' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 5|ForEach-Object {[pscustomobject]@{path=[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/');last_write_utc=$_.LastWriteTimeUtc.ToString('o')}})}
    $host=$null
    if(-not[string]::IsNullOrWhiteSpace($HostAgentStateRoot)){$statusPath=Join-Path $HostAgentStateRoot 'STATUS.json';if(Test-Path -LiteralPath $statusPath -PathType Leaf){$host=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json -Depth 100}}
    [pscustomobject][ordered]@{schema_version='0.1';project=[ordered]@{project_id=[string]$profile.project_id;repository=[string]$profile.repository;project_mode=[string]$profile.project_mode;runner_policy=[string]$profile.runner_policy};runtime=[ordered]@{state=[string]$state.state;definition_id=$state.definition_id;definition_version=$state.definition_version;execution_id=$state.execution_id;revision=$state.revision;review_id=$state.review_id;terminal_result=$state.terminal_result;validation_result=$state.validation_result;updated_at=$state.updated_at};control=$control;human_input=[ordered]@{waiting=@($human|Where-Object {$_.status-eq'WAITING'});resolved=@($human|Where-Object {$_.status-eq'RESOLVED'})};recent_events=$events;host_agent=$host;observed_at=[DateTimeOffset]::UtcNow.ToString('o')}
}

Export-ModuleMember -Function Get-AidosOperatorControlState,Set-AidosOperatorControlState,Submit-AidosControlIntent,Get-AidosOperatorSnapshot
