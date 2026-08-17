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
function Invoke-AidosBootstrapModuleCommand {
    param(
        [Parameter(Mandatory)][string]$ModulePath,
        [Parameter(Mandatory)][string]$CommandName,
        [hashtable]$Arguments=@{}
    )
    # Resolve a fresh command object for every cross-module call. This is intentionally
    # independent of caller/module scope because nested -Force imports may replace a
    # previously loaded module during the same bootstrap process.
    $module=Import-Module -Name $ModulePath -Force -DisableNameChecking -PassThru -ErrorAction Stop
    $command=Get-Command -Name $CommandName -Module $module.Name -ErrorAction Stop | Select-Object -First 1
    if($null -eq $command){throw "Command '$CommandName' was not exported by '$ModulePath'."}
    & $command @Arguments
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
$registryModule=Join-Path $aidosRoot 'bridge/AidosProjectRegistry.psm1'
$runtimeModule=Join-Path $aidosRoot 'bridge/AidosPreparationRuntime.psm1'

$registryPath=Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Get-AidosRegistryProjectPath' -Arguments @{RegistryRoot=$registryRoot;ProjectId=$PreparationProjectId}
if(Test-Path -LiteralPath $registryPath -PathType Leaf){
    $registered=Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Get-AidosRegisteredProject' -Arguments @{RegistryRoot=$registryRoot;ProjectId=$PreparationProjectId}
    if([string]$registered.repository -ne $PreparationRepository -or [string]$registered.local_root -ne [string](Get-Item -LiteralPath $projectRoot).FullName){throw 'Existing preparation registry binding differs from requested AIDOS Interface binding.'}
    if($registered.PSObject.Properties['project_mode'] -and [string]$registered.project_mode -ne 'NEW_PROJECT'){throw 'Existing preparation registry project_mode is not NEW_PROJECT.'}
    if($registered.PSObject.Properties['runner_policy'] -and [string]$registered.runner_policy -ne 'UNATTENDED_ALLOWED'){throw 'Existing preparation registry runner_policy is not UNATTENDED_ALLOWED.'}
}else{
    $registered=Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Register-AidosPreparationProject' -Arguments @{
        RegistryRoot=$registryRoot;ProjectId=$PreparationProjectId;Repository=$PreparationRepository;LocalRoot=$projectRoot;
        ProjectMode='NEW_PROJECT';DefaultBranch='main';RunnerPolicy='UNATTENDED_ALLOWED';GitRuntimeKind='WINDOWS_WSL';
        WslDistribution=$Distribution;WslProjectRoot=$projectWslRoot;AllowedPersistencePaths=@('.aidos')
    }
}
Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Test-AidosRegistryProjectBinding' -Arguments @{Project=$registered}|Out-Null

$validator=Join-Path $builderRoot 'tools/Test-AidosProjectBaseline.ps1'
$validation=& $validator -ProjectRoot $projectRoot -ContractsRoot $contractsRoot -NoExit
if(-not$validation.pass){throw "AIDOS Interface Baseline is not complete; next unresolved item: $($validation.next_item)"}
$baselinePath=Join-Path $projectRoot '.aidos/documentation/PROJECT_BASELINE.json'
$baseline=Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8|ConvertFrom-Json -Depth 100
$acceptance=$null
if([string]::IsNullOrWhiteSpace([string]$baseline.accepted_at)){
    $acceptance=Invoke-AidosBootstrapModuleCommand -ModulePath $runtimeModule -CommandName 'New-AidosPreparationBaselineAcceptanceRequest' -Arguments @{ProjectRoot=$projectRoot;BuilderRoot=$builderRoot;ContractsRoot=$contractsRoot}
    $registered=Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Get-AidosRegisteredProject' -Arguments @{RegistryRoot=$registryRoot;ProjectId=$PreparationProjectId}
    $persistence=Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Invoke-AidosPreparationGitPersistence' -Arguments @{Project=$registered;CommitMessage='AIDOS publish formal Project Baseline acceptance request';Push=$true}
    Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Set-AidosPreparationProjectPhase' -Arguments @{RegistryRoot=$registryRoot;ProjectId=$PreparationProjectId;Phase='BASELINE_ACCEPTANCE';Status='WAITING_HUMAN'}|Out-Null
}else{
    $persistence=[pscustomobject]@{status='NO_CHANGES';commit=$null;pushed=$false;paths=@()}
    Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Set-AidosPreparationProjectPhase' -Arguments @{RegistryRoot=$registryRoot;ProjectId=$PreparationProjectId;Phase='RUNTIME_ONBOARDING';Status='READY_FOR_ONBOARDING'}|Out-Null
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
$finalRegistered=Invoke-AidosBootstrapModuleCommand -ModulePath $registryModule -CommandName 'Get-AidosRegisteredProject' -Arguments @{RegistryRoot=$registryRoot;ProjectId=$PreparationProjectId}

[pscustomobject][ordered]@{
    status='ENABLED'
    synced_repositories=@($sync|ForEach-Object {$_.repo})
    registry_root=$registryRoot
    preparation_project=$finalRegistered
    baseline_validation=$validation
    acceptance_request=$acceptance
    persistence=$persistence
    host_agent=$install
}|ConvertTo-Json -Depth 100
