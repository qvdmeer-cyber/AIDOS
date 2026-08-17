[CmdletBinding()]
param(
    [string]$Distribution='Ubuntu',
    [string]$WslReposRoot='/home/aidos/repos',
    [string]$PreparationProjectId='AIDOS-INTERFACE',
    [string]$PreparationRepository='https://github.com/qvdmeer-cyber/AIDOS-interface.git',
    [string]$PreparationProjectName='AIDOS-interface',
    [string]$RuntimeProjectRoot,
    [string]$AuthorizedUser='AIDOS\qvdm'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not$IsWindows){throw 'This migration must run with PowerShell 7 on the Windows AIDOS host.'}

function Invoke-WslGitPull {
    param([Parameter(Mandatory)][string]$RepoName)
    $path="$WslReposRoot/$RepoName"
    $output=@(& wsl.exe --distribution $Distribution --cd $path --exec git -C $path pull --ff-only 2>&1)
    if($LASTEXITCODE-ne0){throw "Failed to update '$RepoName': $($output -join [Environment]::NewLine)"}
    [pscustomobject]@{repo=$RepoName;output=@($output)}
}
function Convert-WslPathToUnc {
    param([Parameter(Mandatory)][string]$Path)
    $relative=$Path.TrimStart('/').Replace('/','\')
    "\\wsl.localhost\$Distribution\$relative"
}

$sync=@()
foreach($repo in @('AIDOS','AIDOS-Builder','AIDOS-Contracts',$PreparationProjectName)){$sync+=Invoke-WslGitPull $repo}
$aidosRoot=Convert-WslPathToUnc "$WslReposRoot/AIDOS"
$builderRoot=Convert-WslPathToUnc "$WslReposRoot/AIDOS-Builder"
$contractsRoot=Convert-WslPathToUnc "$WslReposRoot/AIDOS-Contracts"
$projectWslRoot="$WslReposRoot/$PreparationProjectName"
$projectRoot=Convert-WslPathToUnc $projectWslRoot
$registryRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\project-registry'
$stateRoot=Join-Path $env:LOCALAPPDATA 'AIDOS\host-agent'

Import-Module (Join-Path $aidosRoot 'bridge/AidosProjectRegistry.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $aidosRoot 'bridge/AidosPreparationRuntime.psm1') -Force -DisableNameChecking

$registryPath=Get-AidosRegistryProjectPath -RegistryRoot $registryRoot -ProjectId $PreparationProjectId
if(Test-Path -LiteralPath $registryPath -PathType Leaf){
    $registered=Get-AidosRegisteredProject -RegistryRoot $registryRoot -ProjectId $PreparationProjectId
    if([string]$registered.repository -ne $PreparationRepository -or [string]$registered.local_root -ne [string](Get-Item -LiteralPath $projectRoot).FullName){throw 'Existing preparation registry binding differs from requested AIDOS Interface binding.'}
}else{
    $registered=Register-AidosPreparationProject -RegistryRoot $registryRoot -ProjectId $PreparationProjectId -Repository $PreparationRepository -LocalRoot $projectRoot -GitRuntimeKind WINDOWS_WSL -WslDistribution $Distribution -WslProjectRoot $projectWslRoot -AllowedPersistencePaths @('.aidos')
}
Test-AidosRegistryProjectBinding $registered|Out-Null

$validator=Join-Path $builderRoot 'tools/Test-AidosProjectBaseline.ps1'
$validation=& $validator -ProjectRoot $projectRoot -ContractsRoot $contractsRoot -NoExit
if(-not$validation.pass){throw "AIDOS Interface Baseline is not complete; next unresolved item: $($validation.next_item)"}
$baselinePath=Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json'
$baseline=Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
$acceptance=$null
if([string]::IsNullOrWhiteSpace([string]$baseline.accepted_at)){
    $acceptance=New-AidosPreparationBaselineAcceptanceRequest -ProjectRoot $projectRoot -BuilderRoot $builderRoot -ContractsRoot $contractsRoot
    $registered=Get-AidosRegisteredProject -RegistryRoot $registryRoot -ProjectId $PreparationProjectId
    $persistence=Invoke-AidosPreparationGitPersistence -Project $registered -CommitMessage 'AIDOS publish formal Project Baseline acceptance request' -Push
    Set-AidosPreparationProjectPhase -RegistryRoot $registryRoot -ProjectId $PreparationProjectId -Phase 'BASELINE_ACCEPTANCE' -Status WAITING_HUMAN|Out-Null
}else{
    $persistence=[pscustomobject]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}
    Set-AidosPreparationProjectPhase -RegistryRoot $registryRoot -ProjectId $PreparationProjectId -Phase 'RUNTIME_ONBOARDING' -Status READY_FOR_ONBOARDING|Out-Null
}

if([string]::IsNullOrWhiteSpace($RuntimeProjectRoot)){
    $configPath=Join-Path $stateRoot 'CONFIG.json'
    if(Test-Path -LiteralPath $configPath -PathType Leaf){$RuntimeProjectRoot=[string](Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 20).project_root}
    if([string]::IsNullOrWhiteSpace($RuntimeProjectRoot)){
        $candidate=Convert-WslPathToUnc "$WslReposRoot/AIDOS-BRIDGE-SMOKE"
        if(Test-Path -LiteralPath $candidate -PathType Container){$RuntimeProjectRoot=$candidate}
    }
}
if([string]::IsNullOrWhiteSpace($RuntimeProjectRoot)){throw 'Unable to resolve the existing runtime project root for the persistent host agent.'}
$agentEntry=Join-Path $aidosRoot 'bridge/Invoke-AidosPersistentLocalDesktopAgent.ps1'
$installJson=& $agentEntry -Command Install -ProjectRoot $RuntimeProjectRoot -AuthorizedUser $AuthorizedUser -StateRoot $stateRoot -PreparationRegistryRoot $registryRoot -BuilderRoot $builderRoot -ContractsRoot $contractsRoot -PreparationPush $true
$install=$installJson|ConvertFrom-Json -Depth 30

[pscustomobject][ordered]@{
    status='ENABLED'
    synced_repositories=@($sync|ForEach-Object {$_.repo})
    registry_root=$registryRoot
    preparation_project=(Get-AidosRegisteredProject -RegistryRoot $registryRoot -ProjectId $PreparationProjectId)
    baseline_validation=$validation
    acceptance_request=$acceptance
    persistence=$persistence
    host_agent=$install
}|ConvertTo-Json -Depth 100
