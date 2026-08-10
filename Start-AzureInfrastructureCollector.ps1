[CmdletBinding()]
param(
    [string]$TenantId,

    [string[]]$SubscriptionId,

    [string[]]$ResourceGroup,

    [string]$OutputPath = './Output',

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = $PSScriptRoot
$configPath = Join-Path $repositoryRoot 'Config/collector.config.json'
$readOnlyGuardModulePath = Join-Path $repositoryRoot 'Modules/Collector.ReadOnlyGuard.psm1'
$bootstrapModulePath = Join-Path $repositoryRoot 'Modules/Collector.Bootstrap.psm1'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Collector configuration not found: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$minimumPowerShellVersion = [version]$config.requirements.minimumPowerShellVersion

# Minimal local runtime preflight. This intentionally happens before importing the
# PowerShell-7-based guard so Windows PowerShell 5.1 receives a controlled message.
# It performs no Azure access and no local installation/elevation.
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt $minimumPowerShellVersion) {
    Write-Error ("PowerShell {0} or newer (PowerShell 7) is required. Current runtime: {1} {2}. PowerShell will NOT be installed automatically and the script will NOT self-elevate." -f $minimumPowerShellVersion, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)
    exit 7
}

Import-Module $readOnlyGuardModulePath -Force -ErrorAction Stop
$readOnlyVerification = Test-CollectorReadOnlyCompliance -RepositoryRoot $repositoryRoot -ThrowOnFailure

Write-Host ''
Write-Host 'BOOTSTRAP READ-ONLY VERIFICATION'
Write-Host ("Status: {0}" -f $readOnlyVerification.status)
Write-Host 'No Azure authentication or Azure collection has occurred yet.'
Write-Host ''

Import-Module $bootstrapModulePath -Force -ErrorAction Stop
$runtime = Test-CollectorPowerShellRuntime -MinimumVersion $minimumPowerShellVersion
$dependencies = @(Ensure-CollectorDependencies -RequiredModules @($config.requirements.requiredModules))

Write-Host 'LOCAL PREREQUISITES'
Write-Host ("PowerShell: {0} {1}" -f $runtime.edition, $runtime.version)
foreach ($dependency in $dependencies) {
    $origin = if ($dependency.installedByBootstrap) { 'installed CurrentUser' } else { 'existing' }
    Write-Host ("{0}: {1} [{2}]" -f $dependency.name, $dependency.version, $origin)
}
Write-Host 'Administrator elevation: NOT USED'
Write-Host ''

# Prepare an Azure authentication context before starting the collector. Authentication
# changes only the local/process Az context; it does not mutate Azure resources.
# If the normal WAM/browser flow is unavailable, fall back to Microsoft's supported
# device-code flow. NonInteractive mode never initiates an interactive sign-in.
if (-not $NonInteractive) {
    $existingContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $existingContext -or -not $existingContext.Account -or -not $existingContext.Account.Id) {
        $loginParameters = @{
            Scope       = 'Process'
            ErrorAction = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $loginParameters.Tenant = $TenantId
        }

        Write-Host 'No active Azure context found. Starting interactive Azure login...'
        try {
            Connect-AzAccount @loginParameters | Out-Null
        }
        catch {
            Write-Warning ("Interactive Azure login failed: {0}" -f $_.Exception.Message)
            Write-Host 'Falling back to Azure device-code authentication...'
            $loginParameters.UseDeviceAuthentication = $true
            Connect-AzAccount @loginParameters | Out-Null
        }

        $existingContext = Get-AzContext -ErrorAction Stop
        if (-not $existingContext -or -not $existingContext.Account -or -not $existingContext.Account.Id) {
            throw 'Azure authentication completed without a usable Azure context.'
        }

        Write-Host ("Azure authentication context ready: {0}" -f $existingContext.Account.Id)
        Write-Host ''
    }
}

$collectorParameters = @{
    OutputPath = $OutputPath
}

if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
    $collectorParameters.TenantId = $TenantId
}

if ($SubscriptionId -and $SubscriptionId.Count -gt 0) {
    $collectorParameters.SubscriptionId = $SubscriptionId
}

if ($ResourceGroup -and $ResourceGroup.Count -gt 0) {
    $collectorParameters.ResourceGroup = $ResourceGroup
}

if ($NonInteractive) {
    $collectorParameters.NonInteractive = $true
}

Push-Location -LiteralPath $repositoryRoot
try {
    .\Collect-AzureDocumentation.ps1 @collectorParameters
}
finally {
    Pop-Location
}
