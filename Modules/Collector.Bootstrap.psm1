Set-StrictMode -Version Latest

function Test-CollectorPowerShellRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version]$MinimumVersion,

        [version]$CurrentVersion = $PSVersionTable.PSVersion,

        [string]$CurrentEdition = $PSVersionTable.PSEdition
    )

    if ($CurrentEdition -ne 'Core' -or $CurrentVersion -lt $MinimumVersion) {
        throw "PowerShell $MinimumVersion or newer (PowerShell 7 / PSEdition Core) is required. Current runtime: $CurrentEdition $CurrentVersion. PowerShell is not installed or upgraded automatically and no self-elevation will be attempted."
    }

    [pscustomobject][ordered]@{
        status         = 'OK'
        edition        = $CurrentEdition
        version        = $CurrentVersion.ToString()
        minimumVersion = $MinimumVersion.ToString()
    }
}

function Get-CollectorInstalledModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    Get-Module -ListAvailable -Name $Name |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Ensure-CollectorDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RequiredModules,

        [string]$Repository = 'PSGallery'
    )

    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        throw "The PowerShellGet command 'Install-Module' is not available. Dependencies cannot be installed automatically. No elevation will be attempted."
    }

    $repositoryInfo = Get-PSRepository -Name $Repository -ErrorAction SilentlyContinue
    if (-not $repositoryInfo) {
        throw "PowerShell repository '$Repository' is not registered. Automatic dependency installation is blocked rather than modifying repository configuration."
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($moduleName in @($RequiredModules | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($moduleName)) {
            continue
        }

        $installedModule = Get-CollectorInstalledModule -Name $moduleName
        $installedByBootstrap = $false

        if (-not $installedModule) {
            Write-Host ("Dependency missing: {0}. Installing for CurrentUser only..." -f $moduleName)

            try {
                Install-Module `
                    -Name $moduleName `
                    -Repository $Repository `
                    -Scope CurrentUser `
                    -Force `
                    -AllowClobber `
                    -ErrorAction Stop
            }
            catch {
                throw "Failed to install required module '$moduleName' for CurrentUser. No administrator elevation was attempted. $($_.Exception.Message)"
            }

            $installedByBootstrap = $true
            $installedModule = Get-CollectorInstalledModule -Name $moduleName
        }

        if (-not $installedModule) {
            throw "Required module '$moduleName' is still unavailable after dependency handling."
        }

        try {
            Import-Module $moduleName -Force -ErrorAction Stop
        }
        catch {
            throw "Required module '$moduleName' is installed but cannot be imported. $($_.Exception.Message)"
        }

        $results.Add([pscustomobject][ordered]@{
            name                 = $moduleName
            version              = $installedModule.Version.ToString()
            installedByBootstrap = $installedByBootstrap
            scope                = if ($installedByBootstrap) { 'CurrentUser' } else { 'ExistingInstallation' }
            status               = 'Ready'
        })
    }

    return @($results)
}

Export-ModuleMember -Function @(
    'Test-CollectorPowerShellRuntime',
    'Get-CollectorInstalledModule',
    'Ensure-CollectorDependencies'
)
