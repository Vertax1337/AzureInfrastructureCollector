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
$preAzureValidationPath = Join-Path $repositoryRoot 'Tools/Invoke-PreAzureValidation.ps1'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Collector configuration not found: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$minimumPowerShellVersion = [version]$config.requirements.minimumPowerShellVersion

# Minimal local runtime preflight. This intentionally happens before importing the
# PowerShell-7-based guard so unsupported runtimes receive a controlled message.
# It performs no Azure access and no local installation/elevation.
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt $minimumPowerShellVersion) {
    Write-Error ("PowerShell {0} or newer (PowerShell 7) is required. Current runtime: {1} {2}. PowerShell will NOT be installed automatically and the script will NOT self-elevate." -f $minimumPowerShellVersion, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)
    exit 7
}

if (-not (Test-Path -LiteralPath $preAzureValidationPath -PathType Leaf)) {
    throw "Mandatory pre-Azure validation script not found: $preAzureValidationPath"
}

# The normal entry point always performs the complete Azure-free validation itself.
# No operator-side pre-command is required. Any validation failure throws and stops
# execution before runtime dependencies, authentication, or Azure collection begin.
Write-Host ''
Write-Host 'AUTOMATIC PRE-AZURE VALIDATION'
Push-Location -LiteralPath $repositoryRoot
try {
    $preAzureValidation = .\Tools\Invoke-PreAzureValidation.ps1 `
        -RepositoryRoot $repositoryRoot `
        -Embedded
}
finally {
    Pop-Location
}

if (-not $preAzureValidation -or $preAzureValidation.status -ne 'READY FOR AZURE TEST') {
    throw 'Automatic pre-Azure validation did not return READY FOR AZURE TEST. Azure execution is blocked.'
}

Write-Host 'Automatic pre-Azure validation completed successfully.'
Write-Host ''

Import-Module $readOnlyGuardModulePath -Force -ErrorAction Stop
$readOnlyVerification = Test-CollectorReadOnlyCompliance -RepositoryRoot $repositoryRoot -ThrowOnFailure

Write-Host 'BOOTSTRAP READ-ONLY VERIFICATION'
Write-Host ("Status: {0}" -f $readOnlyVerification.status)
Write-Host 'No Azure authentication or Azure collection has occurred yet.'
Write-Host ''

# The module currently contains function names that PowerShell classifies as using
# unapproved verbs. This is only a naming/discoverability warning, not a safety issue.
# Suppress the warning in the normal operator path while keeping the functions unchanged.
Import-Module $bootstrapModulePath -Force -DisableNameChecking -ErrorAction Stop
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

        # Azure PowerShell's current login UX uses ANSI decoration for labels and the
        # device code. Force plain-text rendering only for authentication so copied logs
        # remain human-readable. Restore the caller's rendering settings afterwards.
        $previousOutputRendering = $PSStyle.OutputRendering
        $previousNoColor = $env:NO_COLOR

        try {
            $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText
            $env:NO_COLOR = '1'

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
        }
        finally {
            $PSStyle.OutputRendering = $previousOutputRendering
            $env:NO_COLOR = $previousNoColor
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
