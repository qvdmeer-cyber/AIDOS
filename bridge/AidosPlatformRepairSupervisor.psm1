Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

Import-Module (Join-Path $PSScriptRoot 'AidosBridge.psm1') -DisableNameChecking

function Get-AidosPlatformRepairPath {
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$RepairId)
    Join-Path ([IO.Path]::GetFullPath($StateRoot)) ("platform-repairs/{0}.json" -f $RepairId)
}
function Get-AidosPlatformRepairClassification {
    param([Parameter(Mandatory)][string]$ErrorText,[Parameter(Mandatory)][string]$Component)
    if($Component -match 'ChatGPT|Thinker|composer|gateway|bridge|SendInput' -or $ErrorText -match 'ChatGPT|composer|SendInput|UI Automation|WebView|gateway|bridge|focus|sentinel'){'PLATFORM_TRANSPORT'}
    elseif($Component -match 'Interface|Core|runtime' -or $ErrorText -match 'self-update|watchdog|runtime|module'){if($Component -match 'Interface'){'PLATFORM_INTERFACE'}else{'PLATFORM_RUNTIME'}}
    else{'HUMAN_REQUIRED'}
}
function Get-AidosPlatformRepairAllowedPaths {
    param([Parameter(Mandatory)][ValidateSet('AIDOS','AIDOS-interface')][string]$Repository)
    if($Repository-eq'AIDOS'){@('bridge/','schemas/','tests/','docs/','tools/')}
    else {@('src/client/ui/','src/server/','src/shared/','tests/','docs/','scripts/')}
}
function Test-AidosPlatformRepairPaths {
    param([Parameter(Mandatory)][ValidateSet('AIDOS','AIDOS-interface')][string]$Repository,[Parameter(Mandatory)][string[]]$Paths)
    $allowed=@(Get-AidosPlatformRepairAllowedPaths $Repository)
    foreach($path in @($Paths)){
        $normalized=([string]$path).Replace('\','/').TrimStart('./')
        if($normalized -match '(^|/)(\.aidos|secrets?|credentials?)(/|$)' -or $normalized -match '(?i)(api[_-]?key|password|token)'){throw "Platform repair path is forbidden: $path"}
        if(-not(@($allowed|Where-Object {$normalized.StartsWith($_,[StringComparison]::OrdinalIgnoreCase)}).Count)){throw "Platform repair path is outside the $Repository platform allowlist: $path"}
    }
    $true
}
function New-AidosPlatformRepairBlocker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$Component,[Parameter(Mandatory)][string]$ErrorText,[Parameter(Mandatory)][ValidateSet('AIDOS','AIDOS-interface')][string]$Repository,[Parameter(Mandatory)][string[]]$EvidenceRefs,[string[]]$Paths=@())
    $classification=Get-AidosPlatformRepairClassification -ErrorText $ErrorText -Component $Component
    $fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes("$Repository|$Component|$ErrorText"))).ToLowerInvariant()
    $blockerId="PLATFORM-$($fingerprint.Substring(0,24))";$repairId="REPAIR-$([guid]::NewGuid().ToString('N'))"
    $path=Get-AidosPlatformRepairPath -StateRoot $StateRoot -RepairId $repairId
    $value=[ordered]@{schema_version='0.1';repair_id=$repairId;blocker_id=$blockerId;status='DETECTED';classification=$classification;component=$Component;repository=$Repository;allowed_paths=if($Paths.Count){@($Paths)}else{@(Get-AidosPlatformRepairAllowedPaths $Repository)};evidence_refs=@($EvidenceRefs);attempt=0;max_attempts=1;last_error=$ErrorText;created_at=[DateTimeOffset]::UtcNow.ToString('o');updated_at=[DateTimeOffset]::UtcNow.ToString('o')}
    if($classification-eq'HUMAN_REQUIRED'){ $value.status='BLOCKED' }
    Write-AidosJsonAtomic -Path $path -Value ([pscustomobject]$value)
    [pscustomobject][ordered]@{status=[string]$value.status;repair_id=$repairId;blocker_id=$blockerId;classification=$classification;path=$path}
}
function New-AidosPlatformRepairAssignment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)]$Blocker)
    if([string]$Blocker.classification-eq'HUMAN_REQUIRED'){throw 'Human-required platform blockers cannot receive autonomous Codex repair assignments.'}
    Test-AidosPlatformRepairPaths -Repository ([string]$Blocker.repository) -Paths @($Blocker.allowed_paths)|Out-Null
    $path=Get-AidosPlatformRepairPath -StateRoot $StateRoot -RepairId ([string]$Blocker.repair_id);$record=Read-AidosJson $path
    if([string]$record.status-in @('ASSIGNED','PATCHED','VALIDATED','SELF_UPDATED','RETRY_PENDING','RESOLVED')){return [pscustomobject][ordered]@{status='ALREADY_ASSIGNED';repair_id=$record.repair_id;path=$path}}
    $record.status='ASSIGNED';$record.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic -Path $path -Value $record
    [pscustomobject][ordered]@{status='ASSIGNED';repair_id=[string]$record.repair_id;repository=[string]$record.repository;allowed_paths=@($record.allowed_paths);evidence_refs=@($record.evidence_refs);assignment_path=$path;instruction='Repair only the authorized platform paths. Add tests, validate, commit, and return durable repair artifacts. Do not modify project state or secrets.'}
}
function Complete-AidosPlatformRepairValidation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][string]$RepairId,[Parameter(Mandatory)][bool]$TestsPassed,[Parameter(Mandatory)][string]$Commit,[Parameter(Mandatory)][string[]]$ChangedPaths)
    $path=Get-AidosPlatformRepairPath -StateRoot $StateRoot -RepairId $RepairId;$record=Read-AidosJson $path
    if(-not$TestsPassed){throw 'Platform repair cannot advance without passing validation.'};Test-AidosPlatformRepairPaths -Repository ([string]$record.repository) -Paths $ChangedPaths|Out-Null
    $record.status='VALIDATED';$record.attempt=[int]$record.attempt+1
    if(-not$record.PSObject.Properties['commit']){$record|Add-Member -NotePropertyName commit -NotePropertyValue $null}
    if(-not$record.PSObject.Properties['changed_paths']){$record|Add-Member -NotePropertyName changed_paths -NotePropertyValue @()}
    $record.commit=$Commit;$record.changed_paths=@($ChangedPaths);$record.updated_at=[DateTimeOffset]::UtcNow.ToString('o');Write-AidosJsonAtomic -Path $path -Value $record
    [pscustomobject][ordered]@{status='VALIDATED';repair_id=$RepairId;commit=$Commit;changed_paths=@($ChangedPaths)}
}
Export-ModuleMember -Function Get-AidosPlatformRepairPath,Get-AidosPlatformRepairClassification,Get-AidosPlatformRepairAllowedPaths,Test-AidosPlatformRepairPaths,New-AidosPlatformRepairBlocker,New-AidosPlatformRepairAssignment,Complete-AidosPlatformRepairValidation
