[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'bridge/AidosRepositoryHandoff.psm1') -Force -DisableNameChecking

$script:passed=0
function Assert-Handoff([bool]$Condition,[string]$Message){
    if(-not$Condition){throw "ASSERTION FAILED: $Message"}
    $script:passed++
}
function Assert-HandoffThrows([scriptblock]$Action,[string]$Pattern,[string]$Message){
    $thrown=$false
    try{& $Action}catch{$thrown=$true;if($_.Exception.Message-notmatch$Pattern){throw "ASSERTION FAILED: $Message; unexpected error: $($_.Exception.Message)"}}
    if(-not$thrown){throw "ASSERTION FAILED: $Message; no exception was thrown"}
    $script:passed++
}
function New-Binding {
    [pscustomobject][ordered]@{
        project_state='WAITING_DEFINITION'
        definition_id='DEF-1'
        definition_version=1
        execution_id=$null
        revision=$null
        review_id=$null
    }
}
function New-Metadata([string]$Kind,[string]$From,[string]$To,[string]$Parent=$null){
    [pscustomobject][ordered]@{
        schema_version='0.1'
        envelope_type='AIDOS_REPOSITORY_HANDOFF'
        handoff_id=[guid]::NewGuid().ToString()
        project_id='PROJECT-1'
        kind=$Kind
        from_actor=$From
        to_actor=$To
        status='READY'
        parent_handoff_id=$Parent
        created_at=[DateTimeOffset]::UtcNow.ToString('o')
        action=if($Kind-eq'ASSIGNMENT'){'START_DEFINITION'}else{'START_DEFINITION_RESULT'}
        payload_ref=if($Kind-eq'ASSIGNMENT'){'.aidos/runtime/actor-assignments/assignment-1.json'}else{'.aidos/runtime/actor-results/assignment-1.json'}
        payload_sha256=('a'*64)
        binding=New-Binding
        source_refs=@('docs/PRODUCT.md','AIDOS/agents/DEFINITION_AGENT.md')
    }
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aidos-repository-handoff-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp '.aidos') -Force|Out-Null
try{
    $assignment=New-Metadata -Kind ASSIGNMENT -From CORE -To THINKER
    $text=New-AidosRepositoryHandoffText -Metadata $assignment -Body "# Thinker assignment`n`nProcess the bound Definition assignment."
    $parsed=ConvertFrom-AidosRepositoryHandoffText -Text $text -ExpectedProjectId 'PROJECT-1'
    Assert-Handoff ([string]$parsed.metadata.handoff_id-eq[string]$assignment.handoff_id) 'metadata round-trips through HANDOFF.md markers'
    Assert-Handoff ($parsed.body.Contains('Process the bound Definition assignment.')) 'human-readable Markdown body round-trips'
    Assert-Handoff ($parsed.text_sha256-match'^[0-9a-f]{64}$') 'handoff text receives a deterministic SHA-256'
    Assert-Handoff ([string]$parsed.metadata.payload_ref-eq'.aidos/runtime/actor-assignments/assignment-1.json') 'payload_ref remains project-relative'

    $written=Write-AidosRepositoryHandoff -ProjectRoot $temp -Metadata $assignment -Body 'Initial assignment.'
    $read=Read-AidosRepositoryHandoff -ProjectRoot $temp -ExpectedProjectId 'PROJECT-1'
    Assert-Handoff ($null-ne$read) 'written repository handoff can be read from canonical path'
    Assert-Handoff ([string]$read.metadata.handoff_id-eq[string]$written.metadata.handoff_id) 'read handoff identity matches written identity'
    Assert-Handoff ((Get-AidosRepositoryHandoffRelativePath)-eq'.aidos/HANDOFF.md') 'canonical repository handoff path is stable'

    $result=New-Metadata -Kind RESULT -From THINKER -To CORE -Parent ([string]$assignment.handoff_id)
    $transition=Test-AidosRepositoryHandoffTransition -Previous $assignment -Next $result
    Assert-Handoff ([bool]$transition.valid) 'assigned Thinker may return a result to Core'

    $next=New-Metadata -Kind ASSIGNMENT -From CORE -To WORKER -Parent ([string]$result.handoff_id)
    $nextTransition=Test-AidosRepositoryHandoffTransition -Previous $result -Next $next
    Assert-Handoff ([bool]$nextTransition.valid) 'Core may publish the next Worker assignment after a result'

    $autoParent=New-Metadata -Kind RESULT -From THINKER -To CORE
    $autoWritten=Write-AidosRepositoryHandoff -ProjectRoot $temp -Metadata $autoParent -Body 'Result.' -ExpectedParentHandoffId ([string]$assignment.handoff_id)
    Assert-Handoff ([string]$autoWritten.metadata.parent_handoff_id-eq[string]$assignment.handoff_id) 'write fills parent_handoff_id from current canonical handoff when omitted'

    Assert-HandoffThrows {Test-AidosRepositoryHandoffMetadata -Metadata (New-Metadata -Kind ASSIGNMENT -From THINKER -To WORKER)} 'must be published by CORE' 'actors cannot directly assign one another'
    Assert-HandoffThrows {Test-AidosRepositoryHandoffMetadata -Metadata (New-Metadata -Kind RESULT -From THINKER -To WORKER)} 'must return to CORE' 'actor result cannot bypass Core'
    Assert-HandoffThrows {
        $bad=New-Metadata -Kind ASSIGNMENT -From CORE -To THINKER
        $bad.payload_ref='../outside.json'
        Test-AidosRepositoryHandoffMetadata -Metadata $bad
    } 'project-relative' 'payload path traversal is rejected'
    Assert-HandoffThrows {
        $wrong=New-Metadata -Kind RESULT -From WORKER -To CORE -Parent ([string]$assignment.handoff_id)
        Test-AidosRepositoryHandoffTransition -Previous $assignment -Next $wrong
    } 'actor result transition mismatch' 'result actor must match assigned actor'
    Assert-HandoffThrows {
        ConvertFrom-AidosRepositoryHandoffText -Text ($text+"`n<!-- AIDOS_HANDOFF_V1_BEGIN -->")
    } 'multiple begin markers' 'multiple metadata blocks are rejected'
    Assert-HandoffThrows {
        ConvertFrom-AidosRepositoryHandoffText -Text $text -ExpectedProjectId 'OTHER'
    } 'does not match' 'project binding is enforced'
    Assert-HandoffThrows {
        Write-AidosRepositoryHandoff -ProjectRoot $temp -Metadata (New-Metadata -Kind ASSIGNMENT -From CORE -To THINKER) -Body 'stale' -ExpectedParentHandoffId ([guid]::NewGuid().ToString())
    } 'parent changed' 'compare-and-swap parent prevents stale overwrite'

    Write-Output "PASS: $passed repository handoff assertions"
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
