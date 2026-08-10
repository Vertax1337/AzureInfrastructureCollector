BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../Modules/Collector.Bootstrap.psm1') -Force
}

Describe 'Test-CollectorPowerShellRuntime' {
    It 'accepts PowerShell Core at or above the minimum version' {
        $result = Test-CollectorPowerShellRuntime `
            -MinimumVersion ([version]'7.2.0') `
            -CurrentVersion ([version]'7.4.0') `
            -CurrentEdition 'Core'

        $result.status | Should -Be 'OK'
        $result.edition | Should -Be 'Core'
    }

    It 'rejects Windows PowerShell even when the numeric version would be high enough' {
        {
            Test-CollectorPowerShellRuntime `
                -MinimumVersion ([version]'7.2.0') `
                -CurrentVersion ([version]'7.4.0') `
                -CurrentEdition 'Desktop'
        } | Should -Throw '*no self-elevation*'
    }

    It 'rejects a PowerShell Core version below the minimum' {
        {
            Test-CollectorPowerShellRuntime `
                -MinimumVersion ([version]'7.2.0') `
                -CurrentVersion ([version]'7.1.0') `
                -CurrentEdition 'Core'
        } | Should -Throw '*PowerShell 7.2.0 or newer*'
    }
}

Describe 'Ensure-CollectorDependencies' {
    BeforeEach {
        Mock Get-Command -ModuleName Collector.Bootstrap {
            [pscustomobject]@{ Name = 'Install-Module' }
        }

        Mock Get-PSRepository -ModuleName Collector.Bootstrap {
            [pscustomobject]@{ Name = 'PSGallery' }
        }

        Mock Import-Module -ModuleName Collector.Bootstrap { }
        Mock Install-Module -ModuleName Collector.Bootstrap { }
    }

    It 'reuses an existing module without installing anything' {
        Mock Get-CollectorInstalledModule -ModuleName Collector.Bootstrap {
            [pscustomobject]@{
                Name    = 'Az.Accounts'
                Version = [version]'5.0.0'
            }
        }

        $result = @(Ensure-CollectorDependencies -RequiredModules @('Az.Accounts'))

        $result.Count | Should -Be 1
        $result[0].installedByBootstrap | Should -BeFalse
        $result[0].scope | Should -Be 'ExistingInstallation'
        Assert-MockCalled Install-Module -ModuleName Collector.Bootstrap -Times 0
    }

    It 'installs a missing module only in CurrentUser scope' {
        $script:lookupCount = 0
        Mock Get-CollectorInstalledModule -ModuleName Collector.Bootstrap {
            $script:lookupCount++
            if ($script:lookupCount -eq 1) {
                return $null
            }

            return [pscustomobject]@{
                Name    = 'Az.ResourceGraph'
                Version = [version]'1.0.0'
            }
        }

        $result = @(Ensure-CollectorDependencies -RequiredModules @('Az.ResourceGraph'))

        $result[0].installedByBootstrap | Should -BeTrue
        $result[0].scope | Should -Be 'CurrentUser'
        Assert-MockCalled Install-Module -ModuleName Collector.Bootstrap -Times 1 -ParameterFilter {
            $Name -eq 'Az.ResourceGraph' -and
            $Repository -eq 'PSGallery' -and
            $Scope -eq 'CurrentUser'
        }
    }

    It 'fails closed if PSGallery is not registered rather than changing repository configuration' {
        Mock Get-PSRepository -ModuleName Collector.Bootstrap { $null }

        {
            Ensure-CollectorDependencies -RequiredModules @('Az.Accounts')
        } | Should -Throw '*is not registered*'

        Assert-MockCalled Install-Module -ModuleName Collector.Bootstrap -Times 0
    }
}
