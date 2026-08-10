[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Embedded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-PreAzureValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Code,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Embedded) {
        throw $Message
    }

    Write-Error $Message
    exit $Code
}

$configPath = Join-Path $RepositoryRoot 'Config/collector.config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Stop-PreAzureValidation -Code 2 -Message "Collector configuration not found: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$minimumPowerShellVersion = [version]$config.requirements.minimumPowerShellVersion
$requiredPesterVersion = [version]$config.validation.requiredPesterVersion

# Keep this preflight compatible with Windows PowerShell 5.1 so an accidental
# powershell.exe invocation fails cleanly before PowerShell-7-only code is loaded.
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt $minimumPowerShellVersion) {
    Stop-PreAzureValidation -Code 7 -Message (
        "PowerShell {0} or newer (pwsh.exe / PSEdition Core) is required. Current runtime: {1} {2}. No Azure request was made. Re-run with: pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Invoke-PreAzureValidation.ps1" -f `
            $minimumPowerShellVersion,
            $PSVersionTable.PSEdition,
            $PSVersionTable.PSVersion
    )
}

$guardModulePath = Join-Path $RepositoryRoot 'Modules/Collector.ReadOnlyGuard.psm1'
$testsPath = Join-Path $RepositoryRoot 'Tests'

if (-not (Test-Path -LiteralPath $guardModulePath -PathType Leaf)) {
    Stop-PreAzureValidation -Code 2 -Message "Read-only guard module not found: $guardModulePath"
}

if (-not (Test-Path -LiteralPath $testsPath -PathType Container)) {
    Stop-PreAzureValidation -Code 2 -Message "Test directory not found: $testsPath"
}

Import-Module $guardModulePath -Force -ErrorAction Stop

Write-Host ''
Write-Host 'PRE-AZURE VALIDATION'
Write-Host 'Azure access performed: NO'
Write-Host ''

Write-Host '[1/4] Initial read-only verification...'
$initialReadOnly = Test-CollectorReadOnlyCompliance -RepositoryRoot $RepositoryRoot -ThrowOnFailure
Write-Host ("      Status: {0}" -f $initialReadOnly.status)

Write-Host '[2/4] Pester prerequisite...'
$pesterModule = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -eq $requiredPesterVersion } |
    Select-Object -First 1

if (-not $pesterModule) {
    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        Stop-PreAzureValidation -Code 8 -Message "Pester $requiredPesterVersion is required, but Install-Module is unavailable. No elevation will be attempted."
    }

    $repositoryInfo = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
    if (-not $repositoryInfo) {
        Stop-PreAzureValidation -Code 8 -Message "Pester $requiredPesterVersion is required, but PSGallery is not registered. Repository configuration will not be changed automatically."
    }

    Write-Host ("      Pester {0} not found. Installing exactly this version from PSGallery for CurrentUser only..." -f $requiredPesterVersion)

    try {
        Install-Module `
            -Name Pester `
            -RequiredVersion $requiredPesterVersion `
            -Repository PSGallery `
            -Scope CurrentUser `
            -Force `
            -ErrorAction Stop
    }
    catch {
        Stop-PreAzureValidation -Code 8 -Message "Failed to install Pester $requiredPesterVersion for CurrentUser. No administrator elevation was attempted. $($_.Exception.Message)"
    }

    $pesterModule = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -eq $requiredPesterVersion } |
        Select-Object -First 1
}

if (-not $pesterModule) {
    Stop-PreAzureValidation -Code 8 -Message "Required Pester version $requiredPesterVersion is unavailable after dependency handling."
}

# The workstation can contain legacy inbox/system Pester versions (for example 3.4.0).
# Remove any already-loaded Pester module and import the exact validated module path so
# command auto-loading cannot mix multiple Pester generations during the test run.
Get-Module -Name Pester -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module -Name $pesterModule.Path -Force -ErrorAction Stop

$loadedPester = Get-Module -Name Pester |
    Where-Object { $_.Version -eq $requiredPesterVersion } |
    Select-Object -First 1

if (-not $loadedPester) {
    Stop-PreAzureValidation -Code 8 -Message "Pester $requiredPesterVersion was found but could not be loaded as the active validation module."
}

$requiredPesterCommands = @('Invoke-Pester', 'Describe', 'BeforeAll', 'BeforeEach', 'Mock', 'Should')
foreach ($commandName in $requiredPesterCommands) {
    $command = Get-Command -Name $commandName -ErrorAction Stop
    if ($command.Source -ne 'Pester') {
        Stop-PreAzureValidation -Code 8 -Message "Validation command '$commandName' resolved from '$($command.Source)' instead of the pinned Pester $requiredPesterVersion module. Validation is blocked."
    }
}

Write-Host ("      Pester: {0}" -f $loadedPester.Version)
Write-Host ("      Module: {0}" -f $loadedPester.Path)

Write-Host '[3/4] Pester test suite...'
$pesterResult = Invoke-Pester -Path $testsPath -PassThru

if ($null -eq $pesterResult) {
    Stop-PreAzureValidation -Code 9 -Message 'Pester returned no result object. Validation cannot be proven and is blocked.'
}

if ([int]$pesterResult.FailedCount -gt 0) {
    Stop-PreAzureValidation -Code 9 -Message ("Pester validation failed. Passed: {0}; Failed: {1}; Skipped: {2}. Azure test remains blocked." -f $pesterResult.PassedCount, $pesterResult.FailedCount, $pesterResult.SkippedCount)
}

Write-Host ("      Passed: {0}; Failed: {1}; Skipped: {2}" -f $pesterResult.PassedCount, $pesterResult.FailedCount, $pesterResult.SkippedCount)

Write-Host '[4/4] Final read-only verification...'
$finalReadOnly = Test-CollectorReadOnlyCompliance -RepositoryRoot $RepositoryRoot -ThrowOnFailure
Write-Host ("      Status: {0}" -f $finalReadOnly.status)

if (-not $initialReadOnly.verified -or -not $finalReadOnly.verified -or [int]$pesterResult.FailedCount -ne 0) {
    Stop-PreAzureValidation -Code 10 -Message 'Pre-Azure validation could not establish a safe execution state. Azure test remains blocked.'
}

Write-Host ''
Write-Host 'PRE-AZURE VALIDATION RESULT'
Write-Host 'Status: READY FOR AZURE TEST'
Write-Host ("Initial read-only gate: {0}" -f $initialReadOnly.status)
Write-Host ("Pester: {0}; Passed: {1}; Failed: {2}; Skipped: {3}" -f $loadedPester.Version, $pesterResult.PassedCount, $pesterResult.FailedCount, $pesterResult.SkippedCount)
Write-Host ("Final read-only gate: {0}" -f $finalReadOnly.status)
Write-Host 'Azure access performed: NO'
Write-Host 'Administrator elevation: NOT USED'

$result = [pscustomobject][ordered]@{
    status              = 'READY FOR AZURE TEST'
    initialReadOnly     = $initialReadOnly.status
    pesterVersion       = $loadedPester.Version.ToString()
    passed              = [int]$pesterResult.PassedCount
    failed              = [int]$pesterResult.FailedCount
    skipped             = [int]$pesterResult.SkippedCount
    finalReadOnly       = $finalReadOnly.status
    azureAccessPerformed = $false
    administratorElevation = $false
}

if ($Embedded) {
    return $result
}

exit 0
