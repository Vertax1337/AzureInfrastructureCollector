[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configPath = Join-Path $RepositoryRoot 'Config/collector.config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Write-Error "Collector configuration not found: $configPath"
    exit 2
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$minimumPowerShellVersion = [version]$config.requirements.minimumPowerShellVersion
$requiredPesterVersion = [version]$config.validation.requiredPesterVersion

# Keep this preflight compatible with Windows PowerShell 5.1 so an accidental
# powershell.exe invocation fails cleanly before PowerShell-7-only code is loaded.
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt $minimumPowerShellVersion) {
    Write-Error (
        "PowerShell {0} or newer (pwsh.exe / PSEdition Core) is required. Current runtime: {1} {2}. No Azure request was made. Re-run with: pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Invoke-PreAzureValidation.ps1" -f `
            $minimumPowerShellVersion,
            $PSVersionTable.PSEdition,
            $PSVersionTable.PSVersion
    )
    exit 7
}

$guardModulePath = Join-Path $RepositoryRoot 'Modules/Collector.ReadOnlyGuard.psm1'
$testsPath = Join-Path $RepositoryRoot 'Tests'

if (-not (Test-Path -LiteralPath $guardModulePath -PathType Leaf)) {
    Write-Error "Read-only guard module not found: $guardModulePath"
    exit 2
}

if (-not (Test-Path -LiteralPath $testsPath -PathType Container)) {
    Write-Error "Test directory not found: $testsPath"
    exit 2
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
        Write-Error "Pester $requiredPesterVersion is required, but Install-Module is unavailable. No elevation will be attempted."
        exit 8
    }

    $repositoryInfo = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
    if (-not $repositoryInfo) {
        Write-Error "Pester $requiredPesterVersion is required, but PSGallery is not registered. Repository configuration will not be changed automatically."
        exit 8
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
        Write-Error "Failed to install Pester $requiredPesterVersion for CurrentUser. No administrator elevation was attempted. $($_.Exception.Message)"
        exit 8
    }

    $pesterModule = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -eq $requiredPesterVersion } |
        Select-Object -First 1
}

if (-not $pesterModule) {
    Write-Error "Required Pester version $requiredPesterVersion is unavailable after dependency handling."
    exit 8
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
    Write-Error "Pester $requiredPesterVersion was found but could not be loaded as the active validation module."
    exit 8
}

$requiredPesterCommands = @('Invoke-Pester', 'Describe', 'BeforeAll', 'BeforeEach', 'Mock', 'Should')
foreach ($commandName in $requiredPesterCommands) {
    $command = Get-Command -Name $commandName -ErrorAction Stop
    if ($command.Source -ne 'Pester') {
        Write-Error "Validation command '$commandName' resolved from '$($command.Source)' instead of the pinned Pester $requiredPesterVersion module. Validation is blocked."
        exit 8
    }
}

Write-Host ("      Pester: {0}" -f $loadedPester.Version)
Write-Host ("      Module: {0}" -f $loadedPester.Path)

Write-Host '[3/4] Pester test suite...'
$pesterResult = Invoke-Pester -Path $testsPath -PassThru

if ($null -eq $pesterResult) {
    Write-Error 'Pester returned no result object. Validation cannot be proven and is blocked.'
    exit 9
}

if ([int]$pesterResult.FailedCount -gt 0) {
    Write-Error ("Pester validation failed. Passed: {0}; Failed: {1}; Skipped: {2}. Azure test remains blocked." -f $pesterResult.PassedCount, $pesterResult.FailedCount, $pesterResult.SkippedCount)
    exit 9
}

Write-Host ("      Passed: {0}; Failed: {1}; Skipped: {2}" -f $pesterResult.PassedCount, $pesterResult.FailedCount, $pesterResult.SkippedCount)

Write-Host '[4/4] Final read-only verification...'
$finalReadOnly = Test-CollectorReadOnlyCompliance -RepositoryRoot $RepositoryRoot -ThrowOnFailure
Write-Host ("      Status: {0}" -f $finalReadOnly.status)

if (-not $initialReadOnly.verified -or -not $finalReadOnly.verified -or [int]$pesterResult.FailedCount -ne 0) {
    Write-Error 'Pre-Azure validation could not establish a safe execution state. Azure test remains blocked.'
    exit 10
}

Write-Host ''
Write-Host 'PRE-AZURE VALIDATION RESULT'
Write-Host 'Status: READY FOR AZURE TEST'
Write-Host ("Initial read-only gate: {0}" -f $initialReadOnly.status)
Write-Host ("Pester: {0}; Passed: {1}; Failed: {2}; Skipped: {3}" -f $loadedPester.Version, $pesterResult.PassedCount, $pesterResult.FailedCount, $pesterResult.SkippedCount)
Write-Host ("Final read-only gate: {0}" -f $finalReadOnly.status)
Write-Host 'Azure access performed: NO'
Write-Host 'Administrator elevation: NOT USED'

exit 0
