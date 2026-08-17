[CmdletBinding()]
param(
    [ValidateSet('Snapshot','Status','Control')][string]$Command='Snapshot',
    [Parameter(Mandatory)][string]$ProjectRoot,
    [string]$HostAgentStateRoot,
    [ValidateSet('RUN','PAUSE','RESUME','SAFE_STOP','QUERY_STATUS','SUBMIT_HUMAN_INPUT','REQUEST_RECOVERY')][string]$ControlCommand,
    [string]$RequestedBy='LOCAL_OPERATOR',
    [string]$WorkstreamId,
    [hashtable]$Payload=@{},
    [int]$EventLimit=25
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosOperator.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AidosHumanInput.psm1') -Force -DisableNameChecking

switch($Command){
    'Snapshot' {
        Get-AidosOperatorSnapshot -ProjectRoot $ProjectRoot -HostAgentStateRoot $HostAgentStateRoot -EventLimit $EventLimit |
            ConvertTo-Json -Depth 100
    }
    'Status' {
        Get-AidosRuntimeStatusProjection -ProjectRoot $ProjectRoot |
            ConvertTo-Json -Depth 100
    }
    'Control' {
        if([string]::IsNullOrWhiteSpace($ControlCommand)){throw 'Control requires -ControlCommand.'}
        if($ControlCommand -eq 'SUBMIT_HUMAN_INPUT'){
            Submit-AidosHumanInputControlIntent -ProjectRoot $ProjectRoot -RequestedBy $RequestedBy -WorkstreamId $WorkstreamId -Payload $Payload |
                ConvertTo-Json -Depth 100
        }else{
            Submit-AidosControlIntent -ProjectRoot $ProjectRoot -Command $ControlCommand -RequestedBy $RequestedBy -WorkstreamId $WorkstreamId -Payload $Payload |
                ConvertTo-Json -Depth 100
        }
    }
}
